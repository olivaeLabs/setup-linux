#!/usr/bin/env bash
# update-all.sh — "update": atualiza tudo neste ambiente (Arch/Manjaro e WSL).
#
#   sistema + AUR  -> yay -Syu (ou sudo pacman -Syu se nao houver yay)
#   toolchains     -> npm globais, pipx, uv (e o Node do fnm com --node)
#   repos git      -> ~/Projetos/*: fetch + pull --ff-only nos LIMPOS (sujos sao pulados, com aviso)
#   servicos       -> detecta binario trocado sem restart (e reinicia com --restart)
#
# Uso:  update [-n|--dry-run] [-y|--yes] [--node] [--restart]
#   (sem flag)  mostra o PLANO e pede confirmacao antes de mexer no sistema
#   -n          so mostra o plano (nao executa nada)
#   -y          executa sem perguntar (pacman/yay com --noconfirm)
#   --node      tambem instala o Node LTS do fnm e o define como padrao
#   --restart   reinicia servicos cujo binario mudou (ex.: opencode beta atualizado)
#
# Seguro por padrao: nada destrutivo (sem -Sc, sem -Rns, sem reset de repositorio). Repositorio com
# alteracao local nao e tocado - o script avisa e segue.
set -uo pipefail

ASSUME_YES=0; DRY=0; WANT_NODE=0; WANT_RESTART=0
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)     ASSUME_YES=1 ;;
    -n|--dry-run) DRY=1 ;;
    --node)       WANT_NODE=1 ;;
    --restart)    WANT_RESTART=1 ;;
    -h|--help)    sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            printf 'update: opcao desconhecida: %s (use -h)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

log() { printf '  %s\n' "$*"; }
sec() { printf '\n=== %s ===\n' "$*"; }

# ------------------------------------------------------------------ 1. sistema + AUR
SYSUPD=(); SYSUPD_DESC="(sem pacman - pulado)"
if command -v yay >/dev/null 2>&1; then
  SYSUPD=(yay -Syu); SYSUPD_DESC="yay -Syu (sistema + AUR)"
elif command -v pacman >/dev/null 2>&1; then
  SYSUPD=(sudo pacman -Syu); SYSUPD_DESC="sudo pacman -Syu"
fi
[ "$ASSUME_YES" = 1 ] && [ ${#SYSUPD[@]} -gt 0 ] && SYSUPD+=(--noconfirm)

# ------------------------------------------------------------------ 2. toolchains
STEP_NPM=0; STEP_PIPX=0; STEP_UV=0
command -v npm  >/dev/null 2>&1 && STEP_NPM=1
command -v pipx >/dev/null 2>&1 && STEP_PIPX=1
command -v uv   >/dev/null 2>&1 && STEP_UV=1
NTOOLS=$(( STEP_NPM + STEP_PIPX + STEP_UV + WANT_NODE ))

# ------------------------------------------------------------------ 3. repos git
REPOS=()
for d in "$HOME"/Projetos/*/; do
  [ -d "${d}.git" ] && REPOS+=("${d%/}")
done

# ------------------------------------------------------------------ 4. servicos defasados
# O serviço do opencode roda como processo solto (não é unit systemd): comparamos a data do binário
# no disco com o início do processo. Foi assim que descobrimos, em 30/09/2026, um serviço rodando
# binário velho depois de atualizar o pacote.
servicos_defasados() {
  local achou=0 pid ini
  pid=$(ss -ltnp 2>/dev/null | grep opencode | grep -oP '(?<=pid=)\K[0-9]+' | head -1)
  if [ -n "${pid:-}" ] && [ -e /usr/bin/opencode ]; then
    ini=$(stat -c %Y "/proc/$pid" 2>/dev/null || echo 0)
    if [ "$(stat -c %Y /usr/bin/opencode 2>/dev/null || echo 0)" -gt "$ini" ]; then
      log "opencode: binário no disco é MAIS NOVO que o processo (pid $pid) - serviço defasado"
      achou=1
    else
      log "opencode: processo (pid $pid) já usa o binário do disco"
    fi
  fi
  if command -v systemctl >/dev/null 2>&1 && systemctl --user is-active ai-memory.service >/dev/null 2>&1; then
    log "ai-memory: serviço ativo desde $(systemctl --user show -p ActiveEnterTimestamp --value ai-memory.service)"
    achou=1
  fi
  return 0
}

# ------------------------------------------------------------------ PLANO
printf '\n== update ==  plano  (%s)\n' "$([ "$DRY" = 1 ] && echo 'dry-run' || echo 'interativo')"
log "1) sistema + AUR : $SYSUPD_DESC"
if [ "$NTOOLS" = 0 ]; then
  log "2) toolchains    : (nada instalado neste ambiente)"
else
  t=""
  [ "$STEP_NPM" = 1 ]  && t="$t npm update -g;"
  [ "$STEP_PIPX" = 1 ] && t="$t pipx upgrade-all;"
  [ "$STEP_UV" = 1 ]   && t="$t uv self update;"
  [ "$WANT_NODE" = 1 ] && t="$t fnm install --lts;"
  log "2) toolchains    :$t"
fi
log "3) repos git     : ${#REPOS[@]} repositorio(s) em ~/Projetos (limpos recebem pull --ff-only)"
log "4) servicos      : detectar binario trocado sem restart$([ "$WANT_RESTART" = 1 ] && echo ' + reiniciar')"

if [ "$DRY" = 1 ]; then
  sec "repos: situacao atual"
  for r in "${REPOS[@]}"; do
    n=$(basename "$r")
    git -C "$r" fetch -q 2>/dev/null || true
    s=$(git -C "$r" status --porcelain 2>/dev/null | wc -l)
    b=$(git -C "$r" rev-list --count HEAD..@{u} 2>/dev/null || echo '?')
    log "$(printf '%-26s' "$n") sujos=$s atras=$b"
  done
  printf '\n(dry-run: nada foi executado)\n'
  exit 0
fi

if [ "$ASSUME_YES" != 1 ]; then
  printf '\nExecutar? [s/N] '
  read -r resposta || resposta=""
  case "${resposta:-}" in s|S|y|Y) ;; *) printf 'abortado pelo operador\n'; exit 0 ;; esac
fi

erros=0

# ------------------------------------------------------------------ 1. sistema + AUR
sec "1) sistema + AUR"
if [ ${#SYSUPD[@]} -gt 0 ]; then
  if "${SYSUPD[@]}"; then log "ok"; else log "FALHOU: ${SYSUPD[*]}"; erros=$((erros+1)); fi
else
  log "pulado"
fi

# ------------------------------------------------------------------ 2. toolchains
sec "2) toolchains"
if [ "$NTOOLS" = 0 ]; then log "nada instalado - pulado"; fi
if [ "$STEP_NPM" = 1 ]; then
  if npm update -g >/dev/null 2>&1; then log "npm update -g: ok"; else log "npm update -g: FALHOU"; erros=$((erros+1)); fi
fi
if [ "$STEP_PIPX" = 1 ]; then
  if pipx upgrade-all >/dev/null 2>&1; then log "pipx upgrade-all: ok"; else log "pipx upgrade-all: FALHOU"; erros=$((erros+1)); fi
fi
if [ "$STEP_UV" = 1 ]; then
  if uv self update >/dev/null 2>&1; then log "uv self update: ok"; else log "uv self update: sem novidade"; fi
fi
if [ "$WANT_NODE" = 1 ] && command -v fnm >/dev/null 2>&1; then
  if fnm install --lts >/dev/null 2>&1 && fnm default lts-latest >/dev/null 2>&1; then
    log "fnm: lts-latest instalado e definido como padrao (use um shell novo)"
  else
    log "fnm: FALHOU"; erros=$((erros+1))
  fi
fi

# ------------------------------------------------------------------ 3. repos git
sec "3) repos git"
puxados=0; emdia=0; pulados=0
for r in "${REPOS[@]}"; do
  n=$(basename "$r")
  if [ "$(git -C "$r" status --porcelain 2>/dev/null | wc -l)" -gt 0 ]; then
    log "$(printf '%-26s' "$n") PULADO (alteracoes locais)"; pulados=$((pulados+1)); continue
  fi
  git -C "$r" fetch -q 2>/dev/null || true
  atras=$(git -C "$r" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
  if [ "${atras:-0}" -gt 0 ]; then
    if git -C "$r" pull --ff-only -q 2>/dev/null; then
      log "$(printf '%-26s' "$n") atualizado (+$atras)"; puxados=$((puxados+1))
    else
      log "$(printf '%-26s' "$n") FALHOU o pull"; erros=$((erros+1))
    fi
  else
    emdia=$((emdia+1))
  fi
done
log "resumo: $puxados atualizado(s), $emdia em dia, $pulados pulado(s)"

# ------------------------------------------------------------------ 4. servicos
sec "4) servicos"
servicos_defasados
if [ "$WANT_RESTART" = 1 ]; then
  if pkill -f 'opencode serve --service' 2>/dev/null; then
    log "opencode: processo antigo encerrado (ele sobe de novo no proximo uso)"
  else
    log "opencode: nao havia processo para encerrar"
  fi
  if command -v systemctl >/dev/null 2>&1 && systemctl --user is-active ai-memory.service >/dev/null 2>&1; then
    systemctl --user restart ai-memory.service && log "ai-memory: reiniciado"
  fi
fi

# ------------------------------------------------------------------ resumo
printf '\n== update: fim ==\n'
log "erros: $erros"
[ "$erros" -gt 0 ] && log "veja as linhas FALHOU acima"
log "TUI aberta durante o update? feche e reabra (ou use o atalho de recarregar config)"
exit $(( erros > 0 ? 1 : 0 ))
