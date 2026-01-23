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
  # Base paths for test expressions
  libExpr = "import ${pkgs.path}/lib";
  pkgsExpr = "import ${pkgs.path} {system = \"${pkgs.stdenv.hostPlatform.system}\";}";
  coreExpr = "${corePath}";
  fixturesExpr = "${fixturesPath}";

  # Shared context expression
  ctxExpr = ''{lib = ${libExpr}; pkgs = ${pkgsExpr}; mkSecrets = (import ${coreExpr} {lib = ${libExpr};}).mkSecrets; mkSecretsPackages = (import ${coreExpr} {lib = ${libExpr};}).mkSecretsPackages; testDir = /tmp/test-secrets; fixturesSecretsDir = ${fixturesExpr} + "/secrets"; validAgeKey1 = "age1yct6cdz4f2hguaamc0jqxjx0m00v2puqacx0339mutagv8xmpffqcxql4v"; validAgeKey2 = "age1wdw6tuppmmcufrh6wzgy93jah9wzppaqn69wt5un8qzz8lk5ep5ss6ed3f"; validAgeKey3 = "age1jmxpfw8y5e5njm5fq08n65ceu7vuydx5l8wxk7hyu9s3x5qs93ysxqrd8l";}'';

  # Test groups - pure (no pkgs needed for evaluation)
  pureGroups = ["age-key" "format" "derived" "recipient" "operations"];

  # Test groups - require pkgs
  pkgsGroups = ["packages" "exists"];

  allGroups = pureGroups ++ pkgsGroups;

  # Generate expression for a single test group
  groupExpr = group: ''(import ${./unit}/${group}.nix {ctx = ${ctxExpr};})'';

  # Generate expression for all tests
  allTestsExpr = ''(import ${./unit} {lib = ${libExpr}; pkgs = ${pkgsExpr}; corePath = ${coreExpr}; fixturesPath = ${fixturesExpr};})'';

  # Create a check for a single test group
  mkGroupCheck = group:
    pkgs.runCommand "unit-tests-${group}" {
      nativeBuildInputs = [nix-unit];
    } ''
      export HOME=$(mktemp -d)
      nix-unit --expr '${groupExpr group}'
      touch $out
    '';
in {
  # Individual group checks
  checks =
    lib.listToAttrs (map (group: lib.nameValuePair "unit-tests-${group}" (mkGroupCheck group)) allGroups);

  # Single combined package for running all tests
  packages = {
    unit-tests = pkgs.writeShellApplication {
      name = "unit-tests";
      runtimeInputs = [nix-unit];
      text = ''
        nix-unit --expr '${allTestsExpr}'
      '';
    };
  };
}
