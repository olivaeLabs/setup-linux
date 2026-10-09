#!/usr/bin/env bash
# ==============================================================================
# Script: 07-opencode.sh
# Descrição: Instalação do OpenCode CLI e Desktop para Arch/BigLinux
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

log_section "07 - OpenCode CLI e Desktop"

install_cli_official() {
    log_info "Instalando o OpenCode CLI oficial no perfil do usuário..."
    curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$HOME/.opencode/bin/opencode" "$HOME/.local/bin/opencode"
    log_success "OpenCode CLI instalado em ~/.local/bin/opencode."
}

install_with_aur_or_fallback() {
    local package="$1"
    local fallback="$2"
    local aur_helper

    aur_helper=$(get_aur_helper)
    if [ -n "$aur_helper" ]; then
        log_info "Instalando $package via $aur_helper..."
        if "$aur_helper" -S --needed --noconfirm "$package"; then
            log_success "$package instalado via AUR."
            return 0
        fi
        log_warn "A instalação via AUR falhou; usando o fallback sem root."
    fi

    "$fallback"
}

if command -v opencode &>/dev/null; then
    log_success "OpenCode CLI já está instalado: $(opencode --version)"
else
    install_with_aur_or_fallback opencode-bin install_cli_official
fi

# Desktop: exclusivamente via AUR (opencode-desktop-bin). O fallback AppImage foi
# removido por preferência do usuário ("não gosto de AppImage"); sem helper AUR,
# o módulo aborta com erro explícito em vez de instalar um AppImage solto.
if command -v opencode-desktop &>/dev/null; then
    log_success "OpenCode Desktop já está instalado."
else
    aur_helper=$(get_aur_helper)
    if [ -z "$aur_helper" ]; then
        log_error "OpenCode Desktop requer o pacote AUR 'opencode-desktop-bin' e nenhum helper (yay/paru) foi encontrado."
        exit 1
    fi
    log_info "Instalando opencode-desktop-bin via $aur_helper..."
    "$aur_helper" -S --needed --noconfirm opencode-desktop-bin
    log_success "OpenCode Desktop instalado via AUR."
fi

# Garante que o cofre do ai-memory.token exista caso o ai-memory esteja configurado
# (evita crash 500 do OpenCode ao tentar resolver {file:~/.config/anubis/ai-memory.token})
ensure_ai_memory_token() {
    local anubis_dir="$HOME/.config/anubis"
    local token_file="$anubis_dir/ai-memory.token"
    local mem_env="$HOME/.config/ai-memory/env"

    if [ ! -f "$token_file" ] && [ -f "$mem_env" ]; then
        local token
        token=$(grep -E '^AI_MEMORY_AUTH_TOKEN=' "$mem_env" | cut -d'=' -f2- | tr -d ' \n\r"')
        if [ -n "$token" ]; then
            mkdir -p "$anubis_dir"
            chmod 700 "$anubis_dir"
            printf '%s' "$token" > "$token_file"
            chmod 600 "$token_file"
            log_success "Token do ai-memory provisionado em $token_file."
        fi
    fi
}
ensure_ai_memory_token

log_success "Etapa 07 concluída com sucesso!"
