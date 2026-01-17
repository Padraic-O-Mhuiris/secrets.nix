{
  lib,
  name,
  config,
}: let
  inherit (lib) mkOption types;

  mkFindEncryptedSecretPkg = pkgs:
    pkgs.callPackage ./mkFindEncryptedSecret.nix {
      inherit name;
      relPath = config._fileRelativePath;
      storePath = config._fileStorePath;
      existsInStore = config._fileExistsInStore;
    };
in {
  options = {
    mkFindEncryptedSecret = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = mkFindEncryptedSecretPkg;
      description = "Operation: finds and prints the encrypted secret's path";
    };

    mkPrintEncryptedSecret = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = pkgs:
        pkgs.callPackage ./mkPrintEncryptedSecret.nix {
          inherit name;
          findEncryptedSecretBin = mkFindEncryptedSecretPkg pkgs;
        };
      description = "Operation: validates and prints the encrypted secret contents";
    };
  };
}
