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
      
      networkmanager # network manager
      bluez # bluetooth
      bluez-utils # bluetooth utils
      network-manager-applet # nm-applet
      blueman # blueman-applet

      adwaita-dark # theme

      fish # better shell
      starship # prompt
      watchexec

      rofi-wayland # application launcher
      rofi-calc # calculator for rofi
      mako # notification launcher
      waybar # info bar
      wlogout # logout menu
      clipse # clipboard manager

      nerd-fonts # Fonts

      # for screenshotting
      wl-clipboard
      grim
      slurp

      fastfetch # info

      # Lsp
      clang
      tectonic
      tex-fmt

      # Applications
      alacritty
      nautilus
      zen-browser-bin
      evince
      steam

      catppuccin-cursors-mocha # cursors
    )

    yay -S ${pkgs[@]}

git-setup:
    git config --global user.email "alanlu2468@gmail.com"
    git config --global user.name "alanlu"
    git config --global core.editor "vim"

    git config --global alias.co checkout
    git config --global alias.st status


