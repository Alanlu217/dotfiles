# config.nu
#
# Installed by:
# version = "0.104.1"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# This file is loaded after env.nu and before login.nu
#
# You can open this file in your default editor using:
# config nu
#
# See `help config nu` for more options
#
# You can remove these comments if you want or leave
# them for future reference.

$env.config.buffer_editor = "helix"
$env.config.edit_mode = 'vi'

alias hx = helix

alias l = eza -l --git --no-user --no-permissions
alias vi = nvim
alias task = go-task
alias tex = tectonic -X
alias y = yazi

alias gs = git status --short
alias gd = git diff
alias ga  =  git add
alias gc = git commit

alias gp = git push
alias gu = git pull

alias gl = git log
alias gb = git branch

alias gi = git init
alias gcl = git clone

alias edot = helix (fzf --walker-root ~/dotfiles)

$env.TRANSIENT_PROMPT_COMMAND = ""

$env.config.show_banner = false

# source ~/.config/nushell/zoxide.nu
# source ~/.config/nushell/starship.nu
# source ~/.config/nushell/carapace.nu
