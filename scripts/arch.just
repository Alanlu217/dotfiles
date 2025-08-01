deps:
  #!/usr/bin/env bash

  pkgs=(
    # Git stuff
    git
    github-cli

    ly

    niri
    xwayland-satellite
    swaybg
    rofi-wayland # application launcher
    mako # notification launcher
    waybar # info bar
    hyprlock # lock screen

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

    fish # better shell
    starship # prompt
    watchexec

    ttf-iosevka-nerd # Fonts
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

    # Dev
    zig zls
    clang
    openssh
    btop
    rustup rust-analyzer
    go gopls

    # Applications
    ghostty
    firefox
    thunderbird
    nautilus
    eog
    evince
    zed gnu-netcat vulkan-intel
  )

  sudo pacman -S ${pkgs[@]}

  sudo systemctl enable bluetooth
  sudo systemctl enable tlp
  sudo systemctl enable ly
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

extra:
    #!/usr/bin/env bash

    pkgs=(
        noto-fonts-cjk
        steam
        spotify-launcher

        # Latex
        tectonic
        tex-fmt
    )

    paru -Syu ${pkgs[@]}

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

