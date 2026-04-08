mod arch "scripts/arch.just"
mod alpine "scripts/alpine.just"

default:
    just -l

setup: config applications git-setup

unsetup:
    make -C config clean
    make -C applications clean

config:
    touch ~/.profile.fish
    make -C config

applications:
    make -C applications

git-setup:
    git config --global user.email "alanlu2468@gmail.com"
    git config --global user.name "alanlu"
    git config --global core.editor "hx"

    git config --global commit.verbose true

