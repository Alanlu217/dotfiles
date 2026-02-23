deps:
  #!/usr/bin/env bash

  pkgs=(
    # Git stuff
    git
    github-cli

    ly

    niri
    xwayland-satellite
    swww
    rofi # application launcher
    mako # notification launcher
    waybar # info bar
    hyprlock # lock screen
    swayidle # idler

    tlp # Battery Saver

    # Audio stuff
    wireplumber
    pipewire
    pipewire-alsa
    pipewire-pulse
    pipewire-jack
    pavucontrol

    networkmanager # network manager
    bluez # bluetooth
    bluez-utils # bluetooth utils
    network-manager-applet # nm-applet
    blueman # blueman-applet
    brightnessctl
    avahi nss-mdns

    nushell # better shell
    watchexec

    ttf-iosevka-nerd # Fonts
    ttf-jetbrains-mono-nerd # Fonts
    noto-fonts-cjk
    noto-fonts

    # for screenshotting
    wl-clipboard
    grim
    slurp

    fastfetch # info
    eza # Better ls
    zoxide # Better cd
    yazi # File manager
    fzf
    helix
    man-db man-pages

    # Dev
    zig zls
    clang
    openssh
    btop
    rustup rust-analyzer
    go gopls
    uv

    # Tools
    tmux
    tectonic

    # Applications
    alacritty
    obsidian
    firefox
    thunar
    eog
    evince
    zathura zathura-pdf-poppler
    steam
    spotify-launcher
    vulkan-intel
  )

  sudo pacman -S ${pkgs[@]}

  uv tool install ruff
  uv tool install pyrefly

  sudo systemctl enable bluetooth
  sudo systemctl enable tlp
  sudo systemctl enable dbus
  sudo systemctl enable avahi-daemon

paru:
    #!/usr/bin/env bash
    sudo pacman -S --needed base-devel rustup
    rustup toolchain install stable
    git clone https://aur.archlinux.org/paru.git
    cd paru
    makepkg -si
    cd ..
    rm -rf paru

