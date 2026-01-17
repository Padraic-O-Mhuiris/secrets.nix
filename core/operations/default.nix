{
  lib,
  name,
  config,
}: let
  inherit (lib) mkOption types;

  mkEncryptedSecretPathPkg = pkgs:
    pkgs.callPackage ./mkEncryptedSecretPath.nix {
      inherit name;
      relPath = config._fileRelativePath;
      storePath = config._fileStorePath;
      local = false;
    };

  mkLocalEncryptedSecretPathPkg = pkgs:
    pkgs.callPackage ./mkEncryptedSecretPath.nix {
      inherit name;
      relPath = config._fileRelativePath;
      storePath = config._fileStorePath;
      local = true;
    };
in {
  options = {
    mkEncryptedSecretPath = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = mkEncryptedSecretPathPkg;
      description = "Operation: prints the encrypted secret's nix store path";
    };

    mkLocalEncryptedSecretPath = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = mkLocalEncryptedSecretPathPkg;
      description = "Operation: prints the encrypted secret's local path (relative to flake root)";
    };

    mkEncryptedSecret = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = pkgs:
        pkgs.callPackage ./mkEncryptedSecret.nix {
          inherit name;
          encryptedSecretPathBin = mkEncryptedSecretPathPkg pkgs;
          local = false;
        };
      description = "Operation: validates and prints the encrypted secret contents from nix store";
    };

    mkLocalEncryptedSecret = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = pkgs:
        pkgs.callPackage ./mkEncryptedSecret.nix {
          inherit name;
          encryptedSecretPathBin = mkLocalEncryptedSecretPathPkg pkgs;
          local = true;
        };
      description = "Operation: validates and prints the encrypted secret contents from local path";
    };

    mkEditEncryptedSecret = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = pkgs:
        pkgs.callPackage ./mkEditEncryptedSecret.nix {
          inherit name;
          relPath = config._fileRelativePath;
          encryptedSecretPathBin = mkEncryptedSecretPathPkg pkgs;
          local = false;
        };
      description = "Operation: edit encrypted secret from nix store, writing to provided path (default: relative path)";
    };

    mkLocalEditEncryptedSecret = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = pkgs:
        pkgs.callPackage ./mkEditEncryptedSecret.nix {
          inherit name;
          relPath = config._fileRelativePath;
          encryptedSecretPathBin = mkLocalEncryptedSecretPathPkg pkgs;
          local = true;
        };
      description = "Operation: edit encrypted secret from local path in place (or to provided path)";
    };

    mkCreateEncryptedSecret = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = pkgs:
        pkgs.callPackage ./mkCreateEncryptedSecret.nix {
          inherit name;
          relPath = config._fileRelativePath;
          format = config.format;
          recipients = config.recipients;
        };
      description = "Operation: create a new encrypted secret interactively (local only)";
    };
  };
}
