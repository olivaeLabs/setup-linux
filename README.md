# 🚀 Setup Imortal (Linux / Arch / BigLinux)

> Estrutura modular, idempotente e reproduzível para automação de ambiente de desenvolvimento e sistema operacional em distribuições baseadas em Arch Linux (BigLinux, Manjaro, Arch Linux, EndeavourOS).
> Inspirado na filosofia do vídeo *"Meu Setup Imortal"* do Fabio Akita.

---

## 📌 Visão Geral

Este repositório permite que você restaure e configure todo o seu ambiente de trabalho (programas, CLI, IDEs, drivers, swap, dotfiles) em poucos minutos após uma nova instalação do sistema.

### 🛡️ Princípios de Design
1. **Idempotência**: Cada script pode ser executado múltiplas vezes de forma segura. Se um aplicativo ou configuração já existir, ele não será reinstalado nem corrompido.
2. **Modularidade**: Responsabilidades isoladas por camadas (sistema, drivers, CLI, GUI, dev runtimes, dotfiles).
3. **Evolução Contínua**: O comando de **snapshot** (`./setup.sh --snapshot`) atualiza a lista de pacotes sempre que você instala novos softwares no dia a dia.
4. **Symlinks Seguros**: As configurações (`configs/`) são ligadas diretamente ao `$HOME` com backup automático de arquivos preexistentes.

---

## 📂 Estrutura do Repositório

```text
setup-linux/
├── setup.sh                       # 🎛️ Script mestre com menu interativo e flags CLI
├── README.md                      # 📖 Este guia de uso
├── .gitignore                     # 🔒 Bloqueio de arquivos sensíveis e backups locais
│
├── packages/                      # 📦 Listas declarativas de pacotes
│   ├── pacman-base.txt            # Pacotes essenciais de sistema e utilitários
│   ├── pacman-dev.txt             # Pacotes para compilação, linguagens e docker
│   ├── pacman-all-installed.txt   # Snapshot de todos os pacotes nativos da máquina
│   ├── aur-packages.txt           # Pacotes instalados via AUR (yay/paru)
│   └── flatpaks.txt               # Aplicativos Flatpak
│
├── scripts/                       # ⚡ Scripts executáveis modulares
│   ├── lib/utils.sh               # Funções compartilhadas, cores ANSI e helpers
│   ├── 00-system-init.sh          # Pacman tweaks (parallel, candy), fstrim e yay
│   ├── 01-hardware-gpu.sh         # Bumblebee / Nvidia 390xx e Swap prioritária
│   ├── 02-cli-tools.sh            # GitHub CLI (gh), zsh, starship, eza, bat, fzf, etc.
│   ├── 03-gui-apps.sh             # VS Code oficial, JetBrains Toolbox, navegadores
│   ├── 04-dev-runtimes.sh         # C/C++, Python, FNM/Node.js, Docker
│   ├── 05-dotfiles-sync.sh        # Criação de symlinks com backup seguro
│   └── 99-snapshot.sh             # Exportador de estado atual da máquina
│
├── configs/                       # ⚙️ Dotfiles centralizados e versionados
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
Para abrir o painel interativo de configuração:
```bash
./setup.sh
```

### 2. Linha de Comando (Atalhos Rápidos)
```bash
# Executar a instalação completa de todas as etapas
./setup.sh --all

# Executar diagnóstico do ambiente (ver o que está instalado)
./setup.sh --check

# Sincronizar dotfiles (cria symlinks para ~/.bash_aliases, ~/.gitconfig, etc.)
./setup.sh --dotfiles

# Atualizar as listas de pacotes com o estado atual do sistema
./setup.sh --snapshot
```

---

## 🐙 Publicando este Repositório no GitHub

O **GitHub CLI (`gh`)** já está instalado! Para conectar seu repositório ao seu perfil do GitHub:

1. **Autentique no GitHub**:
   ```bash
   gh auth login
   ```
   *(Siga as instruções na tela escolhendo GitHub.com > HTTPS ou SSH > Login via Browser).*

2. **Crie e envie o repositório automaticamente**:
   ```bash
   gh repo create setup-linux --public --source=. --remote=origin --push
   ```
   *(Ou `--private` se preferir mantê-lo privado).*

---

## 🔄 Como Evoluir o Setup no Dia a Dia

Sempre que você instalar novos programas ou modificar configurações:

1. **Gere um novo snapshot**:
   ```bash
   ./setup.sh --snapshot
   ```
2. **Commit e envie as alterações**:
   ```bash
   git add .
   git commit -m "feat: adiciona novos pacotes e atualiza configs"
   git push
   ```

---

## 🖥️ Como Restaurar em uma Nova Máquina

Em qualquer nova instalação baseada em Arch:

```bash
# 1. Clone seu repositório
git clone https://github.com/SEU_USUARIO/setup-linux.git ~/Projetos/setup-linux

# 2. Acesse e execute
cd ~/Projetos/setup-linux
chmod +x setup.sh scripts/*.sh tests/*.sh
./setup.sh --all
```
