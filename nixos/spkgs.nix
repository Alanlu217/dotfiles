{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    discord
    prismlauncher
    glfw3-minecraft
    spotify
    zed-editor
    blender
    freecad
  ];
}
