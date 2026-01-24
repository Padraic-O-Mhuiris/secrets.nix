# Example secrets configuration as a flake-parts module
#
# Demonstrates how to use the secrets.nix flake module.
{secretsDir}: let
  # Example recipients with test keys
  # In real usage, these would be actual age public keys
  recipients = {
    alice = {
      key = "age1yct6cdz4f2hguaamc0jqxjx0m00v2puqacx0339mutagv8xmpffqcxql4v";
      decryptPkg = pkgs:
        pkgs.writeShellScriptBin "get-alice-key" ''
          echo "AGE-SECRET-KEY-1EKATW8QJD4NF4XCX7XME5VDJ8MVER7LM4FHCWF6UFXSRJTLTKGCSYEZW68"
        '';
    };

    bob = {
      key = "age1wdw6tuppmmcufrh6wzgy93jah9wzppaqn69wt5un8qzz8lk5ep5ss6ed3f";
      decryptPkg = pkgs:
        pkgs.writeShellScriptBin "get-bob-key" ''
          echo "AGE-SECRET-KEY-1YM4U0AQYVSRRLCU70DQD5T09SS6CQ9S4ZLCCJ8KW9N7C53NJ7ADSLREPRZ"
        '';
    };

    charlie = {
      key = "age1ekvz0sv77x98lmfyp7208qel42hh5e0a539yeu8vahqhf499se9sdhtw0q";
      decryptPkg = pkgs:
        pkgs.writeShellScriptBin "get-charlie-key" ''
          echo "AGE-SECRET-KEY-1W2V7CW8L8J8K3L3WANE9M6C20FXGHSX5DA7MA0JKZR24CP0MAAHQCGCAVZ"
        '';
    };

    server1 = {
      key = "age1jmxpfw8y5e5njm5fq08n65ceu7vuydx5l8wxk7hyu9s3x5qs93ysxqrd8l";
      decryptPkg = pkgs:
        pkgs.writeShellScriptBin "get-server1-key" ''
          ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i ~/.ssh/id_ed25519
        '';
    };
  };
in {
  secrets = {
    api-key = {
      dir = secretsDir;
      inherit recipients;
      format = "json";
    };

    db-password = {
      dir = secretsDir;
      inherit recipients;
    };

    service-account = {
      dir = secretsDir;
      inherit recipients;
      format = "json";
    };
  };

  # Alternative: define example packages directly in perSystem
  # perSystem = {pkgs, ...}: {
  #   packages.example = mkSecretsPackages (mkSecrets config.secrets) pkgs;
  # };
}
