if status is-interactive
    # Commands to run in interactive sessions can go here
end

set SAL_USE_VCLPLUGIN gtk4

export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/dotfiles/bin:$PATH"

# Abbreviations
alias l="eza -l"
alias hx="helix"
alias task="go-task"
alias tex="tectonic -X"

starship init fish | source
