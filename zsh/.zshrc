ZSH="${HOME}/.oh-my-zsh"

#Theme
ZSH_THEME=""

#Plugins
plugins=(git)
source $ZSH/oh-my-zsh.sh

#Star Ship
eval "$(starship init zsh)"
