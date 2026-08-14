# ==============================================================================
# Aliases Modernos para Bash / Zsh (Setup Imortal)
# ==============================================================================

# Navegação e Listagem (eza / ls)
if command -v eza &>/dev/null; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -la --icons --group-directories-first --git'
    alias la='eza -a --icons --group-directories-first'
    alias tree='eza --tree --icons'
else
    alias ll='ls -la --color=auto'
    alias la='ls -A --color=auto'
fi

# Visualização de Arquivos (bat / cat)
if command -v bat &>/dev/null; then
    alias cat='bat --paging=never --style=plain'
    alias preview='bat --paging=always'
fi

# Busca e Navegação Rápida
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init bash)"
    alias cd='z'
fi

if command -v ripgrep &>/dev/null; then
    alias grep='rg'
fi

# Git Aliases Rápidos
alias gs='git status -sb'
alias ga='git add'
alias gc='git commit -m'
alias gco='git checkout'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias glog='git log --oneline --graph --decorate --all'

# Aceleração de GPU Híbrida (Bumblebee / Nvidia)
alias gpu='optirun'
alias gpugames='primusrun'

# Atualização de Sistema (Arch / Pacman / Yay)
alias pacup='sudo pacman -Syu'
if command -v yay &>/dev/null; then
    alias update='yay -Syu'
elif command -v paru &>/dev/null; then
    alias update='paru -Syu'
fi

# Limpeza de Cache de Pacotes
alias cleanpkgs='sudo pacman -Sc && yay -Sc --noconfirm'

# IP e Rede
alias myip='curl -s ifconfig.me && echo'
alias localip='ip -br a'
