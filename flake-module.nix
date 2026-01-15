{
  lib,
  flake-parts-lib,
  ...
}: let
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
in {
  options.flake = mkSubmoduleOptions {
    secrets = mkOption {
      type = types.submodule {
        options = {
          keys = mkOption {
            type = types.submodule {
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
            default = {};
            description = "Key definitions";
          };
        };
      };
      default = {};
      description = "Secrets management configuration";
    };
  };
}
