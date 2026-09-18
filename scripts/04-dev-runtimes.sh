#!/usr/bin/env bash
# ==============================================================================
# Script: 04-dev-runtimes.sh
# Descrição: Instalação de SDKs, runtimes de desenvolvimento (Node, Python, Docker, etc.)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

log_section "04 - Runtimes de Desenvolvimento e SDKs"

# 1. Compilação Base (base-devel, gcc, make, cmake)
log_info "Instalando ferramentas de compilação C/C++..."
sudo pacman -S --needed --noconfirm base-devel gcc gdb make cmake || true
log_success "Compiladores base configurados!"

# 2. Fast Node Manager (FNM) / Node.js
if ! command -v fnm &>/dev/null && [ ! -f "$HOME/.local/share/fnm/fnm" ]; then
    log_info "Instalando Fast Node Manager (fnm)..."
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell || true
    export PATH="$HOME/.local/share/fnm:$PATH"
    if command -v fnm &>/dev/null; then
        fnm install --lts || true
        fnm default lts-latest || true
    fi
    log_success "FNM / Node.js configurado!"
else
    log_success "FNM já está instalado."
fi

# 3. Python 3 & pip
log_info "Verificando ambiente Python 3..."
sudo pacman -S --needed --noconfirm python python-pip python-virtualenv || true
log_success "Python 3 configurado!"

# 4. Docker & Docker Compose
if ! command -v docker &>/dev/null; then
    log_info "Instalando Docker e Docker Compose..."
    sudo pacman -S --needed --noconfirm docker docker-compose || true
    sudo systemctl enable docker.service || true
    sudo usermod -aG docker "$USER" || true
    log_success "Docker instalado e usuário adicionado ao grupo 'docker'!"
else
    log_success "Docker já está instalado: $(docker --version)"
fi

# 5. Java / SDKMAN (Java 21 LTS Padronizado)
if [ ! -d "$HOME/.sdkman" ]; then
    log_info "Instalando SDKMAN!..."
    curl -s "https://get.sdkman.io" | bash || true
    [ -f "$HOME/.sdkman/etc/config" ] && sed -i 's/sdkman_auto_answer=false/sdkman_auto_answer=true/' "$HOME/.sdkman/etc/config"
fi

if [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    if ! command -v java &>/dev/null; then
        log_info "Instalando Java 21 LTS via SDKMAN..."
        sdk install java 21.0.12+1.1-tem || true
        sdk default java 21.0.12+1.1-tem || true
    fi
    log_success "SDKMAN / Java configurado: $(java -version 2>&1 | head -n 1)"
fi

# 6. Android SDK & CLI
if [ ! -f "$HOME/.local/bin/android" ]; then
    log_info "Instalando Google Android CLI..."
    curl -fsSL https://dl.google.com/android/cli/latest/linux_x86_64/install.sh | bash || true
fi

if [ -d "$HOME/Android/Sdk/cmdline-tools/latest/bin" ]; then
    for tool in "$HOME/Android/Sdk/cmdline-tools/latest/bin/"*; do
        [ -f "$tool" ] && ln -sf "$tool" "$HOME/.local/bin/$(basename "$tool")"
    done
    log_success "Android SDK cmdline-tools vinculados em ~/.local/bin"
fi

# 7. Antigravity CLI (agy)
if command -v agy &>/dev/null; then
    log_success "Antigravity CLI (agy) detectado: $(which agy)"
fi

log_success "Etapa 04 concluída com sucesso!"

