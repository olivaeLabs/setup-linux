#!/usr/bin/env bash
# Instância 2 do OpenCode (conta Go alternativa) — isolada em ~/.opencode-go2
# Idempotente. Uso: ./11-opencode-second-account.sh [porta]   (default 49376)
set -euo pipefail
BASE="$HOME/.opencode-go2"
PORT="${1:-49376}"

mkdir -p "$BASE"/{config,data,state,cache,tmp}/opencode "$BASE/config/opencode/plugins" "$HOME/.local/bin"

CFG="$BASE/config/opencode/opencode.jsonc"
if [ ! -f "$CFG" ]; then
  cat > "$CFG" <<'JSONC'
{
  "$schema": "https://opencode.ai/config.json",
  // Instância 2 — conta Go alternativa, isolada em ~/.opencode-go2 (via XDG_*).
  "username": "Go 2",
  "model": "opencode-go/deepseek-v4.1-flash",
  "small_model": "opencode-go/mimo-v2.6-flash",
  "agent": {
    "general": { "model": "opencode-go/mimo-v2.6-flash" },
    "explore": { "model": "opencode-go/mimo-v2.6-flash" },
    "scout":   { "model": "opencode-go/mimo-v2.6-flash" }
  },
  "command": {
    "review-profundo": {
      "template": "Faça uma revisão profunda e criteriosa do que foi indicado: $ARGUMENTS. Analise riscos, regressões, segurança e conformidade com as regras do workspace. Reporte os achados com severidade e evidência (arquivo:linha), sem editar nada.",
      "description": "Revisão profunda com DeepSeek (principal)",
      "model": "opencode-go/deepseek-v4.1-flash"
    },
    "testes-rapidos": {
      "template": "Detecte a suíte de testes do projeto atual (go test, npm test, pytest ou equivalente) e execute-a. Corrija somente as falhas apontadas, sem refatorações, repetindo até passar. Contexto: $ARGUMENTS",
      "description": "Loop rápido de testes e correções com MiMo",
      "model": "opencode-go/mimo-v2.6-flash"
    },
    "lint-limpo": {
      "template": "Execute a checagem estática/lint do projeto atual (golangci-lint, eslint, ruff ou equivalente) e aplique as correções de conformidade. Contexto: $ARGUMENTS",
      "description": "Lint e conformidade com GLM-5.3-Flash",
      "model": "opencode-go/glm-5.3-flash"
    }
  },
  // Chaves válidas do schema v2 (o binário embute preserve_recent_tokens/reserved; keep/buffer
  // não existem no schema e eram ignoradas — corrigido em 29/09/2026).
  "compaction": { "auto": true, "preserve_recent_tokens": 24000, "reserved": 16000 },
  "mcp": {
    "ai-memory": { "type": "remote", "url": "http://127.0.0.1:49374/mcp", "enabled": true }
  }
}
JSONC
fi

# Plugin de captura (symlink para o global, se existir)
GLOBAL_PLUGIN="$HOME/.config/opencode/plugins/ai-memory-opencode2.ts"
if [ -f "$GLOBAL_PLUGIN" ]; then
  ln -sfn "$GLOBAL_PLUGIN" "$BASE/config/opencode/plugins/ai-memory-opencode2.ts"
fi

cat > "$HOME/.local/bin/opencode-2" <<'SH'
#!/usr/bin/env bash
# OpenCode — instância 2 (conta Go alternativa), isolada em ~/.opencode-go2
export XDG_CONFIG_HOME="$HOME/.opencode-go2/config"
export XDG_DATA_HOME="$HOME/.opencode-go2/data"
export XDG_STATE_HOME="$HOME/.opencode-go2/state"
export XDG_CACHE_HOME="$HOME/.opencode-go2/cache"
export TMPDIR="$HOME/.opencode-go2/tmp"
exec opencode "$@"
SH
chmod +x "$HOME/.local/bin/opencode-2"

cat > "$HOME/.local/bin/quota-meter-2" <<'SH'
#!/usr/bin/env bash
# quota-meter da instância 2: banco e oficiais isolados (ver config2.toml)
export QUOTA_METER_DB="$HOME/.opencode-go2/data/opencode/opencode.db"
export QUOTA_METER_AUB_CONFIG="$HOME/.config/ai-usagebar/config2.toml"
export QUOTA_METER_AUB_CACHE_HOME="$HOME/.cache/ai-usagebar-2"
exec quota-meter "$@"
SH
chmod +x "$HOME/.local/bin/quota-meter-2"

# Porta própria do serviço (evita conflito: ai-memory 49374 · principal 49375)
opencode-2 service set port "$PORT" >/dev/null 2>&1 || true

echo "Instância 2 pronta: ~/.opencode-go2 (porta $PORT)"
echo "1) logue a conta:  opencode-2 auth login opencode-go"
echo "2) abra a sessão:  opencode-2   (ou: opencode-2 --standalone)"
echo "3) oficiais da conta 2 no medidor: ver ~/.config/ai-usagebar/config2.toml"
echo "   (chave 600 + XDG_CACHE_HOME=~/.cache/ai-usagebar-2; doc: generic-dev/knowledge/opencode.md §9)"
