{pkgs, ...}: {
  programs.fish.enable = true;
  programs.git.enable = true;
  programs.zoxide.enable = true;

  environment.systemPackages = with pkgs; [
    alejandra
    btop
    curl
    eza
    fastfetch
    fzf
    gh
    gnutar
    gping
    helix
    just
    nix-index
    nixd
    starship
    unzip
    vim
    wget
    yazi
    zellij
    nushell
  ];
}
