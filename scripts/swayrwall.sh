#!/usr/bin/env sh
cd ~/dotfiles/scripts
wall="$(pwd)/../wallpapers/$(ls ../wallpapers | shuf -n 1)"
pkill swaybg
swaybg -i "$wall" &
rm -rf ~/.curr_bg
ln -s "$wall" ~/.curr_bg

