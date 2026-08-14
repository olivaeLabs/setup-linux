#!/usr/bin/env bash
# ==============================================================================
# Script: check-environment.sh
# Descrição: Diagnóstico completo do ambiente do Setup Imortal
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/scripts/lib/utils.sh"

echo -e "\n${COLOR_BOLD}${COLOR_MAGENTA}======================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_MAGENTA}🔍 Diagnóstico do Ambiente - Setup Imortal${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_MAGENTA}======================================================${COLOR_RESET}\n"

check_cmd() {
    local name="$1"
    local cmd="$2"
    local version_cmd="${3:-$cmd --version}"

    if command -v "$cmd" &>/dev/null; then
        local ver
        ver=$(eval "$version_cmd" 2>&1 | head -n 1)
        printf "  %-22s : ${COLOR_GREEN}✔ INSTALADO${COLOR_RESET}  ${COLOR_GRAY}(%s)${COLOR_RESET}\n" "$name" "$ver"
    else
        printf "  %-22s : ${COLOR_RED}✘ AUSENTE${COLOR_RESET}\n" "$name"
    fi
}

echo -e "${COLOR_BOLD}${COLOR_CYAN}▶ Ferramentas Solicitadas:${COLOR_RESET}"
check_cmd "GitHub CLI (gh)" "gh" "gh --version"
check_cmd "VS Code (code)" "code" "code --version"
check_cmd "JetBrains Toolbox" "jetbrains-toolbox" "jetbrains-toolbox --version || echo 'OK'"

echo -e "\n${COLOR_BOLD}${COLOR_CYAN}▶ Ferramentas de Desenvolvimento:${COLOR_RESET}"
check_cmd "Git" "git" "git --version"
check_cmd "GCC" "gcc" "gcc --version"
check_cmd "Python 3" "python" "python --version"
check_cmd "Node.js" "node" "node --version"
check_cmd "FNM" "fnm" "fnm --version"
check_cmd "Docker" "docker" "docker --version"
check_cmd "Antigravity (agy)" "agy" "agy --version || echo 'OK'"

echo -e "\n${COLOR_BOLD}${COLOR_CYAN}▶ Utilitários de Terminal Modernos:${COLOR_RESET}"
check_cmd "Bat (cat moderno)" "bat" "bat --version"
check_cmd "Eza (ls moderno)" "eza" "eza --version"
check_cmd "Ripgrep (grep)" "rg" "rg --version"
check_cmd "Zoxide" "zoxide" "zoxide --version"
check_cmd "FZF" "fzf" "fzf --version"
check_cmd "Starship Prompt" "starship" "starship --version"

echo -e "\n${COLOR_BOLD}${COLOR_CYAN}▶ Sistema e Hardware:${COLOR_RESET}"
check_cmd "AUR Helper (yay)" "yay" "yay --version"
check_cmd "Bumblebee / Optirun" "optirun" "optirun --version || echo 'Bumblebee daemon'"

echo -e "\n${COLOR_BOLD}${COLOR_CYAN}▶ Dotfiles e Symlinks:${COLOR_RESET}"
for link in "$HOME/.bash_aliases" "$HOME/.gitconfig" "$HOME/.gitignore_global" "$HOME/.config/Code/User/settings.json"; do
    if [ -L "$link" ]; then
        printf "  %-32s : ${COLOR_GREEN}✔ SYMLINK ATIVO${COLOR_RESET} -> %s\n" "$link" "$(readlink -f "$link")"
    elif [ -f "$link" ]; then
        printf "  %-32s : ${COLOR_YELLOW}⚠ ARQUIVO LOCAL (não linkado)${COLOR_RESET}\n" "$link"
    else
        printf "  %-32s : ${COLOR_GRAY}NÃO CRIADO${COLOR_RESET}\n" "$link"
    fi
done

echo -e "\n${COLOR_BOLD}${COLOR_MAGENTA}======================================================${COLOR_RESET}\n"
