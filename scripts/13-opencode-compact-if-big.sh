#!/usr/bin/env bash
# Instala `opencode-compact-if-big`: gatilho de compactação quando o contexto passa do teto.
#
# Motivo (29/09/2026): o config da v2 NÃO tem chave de limite de contexto — o `auto` só compacta
# ao encher (1M), no pior momento. Medimos que `tempo ≈ nº de requisições × pedágio` e que a
# cauda piora com o contexto (p90 149,6 s em 600–900k). Este utilitário implementa o gatilho
# "no limite de tarefa / acima do teto", pedindo a compactação pela API (que roda no próximo
# ponto seguro e funde pedidos repetidos).
#
# Política completa: generic-dev/knowledge/opencode.md §12.
# Idempotente. Uso: ./13-opencode-compact-if-big.sh
set -euo pipefail

mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/opencode-compact-if-big" <<'PY'
#!/usr/bin/env python3
"""opencode-compact-if-big — pede compactação quando o contexto passa do teto.

Medida usada: contexto da ÚLTIMA requisição da sessão = `tokens.input + tokens.cache.read`.

Uso:
  opencode-compact-if-big                          # DRY-RUN: mostra as sessões e o que faria
  opencode-compact-if-big --above 600k --apply     # pede a compactação de fato
  opencode-compact-if-big --session ses_xxx --apply
  opencode-compact-if-big --list                   # lista sessões e tamanhos

Segurança: **dry-run é o padrão**; só `--apply` age. A API executa a compactação no próximo
ponto seguro (step boundary) e funde pedidos repetidos — não interrompe uma tarefa.
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


def load_sessions(db: str) -> list[dict]:
    con = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
    meta = {}
    try:
        for sid, directory, title, tu in con.execute(
                "select id, directory, title, time_updated from session_v2"):
            meta[sid] = {"directory": directory, "title": title, "updated": tu or 0}
    except sqlite3.Error:
        pass
    last = {}
    sql = ("select session_id, time_created, data from session_message "
           "where type='assistant' order by time_created")
    for sid, t, data in con.execute(sql):
        try:
            d = json.loads(data)
        except Exception:
            continue
        tok = d.get("tokens") or {}
        if not tok:
            continue
        model = (d.get("model") or {}).get("id") or d.get("modelID") or ""
        if "deepseek" not in model.lower():
            continue
        ctx = int(tok.get("input") or 0) + int((tok.get("cache") or {}).get("read") or 0)
        if ctx <= 0:
            continue
        last[sid] = {"session": sid, "t": t, "ctx": ctx, "model": model,
                     "title": (meta.get(sid) or {}).get("title", ""),
                     "directory": (meta.get(sid) or {}).get("directory", "")}
    return sorted(last.values(), key=lambda x: -x["t"])


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
    ap.add_argument("--above", type=parse_size, default=600_000,
                    help="teto de contexto (padrão: 600k)")
    ap.add_argument("--apply", action="store_true", help="age de fato (padrão: dry-run)")
    ap.add_argument("--session", help="sessão específica (padrão: a mais recente acima do teto)")
    ap.add_argument("--all", action="store_true", help="considera todas as sessões acima do teto")
    ap.add_argument("--list", action="store_true", help="apenas lista as sessões e tamanhos")
    ap.add_argument("--limit", type=int, default=10, help="linhas no relatório (padrão: 10)")
    ap.add_argument("--db", default=DEFAULT_DB)
    args = ap.parse_args()

    print(f'M=compactIfBig, I="iniciando", teto={human(args.above)}, modo='
          f'{"apply" if args.apply else "dry-run"}, status=init')

    if not os.path.exists(args.db):
        print(f'M=compactIfBig, E="banco ausente: {args.db}", status=error', file=sys.stderr)
        return 2

    sessions = load_sessions(args.db)
    if args.session:
        sessions = [s for s in sessions if s["session"] == args.session] or \
                   [{"session": args.session, "ctx": 0, "title": "(desconhecida)",
                     "directory": "", "t": 0}]

    if args.list or not sessions:
        for s in sessions[:args.limit]:
            quando = time.strftime("%d/%m %H:%M", time.localtime(s["t"] / 1000)) if s["t"] else "-"
            print(f'  {s["session"][:26]:<28} {human(s["ctx"]):>8}  {quando}  {(s["title"] or "")[:40]}')
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
        if not args.apply:
            print(f'  -> [dry-run] pediria: opencode api POST /api/session/{s["session"]}/compact')
            continue
        ok, msg = request_compaction(s["session"])
        print(f'  -> {"pedido aceito" if ok else "FALHOU"}: {msg}')
        if not ok:
            rc = 1
    print(f'M=compactIfBig, I="concluido", alvos={len(alvos)}, '
          f'aplicado={args.apply}, status=complete')
    return rc


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x "$HOME/.local/bin/opencode-compact-if-big"

echo "Instalado: ~/.local/bin/opencode-compact-if-big"
echo "  dry-run: opencode-compact-if-big                 (não age)"
echo "  aplicar: opencode-compact-if-big --above 600k --apply"
echo "  política: generic-dev/knowledge/opencode.md §12"
