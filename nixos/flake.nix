{
  description = "my conf";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
  };

  outputs = {nixpkgs, ...}@inputs: {
    nixosConfigurations.nixriver = let
      system = "x86_64-linux";
    in
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs;};
        modules = [
          ./devices/nixriver/configuration.nix

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
