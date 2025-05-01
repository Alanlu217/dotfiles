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
  doas rc-update add bluetooth

  doas rc-update del elogind
  doas apk del elogind

deps:
  #!/usr/bin/env sh

  pkgs=(
    # Drivers / firmware
    intel-ucode
    linux-firmware sof-firmware
    mesa-dri-gallium mesa-va-gallium intel-media-driver

    # System
    e2fsprogs
    lsblk

    seatd
    dbus dbus-x11
    linux-pam pam-rundir
    shadow shadow-login
    polkit

    fastfetch
    gcompat
    neovim
    fish starship

    # Misc
    btop
    build-base
    cmake ninja
    eza zoxide
    git github-cli
    wget curl
    just

    # Audio
    pipewire wireplumber pipewire-pulse pipewire-alsa pavucontrol

    # Bluetooth
    bluez bluez-openrc pipewire-spa-bluez blueman

    # Dev
    zig
    tectonic
    rust cargo rust-analyzer

    # Sway
    sway swaybg swayidle swaylock swaylock-effects
    libxcursor xdg-utils xwayland
    rofi-wayland
    mako
    wlogout
    wlr-randr
    brightnessctl
    grim slurp
    wl-clipboard

    # Applications
    thunar
    evince
    alacritty
    firefox

    # Themes
    adwaita-icon-theme
    font-fira-code-nerd
    font-terminus
  )

  doas apk del util-linux-login
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

