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
echo
echo "  relatório: opencode-compact-if-big --list"
echo "  TUI:       opencode-compact-if-big --tui"
echo "  aplicar:   opencode-compact-if-big --above 600k --apply"
echo "  política:  generic-dev/knowledge/opencode.md §12"
