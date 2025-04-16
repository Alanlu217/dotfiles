rwal:
    #!/usr/bin/env bash
    wall="$(pwd)/wallpapers/$(ls wallpapers | shuf -n 1)"
    hyprctl hyprpaper reload ",$wall"
    rm -rf ~/.curr_bg
    ln -s "$wall" ~/.curr_bg

swal:
    #!/usr/bin/env bash
    wall="$(pwd)/wallpapers/$(ls wallpapers | rofi -dmenu)"
    hyprctl hyprpaper reload ",$wall"
    rm -rf ~/.curr_bg
    ln -s "$wall" ~/.curr_bg

setup: deps git-setup desktop bg-setup

git-setup:
    git config --global user.email "alanlu2468@gmail.com"
    git config --global user.name "alanlu"
    git config --global core.editor "vim"

    git config --global alias.co checkout
    git config --global alias.st status

desktop:
    #!/usr/bin/env bash

    cd desktop
    for f in *; do
        rm -rf ~/.local/share/applications/$f
        echo "ln -s $(pwd)/$f ~/.local/share/applications"
        ln -s "$(pwd)/$f" ~/.local/share/applications
    done

bg-setup:
    rm -rf ~/.curr_bg
    ln -s ~/dotfiles/wallpapers/dark-flowers.png ~/.curr_bg

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
