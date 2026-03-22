{pkgs, ...}: {
  imports = [
    ./io.nix
    ./powerkeydisable.nix
  ];

  programs.dconf.enable = true;
  programs.niri.enable = true;
  programs.hyprland.enable = true;
  programs.hyprlock.enable = true;
  programs.xwayland.enable = true;
  programs.thunar.enable = true;

  services.upower.enable = true;

  environment.systemPackages = with pkgs; [
    gsettings-desktop-schemas
    alacritty
    waybar
    swayidle
    swww
    mako
    rofi-wayland
    wl-clipboard
    xwayland-satellite
    firefox-bin
    obsidian
    evince
    libnotify
    adwaita-icon-theme
    grim slurp
  ];

  fonts.packages = with pkgs; [
    noto-fonts
    nerd-fonts.jetbrains-mono
    nerd-fonts.iosevka
  ];

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gnome
      pkgs.xdg-desktop-portal-gtk
      pkgs.gnome-keyring
    ];
    xdgOpenUsePortal = true;
  };
}
