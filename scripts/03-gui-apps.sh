#!/usr/bin/env bash
# ==============================================================================
# Script: 03-gui-apps.sh
# Descrição: Instalação de aplicativos gráficos (VS Code, JetBrains Toolbox, Browsers, etc.)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

log_section "03 - Aplicativos Gráficos e IDEs"

AUR_HELPER=$(get_aur_helper)

# 1. JetBrains Toolbox
if ! command -v jetbrains-toolbox &>/dev/null && [ ! -f "$HOME/.local/bin/jetbrains-toolbox" ]; then
    log_info "Instalando JetBrains Toolbox..."
    TOOLBOX_URL=$(curl -s "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" | jq -r '.TBA[0].downloads.linux.link')
    mkdir -p "$HOME/.local/share/JetBrains/Toolbox" "$HOME/.local/bin" "$HOME/.local/share/applications"
    curl -sL "$TOOLBOX_URL" | tar -xz -C "$HOME/.local/share/JetBrains/Toolbox" --strip-components=1
    chmod +x "$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox"
    ln -sf "$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox" "$HOME/.local/bin/jetbrains-toolbox"

    ICON_PATH=$(find "$HOME/.local/share/JetBrains/Toolbox/" -name "*toolbox*.svg" -o -name "*toolbox*.png" | head -n 1)
    [ -z "$ICON_PATH" ] && ICON_PATH="jetbrains-toolbox"

    cat << EOF > "$HOME/.local/share/applications/jetbrains-toolbox.desktop"
[Desktop Entry]
Type=Application
Name=JetBrains Toolbox
Icon=$ICON_PATH
Exec=$HOME/.local/bin/jetbrains-toolbox %u
Comment=Manage all your JetBrains Projects and Tools
Categories=Development;IDE;
Terminal=false
StartupNotify=false
EOF
    log_success "JetBrains Toolbox instalado com sucesso!"
else
    log_success "JetBrains Toolbox já está instalado."
fi

# 2. Visual Studio Code
if ! command -v code &>/dev/null && [ ! -f "$HOME/.local/bin/code" ]; then
    log_info "Instalando Visual Studio Code oficial..."
    mkdir -p "$HOME/.local/share/vscode" "$HOME/.local/bin" "$HOME/.local/share/applications"
    curl -sL "https://update.code.visualstudio.com/latest/linux-x64/stable" -o /tmp/vscode.tar.gz
    tar -xzf /tmp/vscode.tar.gz -C "$HOME/.local/share/vscode" --strip-components=1
    chmod +x "$HOME/.local/share/vscode/bin/code"
    ln -sf "$HOME/.local/share/vscode/bin/code" "$HOME/.local/bin/code"
    rm -f /tmp/vscode.tar.gz

    cat << EOF > "$HOME/.local/share/applications/code.desktop"
[Desktop Entry]
Name=Visual Studio Code
Comment=Code Editing. Redefined.
GenericName=Text Editor
Exec=$HOME/.local/bin/code --unity-launch %F
Icon=$HOME/.local/share/vscode/resources/app/resources/linux/code.png
Type=Application
StartupNotify=false
StartupWMClass=Code
Categories=TextEditor;Development;IDE;
MimeType=text/plain;inode/directory;application/x-code-workspace;
Actions=new-empty-window;
Keywords=vscode;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=$HOME/.local/bin/code --new-window %F
Icon=$HOME/.local/share/vscode/resources/app/resources/linux/code.png
EOF
    log_success "Visual Studio Code instalado com sucesso!"
else
    log_success "Visual Studio Code já está instalado: $(code --version 2>/dev/null | head -n1 || echo 'disponível')"
fi

# 3. Cursor IDE
if ! command -v cursor &>/dev/null && [ ! -f "$HOME/.local/bin/cursor" ]; then
    log_info "Instalando Cursor IDE via AUR ($AUR_HELPER)..."
    if [ -n "$AUR_HELPER" ]; then
        $AUR_HELPER -S --needed --noconfirm cursor-bin || true
    fi
    if command -v cursor &>/dev/null; then
        log_success "Cursor IDE instalado com sucesso!"
    fi
else
    log_success "Cursor IDE já está instalado: $(cursor --version 2>/dev/null | head -n1 || echo 'disponível')"
fi

# 4. Aplicativos adicionais mapeados da máquina (Browsers, Insync, Ayugram)
if [ -n "$AUR_HELPER" ]; then
    log_info "Instalando navegadores e ferramentas mapeadas via $AUR_HELPER..."
    $AUR_HELPER -S --needed --noconfirm \
        google-chrome \
        microsoft-edge-stable-bin \
        opera \
        ayugram-desktop-bin \
        insync \
        insync-dolphin \
        ttf-jetbrains-mono-nerd \
        ttf-fira-code || true
    log_success "Aplicativos de produtividade sincronizados!"
fi

log_success "Etapa 03 concluída com sucesso!"
