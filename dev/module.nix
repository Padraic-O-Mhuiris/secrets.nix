# Development module - tests, checks, devShells, formatter
{
  inputs,
  lib,
  ...
}: {
  imports = [
    inputs.git-hooks.flakeModule
    ../flake-module.nix
    (import ../examples {secretsDir = ../secrets;})
  ];

  perSystem = {
    config,
    pkgs,
    system,
    ...
  }: let
    nix-unit = inputs.nix-unit.packages.${system}.default;
    testsModule = import ../tests {
      inherit lib pkgs nix-unit;
      corePath = ../core;
      fixturesPath = ../tests/fixtures;
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

    packages.unit-tests = testsModule.packages.unit-tests;

    checks =
      testsModule.checks
      // {
        lint-statix =
          pkgs.runCommand "lint-statix" {
            nativeBuildInputs = [pkgs.statix];
            src = ../.;
          } ''
            cd $src
            statix check .
            touch $out
          '';
        lint-deadnix =
          pkgs.runCommand "lint-deadnix" {
            nativeBuildInputs = [pkgs.deadnix];
            src = ../.;
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
}
