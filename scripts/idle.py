#!/usr/bin/env python3

import os

commands = {
    "Hyprland": """
swayidle \
  timeout 100 'brightnessctl set 5' resume 'brightnessctl set 80%' \
  timeout 110 'hyprctl dispatch dpms off' resume 'hyprctl dispatch dpms on' \
  timeout 120 'hyprlock' \
  before-sleep 'hyprlock'
""",
    "niri": """
swayidle \
  timeout 100 'brightnessctl set 5' resume 'brightnessctl set 80%' \
  timeout 110 'niri msg action power-off-monitors' resume 'niri msg action power-on-monitors' \
  timeout 120 'hyprlock' \
  before-sleep 'hyprlock'
""",
    "sway": """
swayidle -w \
     timeout 100 'brightnessctl set 5' resume 'brightnessctl set 80%' \
     timeout 110 'swaymsg "output * power off"' resume 'swaymsg "output * power on"' \
     timeout 120 'hyprlock' \
     before-sleep 'hyprlock'
""",
}

desktop = os.environ["XDG_CURRENT_DESKTOP"]
if desktop not in commands.keys():
    print("Desktop not supported")
    os._exit(0)

os.system(commands[desktop])
