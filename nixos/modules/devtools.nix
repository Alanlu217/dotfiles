{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    gcc
    cmake
    clang-tools
    gnumake
    killall

    iverilog gtkwave
    typst tinymist

    go
    gopls

    rustup
    rust-analyzer

    python3
    uv

    zvm
  ];
}
