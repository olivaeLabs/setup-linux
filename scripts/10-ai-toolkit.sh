#!/usr/bin/env bash
# ==============================================================================
# Script: 10-ai-toolkit.sh
# Descrição: Ferramentas do "Akita's AI Lair" — ai-usagebar, ghpending, tclock e ai-memory.
# Referência: https://ailair.akitaonrails.com/pt-br/
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

log_section "10 - Akita's AI Lair Toolkit"

AUR_HELPER=$(get_aur_helper)
if [ -z "$AUR_HELPER" ]; then
    log_error "Nenhum helper AUR (yay/paru) encontrado. Abortando."
    exit 1
fi

# Pacotes -bin do AUR: binários pré-compilados do autor, com tag fixada e
# sha256 no PKGBUILD (revisar antes quando possível).
AUR_PKGS=(
    ai-usagebar-bin   # Cota de 24 provedores de IA (TUI/CLI)
    ghpending-bin     # Digest de PRs/issues do GitHub de vários repos
    clock-tui-bin     # tclock: relógio de terminal + widgets de comando
    ai-memory-bin     # Memória de longo prazo para agentes (MCP + hooks)
)

log_info "Instalando ferramentas do AI Lair via $AUR_HELPER..."
$AUR_HELPER -S --needed --noconfirm "${AUR_PKGS[@]}"
log_success "Pacotes instalados: ${AUR_PKGS[*]}"

# ------------------------------------------------------------------------------
# ai-memory — memória de longo prazo (MCP local + hooks). Layout canônico:
#   config: ~/.config/ai-memory/config.toml   env: ~/.config/ai-memory/env
#   dados:  ~/.local/share/ai-memory          serviço de usuário: ai-memory.service
# LLM (opcional) em ~/.config/ai-memory/env — NUNCA versionar a chave:
#   AI_MEMORY_LLM_PROVIDER=opencode
#   AI_MEMORY_LLM_MODEL=deepseek-v4.1-flash
#   OPENCODE_API_KEY=<chave do opencode>
# WSL: `loginctl enable-linger $USER` faz o serviço sobreviver ao logout.
# ATENÇÃO (cache-hit): registrar o MCP altera opencode.jsonc e invalida o
# prefix cache — fazer no INÍCIO de uma sessão nova.
# ------------------------------------------------------------------------------
if command -v ai-memory &>/dev/null; then
    log_info "Inicializando ai-memory (config canônico + serviço de usuário)..."
    mkdir -p "$HOME/.config/ai-memory" "$HOME/.local/share/ai-memory"
    if [ ! -f "$HOME/.config/ai-memory/config.toml" ]; then
        ai-memory --data-dir "$HOME/.local/share/ai-memory" \
                  --config "$HOME/.config/ai-memory/config.toml" init || true
    fi
    systemctl --user enable --now ai-memory.service 2>/dev/null || \
        log_warn "ai-memory.service não habilitado (systemd de usuário indisponível?)"
    log_info "Preencha ~/.config/ai-memory/env com o provider de LLM (ver cabeçalho)."
fi

# Detecta provedores de IA com credencial local (somente arquivos locais, sem rede).
if command -v ai-usagebar &>/dev/null; then
    log_info "Detectando provedores de IA já configurados (local)..."
    ai-usagebar detect || true
fi

log_success "Etapa 10 concluída com sucesso!"
