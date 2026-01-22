# secrets.nix - minimal secrets management module
{lib}: let
  inherit (lib) mkOption types;

  # Age public key regex pattern
  ageKeyPattern = "age1[a-z0-9]{58}";

  # Format to file extension mapping
  formatExtension = {
    bin = "";
    json = ".json";
    yaml = ".yaml";
    env = ".env";
  };

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

      decryptPkg = mkOption {
        type = types.nullOr (types.functionTo types.package);
        default = null;
        description = "Function (pkgs -> drv) that produces the key command package for decryption";
      };
    };
  };

  # Secret submodule
  secretModule = {
    name,
    config,
    ...
  }: {
    options = {
      dir = mkOption {
        type = types.path;
        description = "Directory containing the encrypted secret file (relative to where it's declared)";
      };

      recipients = mkOption {
        type = types.attrsOf (types.submodule recipientModule);
        default = {};
        description = "Recipients who can decrypt this secret";
      };

      format = mkOption {
        type = types.enum ["bin" "json" "yaml" "env"];
        default = "bin";
        description = "Secret file format (used by sops for encryption/decryption)";
      };

      # Derived properties (read-only)
      _fileName = mkOption {
        type = types.str;
        readOnly = true;
        default = "${name}${formatExtension.${config.format}}";
        description = "Derived filename: <name><extension>";
      };

      _path = mkOption {
        type = types.path;
        readOnly = true;
        default = config.dir + "/${config._fileName}";
        description = "Derived full path: <dir>/<_fileName>";
      };

      _projectOutPath = mkOption {
        type = types.str;
        readOnly = true;
        default = let
          fullPath = builtins.toString config._path;
          parts = lib.splitString "/" fullPath;
          relativeParts = lib.drop 4 parts;
        in
          "./" + lib.concatStringsSep "/" relativeParts;
        description = "Relative path from flake root";
      };

      _exists = mkOption {
        type = types.bool;
        readOnly = true;
        default = builtins.pathExists config._path;
        description = "Whether the secret file exists at the derived path";
      };

      # Package operations submodule
      __operations = mkOption {
        type = types.submodule (import ./operations {inherit lib name config;});
        internal = true;
        readOnly = true;
        default = {};
        description = "Package operation functions";
      };
    };
  };
in {
  # Evaluate a secrets configuration
  mkSecrets = secrets:
    lib.mapAttrs (name: secretDef:
      (lib.evalModules {
        modules = [secretModule {config = secretDef;}];
        specialArgs = {inherit name;};
      })
      .config)
    secrets;

  # Create a "secrets" package with nested passthru
  mkSecretsPackages = import ./packages.nix {inherit lib;};
}
