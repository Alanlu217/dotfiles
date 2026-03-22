{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    gcc
    cmake
    clang-tools
    gnumake
    killall

    ghc haskell-language-server

    verible
    iverilog gtkwave
    typst tinymist

    go
    gopls

    rustup
    rust-analyzer

    python3
    uv

    arduino-cli

    zvm
  ];
}
