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

    tlp # Battery Saver

    # Audio stuff
    pipewire
    pipewire-alsa
    pipewire-pulse
    pavucontrol

    networkmanager # network manager
    bluez # bluetooth
    bluez-utils # bluetooth utils
    network-manager-applet # nm-applet
    blueman # blueman-applet
    brightnessctl

    adwaita-dark # theme

    fish # better shell
    starship # prompt
    watchexec

    rofi-wayland # application launcher
    rofi-calc # calculator for rofi
    mako # notification launcher
    waybar # info bar
    # wlogout # logout menu
    clipse # clipboard manager

    ttf-firacode-nerd # Fonts

    # for screenshotting
    wl-clipboard
    grim
    slurp

    fastfetch # info
    eza # Better ls
    zoxide # Better cd
    yazi # File manager

    # Latex
    tectonic
    tex-fmt

    # Dev
    zig zls
    clang
    openssh
    btop
    rustup rust-analyzer
    go gopls

    # Data / Math
    python-sympy
    python-matplotlib

    # Applications
    alacritty
    firefox
    nautilus
    eog
    evince
    steam
    spotify-player
  )

  paru -S ${pkgs[@]}

rwall:
    #!/usr/bin/env bash
    wall="$(pwd)/../wallpapers/$(ls ../wallpapers | shuf -n 1)"
    hyprctl hyprpaper reload ",$wall"
    rm -rf ~/.curr_bg
    ln -s "$wall" ~/.curr_bg

swall:
    #!/usr/bin/env bash
    name="$(ls ../wallpapers | rofi -dmenu)"
    if [ "${name}" == "" ]; then exit; fi
    wall="$(pwd)/../wallpapers/$name"
    hyprctl hyprpaper reload ",$wall"
    rm -rf ~/.curr_bg
    ln -s "$wall" ~/.curr_bg

setupwall:
    rm -rf ~/.curr_bg
    ln -s ~/dotfiles/wallpapers/dark-flowers.png ~/.curr_bg

