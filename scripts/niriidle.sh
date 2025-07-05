#!/usr/bin/env bash

swayidle \
  timeout 100 'brightnessctl set 5' resume 'brightnessctl set 80%' \
  timeout 110 'niri msg action power-off-monitors' resume 'niri msg action power-on-monitors' \
  timeout 120 'hyprlock'
  before-sleep 'hyprlock'

