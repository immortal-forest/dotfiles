# envs
# export PYENV_ROOT="$HOME/dev/pyenv"
# [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
export EDITOR=nvim
export GPG_TTY=$(tty)
export SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/ssh-agent.socket

# only if uv is installed
if command -v uv &> /dev/null; then
  export UV_CACHE_DIR="$HOME/dev/uv/cache/"
  export UV_PYTHON_PREFERENCE=only-managed
  export UV_PYTHON_INSTALL_DIR="$HOME/dev/uv/python/"
  export UV_PYTHON_BIN_DIR="$HOME/dev/uv/bin/"
  export UV_TOOL_DIR="$HOME/dev/uv/tools/"
  export UV_TOOL_BIN_DIR="$HOME/dev/uv/tbin/"
  export UV_LINK_MODE=symlink
  export PATH="$UV_PYTHON_BIN_DIR:$PATH"
  export PATH="$UV_TOOL_BIN_DIR:$PATH"
fi

# spicetify
export PATH="$PATH:$HOME/.local/share/spotify-launcher/install/usr/share/spotify/"


# Set the zinit home directory
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download zinit, if it's not there
if [[ ! -d "$ZINIT_HOME" ]]; then
  mkdir -p "$(dirname $ZINIT_HOME)"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Load zinit
source "${ZINIT_HOME}/zinit.zsh"

# zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# Load completions
autoload -U compinit && compinit

zinit cdreplay -q

# Keybinds
# bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
# bindkey '^[[3~' delete-char

# History
HISTSIZE=5000
HISTFILE=~/.zhistory
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Completion style
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

# Aliases
# alias ls='ls --color'
alias ls='eza --icons=auto --color=auto'
alias grep='grep --color=auto'
alias neofetch='fastfetch'
alias launch='hyprctl dispatch exec'


# never beep
setopt NO_BEEP

# Shell integrations
# eval "$(pyenv init - zsh)"
eval "$(fzf --zsh)"
eval "$(zoxide init --cmd cd zsh)"

# starship
function starship_transient_prompt_func {
  starship module character
}

eval "$(starship init zsh)"
enable_transience
