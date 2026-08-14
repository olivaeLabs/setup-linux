#!/usr/bin/env bash
# ==============================================================================
# Script: 05-dotfiles-sync.sh
# Descrição: Sincronização segura de arquivos de configuração (Dotfiles) via symlinks
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIGS_DIR="$ROOT_DIR/configs"
source "$SCRIPT_DIR/lib/utils.sh"

log_section "05 - Sincronização de Dotfiles e Configurações"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

link_file() {
    local src="$1"
    local dest="$2"

    if [ ! -f "$src" ]; then
        log_warn "Arquivo de origem não encontrado: $src (pulando)"
        return 0
    fi

    # Garante que o diretório pai do destino existe
    mkdir -p "$(dirname "$dest")"

    # Se já é o symlink correto, não faz nada
    if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
        log_info "Symlink já atualizado: $dest -> $src"
        return 0
    fi

    # Se existe um arquivo real no destino, faz backup antes
    if [ -f "$dest" ] || [ -L "$dest" ]; then
        local backup="${dest}.bak.${TIMESTAMP}"
        log_warn "Arquivo existente encontrado em $dest. Criando backup em $backup..."
        mv "$dest" "$backup"
    fi

    ln -sf "$src" "$dest"
    log_success "Link criado: $dest -> $src"
}

# 1. Aliases do Bash
link_file "$CONFIGS_DIR/bash/.bash_aliases" "$HOME/.bash_aliases"
if [ -f "$HOME/.bashrc" ] && ! grep -q "\.bash_aliases" "$HOME/.bashrc"; then
    log_info "Adicionando carregamento do .bash_aliases ao ~/.bashrc..."
    echo -e "\n# Carregar aliases personalizados do Setup Imortal\n[ -f ~/.bash_aliases ] && source ~/.bash_aliases" >> "$HOME/.bashrc"
fi

# 2. Configurações do Git
link_file "$CONFIGS_DIR/git/.gitconfig" "$HOME/.gitconfig"
link_file "$CONFIGS_DIR/git/.gitignore_global" "$HOME/.gitignore_global"

# 3. Configurações do VS Code
link_file "$CONFIGS_DIR/vscode/settings.json" "$HOME/.config/Code/User/settings.json"

log_success "Etapa 05 concluída com sucesso!"
