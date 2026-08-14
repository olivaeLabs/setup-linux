#!/usr/bin/env bash
# ==============================================================================
# Script: 99-snapshot.sh
# Descrição: Mapeia apenas as customizações e pacotes do usuário no BigLinux
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PACKAGES_DIR="$ROOT_DIR/packages"
CONFIGS_DIR="$ROOT_DIR/configs"

mkdir -p "$PACKAGES_DIR" "$CONFIGS_DIR/vscode"

echo -e "\033[1;34m[INFO]\033[0m Iniciando snapshot das customizações pós-BigLinux..."

# 1. Pacotes AUR e Manuais (Google Chrome, Edge, Ayugram, Antigravity, etc.)
if command -v pacman &>/dev/null; then
    echo -e "\033[1;36m[AUR]\033[0m Mapeando pacotes AUR e manuais do usuário..."
    pacman -Qemq | sort -u > "$PACKAGES_DIR/user-aur-packages.txt"
    echo "  -> Salvo em $PACKAGES_DIR/user-aur-packages.txt ($(wc -l < "$PACKAGES_DIR/user-aur-packages.txt") pacotes)"
fi

# 2. Flatpaks do Usuário
if command -v flatpak &>/dev/null; then
    echo -e "\033[1;36m[FLATPAK]\033[0m Mapeando Flatpaks instalados..."
    flatpak list --app --columns=application 2>/dev/null | sort -u > "$PACKAGES_DIR/flatpaks.txt" || true
    echo "  -> Salvo em $PACKAGES_DIR/flatpaks.txt ($(wc -l < "$PACKAGES_DIR/flatpaks.txt") flatpaks)"
fi

# 3. Extensões do VS Code
if command -v code &>/dev/null; then
    echo -e "\033[1;36m[VSCODE]\033[0m Mapeando extensões do VS Code..."
    code --list-extensions 2>/dev/null | sort -u > "$CONFIGS_DIR/vscode/extensions.txt" || true
    echo "  -> Salvo em $CONFIGS_DIR/vscode/extensions.txt"
fi

echo -e "\033[1;32m[SUCESSO]\033[0m Snapshot pós-BigLinux concluído!"
