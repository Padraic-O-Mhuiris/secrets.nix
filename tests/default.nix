# Tests module for secrets.nix
#
# Provides checks and packages for running tests.
# Inherited by root flake.
#
# Usage in flake.nix:
#   perSystem = {pkgs, ...}: let
#     testsModule = import ./tests {inherit lib pkgs nix-unit;};
#   in {
#     checks = testsModule.checks;
#     packages = testsModule.packages;
#   };
#
{
  lib,
  pkgs,
  nix-unit,
  corePath ? ../core,
  fixturesPath ? ./fixtures,
}: let
  # Shared test expression string for both check and package
  unitTestExpr = ''(import ${./unit} {lib = import ${pkgs.path}/lib; pkgs = import ${pkgs.path} {system = "${pkgs.system}";}; corePath = ${corePath}; fixturesPath = ${fixturesPath};})'';
in {
  checks = {
    unit-tests =
      pkgs.runCommand "unit-tests" {
        nativeBuildInputs = [nix-unit];
      } ''
        export HOME=$(mktemp -d)
        nix-unit --expr '${unitTestExpr}'
        touch $out
      '';
  };

  packages = {
    # Run unit tests: nix run .#unit-tests
    unit-tests = pkgs.writeShellApplication {
      name = "unit-tests";
      runtimeInputs = [nix-unit];
      text = ''
        nix-unit --expr '${unitTestExpr}'
      '';
    };
  };
}
