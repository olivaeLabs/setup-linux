#!/usr/bin/env python3
"""opencode-compact-if-big — pede compactação quando o contexto passa do teto.

Por quê (medido em 29/09/2026, ver generic-dev/knowledge/opencode.md §12): o pedágio de cada
requisição cresce com o contexto e a v2 **não tem chave de limite** no config — o `auto` só
compacta ao encher (1M), ou seja, no pior momento.

Medida usada: contexto da ÚLTIMA requisição da sessão = `tokens.input + tokens.cache.read`.

TRAVAS (o ponto crítico): compactação é **irreversível e lossy**. Este utilitário **recusa** agir
quando a sessão tem **trabalho em voo** — que é justamente o caso de "aguardando subagentes":
  (a) a última mensagem do assistente é `finish='tool-calls'` (turno em andamento);
  (b) existe **subagente (sessão-filha) com atividade recente** (janela `--idle-window`);
  (c) há **prompts na fila** (`session_pending` / `session_inbox`).
Só `--force` passa por cima — e imprime o motivo em destaque.

Uso (CLI):
  opencode-compact-if-big                          # DRY-RUN: mostra sessões, tamanho e se estão em voo
  opencode-compact-if-big --list                   # só o relatório
  opencode-compact-if-big --above 600k --apply     # pede a compactação (se não houver trabalho em voo)
  opencode-compact-if-big --session ses_xxx --apply
  opencode-compact-if-big --session ses_xxx --apply --force

Uso (TUI — curses, sem dependências):
  opencode-compact-if-big --tui
  teclas: ↑/↓ mover · r atualizar · a armar/aplicar de verdade · +/- teto · o ordenar
          c pedir compactação (com confirmação) · C forçar (exige digitar "force") · q sair

A API do OpenCode executa no próximo ponto seguro (step boundary) e funde pedidos repetidos.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import time

DEFAULT_DB = os.path.expanduser("~/.local/share/opencode/opencode.db")


def parse_size(s: str) -> int:
    m = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*([kKmM]?)\s*", s or "")
    if not m:
        raise argparse.ArgumentTypeError(f"tamanho inválido: {s!r} (use 600k, 1M, 900000)")
    val = float(m.group(1))
    mult = {"": 1, "k": 1_000, "m": 1_000_000}[m.group(2).lower()]
    return int(val * mult)


def human(n: int) -> str:
    if n >= 1_000_000:
        return f"{n/1_000_000:.2f}M"
    if n >= 1_000:
        return f"{n/1000:.0f}k"
    return str(n)


def idade(ms: int) -> str:
    if not ms:
        return "-"
    d = max(0, int(time.time() - ms / 1000))
    if d < 60:
        return f"{d}s"
    if d < 3600:
        return f"{d//60}min"
    return f"{d//3600}h{(d%3600)//60:02d}"


def load_sessions(db: str, idle_window: int) -> list[dict]:
    """Contexto/tamanho + sinais de trabalho em voo, por sessão."""
    con = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
    meta = {}
    try:
        for sid, directory, title in con.execute("select id, directory, title from session_v2"):
            meta[sid] = {"directory": directory or "", "title": title or ""}
    except sqlite3.Error:
        pass
    filhos = {}
    try:
        for sid, parent in con.execute("select id, parent_id from session_v2 where parent_id is not null"):
            filhos.setdefault(parent, []).append(sid)
    except sqlite3.Error:
        pass
    pend = {}
    for tb in ("session_pending", "session_inbox"):
        try:
            for (sid, n) in con.execute(f"select session_id, count(*) from {tb} group by session_id"):
                pend[sid] = pend.get(sid, 0) + n
        except sqlite3.Error:
            pass

    last_ctx, last_msg, kids_last = {}, {}, {}
    sql = "select session_id, time_created, type, data from session_message order by time_created"
    for sid, t, typ, data in con.execute(sql):
        if typ == "assistant":
            try:
                d = json.loads(data)
            except Exception:
                continue
            tok = d.get("tokens") or {}
            model = (d.get("model") or {}).get("id") or d.get("modelID") or ""
            if tok and "deepseek" in model.lower():
                ctx = int(tok.get("input") or 0) + int((tok.get("cache") or {}).get("read") or 0)
                if ctx > 0:
                    last_ctx[sid] = ctx
            last_msg[sid] = {"t": t, "finish": d.get("finish")}
        kids_last[sid] = t

    agora = int(time.time() * 1000)
    out = []
    for sid, ctx in last_ctx.items():
        info = last_msg.get(sid) or {}
        finish = info.get("finish")
        # subagente ativo = filho com atividade RECENTE EM TERMOS ABSOLUTOS (nos últimos idle_window)
        # e posterior ao último item do pai. Sem a checagem absoluta, sessões antigas ficavam
        # marcadas "em voo" para sempre (bug observado no smoke test do TUI).
        limite_pai = (info.get("t") or 0)
        limite_abs = agora - idle_window * 1000
        ativos = [k for k in filhos.get(sid, [])
                  if (kids_last.get(k) or 0) >= limite_abs and (kids_last.get(k) or 0) >= limite_pai]
        em_voo = []
        if finish == "tool-calls":
            em_voo.append("turno em andamento")
        if ativos:
            em_voo.append(f"{len(ativos)} subagente(s) ativo(s)")
        if pend.get(sid):
            em_voo.append(f"{pend[sid]} prompt(s) na fila")
        parada = bool(info.get("t")) and (agora - info["t"]) > 24 * 3600 * 1000
        out.append({"session": sid, "ctx": ctx, "t": info.get("t") or 0, "finish": finish,
                    "kids": len(ativos), "pend": pend.get(sid, 0), "em_voo": em_voo,
                    "parada": parada,
                    "title": (meta.get(sid) or {}).get("title", ""),
                    "directory": (meta.get(sid) or {}).get("directory", "")})
    return sorted(out, key=lambda x: -x["t"])


def request_compaction(session: str, timeout: int = 60) -> tuple[bool, str]:
    cmd = ["opencode", "api", "POST", f"/api/session/{session}/compact", "-d", "{}"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return False, "binário `opencode` não encontrado"
    except subprocess.TimeoutExpired:
        return False, f"timeout de {timeout}s ao chamar a API"
    out = (p.stdout or "").strip() or (p.stderr or "").strip()
    ok = p.returncode == 0 and "error" not in out.lower()
    return ok, out[:300]


# ----------------------------------------------------------------------------- TUI (curses)

def tui(args) -> int:
    import curses

    def corrida(s, armado):
        return 3 if (s["em_voo"] and not armado) else 1 if s["ctx"] >= teto_ref[0] else 2

    teto_ref = [args.above]
    estado = {"sel": 0, "armado": False, "ordem": "ctx", "msg": "", "carregado": 0.0,
              "auto": 20, "todas": False}
    sessions: list[dict] = []

    def recarregar():
        sessions.clear()
        try:
            todas = load_sessions(args.db, args.idle_window)
        except Exception as e:  # noqa: BLE001
            estado["msg"] = f"erro ao ler o banco: {e}"
            todas = []
        # por padrão só sessões recentes (≤24 h); 't' mostra as paradas também
        sessions.extend(todas if estado["todas"] else [s for s in todas if not s.get("parada")])
        if estado["ordem"] == "ctx":
            sessions.sort(key=lambda s: -s["ctx"])
        else:
            sessions.sort(key=lambda s: -s["t"])
        estado["sel"] = max(0, min(estado["sel"], len(sessions) - 1)) if sessions else 0
        estado["carregado"] = time.time()

    def desenhar(stdscr):
        h, w = stdscr.getmaxyx()
        stdscr.erase()
        cor_teto = curses.color_pair(3) if curses.has_colors() else curses.A_BOLD
        titulo = (f" Compactação por teto — OpenCode   teto={human(teto_ref[0])}   "
                  f"[{'ARMADO' if estado['armado'] else 'SIMULAÇÃO'}]   ordem={estado['ordem']}   "
                  f"{'todas' if estado['todas'] else 'recentes(24h)'}")
        try:
            stdscr.addnstr(0, 0, titulo.ljust(w - 1)[:w - 1], w - 1, curses.A_REVERSE)
        except curses.error:
            pass
        cab = f"{'':>2} {'sessão':<26} {'contexto':>9} {'em voo':<28} {'visto':>7}  título"
        stdscr.addnstr(1, 0, cab[:w - 1], w - 1, curses.A_BOLD)
        visiveis = max(1, h - 5)
        inicio = max(0, min(estado["sel"] - visiveis // 3, max(0, len(sessions) - visiveis)))
        for i, s in enumerate(sessions[inicio:inicio + visiveis], start=inicio):
            linha = f"{'→' if i == estado['sel'] else ' '} {s['session'][:26]:<26} {human(s['ctx']):>9} " \
                    f"{(', '.join(s['em_voo']) if s['em_voo'] else ('parada' if s.get('parada') else 'livre'))[:28]:<28} " \
                    f"{idade(s['t']):>7}  {(s['title'] or '')[:max(0, w - 80)]}"
            attr = curses.A_REVERSE if i == estado["sel"] else corrida(s, estado["armado"])
            if i == estado["sel"] and curses.has_colors():
                attr |= curses.color_pair(0)
            try:
                stdscr.addnstr(2 + (i - inicio), 0, linha[:w - 1], w - 1, attr)
            except curses.error:
                pass
        if not sessions:
            stdscr.addnstr(3, 2, "nenhuma sessão com tokens registrados", w - 4)
        dica = ("↑/↓ mover · r atualizar · a armar/aplicar · +/- teto · o ordenar · "
                "c compactar · C forçar · t todas · q sair")
        try:
            stdscr.addnstr(h - 2, 0, dica[:w - 1], w - 1, curses.A_DIM if hasattr(curses, "A_DIM") else 0)
            stdscr.addnstr(h - 1, 0, (estado["msg"] or " ")[:w - 1], w - 1)
        except curses.error:
            pass
        stdscr.refresh()

    def confirmar(stdscr, texto: str, palavra: str | None = None) -> bool:
        h, w = stdscr.getmaxyx()
        curses.echo()
        curses.curs_set(1)
        try:
            stdscr.addnstr(h - 1, 0, " " * (w - 1), w - 1)
            stdscr.addnstr(h - 1, 0, texto[:w - 1], w - 1, curses.A_BOLD)
            stdscr.move(h - 1, min(len(texto) + 1, w - 2))
            resp = stdscr.getstr().decode(errors="ignore").strip()
        except curses.error:
            resp = ""
        finally:
            curses.noecho()
            curses.curs_set(0)
        if palavra:
            return resp.lower() == palavra
        return resp.lower() in ("s", "sim", "y", "yes")

    def agir(stdscr, forcar: bool):
        if not sessions:
            return
        s = sessions[estado["sel"]]
        if s["em_voo"] and not forcar:
            estado["msg"] = f"RECUSADO: {', '.join(s['em_voo'])} — use C para forçar (lossy!)"
            return
        if not estado["armado"] and not forcar:
            estado["msg"] = f"SIMULAÇÃO: pediria compactar {s['session'][:20]} ({human(s['ctx'])}). " \
                            f"Pressione 'a' para armar."
            return
        risco = " ATENÇÃO: trabalho em voo!" if s["em_voo"] else ""
        perg = f"Compactar {s['session'][:20]} ({human(s['ctx'])})?{risco} "
        if forcar and s["em_voo"]:
            ok = confirmar(stdscr, perg + 'digite "force" para confirmar:', palavra="force")
        else:
            ok = confirmar(stdscr, perg + "[s/N]")
        if not ok:
            estado["msg"] = "cancelado"
            return
        ok, msg = request_compaction(s["session"])
        estado["msg"] = f"{'pedido aceito' if ok else 'FALHOU'}: {msg[:80]}"
        recarregar()

    def loop(stdscr):
        curses.curs_set(0)
        stdscr.keypad(True)
        if curses.has_colors():
            try:
                curses.start_color()
                curses.use_default_colors()
                curses.init_pair(1, curses.COLOR_RED, -1)
                curses.init_pair(2, curses.COLOR_WHITE, -1)
                curses.init_pair(3, curses.COLOR_GREEN, -1)
            except curses.error:
                pass
        recarregar()
        while True:
            desenhar(stdscr)
            stdscr.timeout(1000)
            ch = stdscr.getch()
            if ch == -1:
                if time.time() - estado["carregado"] > estado["auto"]:
                    recarregar()
                continue
            if ch in (ord("q"), 27):
                return 0
            if ch in (curses.KEY_UP, ord("k")):
                estado["sel"] = max(0, estado["sel"] - 1)
            elif ch in (curses.KEY_DOWN, ord("j")):
                estado["sel"] = min(max(0, len(sessions) - 1), estado["sel"] + 1)
            elif ch == ord("r"):
                recarregar()
                estado["msg"] = "atualizado"
            elif ch == ord("a"):
                estado["armado"] = not estado["armado"]
                estado["msg"] = ("ARMADO: c vai pedir compactação de verdade"
                                 if estado["armado"] else "SIMULAÇÃO: nada é enviado")
            elif ch in (ord("+"), ord("=")):
                teto_ref[0] = min(1_000_000, teto_ref[0] + 100_000)
            elif ch == ord("-"):
                teto_ref[0] = max(0, teto_ref[0] - 100_000)
            elif ch == ord("t"):
                estado["todas"] = not estado["todas"]
                recarregar()
            elif ch == ord("o"):
                estado["ordem"] = "recencia" if estado["ordem"] == "ctx" else "ctx"
                recarregar()
            elif ch == ord("c"):
                agir(stdscr, forcar=False)
            elif ch == ord("C"):
                agir(stdscr, forcar=True)

    return curses.wrapper(loop)


# ----------------------------------------------------------------------------- CLI

def main() -> int:
    ap = argparse.ArgumentParser(description="Pede compactação quando o contexto passar do teto.")
    ap.add_argument("--above", type=parse_size, default=600_000, help="teto de contexto (padrão: 600k)")
    ap.add_argument("--apply", action="store_true", help="age de fato (padrão: dry-run)")
    ap.add_argument("--force", action="store_true", help="age mesmo com trabalho em voo (perigoso)")
    ap.add_argument("--session", help="sessão específica (padrão: a mais recente acima do teto)")
    ap.add_argument("--all", action="store_true", help="considera todas as sessões acima do teto")
    ap.add_argument("--list", action="store_true", help="apenas lista as sessões e tamanhos")
    ap.add_argument("--tui", action="store_true", help="interface interativa (curses)")
    ap.add_argument("--idle-window", type=int, default=600,
                    help="janela (s) para considerar subagente ativo (padrão: 600)")
    ap.add_argument("--limit", type=int, default=10, help="linhas no relatório (padrão: 10)")
    ap.add_argument("--db", default=DEFAULT_DB)
    args = ap.parse_args()

    if args.tui:
        if not os.path.exists(args.db):
            print(f"M=compactIfBig, E=\"banco ausente: {args.db}\", status=error", file=sys.stderr)
            return 2
        return tui(args)

    print(f'M=compactIfBig, I="iniciando", teto={human(args.above)}, modo='
          f'{"apply" if args.apply else "dry-run"}, status=init')

    if not os.path.exists(args.db):
        print(f'M=compactIfBig, E="banco ausente: {args.db}", status=error', file=sys.stderr)
        return 2

    sessions = load_sessions(args.db, args.idle_window)
    if args.session:
        sessions = [s for s in sessions if s["session"] == args.session] or \
                   [{"session": args.session, "ctx": 0, "title": "(desconhecida)", "directory": "",
                     "t": 0, "finish": None, "kids": 0, "pend": 0, "em_voo": []}]

    if args.list or not sessions:
        for s in sessions[:args.limit]:
            quando = time.strftime("%d/%m %H:%M", time.localtime(s["t"] / 1000)) if s["t"] else "-"
            voo = ("EM VOO: " + "; ".join(s["em_voo"])) if s["em_voo"] else ("livre" if not s.get("parada") else "parada")
            print(f'  {s["session"][:26]:<28} {human(s["ctx"]):>8}  {quando}  {voo[:60]}  {(s["title"] or "")[:28]}')
        if not sessions:
            print("  (nenhuma sessão com tokens registrados)")
        return 0

    alvos = [s for s in sessions if s["ctx"] >= args.above]
    if not alvos:
        print(f'M=compactIfBig, I="nada a fazer", maior={human(sessions[0]["ctx"])}, status=complete')
        return 0
    if not args.all:
        alvos = [alvos[0]]

    rc = 0
    for s in alvos:
        print(f'  alvo {s["session"][:26]} contexto={human(s["ctx"])} '
              f'titulo="{(s["title"] or "")[:40]}" cwd={s["directory"]}')
        if s["em_voo"] and not args.force:
            print(f'  -> RECUSADO: trabalho em voo ({"; ".join(s["em_voo"])}). '
                  f'Espere o turno/subagentes terminarem ou use --force (lossy e irreversível).')
            rc = 3
            continue
        if s["em_voo"] and args.force:
            print(f'  -> ATENÇÃO: --force com trabalho em voo ({"; ".join(s["em_voo"])})')
        if not args.apply:
            print(f'  -> [dry-run] pediria: opencode api POST /api/session/{s["session"]}/compact')
            continue
        ok, msg = request_compaction(s["session"])
        print(f'  -> {"pedido aceito" if ok else "FALHOU"}: {msg}')
        if not ok:
            rc = 1
    print(f'M=compactIfBig, I="concluido", alvos={len(alvos)}, aplicado={args.apply}, status=complete')
    return rc


if __name__ == "__main__":
    sys.exit(main())
