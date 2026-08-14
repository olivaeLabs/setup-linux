---
name: setup-imortal
description: Guia e agente de automação para gerenciar, evoluir, atualizar e corrigir o Setup Imortal (BigLinux / Arch-based). Aplica categorização rigorosa de ferramentas/SDKs, priorização obrigatória de WebApps sobre apps Desktop (Electron), sincronização segura de dotfiles e manutenção de drivers/hardware.
---

# 🚀 Setup Imortal: Guia de Manutenção, Evolução e Categorização

Esta skill atua como o arquiteto e mantenedor do **Setup Imortal** (`/home/marcos/Projetos/setup-linux`). Seu propósito é garantir que qualquer nova ferramenta, SDK, aplicativo, driver ou configuração seja catalogada, integrada e versionada de forma idempotente e modular.

---

## 🧠 1. Memória Arquitetural e Decisões Registradas

### 🖥️ Ambiente Base
* **Distribuição**: BigLinux (Rolling release, baseada em Manjaro/Arch Linux).
* **Filosofia Lean**: **NÃO** versionar pacotes padrão da ISO do BigLinux. O repositório contém **estritamente as customizações pós-instalação** do usuário.
* **Hardware (Asus K46CB)**:
  * CPU: Intel Core i5-3317U (Ivy Bridge, Intel HD 4000).
  * GPU Dedicada: Nvidia GeForce GT 740M (Kepler legado `390xx`).
  * Driver de Vídeo: `video-hybrid-intel-nvidia-390xx-bumblebee` com `BusID "PCI:01:00:0"` em `/etc/bumblebee/xorg.conf.nvidia` e usuário no grupo `bumblebee`.
* **Otimizações de Sistema**:
  * Swap secundário com prioridade `pri=10` no `/etc/fstab` (UUID `5b59608a-773c-44ae-8407-24342edd3d60`).
  * Manutenção de SSD: `fstrim.timer` habilitado.
  * Otimização de boot: `NetworkManager-wait-online.service` e `ModemManager.service` desativados.
  * Pacman tweaks: `Color`, `ParallelDownloads = 5`, `ILoveCandy`.

---

## 🌐 2. Regra de Ouro: Priorização de WebApps (PWAs)

> [!IMPORTANT]
> Sempre que o usuário solicitar a instalação ou integração de um serviço que tenha versão Web ou cuja versão desktop seja baseada em Electron (ex: WhatsApp, Spotify, Discord, Notion, Slack, ChatGPT, Trello, YouTube, Deezer, etc.):
> 
> 1. **PRIORIZE a criação de um WebApp** em vez de baixar o pacote pesado do AUR/Flatpak.
> 2. Registre o WebApp em `configs/webapps/webapps.json`.
> 3. Gere o inicializador `.desktop` usando o `big-webapps-exec` ou o navegador padrão (`--app="URL"`).
> 4. Só instale o pacote desktop nativo se o usuário solicitar explicitamente recursos exclusivos que a versão web não ofereça.

### 💡 Racional da Priorização:
* **Economia de Recursos**: Cada app Electron abre uma instância separada do Chromium + Node.js consumindo 300MB a 800MB de RAM. WebApps compartilham o motor do navegador e aceleram o boot.
* **Manutenção Zero**: Atualizações são transparentes do lado do servidor sem necessidade de compilações frequentes via AUR.

---

## 🗂️ 3. Tabela de Categorização para Novos Pedidos

Quando o usuário pedir para adicionar ou instalar qualquer coisa, siga esta matriz:

| Tipo de Solicitação | Local de Registro no Repositório | Script Responsável | Exemplo |
| :--- | :--- | :--- | :--- |
| **Utilitário CLI / Terminal** | `packages/user-native-packages.txt` | `scripts/02-cli-tools.sh` | `bat`, `ripgrep`, `fzf`, `eza`, `zoxide`, `gh` |
| **SDK / Runtime / Compilador** | `packages/user-native-packages.txt` | `scripts/04-dev-runtimes.sh` | `gcc`, `cmake`, `fnm`/`node`, `python`, `docker` |
| **WebApp / Serviço Web** | `configs/webapps/webapps.json` | `scripts/06-webapps.sh` | `WhatsApp`, `Discord`, `Spotify`, `Notion` |
| **App Gráfico Nativo / IDE** | `packages/user-aur-packages.txt` | `scripts/03-gui-apps.sh` | `visual-studio-code-bin`, `jetbrains-toolbox`, `insync` |
| **Driver / Kernel / Hardware** | `packages/hardware-drivers.txt` | `scripts/01-hardware-gpu.sh` | `bumblebee`, `nvidia-390xx`, `linux612-r8168` |
| **Dotfile / Configuração** | `configs/<categoria>/` | `scripts/05-dotfiles-sync.sh` | `.bash_aliases`, `.gitconfig`, `settings.json` |

---

## 🛠️ 4. Fluxo de Execução e Manutenção

Ao atualizar o Setup Imortal:

1. **Aplicar a Alteração no Script/Config Apropriado**:
   * Escreva scripts idempotentes (usar `command -v`, `mkdir -p`, `--needed`, `ln -sf`, etc.).
2. **Atualizar o Snapshot**:
   ```bash
   cd /home/marcos/Projetos/setup-linux
   ./setup.sh --snapshot
   ```
3. **Validar o Diagnóstico**:
   ```bash
   ./setup.sh --check
   ```
4. **Registrar no Git**:
   ```bash
   git add .
   git commit -m "feat(<categoria>): <descrição da mudança>"
   ```

---

## 🧩 5. Estrutura Padrão de um WebApp (`webapps.json`)

Para registrar um novo WebApp, adicione ao array em `configs/webapps/webapps.json`:

```json
{
  "browser": "google-chrome-stable",
  "app_file": "webapp-nome-do-app.desktop",
  "app_name": "Nome do App",
  "app_url": "https://url-do-servico.com",
  "app_icon": "webapp-icone",
  "app_profile": "Browser",
  "app_categories": "Webapps;Network;",
  "app_icon_url": "",
  "app_mode": "browser",
  "auto_hide_headerbar": false
}
```
E execute `./setup.sh --webapps` para gerar o `.desktop`.
