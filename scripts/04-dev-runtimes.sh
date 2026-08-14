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

# 5. Antigravity CLI (agy)
if command -v agy &>/dev/null; then
    log_success "Antigravity CLI (agy) detectado: $(which agy)"
fi

log_success "Etapa 04 concluída com sucesso!"
