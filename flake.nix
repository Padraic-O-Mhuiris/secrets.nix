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

    admins = {
      # created: 2026-01-17T18:17:06Z
      # public key: age1yct6cdz4f2hguaamc0jqxjx0m00v2puqacx0339mutagv8xmpffqcxql4v
      # AGE-SECRET-KEY-1EKATW8QJD4NF4XCX7XME5VDJ8MVER7LM4FHCWF6UFXSRJTLTKGCSYEZW68
      alice = "age1yct6cdz4f2hguaamc0jqxjx0m00v2puqacx0339mutagv8xmpffqcxql4v";

      # created: 2026-01-17T18:17:25Z
      # public key: age1wdw6tuppmmcufrh6wzgy93jah9wzppaqn69wt5un8qzz8lk5ep5ss6ed3f
      # AGE-SECRET-KEY-1YM4U0AQYVSRRLCU70DQD5T09SS6CQ9S4ZLCCJ8KW9N7C53NJ7ADSLREPRZ
      bob = "age1wdw6tuppmmcufrh6wzgy93jah9wzppaqn69wt5un8qzz8lk5ep5ss6ed3f";
    };

    targets = {
      # created: 2026-01-17T18:17:38Z
      # public key: age13kzxh2jpksuad8yaegf4wg8zzl93mgns0fj32a23ldl8nwjweprq6efm0t
      # AGE-SECRET-KEY-15S77DSN4T7ZQLUXGU2XPZMRP5J5WMSL5YZSMV3Q5WFZQUR4EZKMS9VN3PD
      server1 = "age13kzxh2jpksuad8yaegf4wg8zzl93mgns0fj32a23ldl8nwjweprq6efm0t";
    };

    mkRecipients = keys:
      builtins.mapAttrs (_: key: {inherit key;}) keys;

    example = mkSecrets {
      api-key = {
        dir = ./secrets;
        recipients = mkRecipients admins;
      };
      db-password = {
        dir = ./secrets;
        recipients = mkRecipients (admins // targets);
      };
      service-account = {
        dir = ./secrets;
        recipients = mkRecipients admins;
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

        packages.secrets = mkSecretsPackages example pkgs;
      };

      flake = {
        inherit mkSecrets mkSecretsPackages example;
      };
    };
}
