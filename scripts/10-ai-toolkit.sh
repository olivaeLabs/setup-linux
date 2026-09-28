#!/usr/bin/env bash
# ==============================================================================
# Script: 10-ai-toolkit.sh
# Descrição: Ferramentas do "Akita's AI Lair" — ai-usagebar, ghpending e tclock.
#            O ai-memory é OPCIONAL e fica DESLIGADO por padrão (ver abaixo).
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
)

log_info "Instalando ferramentas do AI Lair via $AUR_HELPER..."
$AUR_HELPER -S --needed --noconfirm "${AUR_PKGS[@]}"
log_success "Pacotes base instalados: ${AUR_PKGS[*]}"

# ------------------------------------------------------------------------------
# ONDA 2 — ai-memory (ADIADO por decisão do operador em 2026-09-27).
# Memória de longo prazo para agentes. Quando for a hora, habilite com:
#   INSTALL_AI_MEMORY=1 ./scripts/10-ai-toolkit.sh
# Depois:  ai-memory init && ai-memory serve --transport http --bind 127.0.0.1:49374
# ATENÇÃO (cache-hit): registrar o MCP altera ~/.config/opencode/opencode.jsonc
# e invalida o prefix cache — fazer no INÍCIO de uma sessão nova.
# ------------------------------------------------------------------------------
if [ "${INSTALL_AI_MEMORY:-0}" = "1" ]; then
    log_warn "INSTALL_AI_MEMORY=1 — instalando ai-memory (memória de longo prazo)..."
    $AUR_HELPER -S --needed --noconfirm ai-memory-bin
    log_info "Próximo passo manual: ai-memory init && ai-memory serve"
else
    log_info "ai-memory ADIADO (padrão). Use INSTALL_AI_MEMORY=1 para instalar."
fi

# Detecta provedores de IA com credencial local (somente arquivos locais, sem rede).
if command -v ai-usagebar &>/dev/null; then
    log_info "Detectando provedores de IA já configurados (local)..."
    ai-usagebar detect || true
fi

log_success "Etapa 10 concluída com sucesso!"
