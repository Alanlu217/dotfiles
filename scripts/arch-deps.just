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
    eza # Better ls

    # Latex
    tectonic
    tex-fmt

    # Dev
    zig
    clang
    openssh
    htop

    # Data / Math
    python-sympy
    python-matplotlib

    # Applications
    alacritty
    nautilus
    zen-browser-bin
    eog
    evince
    steam

    catppuccin-cursors-mocha # cursors
  )

  yay -S ${pkgs[@]}

