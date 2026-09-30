#!/usr/bin/env bash
# Instala `opencode-compact-if-big`: gatilho de compactação por teto de contexto.
#
# UPSTREAM (público, MIT): https://github.com/marcos-toliveira/opencode-compact-if-big
# Este script baixa do upstream; se a rede falhar, usa o espelho local
# (scripts/opencode-compact-if-big.py) e avisa.
#
# Motivo (medido 29/09/2026): o config da v2 NÃO tem chave de limite de contexto — o `auto` só
# compacta ao encher (1M), no pior momento. O utilitário pede a compactação pela API (que roda no
# próximo ponto seguro) e **recusa** quando há trabalho em voo (turno em andamento, subagentes
# ativos ou prompts na fila).
#
# Política completa: generic-dev/knowledge/opencode.md §12.
# Idempotente. Uso: ./13-opencode-compact-if-big.sh
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM="https://raw.githubusercontent.com/marcos-toliveira/opencode-compact-if-big/main/opencode-compact-if-big"
ESPELHO="$AQUI/opencode-compact-if-big.py"
DESTINO="$HOME/.local/bin/opencode-compact-if-big"
TMP="$DESTINO.baixando"

mkdir -p "$HOME/.local/bin"

origem=""
if command -v curl >/dev/null 2>&1 && curl -fsSL --max-time 25 "$UPSTREAM" -o "$TMP"; then
  install -m 755 "$TMP" "$DESTINO"
  rm -f "$TMP"
  origem="upstream (github.com/marcos-toliveira/opencode-compact-if-big)"
elif [ -f "$ESPELHO" ]; then
  install -m 755 "$ESPELHO" "$DESTINO"
  origem="espelho local (upstream indisponível nesta execução)"
else
  echo "ERRO: upstream inacessível e espelho ausente ($ESPELHO)" >&2
  exit 1
fi

echo "Instalado: $DESTINO"
echo "  origem: $origem"
"$DESTINO" --version 2>/dev/null | sed 's/^/  versão: /' || true

# Wrapper da instância 2: as duas pontas (banco + binário) da MESMA instância, sem caminho absoluto
# espalhado por aí. Usado, por exemplo, pelo widget do tclock.
cat > "$HOME/.local/bin/opencode-2-compact" <<'SH'
#!/usr/bin/env bash
# opencode-compact-if-big apontando para a instância 2 (banco + binário da conta 2).
export OPENCODE_COMPACT_DB="${OPENCODE_COMPACT_DB:-$HOME/.opencode-go2/data/opencode/opencode.db}"
export OPENCODE_COMPACT_BIN="${OPENCODE_COMPACT_BIN:-opencode-2}"
exec opencode-compact-if-big "$@"
SH
chmod +x "$HOME/.local/bin/opencode-2-compact"

# compact-tui: abre a TUI num terminal disponível (WSL/Windows Terminal ou Linux).
# Existe para o widget do tclock não depender de um terminal específico.
cat > "$HOME/.local/bin/compact-tui" <<'SH'
#!/usr/bin/env bash
# Abre a TUI do opencode-compact-if-big no terminal disponível.
set -euo pipefail
CMD_INNER="${COMPACT_TUI_CMD:-opencode-compact-if-big --tui}"

# WSL com Windows Terminal
if command -v wt.exe >/dev/null 2>&1; then
  exec wt.exe wsl.exe -e bash -lc "$CMD_INNER"
fi
# Linux (primeiro que existir)
for t in kitty alacritty wezterm ghostty konsole gnome-terminal xfce4-terminal x-terminal-emulator xterm; do
  if command -v "$t" >/dev/null 2>&1; then
    case "$t" in
      gnome-terminal) exec "$t" -- bash -lc "$CMD_INNER" ;;
      *)              exec "$t" -e bash -lc "$CMD_INNER" ;;
    esac
  fi
done
echo "compact-tui: nenhum terminal gráfico encontrado. Rode: $CMD_INNER" >&2
exit 1
SH
chmod +x "$HOME/.local/bin/compact-tui"

echo "  instalado: ~/.local/bin/opencode-2-compact (instância 2)"
echo "  instalado: ~/.local/bin/compact-tui (abre a TUI no terminal disponível)"

# ---------------------------------------------------------------------------
# Gatilho automático (systemd user): compacta sessões acima do teto que estejam OCIOSAS
# e sem trabalho em voo. Unidades versionadas em configs/opencode-compact/.
# ---------------------------------------------------------------------------
UNITS="$AQUI/../configs/opencode-compact"
if [ -d "$UNITS" ]; then
  mkdir -p "$HOME/.config/systemd/user"
  cp -f "$UNITS/opencode-compact.service" "$UNITS/opencode-compact.timer" "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload
  systemctl --user enable --now opencode-compact.timer >/dev/null 2>&1 || true
  printf "  timer: %s (a cada 5 min, --above 600k --apply --ocioso 2h)\n" "$(systemctl --user is-active opencode-compact.timer 2>/dev/null)"
  echo "  log:   ~/.local/state/opencode-compact/compact.log"
  echo "  teste: systemctl --user start opencode-compact.service   (executa uma varredura agora)"
fi
echo
echo "  relatório: opencode-compact-if-big --list"
echo "  painel:    opencode-compact-if-big --status"
echo "  TUI:       opencode-compact-if-big --tui"
echo "  aplicar:   opencode-compact-if-big --above 600k --apply"
echo "  conta 2:   opencode-2-compact --status | --tui | --above 600k --apply"
echo "  política:  generic-dev/knowledge/opencode.md §12"
