{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    gcc
    cmake
    clang-tools
    gnumake
    killall

    verible
    iverilog gtkwave
    typst tinymist typstyle
    tectonic texlab tex-fmt

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
