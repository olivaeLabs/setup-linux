# 🚀 Setup Imortal (BigLinux Based)

> Estrutura modular, idempotente e reproduzível com todas as customizações, ferramentas de desenvolvimento, IDEs, drivers, dotfiles e **WebApps priorizados** em cima de uma instalação padrão do BigLinux.
> Inspirado na filosofia do vídeo *"Meu Setup Imortal"* do Fabio Akita.

---

## 📌 Filosofia do Projeto

Como a base do sistema é o **BigLinux**, todo o ecossistema padrão da distribuição (Centro de Controle, temas base, suíte de áudio, codecs e pacotes do sistema) já vem pré-configurado de fábrica.

### 🌐 Regra de Ouro: Priorização de WebApps (PWAs)
Em vez de instalar dezenas de aplicativos pesados em Electron (como Spotify, WhatsApp, Discord, Notion, YouTube, etc.) que consomem gigabytes de memória RAM e processos isolados, este setup **prioriza WebApps integrados via BigLinux WebApps (`big-webapps-exec`)**:
- Consumo mínimo de memória e CPU.
- Aceleração gráfica nativa compartilhada.
- Inicialização instantânea e atualização automática.

### 🛠️ Pilares do Setup
1. **WebApps & PWAs**: WhatsApp, Spotify, Discord, YouTube, Telegram Web, Google Drive, Calendar, Jitsi, etc. (em `configs/webapps/`).
2. **Ferramentas de Desenvolvimento & CLI**: GitHub CLI (`gh`), OpenCode CLI e Desktop, FNM / Node.js, Python, Docker, C/C++ toolchain, Antigravity (`agy`).
3. **IDEs & Editores**: Visual Studio Code Oficial, JetBrains Toolbox.
4. **Aplicativos de Produtividade**: Google Chrome, Microsoft Edge, Opera, Ayugram, Insync + Dolphin.
5. **Hardware & Otimizações**: Driver Híbrido Nvidia GT 740M (`390xx` + Bumblebee com BusID), Swap secundária com prioridade no `fstab`, ativação do `fstrim.timer` e limpeza de serviços de boot.
6. **Dotfiles**: Aliases de terminal (`.bash_aliases`), configurações do Git (`.gitconfig`, `.gitignore_global`) e preferências do VS Code (`settings.json`).

---

## 📂 Estrutura do Repositório

```text
setup-linux/
├── setup.sh                       # 🎛️ Script mestre com menu interativo e flags CLI
├── README.md                      # 📖 Este guia de uso
├── .gitignore                     # 🔒 Bloqueio de arquivos locais e backups
│
├── packages/                      # 📦 Listas declarativas (apenas pós-BigLinux)
│   ├── user-native-packages.txt   # Pacotes nativos adicionados (gcc, docker, rclone, etc.)
│   ├── user-aur-packages.txt      # Pacotes AUR (chrome, edge, insync, vscode, ayugram, etc.)
│   ├── hardware-drivers.txt       # Stack Nvidia 390xx, Bumblebee e módulos de kernel
│   └── flatpaks.txt               # Aplicativos Flatpak
│
├── scripts/                       # ⚡ Scripts executáveis modulares
│   ├── lib/utils.sh               # Funções compartilhadas, cores ANSI e helpers
│   ├── 00-system-init.sh          # Pacman tweaks (parallel, candy), fstrim e yay
│   ├── 01-hardware-gpu.sh         # Bumblebee / Nvidia 390xx e Swap prioritária
│   ├── 02-cli-tools.sh            # GitHub CLI (gh), zsh, starship, eza, bat, fzf, etc.
│   ├── 03-gui-apps.sh             # VS Code oficial, JetBrains Toolbox, navegadores, insync
│   ├── 04-dev-runtimes.sh         # C/C++, Python, FNM/Node.js, Docker
│   ├── 05-dotfiles-sync.sh        # Criação de symlinks com backup seguro
│   ├── 06-webapps.sh              # 🌐 Restauração de WebApps priorizados sobre Electron
│   ├── 07-opencode.sh             # OpenCode CLI e Desktop (AUR ou fallback sem root)
│   └── 99-snapshot.sh             # Exportador do estado atual da máquina
│
├── configs/                       # ⚙️ Dotfiles centralizados e versionados
│   ├── webapps/                   # 🌐 Declaração de WebApps (webapps.json e ícones)
│   ├── bash/.bash_aliases         # Aliases modernos (ls->eza, cat->bat, gpu->optirun)
│   ├── git/.gitconfig             # Configuração padrão de Git e aliases
│   ├── git/.gitignore_global      # Regras globais de ignore
│   ├── vscode/settings.json       # Configurações de editor (fontes, formatação)
│   └── system/                    # Exemplos de configurações de sistema (fstab, xorg)
│
└── tests/
    └── check-environment.sh       # 🔍 Diagnóstico do status de ferramentas instaladas
```

---

## 💻 Como Usar

### 1. Menu Interativo
```bash
./setup.sh
```

### 2. Atalhos Diretos via CLI
```bash
# Executar a instalação e configuração completa (incluindo WebApps)
./setup.sh --all

# Restaurar apenas os WebApps
./setup.sh --webapps

# Diagnóstico de ferramentas instaladas
./setup.sh --check

# Instalar OpenCode CLI e Desktop
./setup.sh --opencode

# Sincronizar dotfiles (symlinks para ~/.bash_aliases, ~/.gitconfig, etc.)
./setup.sh --dotfiles

# Atualizar as listas com novos programas instalados
./setup.sh --snapshot
```
