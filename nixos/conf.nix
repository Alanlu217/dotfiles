{ config, pkgs, ... }:

{
  time.timeZone = "Australia/Adelaide";

  # Programs
  programs.fish.enable = true;
  programs.niri.enable = true;
  programs.waybar.enable = true;
  programs.git.enable = true;
  programs.hyprlock.enable = true;
  programs.zoxide.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
     vim helix
     fastfetch eza yazi fzf
     wget
     just

     gh

     swww mako
     rofi-wayland

     alacritty
     firefox
  ];

  fonts.packages = with pkgs; [
    noto-fonts
    nerd-fonts.jetbrains-mono
  ];
}
