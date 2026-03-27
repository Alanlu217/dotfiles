#!/usr/bin/env sh
cd ~/dotfiles/wallpapers
wall="$(ls | shuf -n 1)"
awww img --transition-step=4 --transition-fps 120 "$wall" &
awww img -n overlay --transition-step=4 --transition-fps 120 "$wall" &
rm -rf ~/.curr_bg
ln -s "$HOME/dotfiles/wallpapers/$wall" ~/.curr_bg
