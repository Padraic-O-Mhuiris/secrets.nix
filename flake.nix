{
  description = "Declarative SOPS secrets management with flake-parts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}: let
    inherit (inputs.nixpkgs) lib;
    inherit (import ./core {inherit lib;}) mkSecrets mkSecretsPackages;
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [inputs.flake-parts.flakeModules.partitions];

      systems = lib.systems.flakeExposed;

      # Dev outputs come from the dev partition
      partitionedAttrs = {
        checks = "dev";
        devShells = "dev";
        formatter = "dev";
        packages = "dev";
      };

      partitions.dev = {
        extraInputsFlake = ./dev;
        module = ./dev/module.nix;
      };

      # Main flake only exposes lib and flakeModule
      flake = {
        flakeModule = ./flake-module.nix;
        lib = {inherit mkSecrets mkSecretsPackages;};
      };
    };
}
