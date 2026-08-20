# .bashrc fedoriri — CLI « Omarchy-like ».

[ -f /etc/bashrc ] && . /etc/bashrc

# Outils modernes (tous packagés Fedora).
alias ls='eza --group-directories-first'
alias ll='eza -l --group-directories-first'
alias la='eza -la --group-directories-first'
alias cat='bat --paging=never --style=plain'
alias grep='rg'
alias find='fd'
alias vim='nvim'

export EDITOR=nvim
export VISUAL=nvim

# zoxide : cd intelligent (z / zi).
command -v zoxide >/dev/null && eval "$(zoxide init bash)"

# starship : prompt (installé par packaging/starship au premier boot ;
# le test évite un prompt cassé avant cela).
command -v starship >/dev/null && eval "$(starship init bash)"

command -v fastfetch >/dev/null && [ -n "${WAYLAND_DISPLAY:-}" ] && fastfetch
