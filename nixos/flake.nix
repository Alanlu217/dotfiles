{
  description = "my conf";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = {nixpkgs, ...}@inputs: {
    nixosConfigurations.iodine-nix = let
      system = "x86_64-linux";
    in
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs;};
        modules = [
          ./devices/iodine-nix/configuration.nix

          ./spkgs.nix

          ./modules/enableflakes.nix
          ./modules/shell.nix
          ./modules/devtools.nix
          ./modules/nix-ld.nix
          ./modules/distrobox.nix

          ./modules/compositor.nix
          ./modules/steam.nix
          ./modules/libreoffice.nix
        ];
      };
  };
}
