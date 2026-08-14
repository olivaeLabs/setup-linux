#!/usr/bin/env bash
# ==============================================================================
# Script: 99-snapshot.sh
# Descrição: Mapeia e exporta o estado atual do sistema para os arquivos de pacotes
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PACKAGES_DIR="$ROOT_DIR/packages"
CONFIGS_DIR="$ROOT_DIR/configs"

mkdir -p "$PACKAGES_DIR" "$CONFIGS_DIR/vscode"

echo -e "\033[1;34m[INFO]\033[0m Iniciando snapshot do sistema..."

# 1. Pacotes Oficiais Nativos (pacman)
if command -v pacman &>/dev/null; then
    echo -e "\033[1;36m[PACMAN]\033[0m Mapeando pacotes explicitamente instalados (nativos)..."
    pacman -Qenq | sort -u > "$PACKAGES_DIR/pacman-all-installed.txt"
    echo "  -> Salvo em $PACKAGES_DIR/pacman-all-installed.txt ($(wc -l < "$PACKAGES_DIR/pacman-all-installed.txt") pacotes)"
fi

# 2. Pacotes AUR / Estrangeiros
if command -v pacman &>/dev/null; then
    echo -e "\033[1;36m[AUR]\033[0m Mapeando pacotes AUR/estrangeiros instalados..."
    pacman -Qemq | sort -u > "$PACKAGES_DIR/aur-packages.txt"
    echo "  -> Salvo em $PACKAGES_DIR/aur-packages.txt ($(wc -l < "$PACKAGES_DIR/aur-packages.txt") pacotes)"
fi

# 3. Flatpaks
if command -v flatpak &>/dev/null; then
    echo -e "\033[1;36m[FLATPAK]\033[0m Mapeando Flatpaks instalados..."
    flatpak list --app --columns=application | sort -u > "$PACKAGES_DIR/flatpaks.txt" 2>/dev/null || true
    echo "  -> Salvo em $PACKAGES_DIR/flatpaks.txt ($(wc -l < "$PACKAGES_DIR/flatpaks.txt") flatpaks)"
fi

# 4. Extensões do VS Code
if command -v code &>/dev/null; then
    echo -e "\033[1;36m[VSCODE]\033[0m Mapeando extensões do VS Code..."
    code --list-extensions | sort -u > "$CONFIGS_DIR/vscode/extensions.txt" 2>/dev/null || true
    echo "  -> Salvo em $CONFIGS_DIR/vscode/extensions.txt"
fi

echo -e "\033[1;32m[SUCESSO]\033[0m Snapshot concluído com sucesso!"
