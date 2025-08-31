{
  description = "my conf";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs =
    { nixpkgs, ... }:
    {
      nixosConfigurations.nixriver =
        let
          system = "x86_64-linux";
        in
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./devices/nixriver/configuration.nix

            ./spkgs.nix

            ./modules/enableflakes.nix
            ./modules/shell.nix
            ./modules/devtools.nix
            ./modules/distrobox.nix

            ./modules/niri.nix
            ./modules/steam.nix
            ./modules/libreoffice.nix
          ];
        };
    };
}
