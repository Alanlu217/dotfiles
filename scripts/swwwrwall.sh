#!/usr/bin/env sh
cd ~/dotfiles/wallpapers
wall="$(ls | shuf -n 1)"
swww img --transition-step=4 --transition-fps 120 "$wall" &
swww img -n overlay --transition-step=4 --transition-fps 120 "$wall" &
rm -rf ~/.curr_bg
ln -s "$HOME/dotfiles/wallpapers/$wall" ~/.curr_bg
