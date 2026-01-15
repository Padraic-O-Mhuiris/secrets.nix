{flake}: {
  lib,
  flake-parts-lib,
  ...
}: let
  packagesModule = import ./packages.nix {inherit flake;};
in {
  imports = [packagesModule];
}
// (let
  inherit (lib) mkOption types;
  inherit (flake-parts-lib) mkSubmoduleOptions;

  # Age public key regex pattern
  ageKeyPattern = "age1[a-z0-9]{58}";

  keyType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Identifier for this key";
      };
      key = mkOption {
        type = types.strMatching ageKeyPattern;
        description = "Age public key (age1...)";
      };
    };
  };

  keysType = types.submodule {
    options = {
      admins = mkOption {
        type = types.listOf keyType;
        default = [];
        description = "Admin keys - included in all secrets for management";
      };
      targets = mkOption {
        type = types.listOf keyType;
        default = [];
        description = "Target keys - referenced per-secret for runtime decryption";
      };
    };
  };

  # Base secrets configuration (keys + future secret definitions)
  secretsType = types.submodule ({name, ...}: {
    options = {
      keys = mkOption {
        type = keysType;
        default = {};
        description = "Key definitions";
      };

      # Bash snippet that sets $workdir to this secrets section directory
      _workdir = mkOption {
        type = types.lines;
        internal = true;
        readOnly = true;
        default = flake.lib.buildWorkdirScript (
          if name == "default"
          then "secrets"
          else "secrets/${name}"
        );
        description = "Bash snippet that sets $workdir to this secrets section directory";
      };
    };
  });
in {
  options.flake = mkSubmoduleOptions {
    secrets = mkOption {
      type = types.attrsOf secretsType;
      default = {};
      description = ''
        Secrets management configuration.

        Each attribute defines a secrets section stored in `secrets/<name>/`.
        For a single scope, use `default` as the name → `secrets/default/`.

        Example:
          secrets.dev = { keys.targets = [...]; };      # secrets/dev/
          secrets.production = { keys.targets = [...]; }; # secrets/production/
      '';
    };
  };
})
