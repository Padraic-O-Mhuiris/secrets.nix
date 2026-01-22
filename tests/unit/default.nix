# Unit tests aggregator for secrets.nix
#
# Aggregates all unit test groups and provides the test expression.
# Each group file receives a shared context (ctx) with common fixtures.
#
{
  lib,
  pkgs ? null,
  corePath ? ../../core,
  fixturesPath ? ../fixtures,
}: let
  inherit (import corePath {inherit lib;}) mkSecrets mkSecretsPackages;

  # Shared test context passed to all test groups
  ctx = {
    inherit lib pkgs mkSecrets mkSecretsPackages;

    # Valid age keys for testing
    validAgeKey1 = "age1yct6cdz4f2hguaamc0jqxjx0m00v2puqacx0339mutagv8xmpffqcxql4v";
    validAgeKey2 = "age1wdw6tuppmmcufrh6wzgy93jah9wzppaqn69wt5un8qzz8lk5ep5ss6ed3f";
    validAgeKey3 = "age1jmxpfw8y5e5njm5fq08n65ceu7vuydx5l8wxk7hyu9s3x5qs93ysxqrd8l";

    # Test directories
    testDir = /tmp/test-secrets;
    fixturesSecretsDir = fixturesPath + "/secrets";
  };

  # Test groups that don't require pkgs (pure evaluation)
  pureTests =
    (import ./age-key.nix {inherit ctx;})
    // (import ./format.nix {inherit ctx;})
    // (import ./derived.nix {inherit ctx;})
    // (import ./recipient.nix {inherit ctx;})
    // (import ./operations.nix {inherit ctx;});

  # Test groups that require pkgs (derivation construction)
  pkgsTests = lib.optionalAttrs (pkgs != null) (
    (import ./packages.nix {inherit ctx;})
    // (import ./exists.nix {inherit ctx;})
  );
in
  pureTests // pkgsTests
