{
  description = "Declarative SOPS secrets management with flake-parts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    nix-unit = {
      url = "github:nix-community/nix-unit";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}: let
    inherit (inputs.nixpkgs) lib;
    inherit (import ./core {inherit lib;}) mkSecrets mkSecretsPackages;
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.git-hooks.flakeModule
        ./flake-module.nix
        (import ./examples {secretsDir = ./secrets;})
      ];

      systems = inputs.nixpkgs.lib.systems.flakeExposed;

      perSystem = {
        config,
        pkgs,
        system,
        ...
      }: let
        nix-unit = inputs.nix-unit.packages.${system}.default;
        testsModule = import ./tests {
          inherit lib pkgs nix-unit;
          corePath = ./core;
          fixturesPath = ./tests/fixtures;
        };
      in {
        pre-commit.settings.hooks = {
          alejandra.enable = true;
          statix.enable = true;
          deadnix.enable = true;
        };

        devShells.default = pkgs.mkShell {
          shellHook = config.pre-commit.installationScript;
          packages =
            [
              pkgs.sops
              pkgs.age
              nix-unit
            ]
            ++ config.pre-commit.settings.enabledPackages;
        };

        packages = {
          inherit (testsModule.packages) unit-tests;
        };

        checks =
          testsModule.checks
          // {
            lint-statix =
              pkgs.runCommand "lint-statix" {
                nativeBuildInputs = [pkgs.statix];
                src = ./.;
              } ''
                cd $src
                statix check .
                touch $out
              '';
            lint-deadnix =
              pkgs.runCommand "lint-deadnix" {
                nativeBuildInputs = [pkgs.deadnix];
                src = ./.;
              } ''
                cd $src
                deadnix --fail .
                touch $out
              '';
          };

        formatter = pkgs.writeShellApplication {
          name = "fmt";
          runtimeInputs = [pkgs.alejandra pkgs.findutils];
          text = ''
            find . -name '*.nix' -exec alejandra "$@" {} +
          '';
        };
      };

      flake = {
        flakeModule = ./flake-module.nix;
        lib = {inherit mkSecrets mkSecretsPackages;};
      };
    };
}
