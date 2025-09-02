{ pkgs, ... }:

{
  programs.fish.enable = true;
  programs.git.enable = true;
  programs.zoxide.enable = true;
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    helix
    fastfetch
    eza
    yazi
    fzf
    zellij
    just
    nixd
    nixfmt-rfc-style
    wget
    curl
    btop
    gh

    nix-index
  ];
}
