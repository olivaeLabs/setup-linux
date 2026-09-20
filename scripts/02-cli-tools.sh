#!/usr/bin/env bash
# ==============================================================================
# Script: 02-cli-tools.sh
# Descrição: Instalação de utilitários modernos de terminal (CLI) e GitHub CLI
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

log_section "02 - Utilitários Modernos de Terminal (CLI)"

# 1. Instalar GitHub CLI (gh)
if ! command -v gh &>/dev/null; then
    log_info "Instalando GitHub CLI (gh)..."
    if sudo pacman -S --needed --noconfirm github-cli 2>/dev/null; then
        log_success "GitHub CLI instalado via pacman."
    else
        log_info "Instalando GitHub CLI via binário oficial..."
        GH_TAG=$(curl -s "https://api.github.com/repos/cli/cli/releases/latest" | jq -r '.tag_name')
        GH_VER="${GH_TAG#v}"
        mkdir -p ~/.local/bin
        curl -sL "https://github.com/cli/cli/releases/download/${GH_TAG}/gh_${GH_VER}_linux_amd64.tar.gz" | tar -xz -C /tmp/
        cp "/tmp/gh_${GH_VER}_linux_amd64/bin/gh" ~/.local/bin/gh
        chmod +x ~/.local/bin/gh
        rm -rf "/tmp/gh_${GH_VER}_linux_amd64"
        log_success "GitHub CLI instalado em ~/.local/bin/gh."
    fi
else
    log_success "GitHub CLI já instalado: $(gh --version | head -n1)"
fi

# 2. Pacotes CLI Essenciais via pacman
CLI_PKGS=(
    git
    curl
    wget
    jq
    bat
    eza
    fzf
    ripgrep
    zoxide
    htop
    btop
    tmux
    zellij
    unzip
    zip
    rsync
    starship
    zsh
    opencode
)

log_info "Instalando utilitários de terminal essenciais..."
sudo pacman -S --needed --noconfirm "${CLI_PKGS[@]}" || true

log_success "Etapa 02 concluída com sucesso!"
