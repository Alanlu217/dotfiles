#!/usr/bin/env sh
cd ~/dotfiles/wallpapers
name="$(ls | rofi -dmenu)"
if [ "${name}" == "" ]; then exit; fi
wall="$(pwd)/../wallpapers/$name"
swww img --transition-step=4 --transition-fps 120 "$wall" &
rm -rf ~/.curr_bg
ln -s "$wall" ~/.curr_bg
