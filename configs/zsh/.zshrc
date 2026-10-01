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

# >>> ai-jail browsers >>>
# Abre Brave/Chrome/Chromium isolados pelo ai-jail.
# Uso: jail brave | jail chrome | jail chromium  [args extras do navegador]
# Perfis persistentes em ~/jail-browsers/<browser>/{data,cache}
# GPU habilitada (--gpu) e áudio (--audio).
jail() {
	local browser="${1:-}"
	[ "$#" -gt 0 ] && shift
	local bin dir xauth
	case "$browser" in
		brave)    bin="/usr/bin/brave" ;;
		chrome)   bin="/usr/bin/google-chrome-stable" ;;
		chromium) bin="/usr/bin/chromium" ;;
		""|-h|--help|help)
			printf 'uso: jail {brave|chrome|chromium} [args extras do navegador]\n' >&2
			return 0 ;;
		*)
			printf 'jail: navegador "%s" não suportado (use: brave, chrome, chromium)\n' "$browser" >&2
			return 2 ;;
	esac
	[ -x "$bin" ] || { printf 'jail: não encontrei %s\n' "$bin" >&2; return 1; }

	dir="$HOME/jail-browsers/$browser"
	xauth="$HOME/jail-browsers/.Xauthority"
	mkdir -p "$dir"

	# O home real fica privado (tmpfs) dentro do jail, então o cookie X tem
	# de viver em ~/jail-browsers (montado por cima do tmpfs) e ter nome com
	# "Xauthority" — o ai-jail rejeita o /tmp/xauth_XXXX criado pelo Plasma.
	if [ -n "${XAUTHORITY:-}" ] && [ -r "$XAUTHORITY" ] && [ ! "$XAUTHORITY" -ef "$xauth" ]; then
		install -m 600 "$XAUTHORITY" "$xauth"
	fi
	if [ ! -r "$xauth" ]; then
		printf 'jail: cookie X não encontrado (%s). Verifique a sessão gráfica: xauth list\n' "$xauth" >&2
		return 1
	fi

	# O ai-jail monta o diretório ATUAL como "projeto" (gravável). Se rodar
	# do HOME, o home inteiro vira gravável. Entrando no diretório do perfil,
	# o HOME real vira um tmpfs privado e só ~/jail-browsers fica exposto.
	(
		export XAUTHORITY="$xauth"
		cd "$dir" || exit 1
		exec ai-jail --no-browser --gpu --audio --display --x11 --network \
			--rw-map "$HOME/jail-browsers" \
			--exec --terminal-passthrough -- "$bin" \
			--no-sandbox --test-type \
			--ignore-gpu-blocklist --enable-gpu-rasterization \
			--enable-features=VaapiVideoDecoder,VaapiVideoEncoder \
			--user-data-dir="$dir/data" \
			--disk-cache-dir="$dir/cache" "$@"
	)
}
# <<< ai-jail browsers <<<

# --- 8. Histórico Inteligente ---
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY

# --- 9. Ajustes locais da maquina (opcional) ---
# O .zshrc e COMPARTILHADO entre as maquinas (symlink para este repo). O que for especifico de UMA
# maquina vive em ~/.zshrc.local: ex. no WSL, o comando `update` (fontes em scripts/update-all.sh).
# O notebook NAO tem esse arquivo - la o `update` e o da propria distro (BigLinux: `yay -Syu`) e nao
# deve ser sobrescrito por nos.
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
