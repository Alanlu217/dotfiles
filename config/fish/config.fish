if status is-interactive
    # Commands to run in interactive sessions can go here
end

export PATH="$HOME/dotfiles/bin:$PATH"

set -gx GTK_THEME Adwaita:dark

set -gx PAGER less
set -gx MANPAGER less

function f
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file="$tmp"
    if read -z cwd <"$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
        builtin cd -- "$cwd"
    end
    rm -f -- "$tmp"
end

# Abbreviations
alias ls="eza --icons --git"
alias l="eza --icons -l --git --no-user --no-permissions"
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
alias gco="git checkout"

alias gi="git init"
alias gcl="git clone"

alias d="docker"
alias dc="docker compose"

alias edot='helix $(fzf --walker-root ~/dotfiles)'

starship init fish | source
zoxide init fish | source

enable_transience

source ~/.profile.fish
