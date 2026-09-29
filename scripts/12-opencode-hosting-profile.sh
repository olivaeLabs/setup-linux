#!/usr/bin/env bash
# Perfil SOB DEMANDA do OpenCode: Hostinger + ClickBank ligados (wrapper `opencode-hosting`).
#
# Motivo (medido em 29/09/2026): a latência de cada requisição é dominada pelo processamento do
# PREFIXO no provedor. Os 2 MCPs Hostinger somavam 102 dos 131 schemas de tool injetados em toda
# requisição → o padrão passou a habilitar apenas o MCP remoto `ai-memory` (23 tools, zero spawn).
# Este perfil existe para quem precisa das tools de Hostinger/ClickBank: ele NÃO altera o config
# canônico — gera um config próprio a partir dele e roda o OpenCode isolado (data/state/cache
# compartilhados: mesma sessão/login/histórico).
#
# Evidência: tasks/opencode-latency-test/evidence/perf-latencia-prefixo.md
# Idempotente. Uso: ./12-opencode-hosting-profile.sh
set -euo pipefail

PERFIL="$HOME/.config/opencode-hosting"
CANONICO="$HOME/.config/opencode/opencode.jsonc"

mkdir -p "$PERFIL/opencode" "$HOME/.local/bin"

if [ ! -f "$CANONICO" ]; then
  echo "AVISO: config canônica ausente ($CANONICO) — rode 07-opencode.sh antes." >&2
fi

cat > "$HOME/.local/bin/opencode-hosting" <<'SH'
#!/usr/bin/env bash
# opencode-hosting — perfil SOB DEMANDA com os MCPs de Hostinger + ClickBank ligados.
# Gerado a partir do config canônico a cada execução (sem drift) e isolado por XDG_CONFIG_HOME.
# Data/state/cache são COMPARTILHADOS → mesma sessão/login/histórico.
# Uso: opencode-hosting [subcomando do opencode]
set -euo pipefail

PERFIL="$HOME/.config/opencode-hosting"
CANONICO="$HOME/.config/opencode/opencode.jsonc"
DESTINO="$PERFIL/opencode/opencode.jsonc"

[ -f "$CANONICO" ] || { echo "M=opencodeHosting, E=\"config canônica ausente: $CANONICO\", status=error" >&2; exit 1; }

mkdir -p "$PERFIL/opencode"
python3 - "$CANONICO" "$DESTINO" <<'PY'
import pathlib, re, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
txt = src.read_text()
ligados = []
for server in ("clickbank", "hostinger-hosting", "hostinger-wordpress"):
    txt, n = re.subn(r'("' + server + r'":\s*\{[^}]*?"enabled":\s*)false', r'\1true', txt, flags=re.S)
    ligados.append(f"{server}={'on' if n else 'ja-on'}")
dst.write_text(txt)
print('M=opencodeHosting, I="perfil gerado", servidores="' + ", ".join(ligados) + f'", destino={dst}', file=sys.stderr)
PY

ln -sfn "$HOME/.config/opencode/plugins" "$PERFIL/opencode/plugins"
export XDG_CONFIG_HOME="$PERFIL"
exec opencode "$@"
SH
chmod +x "$HOME/.local/bin/opencode-hosting"

# Primeira geração do config do perfil (idempotente; o wrapper regenera a cada execução)
opencode-hosting --version >/dev/null 2>&1 || true

echo "Perfil sob demanda instalado: ~/.local/bin/opencode-hosting"
echo "  uso:  opencode-hosting            (TUI com Hostinger + ClickBank)"
echo "        opencode-hosting run \"...\"   (qualquer subcomando do opencode)"
echo "  padrão (canônico) segue com SOMENTE o MCP ai-memory habilitado."
