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

      # Audio stuff
      pipewire
      pipewire-alsa
      pipewire-pulse
      pwvucontrol
      
      networkmanager # network manager
      bluez # bluetooth
      bluez-utils # bluetooth utils
      network-manager-applet # nm-applet
      blueman # blueman-applet

      adwaita-dark # theme

      fish # better shell
      starship # prompt

      rofi-wayland # application launcher
      rofi-calc # calculator for rofi
      mako # notification launcher
      waybar # info bar
      blueman # bluetooth
      wlogout # logout menu
      clipse # clipboard manager

      nerd-fonts # Fonts

      # for screenshotting
      wl-clipboard
      grim
      slurp

      fastfetch # info

      # Lsp
      yaml-language-server
      clang
      tectonic
      tex-fmt

      # Applications
      alacritty
      nautilus
      firefox
      evince
      steam
      vesktop

      catppuccin-cursors-mocha # cursors
    )

    yay -S ${pkgs[@]}

