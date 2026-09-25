#!/usr/bin/env bash
# ==============================================================================
# Script: 09-ssh-access.sh
# Descrição: Acesso remoto SSH — habilita o servidor (sshd), gera a chave do
#            usuário (opcional) e, no WSL, garante a regra de firewall Hyper-V
#            para ingresso via LAN no modo mirrored.
# Uso:
#   ./scripts/09-ssh-access.sh                # habilita/inicia o sshd no Linux atual
#   ./scripts/09-ssh-access.sh --gen-key      # também gera ~/.ssh/id_ed25519 (se ausente)
#   ./scripts/09-ssh-access.sh --wsl-firewall # no WSL: cria a regra Hyper-V (UAC) se ausente
#   ./scripts/09-ssh-access.sh --show         # mostra estado atual
#   ./scripts/09-ssh-access.sh --help
# Referência: knowledge/SSH-REMOTE-ACCESS.md
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/utils.sh
if [ -f "$SCRIPT_DIR/lib/utils.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/utils.sh"
fi

SSH_PORT="${SSH_PORT:-22}"
WSL_FW_RULE="${WSL_FW_RULE:-WSL-SSH-In}"
# VM Creator ID fixo do WSL (ver knowledge/SSH-REMOTE-ACCESS.md)
WSL_VM_GUID='{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'
WSL_FW_REMOTE="${WSL_FW_REMOTE:-LocalSubnet}"

log()  { echo "[ssh-access] $*"; }
warn() { echo "[ssh-access] AVISO: $*" >&2; }
fail() { echo "[ssh-access] ERRO: $*" >&2; exit 1; }

is_wsl() {
    grep -qiE "microsoft|wsl" /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]
}

use_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        fail "esta etapa exige root (ou sudo disponível)"
    fi
}

ensure_sshd() {
    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemctl indisponível; habilite o sshd manualmente."
        return 0
    fi
    if ! command -v sshd >/dev/null 2>&1; then
        warn "sshd não encontrado. Instale o OpenSSH (ex.: sudo pacman -S openssh) e rode novamente."
        return 0
    fi
    log "habilitando/iniciando o servidor SSH (sshd)..."
    if use_sudo systemctl enable --now sshd >/dev/null 2>&1; then
        log "sshd: ativo (porta ${SSH_PORT})"
    else
        warn "não foi possível habilitar o sshd via systemd; verifique manualmente."
    fi
}

ensure_user_key() {
    local key="$HOME/.ssh/id_ed25519"
    if [ -f "$key" ]; then
        log "chave do usuário já existe: $key"
        return 0
    fi
    log "gerando chave ed25519 do usuário (sem passphrase)..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -N '' -C "$(id -un)@$(hostname 2>/dev/null || echo linux)" -f "$key" </dev/null >/dev/null
    chmod 600 "$key"
    chmod 644 "$key.pub"
    log "chave criada: $key — autorize-a no destino com: ssh-copy-id <usuário>@<host>"
}

wsl_windows_path() { # C:\Users\x -> /mnt/c/Users/x
    local drive
    drive="$(printf '%s' "$1" | sed -E 's#^([A-Za-z]):.*#\L\1#')"
    printf '/mnt/%s/%s' "$drive" "$(printf '%s' "$1" | sed -E 's#^[A-Za-z]:\\##; s#\\#/#g')"
}

wsl_firewall_rule_exists() {
    command -v powershell.exe >/dev/null 2>&1 || return 2
    powershell.exe -NoProfile -Command "Get-NetFirewallHyperVRule -Name '$WSL_FW_RULE' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Name" 2>/dev/null | tr -d '\r' | grep -q .
}

wsl_firewall_manual() {
    cat <<EOF

  Aplique manualmente no Windows (PowerShell COMO ADMINISTRADOR):
    New-NetFirewallHyperVRule -Name '$WSL_FW_RULE' -DisplayName 'WSL SSH Inbound (TCP ${SSH_PORT})' -Direction Inbound -VMCreatorId '$WSL_VM_GUID' -Protocol TCP -LocalPorts ${SSH_PORT} -RemoteAddresses ${WSL_FW_REMOTE} -Action Allow

  Depois teste de outro PC da LAN:  ssh <usuário>@<IP-do-Windows>
  Detalhes: knowledge/SSH-REMOTE-ACCESS.md

EOF
}

wsl_firewall_apply() {
    if ! command -v powershell.exe >/dev/null 2>&1; then
        warn "powershell.exe indisponível (interop do WSL desligado?)"
        wsl_firewall_manual
        return 0
    fi
    if wsl_firewall_rule_exists; then
        log "regra de firewall já existe: $WSL_FW_RULE"
        return 0
    fi

    local win_tmp ps1_file
    win_tmp="$(cmd.exe /c 'echo %TEMP%' 2>/dev/null | tr -d '\r' || true)"
    if [ -z "$win_tmp" ]; then
        warn "não foi possível obter %TEMP% do Windows"
        wsl_firewall_manual
        return 0
    fi
    ps1_file="$(wsl_windows_path "$win_tmp")/setup-imortal-wsl-ssh.ps1"

    if ! cat > "$ps1_file" <<EOF
New-NetFirewallHyperVRule -Name '$WSL_FW_RULE' -DisplayName 'WSL SSH Inbound (TCP ${SSH_PORT})' -Direction Inbound -VMCreatorId '$WSL_VM_GUID' -Protocol TCP -LocalPorts ${SSH_PORT} -RemoteAddresses ${WSL_FW_REMOTE} -Action Allow | Out-Null
EOF
    then
        warn "sem permissão para escrever em $ps1_file"
        wsl_firewall_manual
        return 0
    fi

    log "solicitando elevação (UAC) para criar a regra no Hyper-V firewall..."
    if ! powershell.exe -NoProfile -Command "Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','${win_tmp}\\setup-imortal-wsl-ssh.ps1'" 2>/dev/null; then
        warn "elevação cancelada ou falhou"
        rm -f "$ps1_file"
        wsl_firewall_manual
        return 0
    fi
    rm -f "$ps1_file"

    if wsl_firewall_rule_exists; then
        log "regra criada com sucesso: $WSL_FW_RULE (TCP ${SSH_PORT}, ${WSL_FW_REMOTE})"
    else
        warn "regra ainda não visível após a execução"
        wsl_firewall_manual
    fi
}

show_state() {
    echo "== servidor SSH =="
    echo "sshd: $(systemctl is-active sshd 2>/dev/null || echo inativo) / $(systemctl is-enabled sshd 2>/dev/null || echo '?')"
    echo "== porta ${SSH_PORT} =="
    ss -tln 2>/dev/null | grep -E ":${SSH_PORT}[[:space:]]" || echo "(sem listener na porta ${SSH_PORT})"
    echo "== chave do usuário =="
    if [ -f "$HOME/.ssh/id_ed25519" ]; then echo "OK: ~/.ssh/id_ed25519"; else echo "(ausente — use --gen-key)"; fi
    if [ -s "$HOME/.ssh/authorized_keys" ]; then
        echo "OK: ~/.ssh/authorized_keys ($(wc -l < "$HOME/.ssh/authorized_keys") chave(s))"
    else
        echo "(sem authorized_keys — troque chaves com ssh-copy-id)"
    fi
    if is_wsl; then
        echo "== WSL (mirrored) =="
        echo "IP global: $(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2"="$4}' | paste -sd' ' -)"
        if wsl_firewall_rule_exists; then
            echo "firewall Hyper-V: OK ($WSL_FW_RULE)"
        else
            echo "firewall Hyper-V: regra ausente (use --wsl-firewall)"
        fi
    fi
}

main() {
    local gen_key="no" fw="no" mode="apply"
    while [ $# -gt 0 ]; do
        case "$1" in
            --gen-key) gen_key="yes" ;;
            --wsl-firewall) fw="yes" ;;
            --show) mode="show" ;;
            --help|-h)
                cat <<'USAGE'
Uso: ./scripts/09-ssh-access.sh [opções]
  (sem opções)       habilita/inicia o sshd no Linux atual
  --gen-key          também gera ~/.ssh/id_ed25519 (se ausente)
  --wsl-firewall     no WSL: cria a regra de firewall Hyper-V para a LAN (UAC)
  --show             mostra estado atual (sshd, porta, chaves, regra WSL)
  --help, -h         exibe esta ajuda

Variáveis: SSH_PORT (22), WSL_FW_RULE (WSL-SSH-In), WSL_FW_REMOTE (LocalSubnet)
USAGE
                exit 0 ;;
            *) fail "opção desconhecida: $1 (use --help)" ;;
        esac
        shift
    done

    if [ "$mode" = "show" ]; then
        show_state
        exit 0
    fi

    ensure_sshd

    if [ "$gen_key" = "yes" ]; then
        ensure_user_key
    elif [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        warn "sem chave ~/.ssh/id_ed25519 (use --gen-key para gerar)"
    fi

    if is_wsl; then
        if [ "$fw" = "yes" ]; then
            wsl_firewall_apply
        elif command -v powershell.exe >/dev/null 2>&1 && ! wsl_firewall_rule_exists; then
            warn "WSL: regra Hyper-V '$WSL_FW_RULE' ausente — a LAN pode tomar timeout no SSH"
            warn "execute: ./scripts/09-ssh-access.sh --wsl-firewall   (ou veja knowledge/SSH-REMOTE-ACCESS.md)"
        fi
    fi

    log "concluído"
}

main "$@"
