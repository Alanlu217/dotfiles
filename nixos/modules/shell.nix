{pkgs, inputs, ...}: {
  programs.fish.enable = true;
  programs.git.enable = true;
  programs.zoxide.enable = true;
  programs.neovim.enable = true;

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
    guile
    helix
    just
    nix-index
    nixd
    starship
    unzip
    rlwrap
    vim
    wget
    yazi
    zellij
    nushell
    tree-sitter
    watchexec
    ripgrep
    tmux
  ];
}
