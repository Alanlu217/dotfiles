#!/usr/bin/env sh
cd ~/dotfiles/wallpapers
wall="$(ls | shuf -n 1)"
swww img --transition-step=4 --transition-fps 120 "$wall" &
rm -rf ~/.curr_bg
ln -s "$wall" ~/.curr_bg
