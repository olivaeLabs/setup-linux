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

install_desktop_appimage() {
    local release_file version asset_url asset_digest install_dir appimage

    log_info "Instalando o OpenCode Desktop AppImage oficial no perfil do usuário..."
    release_file=$(mktemp)

    curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest -o "$release_file"
    version=$(jq -er '.tag_name | ltrimstr("v")' "$release_file")
    asset_url=$(jq -er '.assets[] | select(.name == "opencode-desktop-linux-x86_64.AppImage") | .browser_download_url' "$release_file")
    asset_digest=$(jq -er '.assets[] | select(.name == "opencode-desktop-linux-x86_64.AppImage") | .digest | sub("^sha256:"; "")' "$release_file")

    install_dir="$HOME/.local/share/opencode-desktop"
    appimage="$install_dir/opencode-desktop-${version}-x86_64.AppImage"
    mkdir -p "$install_dir" "$HOME/.local/share/applications" "$HOME/.local/bin"

    curl -fL --progress-bar "$asset_url" -o "$appimage"
    printf '%s  %s\n' "$asset_digest" "$appimage" | sha256sum --check --status
    chmod 755 "$appimage"
    ln -sfn "$appimage" "$install_dir/opencode-desktop.AppImage"
    ln -sfn "$install_dir/opencode-desktop.AppImage" "$HOME/.local/bin/opencode-desktop"

    cat > "$HOME/.local/share/applications/opencode-desktop.desktop" <<EOF
[Desktop Entry]
Name=OpenCode
Comment=AI coding agent desktop app
Exec=$HOME/.local/bin/opencode-desktop %U
Icon=opencode
Terminal=false
Type=Application
Categories=Development;IDE;
MimeType=x-scheme-handler/opencode;
StartupWMClass=OpenCode
EOF

    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
rm -f "$release_file"
log_success "OpenCode Desktop $version instalado em ~/.local/bin/opencode-desktop."
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

if command -v opencode-desktop &>/dev/null; then
    log_success "OpenCode Desktop já está instalado."
else
    install_with_aur_or_fallback opencode-desktop-bin install_desktop_appimage
fi

log_success "Etapa 07 concluída com sucesso!"
