# Tuning de Memória do WSL (swap, zram e `.wslconfig`)

> Contexto: sessões de validação/benchmark (ex.: `browser-harness-go`) com vários agentes
> em paralelo derrubavam o WSL inteiro por **OOM**. Este guia registra a configuração
> aplicada e como reproduzi-la **em qualquer perfil Windows** (incluindo `marco`).

## 1. Por que

- O WSL herdava ~7,5 GB de RAM e 2 GB de swap; Chrome (20 renderers) + OpenCode + MCP já
  ocupavam ~4,5 GB — sobrava pouco para dois ou mais processos Go (`go test -race` +
  benchmarks alocam centenas de MB por operação).
- O kernel mata o processo mais gordo, e o `vmmem` pode levar a VM inteira junto.

## 2. Camadas da solução

| Camada | Onde vive | Escopo | Requer restart |
|---|---|---|---|
| `.wslconfig` (memória/swap) | `C:\Users\<perfil>\.wslconfig` | **Por usuário Windows** | Sim (`wsl --shutdown`) |
| `zram` (swap comprimido) | dentro do distro (systemd) | Por distro WSL | Não (aplicável ao vivo) |
| `vm.swappiness`/`vm.page-cluster` | `/etc/sysctl.d/99-zram.conf` | Por distro WSL | Não |
| `GOMEMLIMIT`/`GOMAXPROCS` | comando de teste | Por execução | Não |

## 3. Aplicação (script idempotente)

```bash
cd ~/Projetos/setup-linux

# Lado Linux (zram + sysctl) no distro atual:
./scripts/08-wsl-memory.sh

# Também grava o .wslconfig do perfil Windows ATUAL:
./scripts/08-wsl-memory.sh --windows-config

# Perfil específico (ex.: marco), quando o distro roda sob outro login:
./scripts/08-wsl-memory.sh --profile marco

# Inspecionar:
./scripts/08-wsl-memory.sh --show
```

Valores padrão (sobrescrevíveis por variável de ambiente):
`WSL_MEMORY=10GB`, `WSL_SWAP=20GB`, `ZRAM_SIZE=3G`, `ZRAM_PRIORITY=100`, `SWAPPINESS=150`.

## 4. Conteúdo do `.wslconfig`

```ini
[wsl2]
memory=10GB
swap=20GB
swapfile=C:\\wsl-swap.vhdx
autoMemoryReclaim=gradual
```

> **Importante:** o WSL lê o `.wslconfig` do **`%USERPROFILE%` do usuário que inicia o WSL**.
> Com dois perfis Windows (`marco`, `lamar`), cada um pode ter o seu arquivo — mas o tuning
> só vale para as sessões iniciadas por aquele perfil.
>
> O perfil `marco` estava com permissão `000` no diretório, então **não é gravável a partir
> do WSL logado como `lamar`**. Nesse caso o script imprime o comando PowerShell; rode-o
> **logado no perfil `marco`**:
>
> ```powershell
> @"
> [wsl2]
> memory=10GB
> swap=20GB
> swapfile=C:\\wsl-swap.vhdx
> autoMemoryReclaim=gradual
> "@ | Set-Content -Path "$env:USERPROFILE\.wslconfig" -Encoding ASCII
> wsl --shutdown
> ```

## 5. Validação após `wsl --shutdown`

```bash
free -h                         # esperado: ~10Gi RAM e ~23Gi swap (20G disco + 3G zram)
cat /proc/swaps                 # /dev/sdc (swap) + /dev/zram0 (prioridade 100)
zramctl                         # zram0 ativo
systemctl is-active zram-swap   # active
sysctl vm.swappiness vm.page-cluster   # 150 / 0
```

## 6. Disciplina de validação (evita OOM mesmo com tuning)

- **1 validador/agente por vez** — nunca rodar `go test`/benchmarks em paralelo.
- Usar o alvo com teto de heap: `make test-safe` (`GOMAXPROCS=4 GOMEMLIMIT=2GiB`).
- Benchmarks: entradas ≤ 256 KB e `-benchtime=1x`; evitar `ScrubText` de 3,4 MB em loop.
- Se estável e produtivo, aumentar os tetos em rodadas futuras (decisão registrada aqui).

## 7. Rollback

```bash
./scripts/08-wsl-memory.sh   # idempotente: reaplica o padrão
# para remover o zram:
sudo systemctl disable --now zram-swap.service && sudo rm /etc/systemd/system/zram-swap.service
# para remover o swap extra: apagar/editar o .wslconfig do perfil e rodar 'wsl --shutdown'
```
