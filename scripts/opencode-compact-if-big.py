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

Uso:
  opencode-compact-if-big                          # DRY-RUN: mostra sessões, tamanho e se estão em voo
  opencode-compact-if-big --list                   # só o relatório
  opencode-compact-if-big --above 600k --apply     # pede a compactação (se não houver trabalho em voo)
  opencode-compact-if-big --session ses_xxx --apply
  opencode-compact-if-big --session ses_xxx --apply --force

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
    sql = ("select session_id, time_created, type, data from session_message "
           "order by time_created")
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
        if sid in filhos or any(sid in v for v in filhos.values()):
            kids_last[sid] = t

    out = []
    for sid, ctx in last_ctx.items():
        info = last_msg.get(sid) or {}
        finish = info.get("finish")
        limite = (info.get("t") or 0) - idle_window * 1000
        ativos = [k for k in filhos.get(sid, []) if (kids_last.get(k) or 0) >= limite]
        em_voo = []
        if finish == "tool-calls":
            em_voo.append("turno em andamento (finish=tool-calls)")
        if ativos:
            em_voo.append(f"{len(ativos)} subagente(s) ativo(s) na janela")
        if pend.get(sid):
            em_voo.append(f"{pend[sid]} prompt(s) na fila")
        out.append({"session": sid, "ctx": ctx,
                    "t": info.get("t") or 0,
                    "finish": finish,
                    "kids": len(ativos),
                    "pend": pend.get(sid, 0),
                    "em_voo": em_voo,
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


def main() -> int:
    ap = argparse.ArgumentParser(description="Pede compactação quando o contexto passar do teto.")
    ap.add_argument("--above", type=parse_size, default=600_000, help="teto de contexto (padrão: 600k)")
    ap.add_argument("--apply", action="store_true", help="age de fato (padrão: dry-run)")
    ap.add_argument("--force", action="store_true", help="age mesmo com trabalho em voo (perigoso)")
    ap.add_argument("--session", help="sessão específica (padrão: a mais recente acima do teto)")
    ap.add_argument("--all", action="store_true", help="considera todas as sessões acima do teto")
    ap.add_argument("--list", action="store_true", help="apenas lista as sessões e tamanhos")
    ap.add_argument("--idle-window", type=int, default=600,
                    help="janela (s) para considerar subagente ativo (padrão: 600)")
    ap.add_argument("--limit", type=int, default=10, help="linhas no relatório (padrão: 10)")
    ap.add_argument("--db", default=DEFAULT_DB)
    args = ap.parse_args()

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
            voo = ("EM VOO: " + "; ".join(s["em_voo"])) if s["em_voo"] else "livre"
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
