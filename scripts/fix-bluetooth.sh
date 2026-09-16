#!/usr/bin/env bash
# ==============================================================================
# Script: fix-bluetooth.sh
# Descrição: Cria ponto de restauração Timeshift e aplica correções de Bluetooth
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/utils.sh"

log_section "Correção de Bluetooth (Realtek RTL8822CE & Fones Thinkplus)"

# 1. Ponto de Restauração via Timeshift
log_info "1/5 - Criando ponto de restauração (Timeshift)..."
if command -v timeshift &>/dev/null; then
    sudo timeshift --create --comments "Antes_Ajuste_Bluetooth_Thinkplus" --tags D --scripted || {
        log_warn "Aviso: Timeshift retornou código diferente de 0, continuando com cautela..."
    }
    log_success "Ponto de restauração processado com sucesso!"
else
    log_warn "Timeshift não encontrado, pulando criação de snapshot."
fi

# 2. Configuração de Módulo do Kernel (Realtek btusb + rtw88_core)
log_info "2/5 - Aplicando configurações de economia de energia no Kernel..."
sudo cp "$ROOT_DIR/configs/system/bluetooth-realtek.conf" /etc/modprobe.d/bluetooth-realtek.conf
log_success "Arquivo /etc/modprobe.d/bluetooth-realtek.conf instalado!"

# 3. Configurações do BlueZ (/etc/bluetooth/main.conf)
log_info "3/5 - Ajustando parâmetros do BlueZ (/etc/bluetooth/main.conf)..."
if [ -f /etc/bluetooth/main.conf ]; then
    sudo cp /etc/bluetooth/main.conf "/etc/bluetooth/main.conf.bak.$(date +%s)"
    sudo sed -i 's/^#\?JustWorksRepairing.*/JustWorksRepairing = always/' /etc/bluetooth/main.conf
    sudo sed -i 's/^#\?FastConnectable.*/FastConnectable = true/' /etc/bluetooth/main.conf
    sudo sed -i 's/^#\?AutoEnable.*/AutoEnable = true/' /etc/bluetooth/main.conf
    log_success "Configurações do BlueZ atualizadas com sucesso!"
fi

# 4. Configurações do WirePlumber (Áudio Bluetooth)
log_info "4/5 - Ajustando regras do WirePlumber para priorizar A2DP..."
sudo mkdir -p /etc/wireplumber/wireplumber.conf.d/
sudo cp "$ROOT_DIR/configs/system/51-bluez-config.conf" /etc/wireplumber/wireplumber.conf.d/51-bluez-config.conf
log_success "Regra do WirePlumber aplicada com sucesso!"

# 5. Limpeza de dispositivos Thinkplus antigos e reinício de serviços
log_info "5/5 - Limpando pareamentos antigos e reiniciando serviços..."
bluetoothctl remove 41:42:5B:C2:96:36 2>/dev/null || true
bluetoothctl remove 41:42:ED:3D:E4:FC 2>/dev/null || true

sudo systemctl restart bluetooth

# Reinicia pipewire e wireplumber para o usuário real que chamou o sudo
if [ -n "${SUDO_USER:-}" ]; then
    TARGET_UID=$(id -u "$SUDO_USER")
    sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$TARGET_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" systemctl --user restart pipewire wireplumber || true
else
    systemctl --user restart pipewire wireplumber 2>/dev/null || true
fi

log_success "🎉 Todas as correções foram aplicadas com sucesso!"
echo -e "\n${COLOR_BOLD}${COLOR_GREEN}Pronto para parear:${COLOR_RESET}"
echo -e "1. Retire os fones da caixinha ao mesmo tempo."
echo -e "2. No BigLinux, abra o painel de Bluetooth e conecte ao seu fone Thinkplus."
