mod arch "scripts/arch.just"
mod alpine "scripts/alpine.just"
mod config
mod desktop

default:
    just -l

git-setup:
    git config --global user.email "alanlu2468@gmail.com"
    git config --global user.name "alanlu"
    git config --global core.editor "vim"

    git config --global alias.co checkout
    git config --global alias.st status

setup:
    just git-setup
    just desktop::desktop
    just wall::setup
    just config::all
