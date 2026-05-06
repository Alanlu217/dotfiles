{pkgs, ...}: {
  services.flatpak.enable = true;
  
  environment.systemPackages = with pkgs; [
    gcc
    cmake
    clang-tools
    gnumake
    killall

    tailscale

    verible
    iverilog surfer
    typst tinymist typstyle
    tectonic texlab tex-fmt

    podman-compose

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
