#!/usr/bin/env bash

SCRIPT=$(realpath "$0")
BASEDIR=$(dirname "$SCRIPT")

rm -f ~/.config/alacritty
ln -s "$BASEDIR/alacritty" ~/.config/alacritty

rm -f ~/.config/hypr
ln -s "$BASEDIR/hypr" ~/.config/hypr

rm -f ~/.config/mako
ln -s "$BASEDIR/mako" ~/.config/mako

rm -f ~/.config/rofi
ln -s "$BASEDIR/rofi" ~/.config/rofi

rm -f ~/.config/waybar
ln -s "$BASEDIR/waybar" ~/.config/waybar
