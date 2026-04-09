{ pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;
  programs.nix-ld = {
    enable = true;
    libraries = [];
  };  

}
