#!/usr/bin/env bash

rm -rf ~/.config/lvim
stow lvim

rm -rf ~/.config/starship.toml
stow starship

rm -rf ~/.zshrc
rm -rf ~/.zprofile
stow zsh
