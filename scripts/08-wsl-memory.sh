#!/usr/bin/env bash
# ==============================================================================
# Script: 08-wsl-memory.sh
# Descrição: Tuning de memória do WSL (swap comprimido/zram + .wslconfig por perfil)
# Uso:
#   ./scripts/08-wsl-memory.sh                  # aplica o lado Linux (zram+sysctl) no distro atual
#   ./scripts/08-wsl-memory.sh --windows-config # também grava .wslconfig do perfil Windows ATUAL
#   ./scripts/08-wsl-memory.sh --profile marco  # tenta gravar .wslconfig do perfil marco
#   ./scripts/08-wsl-memory.sh --show           # mostra estado atual
#   ./scripts/08-wsl-memory.sh --help
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/utils.sh
if [ -f "$SCRIPT_DIR/lib/utils.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/utils.sh"
fi

ZRAM_SIZE="${ZRAM_SIZE:-3G}"
ZRAM_PRIORITY="${ZRAM_PRIORITY:-100}"
SWAPPINESS="${SWAPPINESS:-150}"
WSL_MEMORY="${WSL_MEMORY:-10GB}"
WSL_SWAP="${WSL_SWAP:-20GB}"

log()  { echo "[wsl-memory] $*"; }
warn() { echo "[wsl-memory] AVISO: $*" >&2; }
fail() { echo "[wsl-memory] ERRO: $*" >&2; exit 1; }

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

wslconfig_content() {
    cat <<EOF
[wsl2]
memory=${WSL_MEMORY}
swap=${WSL_SWAP}
swapfile=C:\\\\wsl-swap.vhdx
autoMemoryReclaim=gradual
EOF
}

write_if_changed() {
    local path="$1"
    local content="$2"
    if [ -f "$path" ] && [ "$(cat "$path" 2>/dev/null)" = "$content" ]; then
        log "sem mudanças: $path"
        return 0
    fi
    printf '%s\n' "$content" | use_sudo tee "$path" >/dev/null
    log "escrito: $path"
}

apply_linux_side() {
    log "aplicando zram + sysctl (distro: ${WSL_DISTRO_NAME:-?})"
    write_if_changed /etc/sysctl.d/99-zram.conf "vm.swappiness=${SWAPPINESS}
vm.page-cluster=0"
    use_sudo sysctl -p /etc/sysctl.d/99-zram.conf >/dev/null

    local unit="/etc/systemd/system/zram-swap.service"
    local unit_content
    unit_content=$(cat <<EOF
[Unit]
Description=zram compressed swap (browser-harness-go dev)
After=multi-user.target
Before=swap.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'modprobe zram num_devices=1 || exit 0; echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || true; echo ${ZRAM_SIZE} > /sys/block/zram0/disksize; mkswap /dev/zram0 >/dev/null; swapon -p ${ZRAM_PRIORITY} /dev/zram0'
ExecStop=/bin/bash -c 'swapoff /dev/zram0 2>/dev/null || true; echo 1 > /sys/block/zram0/reset 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF
)
    write_if_changed "$unit" "$unit_content"
    use_sudo systemctl daemon-reload
    use_sudo systemctl enable --now zram-swap.service >/dev/null 2>&1 || warn "não foi possível habilitar o zram-swap.service"
    log "zram: $(zramctl --output NAME,DISKSIZE,ALGORITHM --noheadings 2>/dev/null | tr -s ' ' | head -1 || echo 'indisponível')"
}

windows_profile_home() {
    local profile="$1"
    if [ -z "$profile" ] || [ "$profile" = "current" ]; then
        local raw
        raw="$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' || true)"
        if [ -z "$raw" ]; then
            warn "não foi possível detectar %USERPROFILE% (cmd.exe indisponível)"
            return 1
        fi
        printf '%s' "$raw"
        return 0
    fi
    printf 'C:\\Users\\%s' "$profile"
}

apply_windows_config() {
    local profile="${1:-current}"
    local winhome
    winhome="$(windows_profile_home "$profile")" || return 1

    # C:\Users\x -> /mnt/c/Users/x
    local drive dir
    drive="$(printf '%s' "$winhome" | sed -E 's#^([A-Za-z]):.*#\L\1#')"
    dir="/mnt/${drive}/$(printf '%s' "$winhome" | sed -E 's#^[A-Za-z]:\\##; s#\\#/#g')"
    [ -d "$dir" ] || fail "diretório do perfil não encontrado: $dir"

    local content target
    content="$(wslconfig_content)"
    target="$dir/.wslconfig"
    if [ -f "$target" ] && [ "$(cat "$target" 2>/dev/null || true)" = "$content" ]; then
        log "sem mudanças: $target"
    elif printf '%s\n' "$content" > "$target" 2>/dev/null; then
        log "escrito: $target"
    else
        warn "sem permissão para escrever em $target (perfil de outro usuário Windows)"
        cat <<EOF

  Aplique manualmente no Windows, logado no perfil '$profile':
    1. Abra o PowerShell e rode:
         @"
$(wslconfig_content)
"@ | Set-Content -Path "\$env:USERPROFILE\\.wslconfig" -Encoding ASCII
    2. Depois:  wsl --shutdown
    3. Reabra o WSL e valide com: free -h && cat /proc/swaps

EOF
        return 1
    fi
    log "atenção: '.wslconfig' só passa a valer após 'wsl --shutdown' no Windows"
}

show_state() {
    echo "== distro =="; echo "${WSL_DISTRO_NAME:-fora do WSL}"
    echo "== memória =="; free -h | head -3
    echo "== swaps =="; cat /proc/swaps
    echo "== zram =="; zramctl 2>/dev/null || echo "(zramctl ausente)"
    echo "== sysctl =="; sysctl vm.swappiness vm.page-cluster 2>/dev/null || true
    echo "== .wslconfig por perfil =="
    local winhome drive dir
    winhome="$(windows_profile_home current 2>/dev/null || true)"
    if [ -n "${winhome:-}" ]; then
        drive="$(printf '%s' "$winhome" | sed -E 's#^([A-Za-z]):.*#\L\1#')"
        dir="/mnt/${drive}/$(printf '%s' "$winhome" | sed -E 's#^[A-Za-z]:\\##; s#\\#/#g')/.wslconfig"
        if [ -f "$dir" ]; then echo "--- $dir"; cat "$dir"; else echo "(ausente: $dir)"; fi
    fi
}

main() {
    local mode="linux" profile="current"
    while [ $# -gt 0 ]; do
        case "$1" in
            --windows-config) mode="both" ;;
            --profile) shift; profile="${1:-}"; mode="windows" ;;
            --show) mode="show" ;;
            --help|-h)
                cat <<'USAGE'
Uso: ./scripts/08-wsl-memory.sh [opções]
  (sem opções)      aplica o lado Linux (zram + sysctl) no distro atual
  --windows-config  também grava .wslconfig do perfil Windows ATUAL
  --profile <nome>  tenta gravar .wslconfig do perfil <nome> (ex.: marco)
  --show            mostra estado atual (memória, swaps, zram, sysctl, .wslconfig)
  --help, -h        exibe esta ajuda

Variáveis: ZRAM_SIZE (3G), ZRAM_PRIORITY (100), SWAPPINESS (150),
           WSL_MEMORY (10GB), WSL_SWAP (20GB)
USAGE
                exit 0 ;;
            *) fail "opção desconhecida: $1 (use --help)" ;;
        esac
        shift
    done

    if ! is_wsl; then
        warn "este ambiente não parece WSL; nada a fazer (use --show para inspecionar)"
        exit 0
    fi

    case "$mode" in
        show) show_state ;;
        linux) apply_linux_side ;;
        windows) apply_windows_config "$profile" ;;
        both) apply_linux_side; apply_windows_config "$profile" ;;
    esac
    log "concluído"
}

main "$@"
