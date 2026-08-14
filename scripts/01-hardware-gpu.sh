#!/usr/bin/env bash
# ==============================================================================
# Script: 01-hardware-gpu.sh
# Descrição: Configurações de GPU híbrida (Intel + Nvidia Bumblebee 390xx) e Swap
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

log_section "01 - Hardware, Drivers de Vídeo (Bumblebee) e Swap"

# 1. Configuração de Vídeo Híbrido (Intel Ivy Bridge + Nvidia GT 740M 390xx)
if lspci | grep -qi "nvidia"; then
    log_info "Placa de vídeo NVIDIA detectada no barramento PCI."
    
    # Se estiver em Manjaro/BigLinux, pode usar mhwd
    if command -v mhwd &>/dev/null; then
        log_info "Instalando driver híbrido via mhwd..."
        sudo mhwd -i pci video-hybrid-intel-nvidia-390xx-bumblebee --nonfree || true
    else
        log_info "Instalando stack Bumblebee + Nvidia 390xx via pacman/AUR..."
        sudo pacman -S --needed --noconfirm bumblebee bbswitch virtualgl primus || true
    fi

    # Adiciona o usuário atual ao grupo bumblebee
    log_info "Adicionando usuário $USER ao grupo bumblebee..."
    sudo gpasswd -a "$USER" bumblebee || true

    # Configuração de BusID se existir /etc/bumblebee/xorg.conf.nvidia
    if [ -f /etc/bumblebee/xorg.conf.nvidia ]; then
        if ! grep -q "BusID" /etc/bumblebee/xorg.conf.nvidia; then
            log_info "Configurando BusID da GPU em /etc/bumblebee/xorg.conf.nvidia..."
            sudo sed -i '/VendorName "NVIDIA Corporation"/a \    BusID       "PCI:01:00:0"' /etc/bumblebee/xorg.conf.nvidia
        fi
    fi

    # Habilita serviço do bumblebee
    sudo systemctl enable bumblebeed.service 2>/dev/null || true
    log_success "Configuração do Bumblebee concluída!"
else
    log_info "Nenhuma GPU Nvidia detectada ou configuração não necessária."
fi

# 2. Configuração de Swap em Disco Secundário (se houver)
SWAP_UUID="5b59608a-773c-44ae-8407-24342edd3d60"
if blkid | grep -q "$SWAP_UUID"; then
    log_info "Partição de swap secundária detectada (UUID: $SWAP_UUID)."
    if ! grep -q "$SWAP_UUID" /etc/fstab; then
        log_info "Adicionando swap de alta prioridade (pri=10) ao /etc/fstab..."
        echo "UUID=$SWAP_UUID none swap defaults,pri=10 0 0" | sudo tee -a /etc/fstab
    fi
    sudo swapon -a 2>/dev/null || true
    log_success "Swap configurada com sucesso!"
fi

log_success "Etapa 01 concluída com sucesso!"
