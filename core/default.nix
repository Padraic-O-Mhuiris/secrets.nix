# secrets.nix - minimal secrets management module
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

  # Root settings submodule
  rootModule = {
    options = {
      envVarName = mkOption {
        type = types.str;
        default = "SECRET_ROOT_DIR";
        description = "Environment variable name for the secrets root directory";
      };

      mkPackage = mkOption {
        type = types.functionTo types.package;
        description = "Builder function that produces a derivation to find the project root at runtime";
        default = pkgs:
          pkgs.writeShellApplication {
            name = "secret-root";
            runtimeInputs = [pkgs.gitMinimal];
            text = ''
              git rev-parse --show-toplevel
            '';
          };
      };
    };
  };

  # Settings submodule
  settingsModule = {
    options = {
      root = mkOption {
        type = types.submodule rootModule;
        default = {};
        description = "Root directory settings";
      };

      dir = mkOption {
        type = types.str;
        default = "secrets";
        description = "Default directory for secret files (relative to project root)";
      };
    };
  };

  # Secret submodule
  secretModule = settings: {
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
        default = settings.dir;
        description = "Directory for secret file (relative to project root)";
      };

      _fileName = mkOption {
        type = types.str;
        internal = true;
        readOnly = true;
        default = "${name}";
        description = "Secret filename";
      };

      _runtimePath = mkOption {
        type = types.str;
        internal = true;
        readOnly = true;
        default = "\$${settings.root.envVarName}/${config.dir}/${config._fileName}";
        description = "Runtime path using environment variable";
      };

      _storePath = mkOption {
        type = types.path;
        internal = true;
        readOnly = true;
        default = self + "/${config.dir}/${config._fileName}";
        description = "Nix store path to the secret file";
      };

      _existsInStore = mkOption {
        type = types.bool;
        internal = true;
        readOnly = true;
        default = builtins.pathExists config._storePath;
        description = "Whether the secret file exists in the store";
      };

      # Package operations submodule
      __operations = mkOption {
        type = types.submodule (import ./operations {inherit lib name config settings;});
        internal = true;
        readOnly = true;
        default = {};
        description = "Package operation functions";
      };
    };
  };
in {
  # Evaluate a secrets configuration
  mkSecrets = {
    self, # flake self reference for store paths
    settings ? {},
  }: secrets: let
    evaluatedSettings =
      (lib.evalModules {
        modules = [settingsModule {config = settings;}];
      })
      .config;
  in
    lib.mapAttrs (name: secretDef:
      (lib.evalModules {
        modules = [(secretModule evaluatedSettings) {config = secretDef;}];
        specialArgs = {inherit self name;};
      })
      .config)
    secrets;

  # Create a "secrets" package with nested passthru
  mkSecretsPackages = import ./packages.nix {inherit lib;};
}
