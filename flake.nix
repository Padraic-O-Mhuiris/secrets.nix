{
  description = "Declarative SOPS secrets management with flake-parts";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs @ {
    flake-parts,
    self,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} ({flake-parts-lib, ...}: let
      flake-module = flake-parts-lib.importApply ./flake-module {flake = self;};
      lib = import ./lib {inherit (inputs.nixpkgs) lib;};
    in {
      imports = [
        flake-module
        ./examples
      ];
      systems = inputs.nixpkgs.lib.systems.flakeExposed;
      perSystem = {
        config,
        pkgs,
        ...
      }: {
        devShells.default = pkgs.mkShell {
          packages = [pkgs.alejandra pkgs.sops pkgs.age];
        };
      };
      flake = rec {
        inherit flake-module lib;
        flakeModules.default = flake-module;
      };
    });
}
