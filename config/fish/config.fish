if status is-interactive
    # Commands to run in interactive sessions can go here
end

export PATH="$HOME/dotfiles/bin:$PATH"
set -gx PAGER "nvim +Man!"
set -gx MANPAGER "nvim +Man!"

# Abbreviations
alias l="eza -l --git --no-user --no-permissions"
alias vi="nvim"
alias task="go-task"
alias tex="tectonic -X"

starship init fish | source
zoxide init fish | source
