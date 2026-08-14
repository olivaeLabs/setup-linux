#!/usr/bin/env bash
# ==============================================================================
# Script: 00-system-init.sh
# Descrição: Otimização de Pacman, SSD (fstrim), limpeza de serviços de boot e AUR helper
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

log_section "00 - Inicialização e Otimização do Sistema"

# 1. Configurações de performance e usabilidade no pacman.conf
if [ -f /etc/pacman.conf ]; then
    log_info "Otimizando /etc/pacman.conf (Color, ParallelDownloads, ILoveCandy)..."
    sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
    sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
    if ! grep -q "ILoveCandy" /etc/pacman.conf; then
        sudo sed -i '/Color/a ILoveCandy' /etc/pacman.conf
    fi
    log_success "pacman.conf otimizado!"
fi

# 2. Verificação / Instalação do AUR Helper (yay ou paru)
AUR_HELPER=$(get_aur_helper)
if [ -z "$AUR_HELPER" ]; then
    log_info "Nenhum AUR helper detectado. Instalando 'yay'..."
    sudo pacman -S --needed --noconfirm base-devel git
    git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
    (cd /tmp/yay-bin && makepkg -si --noconfirm)
    rm -rf /tmp/yay-bin
    log_success "yay instalado com sucesso!"
else
    log_success "AUR Helper detectado: $AUR_HELPER"
fi

# 3. Otimização de SSD: Ativar fstrim.timer
log_info "Ativando fstrim.timer para manutenção automática de SSDs..."
sudo systemctl enable --now fstrim.timer || true
log_success "fstrim.timer configurado!"

# 4. Desativar serviços desnecessários para acelerar o boot
log_info "Desativando serviços lentos/desnecessários no boot..."
sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
sudo systemctl disable ModemManager.service 2>/dev/null || true
log_success "Serviços de boot otimizados!"

log_success "Etapa 00 concluída com sucesso!"
