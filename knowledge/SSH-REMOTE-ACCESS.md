# 🔐 Acesso Remoto SSH — Linux (BigLinux) e WSL Mirrored

Este guia consolida o padrão de **acesso remoto via SSH** das máquinas do ecossistema:
o servidor Linux nativo (BigLinux), o servidor dentro do WSL e os pontos de atenção
de rede que já custaram sessões de diagnóstico — em especial o **Hyper-V firewall do
WSL em modo mirrored**.

> Automação: `scripts/09-ssh-access.sh` (também via `./setup.sh --ssh`).

---

## 🐧 Linux nativo (BigLinux / Arch)

```bash
# 1. Servidor (habilita e inicia agora, e persiste no boot)
sudo systemctl enable --now sshd
systemctl is-active sshd && ss -tln | grep ':22 '

# 2. Verificação de permissões (StrictModes do sshd)
stat -c '%a %U:%G %n' ~ ~/.ssh ~/.ssh/authorized_keys
#    esperado: 700/700/600
```

- **Troca de chaves (cliente → servidor)**: no cliente, `ssh-copy-id usuario@host`.
- **Chave do usuário**: `ssh-keygen -t ed25519` em cada máquina cliente. O script
  `09-ssh-access.sh --gen-key` gera `~/.ssh/id_ed25519` sem passphrase (padrão do setup;
  use passphrase + ssh-agent se preferir mais segurança).
- **Aliases de conveniência** (`~/.ssh/config`): uma entrada `Host alias` com
  `HostName`, `User` e `IdentityFile` por destino. Evite versionar IPs/aliases
  específicos de rede em repositório.

---

## 🪟 WSL em modo `mirrored` (ponto crítico de rede)

Com `networkingMode=mirrored` (ver `.wslconfig`), o WSL **compartilha o IP do Windows** —
e o ingresso da LAN passa pelo **Hyper-V firewall** (Windows Security → Firewall →
regras da VM do WSL), **não** pelo Windows Firewall tradicional.

- **Padrão da VM WSL**: `DefaultInboundAction = Block` → sem regra explícita, a LAN toma
  **timeout** (pacote descartado; não é "connection refused").
- **Regra canônica** (PowerShell como Administrador):

```powershell
New-NetFirewallHyperVRule -Name "WSL-SSH-In" `
  -DisplayName "WSL SSH Inbound (TCP 22)" -Direction Inbound `
  -VMCreatorId "{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}" `
  -Protocol TCP -LocalPorts 22 -RemoteAddresses LocalSubnet -Action Allow
```

- `{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}` é o **VMCreatorId fixo do WSL** (confirmável
  via `Get-NetFirewallHyperVVMCreator`; `FriendlyName = WSL`).
- `-RemoteAddresses LocalSubnet` restringe à rede local (não expõe à internet).
- Aplicação/verificação: `./scripts/09-ssh-access.sh --wsl-firewall` e `--show`.
- Rollback: `Remove-NetFirewallHyperVRule -Name "WSL-SSH-In"`.

### Diagnóstico rápido (WSL)

```bash
# sshd ativo dentro do WSL
systemctl is-active sshd && ss -tln | grep ':22 '

# Logs de conexões (acertos e erros)
sudo journalctl -u sshd --since "30 minutes ago" | tail -20
```

Sinais comuns no log:
- `Invalid user marco from ...` → **typo no usuário** (ex.: faltou o "s").
- `Accepted password for ...` → login por senha (chave com passphrase sem agent cai para senha).
- `Accepted publickey for ...` → login por chave OK.

### Falsos negativos no teste a partir do próprio Windows

Em mirrored, **host↔WSL se falam por `localhost`** (funciona: `Test-NetConnection localhost -Port 22`).
Testar do **próprio Windows** para o **IP da LAN** (`192.168.x.x:22`) pode falhar por
roteamento local — esse teste **não representa** o ingresso da LAN. O teste definitivo é
de **outra máquina** da rede.

---

## ⚠️ Conflitos e pegadinhas

- **Windows OpenSSH Server** no mesmo host: se instalado/ativo, disputa a porta 22 da LAN.
  Neste setup, a porta 22 pertence ao **sshd do WSL**. (`Get-Service sshd` no Windows = ausente.)
- **`administrators_authorized_keys` / `Match Group administrators`** são conceitos
  **exclusivos do OpenSSH Server do Windows** — não existem no sshd do Linux/WSL
  (que usa `~/.ssh/authorized_keys`).
- **Chave com passphrase sem ssh-agent**: o ssh tenta a chave, pede a passphrase e, se não
  for fornecida, cai para senha silenciosamente do ponto de vista do servidor.
- **Sessões não interativas** (`ssh host 'comando'`): o PATH pode não incluir
  `~/.local/bin` — use caminho absoluto para binários instalados no perfil.

---

## ✅ Checklist pós-configuração

1. `systemctl is-active sshd` → `active` (nas duas pontas: Linux e/ou WSL).
2. `ssh <user>@<host>` de outro PC da LAN → conecta.
3. `Accepted publickey` no `journalctl -u sshd` quando usar chave.
4. WSL: `Get-NetFirewallHyperVRule -Name 'WSL-SSH-In'` presente e `Enabled=True`.

---

## 🔁 Referência de sessão

Padrão validado em 2026-09-24 no par **WSL (Arch) ↔ k46cb (BigLinux/Manjaro)**: regra
Hyper-V criada via UAC, chave dedicada `id_ed25519_wsl` (sem passphrase) autorizada no
WSL e alias `Host wsl` no cliente. Evidências: `tasks/WSL-SSH-LAN/` e
`tasks/OPENCODE-K46CB-PARIDADE/` (workspace).
