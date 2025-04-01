deps:
    #!/usr/bin/env bash

    pkgs=(
      # Git stuff
      git 
      github-cli

      hyprland 
      hyprpaper # background
      hypridle # idler
      hyprlock # lock screen

      fish # better shell
      starship # prompt

      rofi-wayland # application launcher
      roficalc # calculator for rofi
      mako # notification launcher
      waybar # info bar
      blueman # bluetooth
      better-control-git # Better status
      wlogout # logout menu
      clipse # clipboard manager

      fastfetch # info

      # Lsp
      yaml-language-server
      clang
      tectonic

      # Applications
      alacritty
      nautilus
      firefox

      catppuccin-cursors-mocha # cursors
    )

    yay -S ${pkgs[@]}

