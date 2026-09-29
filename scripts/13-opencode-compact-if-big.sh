#!/usr/bin/env bash
# Instala `opencode-compact-if-big`: gatilho de compactação por teto de contexto.
#
# Motivo (29/09/2026): o config da v2 NÃO tem chave de limite de contexto — o `auto` só compacta
# ao encher (1M), no pior momento. Medimos `tempo ≈ nº de requisições × pedágio` e cauda p90
# piorando com o contexto (149,6 s em 600–900k). Este utilitário pede a compactação pela API
# (que roda no próximo ponto seguro e funde pedidos repetidos) — e **recusa** quando há
# trabalho em voo (turno em andamento, subagentes ativos ou prompts na fila).
#
# Fonte versionada (copiada, sem drift): scripts/opencode-compact-if-big.py
# Política completa: generic-dev/knowledge/opencode.md §12.
# Idempotente. Uso: ./13-opencode-compact-if-big.sh
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGEM="$AQUI/opencode-compact-if-big.py"
DESTINO="$HOME/.local/bin/opencode-compact-if-big"

[ -f "$ORIGEM" ] || { echo "ERRO: fonte não encontrada: $ORIGEM" >&2; exit 1; }

mkdir -p "$HOME/.local/bin"
install -m 755 "$ORIGEM" "$DESTINO"

echo "Instalado: $DESTINO"
echo "  dry-run: opencode-compact-if-big                 (não age; mostra 'EM VOO' por sessão)"
echo "  aplicar: opencode-compact-if-big --above 600k --apply"
echo "  política: generic-dev/knowledge/opencode.md §12"
