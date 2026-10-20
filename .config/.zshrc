# --------------------------------------------------
# Live autocompletion (must be sourced FIRST, before compinit)
# --------------------------------------------------

# Arch package path, then a distro package elsewhere, then the per-user clone
# that fedora/install.sh makes (~/.local/share/zsh/zsh-autocomplete)
for _43pr_ac in \
    /usr/share/zsh/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh \
    /usr/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh \
    "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/zsh-autocomplete/zsh-autocomplete.plugin.zsh"; do
    [[ -r "$_43pr_ac" ]] && { source "$_43pr_ac"; break; }
done
unset _43pr_ac

# Start suggesting after 1 character, with a tiny delay so it feels smooth
zstyle ':autocomplete:*' min-input 1
zstyle ':autocomplete:*' delay 0.05

# Tab cycles through the menu, Shift+Tab goes backwards
bindkey '^I' menu-complete
bindkey "$terminfo[kcbt]" reverse-menu-complete

# Keep Up/Down arrows as normal history navigation
bindkey '^[[A' up-line-or-history
bindkey '^[[B' down-line-or-history

# --------------------------------------------------
# Prompt
# --------------------------------------------------

eval "$(starship init zsh)"

# --------------------------------------------------
# eza (monochrome)
# --------------------------------------------------

export EZA_COLORS="uu=bright-black:gu=bright-black:da=bright-black:ur=white:uw=bright-black:ux=white:ue=bright-black:gr=bright-black:gw=bright-black:gx=white:tr=bright-black:fi=white:di=bright-white:ln=bright-black:pi=bright-black:so=bright-black:bd=bright-black:cd=bright-black:or=bright-black:mi=bright-black:ex=white"

alias ls='eza --icons'
alias ll='eza -lah --icons --git'
alias la='eza -a --icons'
alias lt='eza --tree --icons'

# --------------------------------------------------
# Completion styling
# --------------------------------------------------

# Case-insensitive matching
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Grayscale completion colors
zstyle ':completion:*' list-colors \
  '=(#b)*(=0)=38;5;250' \
  '=(#b)*(=1)=38;5;255' \
  '=(#b)*(=2)=38;5;245' \
  '=(#b)*(=3)=38;5;240'

# Dim group headers
zstyle ':completion:*:descriptions' format '%F{8}-- %d --%f'

# --------------------------------------------------
# History
# --------------------------------------------------

HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000

setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS

# --------------------------------------------------
# Autosuggestions
# --------------------------------------------------

# Plugin paths differ per distro (Arch: /usr/share/zsh/plugins/<name>, Fedora: /usr/share/<name>)
_43pr_source_plugin() {
    local f
    for f in "/usr/share/zsh/plugins/$1/$1.zsh" "/usr/share/$1/$1.zsh"; do
        [[ -r "$f" ]] && { source "$f"; return 0; }
    done
}

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
_43pr_source_plugin zsh-autosuggestions

# --------------------------------------------------
# Syntax highlighting (keep LAST)
# --------------------------------------------------

_43pr_source_plugin zsh-syntax-highlighting
unfunction _43pr_source_plugin

ZSH_HIGHLIGHT_STYLES[command]='fg=white'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=white'
ZSH_HIGHLIGHT_STYLES[function]='fg=white'
ZSH_HIGHLIGHT_STYLES[alias]='fg=white'
ZSH_HIGHLIGHT_STYLES[path]='fg=245'
ZSH_HIGHLIGHT_STYLES[comment]='fg=240'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=245'

# --------------------------------------------------
# 43PR theme controller
# --------------------------------------------------

theme() { python3 "$HOME/.config/43pr/bin/theme.py" "$@"; }

# --------------------------------------------------
# SSH from kitty
# --------------------------------------------------
# kitty sets TERM=xterm-kitty, which most remote hosts have no terminfo
# for: `clear` fails ("unknown terminal type") and Ctrl+L just prints a new
# prompt. Plain `ssh` advertises xterm-256color instead: works everywhere
# and leaves nothing on the remote host (matters on engagement targets).
# `kssh` = kitten ssh: full kitty features, but it copies kitty's terminfo
# and shell integration onto the remote host. Use it only on your own boxes.
if [[ "$TERM" == "xterm-kitty" ]]; then
    ssh() { TERM=xterm-256color command ssh "$@" }
    alias kssh='kitten ssh'
fi
