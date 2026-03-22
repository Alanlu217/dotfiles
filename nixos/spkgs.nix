{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    discord
    prismlauncher
    spotify
    zed-editor
    blender
    freecad
  ];
}
