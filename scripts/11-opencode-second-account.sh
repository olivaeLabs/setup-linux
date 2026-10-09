#!/usr/bin/env bash
# ==============================================================================
# Script: 11-opencode-second-account.sh
# Descrição: Instância 2 do OpenCode — CLONE do perfil normal (mesma conta Go,
#            skills, agents, TUI/theme e ai-memory completo), com a ÚNICA
#            diferença: NÃO carrega os MCPs pesados (hostinger-hosting,
#            hostinger-wordpress, clickbank). Isolada em ~/.opencode-go2 (XDG
#            próprio + porta de serviço própria) para rodar EM PARALELO ao
#            principal sem que mexer em MCP/opencode.jsonc afete o Desktop.
# Origem: config derivada do canônico (single source, sem drift).
# Idempotente. Uso: ./11-opencode-second-account.sh [porta]   (default 49376)
# ==============================================================================
set -euo pipefail
BASE="$HOME/.opencode-go2"
PORT="${1:-49376}"
CANONICO="$HOME/.config/opencode/opencode.jsonc"   # symlink -> setup-linux/configs/opencode/opencode.jsonc
DESTINO="$BASE/config/opencode/opencode.jsonc"
AUTH_SHARED="$HOME/.local/share/opencode/auth.json"

mkdir -p "$BASE"/{config,data,state,cache,tmp}/opencode "$HOME/.local/bin"

# --- 1. Config: deriva do canônico, desligando os 3 MCPs pesados (sem drift) ---
[ -f "$CANONICO" ] || { echo "M=opencode2, E=\"config canônica ausente: $CANONICO\", status=error" >&2; exit 1; }
python3 - "$CANONICO" "$DESTINO" <<'PY'
import pathlib, re, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
txt = src.read_text()
estado = []
# Desliga apenas os 3 servidores pesados; mantém ai-memory e google-ads ligados.
for server in ("hostinger-hosting", "hostinger-wordpress", "clickbank"):
    txt, n = re.subn(r'("' + server + r'":\s*\{[^}]*?"enabled":\s*)true', r'\1false', txt, flags=re.S)
    estado.append(f"{server}={'off' if n else 'ja-off/sem-bloco'}")
if '"username"' not in txt:
    txt = re.sub(r'(\n\s*"\$schema":[^\n]*\n)', r'\1  "username": "Go 2",\n', txt, count=1)
dst.write_text(txt)
print('M=opencode2, I="config gerada do canônico", ' + ", ".join(estado) + f', destino={dst}', file=sys.stderr)
PY

# --- 2. Paridade com o perfil normal: TUI/theme, agents, skills, plugins ---
lnk() { ln -sfn "$1" "$2"; }
[ -e "$HOME/.config/opencode/cli.json" ] && lnk "$HOME/.config/opencode/cli.json" "$BASE/config/opencode/cli.json" || true
rm -rf "$BASE/config/opencode/agents" "$BASE/config/opencode/skills" "$BASE/config/opencode/plugins"
[ -d "$HOME/.config/opencode/agents" ]  && lnk "$HOME/.config/opencode/agents"  "$BASE/config/opencode/agents"  || true
[ -d "$HOME/.config/opencode/skills" ]  && lnk "$HOME/.config/opencode/skills"  "$BASE/config/opencode/skills"  || true
[ -d "$HOME/.config/opencode/plugins" ] && lnk "$HOME/.config/opencode/plugins" "$BASE/config/opencode/plugins" || true

# --- 3. Mesma conta do OpenCode Go (auth compartilhado com o perfil principal) ---
if [ -f "$AUTH_SHARED" ]; then
  mkdir -p "$BASE/data/opencode"
  lnk "$AUTH_SHARED" "$BASE/data/opencode/auth.json"
fi

# --- 4. Launcher da instância 2 ---
cat > "$HOME/.local/bin/opencode-2" <<'SH'
#!/usr/bin/env bash
# OpenCode — instância 2 (clone do perfil normal SEM os MCPs pesados), isolada em ~/.opencode-go2
export XDG_CONFIG_HOME="$HOME/.opencode-go2/config"
export XDG_DATA_HOME="$HOME/.opencode-go2/data"
export XDG_STATE_HOME="$HOME/.opencode-go2/state"
export XDG_CACHE_HOME="$HOME/.opencode-go2/cache"
export TMPDIR="$HOME/.opencode-go2/tmp"
exec opencode "$@"
SH
chmod +x "$HOME/.local/bin/opencode-2"

# --- 5. quota-meter da instância 2 ---
cat > "$HOME/.local/bin/quota-meter-2" <<'SH'
#!/usr/bin/env bash
# quota-meter da instância 2: banco e oficiais isolados (ver config2.toml)
export QUOTA_METER_DB="$HOME/.opencode-go2/data/opencode/opencode.db"
export QUOTA_METER_AUB_CONFIG="$HOME/.config/ai-usagebar/config2.toml"
export QUOTA_METER_AUB_CACHE_HOME="$HOME/.cache/ai-usagebar-2"
exec quota-meter "$@"
SH
chmod +x "$HOME/.local/bin/quota-meter-2"

# --- 6. Porta própria do serviço (ai-memory 49374 · principal 49375 · instância 2 49376) ---
opencode-2 service set port "$PORT" >/dev/null 2>&1 || true

echo "Instância 2 pronta: ~/.opencode-go2 (porta $PORT)"
echo "  - mesma conta do OpenCode Go (auth compartilhado) — sem login extra"
echo "  - skills, agents, TUI/theme e ai-memory iguais ao perfil normal"
echo "  - MCPs desligados: hostinger-hosting, hostinger-wordpress, clickbank"
echo "  - abra a sessão:  opencode-2"
echo "  - oficiais da conta 2 no medidor: ver ~/.config/ai-usagebar/config2.toml"
