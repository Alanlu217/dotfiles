{ config, pkgs, ... }:

{
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true; 
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # Programs
  programs.fish.enable = true;
  programs.niri.enable = true;
  programs.git.enable = true;
  programs.hyprlock.enable = true;
  programs.zoxide.enable = true;
  programs.thunderbird.enable = true;
  programs.xwayland.enable = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true; 
  };

  programs.nix-ld = {
    enable = true;
    libraries = pkgs.steam-run.args.multiPkgs pkgs;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim helix
    fastfetch eza yazi fzf
    btop
    wget
    just
    gh

    nix-index
    gcc cmake clang-tools gnumake
    go gopls
    rustup rust-analyzer
    python3
    zvm zls
    xwayland-satellite

    waybar
    swww mako
    rofi-wayland
    pavucontrol
    adwaita-icon-theme

    alacritty
    firefox
    nautilus
    evince
    vesktop
    prismlauncher
    spotify
    zed-editor
    blender
    freecad

    libreoffice-qt
    hunspell
    hunspellDicts.en_AU
  ];

  fonts.packages = with pkgs; [
    noto-fonts
    nerd-fonts.jetbrains-mono
  ];

  services.logind.extraConfig = ''
    HandlePowerKey=ignore
  '';
}
