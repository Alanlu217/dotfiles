#!/usr/bin/env sh
cd ~/dotfiles/scripts
name="$(ls ../wallpapers | rofi -dmenu)"
if [ "${name}" == "" ]; then exit; fi
wall="$(pwd)/../wallpapers/$name"
niri msg action do-screen-transition --delay-ms 150
pkill swaybg
swaybg -i "$wall" &
rm -rf ~/.curr_bg
ln -s "$wall" ~/.curr_bg

