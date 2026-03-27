{pkgs, inputs, ...}: {
  programs.fish.enable = true;
  programs.git.enable = true;
  programs.zoxide.enable = true;
  programs.neovim = {
    enable = true;
    withNodeJs = true;
    vimAlias = true;
    viAlias = true;
    package = inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;
  };

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
  ];
}
