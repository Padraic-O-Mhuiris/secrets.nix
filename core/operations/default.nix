# Secret operations module
#
# Operations (availability depends on whether secret exists):
#
# ALWAYS AVAILABLE:
# - encrypt: encrypts content from --input (no decryption needed)
# - edit: interactive editor (empty if new, decrypts if exists)
# - env: outputs env var template for key configuration
#
# ONLY WHEN SECRET EXISTS:
# - decrypt: outputs secret to stdout
# - rotate: rotates data encryption key (sops rotate), content unchanged
# - rekey: updates recipients to match config (sops updatekeys), data key unchanged
#
# Decrypt-dependent operations support the builder pattern:
# - .withSopsAgeKeyCmd "command"
# - .withSopsAgeKeyCmdPkg drv
# - .buildSopsAgeKeyCmdPkg (pkgs: drv)
# - .recipient.<name> (for recipients with decryptPkg configured)
#
{
  lib,
  name,
  config,
}: let
  inherit (lib) mkOption types;

  # Import shared utilities
  ops = import ./lib.nix {inherit lib name config;};

  # Import individual operations
  mkEncrypt = import ./encrypt.nix {inherit lib name config ops;};
  mkDecrypt = import ./decrypt.nix {inherit lib name config ops;};
  editOps = import ./edit.nix {inherit lib name config ops;};
  mkRotate = import ./rotate.nix {inherit lib name config ops;};
  mkRekey = import ./rekey.nix {inherit lib name config ops;};
  mkEnv = import ./env.nix {inherit lib name config ops;};

  # Entry points for operations that need the builder pattern
  decryptPkg = ops.mkWithRecipients mkDecrypt;
  editExistingPkg = ops.mkWithRecipients editOps.mkEditExisting;
  rotatePkg = ops.mkWithRecipients mkRotate;
  rekeyPkg = ops.mkWithRecipients mkRekey;

  # Conditional operation options based on whether secret exists
  exists = config._exists;
in {
  options =
    # Operations available when secret EXISTS (decrypt, rotate, rekey)
    lib.optionalAttrs exists {
      decrypt = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        default = decryptPkg;
        description = "Decrypts secret from store and outputs to stdout. Supports builder methods: .withSopsAgeKeyCmd, .withSopsAgeKeyCmdPkg, .buildSopsAgeKeyCmdPkg";
      };

      rotate = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        default = rotatePkg;
        description = "Rotates the data encryption key (sops rotate). Content unchanged. Supports builder methods.";
      };

      rekey = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        default = rekeyPkg;
        description = "Updates recipients to match current config (sops updatekeys). Data key unchanged. Supports builder methods.";
      };
    }
    # Operations available ALWAYS (regardless of secret existence)
    // {
      encrypt = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        default = mkEncrypt;
        description = "Encrypts content from --input to a secret file. No decryption needed.";
      };

      edit = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        default =
          if exists
          then editExistingPkg
          else editOps.mkEditNew;
        description =
          if exists
          then "Decrypts secret, opens in $EDITOR, re-encrypts. Supports builder methods."
          else "Opens $EDITOR to create new secret. No decryption needed.";
      };

      env = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        default = mkEnv;
        description = "Outputs environment variable template for configuring decryption keys.";
      };
    };
}
