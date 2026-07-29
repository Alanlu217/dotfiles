{pkgs, ...}: {
  services.flatpak.enable = true;

  environment.systemPackages = with pkgs; [
    gcc
    cmake
    clang-tools
    gnumake ninja
    killall

    tailscale

    verible
    iverilog surfer
    typst tinymist typstyle

    podman-compose

    go gopls
    rustup rust-analyzer
    python3 uv
    arduino-cli
  ];
}
