#!/usr/bin/env bash
# ==============================================================================
# Script: lib/utils.sh
# Descrição: Funções utilitárias e cores compartilhadas entre os scripts
# ==============================================================================

# Cores ANSI
export COLOR_RESET="\033[0m"
export COLOR_BOLD="\033[1m"
export COLOR_RED="\033[1;31m"
export COLOR_GREEN="\033[1;32m"
export COLOR_YELLOW="\033[1;33m"
export COLOR_BLUE="\033[1;34m"
export COLOR_MAGENTA="\033[1;35m"
export COLOR_CYAN="\033[1;36m"
export COLOR_GRAY="\033[0;90m"

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCESSO]${COLOR_RESET} $1"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[AVISO]${COLOR_RESET} $1"
}

log_error() {
    echo -e "${COLOR_RED}[ERRO]${COLOR_RESET} $1"
}

log_section() {
    echo -e "\n${COLOR_BOLD}${COLOR_CYAN}======================================================${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}▶ $1${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}======================================================${COLOR_RESET}\n"
}

# Detecta AUR Helper disponível (yay, paru ou instala yay)
get_aur_helper() {
    if command -v yay &>/dev/null; then
        echo "yay"
    elif command -v paru &>/dev/null; then
        echo "paru"
    else
        echo ""
    fi
}

# Pergunta confirmação com padrão Sim/Não
confirm() {
    local prompt="${1:-Tem certeza que deseja continuar?} [s/N]: "
    read -r -p "$prompt" response
    case "$response" in
        [sS][iI][mM]|[sS]|[yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
