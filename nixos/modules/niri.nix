{pkgs, ...}: {
  imports = [
    ./io.nix
    ./powerkeydisable.nix
  ];

  programs.niri.enable = true;
  programs.hyprlock.enable = true;
  programs.xwayland.enable = true;
  programs.thunar.enable = true;

  environment.systemPackages = with pkgs; [
    alacritty
    waybar
    swayidle
    swww
    mako
    rofi-wayland
    wl-clipboard
    adwaita-icon-theme
    xwayland-satellite
    firefox-bin
    obsidian
    evince
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
