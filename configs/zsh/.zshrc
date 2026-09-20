# ==============================================================================
# Modern ZSH Configuration - Zinit (Turbo Mode) + Starship Prompt
# Setup Imortal / Arch Linux
# ==============================================================================

# --- 1. Zinit Package Manager Initialization ---
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# --- 2. Zinit Plugins (Turbo Mode / Asynchronous) ---
# Syntax Highlighting em tempo real
zinit light-mode for \
    zdharma-continuum/fast-syntax-highlighting

# Autosuggestions (sugestões inteligentes com autocompletar na seta direita)
zinit wait lucid light-mode for \
    atload"_zsh_autosuggest_start" \
    zsh-users/zsh-autosuggestions

# Completions adicionais
zinit wait lucid light-mode blockf for \
    zsh-users/zsh-completions

# Snippets essenciais do Oh My Zsh (sem o peso do framework inteiro)
zinit wait lucid for \
    OMZL::git.zsh \
    OMZP::git \
    OMZP::sudo

# --- 3. Motor de Autocompletar e Cores ---
autoload -Uz compinit
compinit -C
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Keybindings: Setas Up/Down para buscar no histórico baseado no que foi digitado
bindkey '^[[A' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward

# --- 4. Starship Prompt (Rust) ---
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi

# --- 5. FZF (Fuzzy Finder) Keybindings & Completions ---
if command -v fzf >/dev/null 2>&1; then
    source <(fzf --zsh) 2>/dev/null || true
fi

# --- 6. Environment & Development PATHs ---
export GOPATH="$HOME/go"
export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"

# FNM (Fast Node Manager)
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --use-on-cd)"
elif [ -f "$HOME/.local/share/fnm/fnm" ]; then
    export PATH="$HOME/.local/share/fnm:$PATH"
    eval "$(fnm env --use-on-cd)"
fi

# SDKMAN!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# Carregar Aliases Globais
if [ -f "$HOME/.bash_aliases" ]; then
    source "$HOME/.bash_aliases"
fi

# --- 7. AI Jail & Security Aliases ---
alias claude-jail='ai-jail claude'
alias gemini-jail='ai-jail gemini'
alias agy-jail='ai-jail agy'
alias ai-sandbox='ai-jail'

# --- 8. Histórico Inteligente ---
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
