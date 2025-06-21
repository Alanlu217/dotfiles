#!/usr/bin/env sh
cd ~/dotfiles/scripts
name="$(ls ../wallpapers | rofi -dmenu)"
if [ "${name}" == "" ]; then exit; fi
wall="$(pwd)/../wallpapers/$name"
pkill swaybg
swaybg -i "$wall" &
rm -rf ~/.curr_bg
ln -s "$wall" ~/.curr_bg

