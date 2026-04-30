deps:
  #!/usr/bin/env bash

  pkgs=(
    base-devel
  
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

    # Audio stuff
    wireplumber
    pipewire
    pipewire-alsa
    pipewire-pulse
    pipewire-jack
    pavucontrol

    bluez # bluetooth
    bluez-utils # bluetooth utils
    blueman # blueman-applet
    brightnessctl
    avahi nss-mdns iwd

    fish # better shell
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
    clang
    openssh
    btop
    rustup rust-analyzer
    go gopls
    uv

    # Tools
    tmux
    tectonic
    typst tinymist typstyle

    # Applications
    kitty
    obsidian
    firefox
    thunar
    eog
    xdg-desktop-portal-gnome
    zathura zathura-pdf-poppler
    discord
    steam lib32-vulkan-intel
    spotify_player
    vulkan-intel
  )

  sudo pacman -S ${pkgs[@]}

  uv tool install ruff
  uv tool install pyrefly
  uv tool install ipython

  sudo systemctl enable bluetooth
  sudo systemctl enable dbus
  sudo systemctl enable avahi-daemon
  sudo systemctl enable iwd

paru:
    #!/usr/bin/env bash
    sudo pacman -S --needed base-devel rustup
    rustup toolchain install stable
    git clone https://aur.archlinux.org/paru.git
    cd paru
    makepkg -si
    cd ..
    rm -rf paru

