{pkgs, ...}: {
  imports = [
    ./io.nix
    ./powerkeydisable.nix
  ];

  programs.niri.enable = true;
  programs.hyprlock.enable = true;
  programs.xwayland.enable = true;
  programs.thunderbird.enable = true;

  environment.systemPackages = with pkgs; [
    alacritty
    waybar
    swayidle
    swww
    mako
    rofi-wayland
    adwaita-icon-theme
    xwayland-satellite
    firefox-bin
    nautilus
    evince
  ];

  fonts.packages = with pkgs; [
    noto-fonts
    nerd-fonts.jetbrains-mono
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
