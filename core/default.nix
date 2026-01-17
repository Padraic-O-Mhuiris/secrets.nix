# secrets.nix - minimal secrets management module
# TODO: settings = {...}; for global configuration (future work)
{lib}: let
  inherit (lib) mkOption types;

  # Age public key regex pattern
  ageKeyPattern = "age1[a-z0-9]{58}";

  # Recipient submodule
  recipientModule = {
    options = {
      key = mkOption {
        type = types.strMatching ageKeyPattern;
        description = "Public key for this recipient";
      };

      type = mkOption {
        type = types.enum ["age"];
        default = "age";
        readOnly = true; # Note only supporting age keys initially
        description = "Key type (sops backend)";
      };
    };
  };

  # Secret submodule
  secretModule = {
    name,
    config,
    self,
    ...
  }: {
    options = {
      recipients = mkOption {
        type = types.attrsOf (types.submodule recipientModule);
        default = {};
        description = "Recipients who can decrypt this secret";
      };

      dir = mkOption {
        type = types.str;
        default = "secrets";
        description = "Directory for secret file (relative to project root)";
      };

      format = mkOption {
        type = types.enum ["json" "yaml" "env" "ini"];
        default = "yaml";
        description = "File format for the secret";
      };

      _fileName = mkOption {
        type = types.str;
        internal = true;
        readOnly = true;
        default = "${name}.${config.format}";
        description = "Secret filename (<secret>.<format>)";
      };

      _fileRelativePath = mkOption {
        type = types.str;
        internal = true;
        readOnly = true;
        default = "${config.dir}/${config._fileName}";
        description = "Relative path from project root to secret file";
      };

      _fileStorePath = mkOption {
        type = types.path;
        internal = true;
        readOnly = true;
        default = self + "/${config._fileRelativePath}";
        description = "Nix store path to the secret file";
      };

      _fileExistsInStore = mkOption {
        type = types.bool;
        internal = true;
        readOnly = true;
        default = builtins.pathExists config._fileStorePath;
        description = "Whether the secret file exists in the store";
      };

      _fileExistsInRelPath = mkOption {
        type = types.bool;
        internal = true;
        readOnly = true;
        default = builtins.pathExists ((builtins.getEnv "FLAKE_ROOT") + "/${config._fileRelativePath}");
        description = "Whether the secret file exists at the relative path (requires --impure and FLAKE_ROOT)";
      };
    };
  };
in {
  # Evaluate a secrets configuration
  mkSecrets = {
    self, # flake self reference for store paths
  }: secrets:
    lib.mapAttrs (name: secretDef:
      (lib.evalModules {
        modules = [secretModule {config = secretDef;}];
        specialArgs = {inherit self name;};
      })
      .config)
    secrets;
}
