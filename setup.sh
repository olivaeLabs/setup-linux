#!/usr/bin/env bash
# ==============================================================================
# Script: setup.sh (Master Entrypoint)
# Descrição: Orquestrador interativo do Setup Imortal
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib/utils.sh"

run_all() {
    log_section "Iniciando Instalação Completa do Setup Imortal"
    "$SCRIPT_DIR/scripts/00-system-init.sh"
    "$SCRIPT_DIR/scripts/01-hardware-gpu.sh"
    "$SCRIPT_DIR/scripts/02-cli-tools.sh"
    "$SCRIPT_DIR/scripts/03-gui-apps.sh"
    "$SCRIPT_DIR/scripts/04-dev-runtimes.sh"
    "$SCRIPT_DIR/scripts/05-dotfiles-sync.sh"
    "$SCRIPT_DIR/scripts/99-snapshot.sh"
    "$SCRIPT_DIR/tests/check-environment.sh"
    log_success "🎉 Configuração completa do Setup Imortal finalizada com sucesso!"
}

show_menu() {
    clear
    echo -e "${COLOR_BOLD}${COLOR_CYAN}"
    echo "  ███████╗███████╗████████╗██╗   ██╗██████╗     ██╗███╗   ███╗ ██████╗ ██████╗ ████████╗ █████╗ ██╗     "
    echo "  ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗    ██║████╗ ████║██╔═══██╗██╔══██╗╚══██╔══╝██╔══██╗██║     "
    echo "  ███████╗█████╗     ██║   ██║   ██║██████╔╝    ██║██╔████╔██║██║   ██║██████╔╝   ██║   ███████║██║     "
    echo "  ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝     ██║██║╚██╔╝██║██║   ██║██╔══██╗   ██║   ██╔══██║██║     "
    echo "  ███████║███████╗   ██║   ╚██████╔╝██║         ██║██║ ╚═╝ ██║╚██████╔╝██║  ██║   ██║   ██║  ██║███████╗"
    echo "  ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝         ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚══════╝"
    echo -e "${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_BLUE}    Setup Imortal para Linux (Arch / BigLinux / Manjaro) - Inspirado em Fabio Akita${COLOR_RESET}\n"

    echo -e "${COLOR_BOLD}Escolha uma opção:${COLOR_RESET}"
    echo -e "  ${COLOR_GREEN}[1]${COLOR_RESET} Instalação Completa (Tudo)"
    echo -e "  ${COLOR_CYAN}[2]${COLOR_RESET} Otimizações de Sistema e AUR (00-system-init.sh)"
    echo -e "  ${COLOR_CYAN}[3]${COLOR_RESET} Hardware, GPU Híbrida e Swap (01-hardware-gpu.sh)"
    echo -e "  ${COLOR_CYAN}[4]${COLOR_RESET} Ferramentas CLI & GitHub CLI (02-cli-tools.sh)"
    echo -e "  ${COLOR_CYAN}[5]${COLOR_RESET} Aplicativos Gráficos, VS Code & JetBrains (03-gui-apps.sh)"
    echo -e "  ${COLOR_CYAN}[6]${COLOR_RESET} Runtimes de Dev, Node & Docker (04-dev-runtimes.sh)"
    echo -e "  ${COLOR_CYAN}[7]${COLOR_RESET} Sincronizar Dotfiles / Symlinks (05-dotfiles-sync.sh)"
    echo -e "  ${COLOR_YELLOW}[8]${COLOR_RESET} Snapshot do Sistema Atual (99-snapshot.sh)"
    echo -e "  ${COLOR_MAGENTA}[9]${COLOR_RESET} Diagnóstico do Ambiente (check-environment.sh)"
    echo -e "  ${COLOR_RED}[0]${COLOR_RESET} Sair\n"
    read -r -p "Digite a opção desejada [0-9]: " choice
    echo ""

    case "$choice" in
        1) run_all ;;
        2) "$SCRIPT_DIR/scripts/00-system-init.sh" ;;
        3) "$SCRIPT_DIR/scripts/01-hardware-gpu.sh" ;;
        4) "$SCRIPT_DIR/scripts/02-cli-tools.sh" ;;
        5) "$SCRIPT_DIR/scripts/03-gui-apps.sh" ;;
        6) "$SCRIPT_DIR/scripts/04-dev-runtimes.sh" ;;
        7) "$SCRIPT_DIR/scripts/05-dotfiles-sync.sh" ;;
        8) "$SCRIPT_DIR/scripts/99-snapshot.sh" ;;
        9) "$SCRIPT_DIR/tests/check-environment.sh" ;;
        0) echo -e "${COLOR_GREEN}Até mais!${COLOR_RESET}"; exit 0 ;;
        *) log_error "Opção inválida!"; exit 1 ;;
    esac
}

# Tratamento de argumentos por linha de comando
if [ $# -gt 0 ]; then
    case "$1" in
        --all|-a) run_all ;;
        --check|-c) "$SCRIPT_DIR/tests/check-environment.sh" ;;
        --snapshot|-s) "$SCRIPT_DIR/scripts/99-snapshot.sh" ;;
        --dotfiles|-d) "$SCRIPT_DIR/scripts/05-dotfiles-sync.sh" ;;
        --help|-h)
            echo "Uso: ./setup.sh [OPÇÃO]"
            echo "Opções:"
            echo "  --all, -a        Executa todas as etapas sequencialmente"
            echo "  --check, -c      Executa diagnóstico do ambiente"
            echo "  --snapshot, -s   Gera snapshot dos pacotes instalados"
            echo "  --dotfiles, -d   Sincroniza apenas os dotfiles"
            echo "  --help, -h       Exibe esta ajuda"
            exit 0
            ;;
        *)
            log_error "Opção desconhecida: $1. Use --help para ver as opções."
            exit 1
            ;;
    esac
else
    show_menu
fi
