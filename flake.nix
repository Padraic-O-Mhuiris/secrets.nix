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
            ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i ~/.ssh/id_ed25519
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

      perSystem = {pkgs, ...}: let
        nix-unit = inputs.nix-unit.packages.${pkgs.system}.default;
        testsModule = import ./tests {
          inherit lib pkgs nix-unit;
          corePath = ./core;
          fixturesPath = ./tests/fixtures;
        };
      in {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.alejandra
            pkgs.sops
            pkgs.age
            nix-unit
          ];
        };

        packages = let
          secrets = mkSecretsPackages example pkgs;
        in {
          inherit secrets;
          inherit (testsModule.packages) unit-tests;
          decrypt-api-key = secrets.api-key.decrypt.recipient.alice;
        };

        checks =
          testsModule.checks
          // {
            lint-statix = pkgs.runCommand "lint-statix" {
              nativeBuildInputs = [pkgs.statix];
              src = ./.;
            } ''
              cd $src
              statix check .
              touch $out
            '';
            lint-deadnix = pkgs.runCommand "lint-deadnix" {
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
        inherit mkSecrets mkSecretsPackages example;
      };
    };
}
