if status is-interactive
    # Commands to run in interactive sessions can go here
end

export PATH="$HOME/dotfiles/bin:$PATH"

set -gx GTK_THEME Adwaita:dark

set -gx PAGER less
set -gx MANPAGER less

# Abbreviations
alias l="eza -l --git --no-user --no-permissions"
alias vi="nvim"
alias task="go-task"
alias tex="tectonic -X"
alias y="yazi"

alias gs="git status --short"
alias gd="git diff"
alias ga="git add"
alias gc="git commit"

alias gp="git push"
alias gu="git pull"

alias gl="git log"
alias gb="git branch"

alias gi="git init"
alias gcl="git clone"

alias edot='helix $(fzf --walker-root ~/dotfiles)'

starship init fish | source
zoxide init fish | source
carapace _carapace | source

enable_transience

source ~/.profile.fish
