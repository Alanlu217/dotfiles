default:
    just -l

setup:
  #!/usr/bin/env sh
  doas setup-devd udev
  doas setup-wayland-base
  doas setup-xorg-base

  doas rc-update add udev
  doas rc-update add swap
  doas rc-update add consolefont
  doas rc-update add seatd
  doas rc-update add polkit
  doas rc-update add dbus

deps:
  #!/usr/bin/env sh

  pkgs=(
    # Drivers / firmware
    intel-media-driver
    intel-ucode
    linux-firmware
    sof-firmware
    mesa-dri-gallium
    mesa-va-gallium

    # System
    dbus
    fastfetch
    e2fsprogs
    gcompat
    fish
    linux-pam
    pam-rundir
    polkit
    lsblk
    seatd
    shadow
    shadow-login
    starship
    neovim

    # Sway
    xdg-utils
    xwayland
    rofi-wayland
    mako
    sway
    wlogout
    wlr-randr
    brightnessctl

    # Applications
    dolphin
    alacritty
    firefox

    # Themes
    adwaita-icon-theme
    font-fira-code-nerd
    font-terminus

    # Dev
    btop
    build-base
    cmake
    eza
    git
    github-cli
    grim
    just
    ninja
    rustup
    wget
    zig

  )

  doas apk add ${pkgs[@]}

rwall:
    #!/usr/bin/env sh
    wall="$(pwd)/../wallpapers/$(ls ../wallpapers | shuf -n 1)"
    pkill swaybg
    swaybg -i "$wall" &
    rm -rf ~/.curr_bg
    ln -s "$wall" ~/.curr_bg

swall:
    #!/usr/bin/env sh
    name="$(ls ../wallpapers | rofi -dmenu)"
    if [ "${name}" == "" ]; then exit; fi
    wall="$(pwd)/../wallpapers/$name"
    pkill swaybg
    swaybg -i "$wall" &
    rm -rf ~/.curr_bg
    ln -s "$wall" ~/.curr_bg

setupwall:
    rm -rf ~/.curr_bg
    ln -s ~/dotfiles/wallpapers/dark-flowers.png ~/.curr_bg

