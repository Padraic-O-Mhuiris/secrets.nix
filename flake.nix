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
      alice = "age1v9z267t653yn0pklhy9v23hy3y430snqpeatzp48958utqnhedzq6uvtkd";
      bob = "age19t7cnvcpqxv5walahqwz7udv3rrelqm7enztwgk5pg3famr3sq7shzx0ry";
    };

    targets = {
      server1 = "age1dpnznv446qgzah35vndw5ys763frgz8h6exfmecn8cvnu394ty5q0cts7s";
    };

    mkRecipients = keys:
      builtins.mapAttrs (_: key: {inherit key;}) keys;

    example = mkSecrets {inherit self;} {
      api-key.recipients = mkRecipients admins;
      db-password = {
        recipients = mkRecipients (admins // targets);
        dir = "secrets/prod";
      };
      service-account = {
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
