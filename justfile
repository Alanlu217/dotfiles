deps:
    #!/usr/bin/env bash

    pkgs=(
      better-control-git
      catppuccin-cursors-mocha
      roficalc
      wlogout
      clipse
      git 
      github-cli
      hyprland
      hyprpaper
      hypridle
      hyprlock
      fish
      rofi-wayland
      mako
      waybar
      blueman
      fastfetch
      yaml-language-server
      clang
      tectonic
      alacritty
      nautilus
      firefox
    )

    yay -S ${pkgs[@]}

