if status is-interactive
    # Commands to run in interactive sessions can go here
end

export PATH="$HOME/dotfiles/bin:$PATH"

set -gx GTK_THEME Adwaita:dark

set -gx PAGER "nvim +Man!"
set -gx MANPAGER "nvim +Man!"

# Abbreviations
alias l="eza -l --git --no-user --no-permissions"
alias vi="nvim"
alias task="go-task"
alias tex="tectonic -X"

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

starship init fish | source
zoxide init fish | source

source ~/.profile.fish
