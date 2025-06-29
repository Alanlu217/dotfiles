mod arch "scripts/arch.just"
mod alpine "scripts/alpine.just"
mod config

default:
    just -l

git-setup:
    git config --global user.email "alanlu2468@gmail.com"
    git config --global user.name "alanlu"
    git config --global core.editor "nvim"

    git config --global commit.verbose true

setup:
    just git-setup
    just config::all
