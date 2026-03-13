{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    gcc
    cmake
    clang-tools
    gnumake
    killall

    go
    gopls

    rustup
    rust-analyzer

    python3

    zvm
  ];
}
