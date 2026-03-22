#!/usr/bin/env python3

import os

hyprland_command = """
swayidle \
  timeout 100 'brightnessctl set 5' resume 'brightnessctl set 80%' \
  timeout 110 'hyprctl dispatch dpms off' resume 'hyprctl dispatch dpms on' \
  timeout 120 'hyprlock' \
  before-sleep 'hyprlock'
"""

niri_command = """
swayidle \
  timeout 100 'brightnessctl set 5' resume 'brightnessctl set 80%' \
  timeout 110 'niri msg action power-off-monitors' resume 'niri msg action power-on-monitors' \
  timeout 120 'hyprlock' \
  before-sleep 'hyprlock'
"""

match os.environ["XDG_CURRENT_DESKTOP"]:
    case "niri":
        os.system(niri_command)
    case "Hyprland":
        os.system(hyprland_command)
