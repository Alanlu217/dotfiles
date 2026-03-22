#!/usr/bin/env bash

if [[ $XDG_CURRENT_DESKTOP -eq "Hyprland" ]]; then
  swayidle \
    timeout 100 'brightnessctl set 5' resume 'brightnessctl set 80%' \
    timeout 110 'hyprctl dispatch dpms off' resume 'hyprctl dispatch dpms on' \
    timeout 120 'hyprlock' \
    before-sleep 'hyprlock'

    exit
fi

if [[ $XDG_CURRENT_DESKTOP -eq "Niri" ]]; then
  swayidle \
    timeout 100 'brightnessctl set 5' resume 'brightnessctl set 80%' \
    timeout 110 'niri msg action power-off-monitors' resume 'niri msg action power-on-monitors' \
    timeout 120 'hyprlock' \
    before-sleep 'hyprlock'

    exit
fi

