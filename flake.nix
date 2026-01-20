{
  description = "Declarative SOPS secrets management with flake-parts";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs @ {
    flake-parts,
    self,
    ...
  }: let
    inherit (inputs.nixpkgs) lib;
    inherit (import ./core {inherit lib;}) mkSecrets mkSecretsPackages;

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

      server1 = {
        key = "age1jmxpfw8y5e5njm5fq08n65ceu7vuydx5l8wxk7hyu9s3x5qs93ysxqrd8l";
        decryptPkg = pkgs:
          pkgs.writeShellScriptBin "get-server1-key" ''
            echo "AGE-SECRET-KEY-1NEF2YXJC4K7L82VNGJGT5JPHQX0UQ8VWFJQF09W6S3U4ZC9RE3KQYAAP6L"
          '';
      };
    };

    example = mkSecrets {
      api-key = {
        dir = ./secrets;
        inherit recipients;
      };
      db-password = {
        dir = ./secrets;
        inherit recipients;
      };
      service-account = {
        dir = ./secrets;
        inherit recipients;
        format = "json";
      };
    };
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = inputs.nixpkgs.lib.systems.flakeExposed;

      perSystem = {pkgs, ...}: {
        devShells.default = pkgs.mkShell {
          packages = [pkgs.alejandra pkgs.sops pkgs.age];
        };

        packages = let
          secrets = mkSecretsPackages example pkgs;
        in {
          inherit secrets;

          decrypt-api-key = secrets.api-key.decrypt.recipient.alice;
        };
      };

      flake = {
        inherit mkSecrets mkSecretsPackages example;
      };
    };
}
