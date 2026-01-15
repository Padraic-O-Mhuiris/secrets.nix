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

  recipientsType = types.submodule {
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

  # Individual secret definition - takes group config for recipient resolution
  mkSecretType = groupConfig:
    types.submodule ({config, ...}: {
      options = {
        # User-specified targets (by name) for this secret
        targets = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Target recipient names to include for this secret";
        };

        # Computed: all recipients (admins + selected targets)
        _recipients = mkOption {
          type = types.listOf keyType;
          internal = true;
          readOnly = true;
          default = let
            admins = groupConfig.recipients.admins;
            allTargets = groupConfig.recipients.targets;
            selectedTargets = builtins.filter (t: builtins.elem t.name config.targets) allTargets;
          in
            admins ++ selectedTargets;
          description = "Computed list of all recipients (admins + selected targets)";
        };
      };
    });

  # Base secrets configuration (recipients + secret definitions)
  secretsGroupType = types.submodule ({name, config, ...}: {
    options = {
      recipients = mkOption {
        type = recipientsType;
        default = {};
        description = "Age recipient keys for encryption";
      };

      secret = mkOption {
        type = types.attrsOf (mkSecretType config);
        default = {};
        description = "Secret definitions for this group";
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
      type = types.attrsOf secretsGroupType;
      default = {};
      description = ''
        Secrets management configuration.

        Each attribute defines a secrets group stored in `secrets/<name>/`.
        For a single scope, use `default` as the name → `secrets/`.

        Example:
          secrets.dev = {
            recipients.targets = [...];
            secret.apiKey = {};
            secret.dbPassword = {};
          };
      '';
    };
  };
})
