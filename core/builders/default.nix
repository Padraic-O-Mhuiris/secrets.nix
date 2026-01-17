{
  lib,
  name,
  config,
}: let
  inherit (lib) mkOption types;
in {
  options = {
    mkFindLocalSecret = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = pkgs:
        pkgs.callPackage ./mkFindLocalSecret.nix {
          inherit name;
          relPath = config._fileRelativePath;
        };
      description = "Operation: finds and prints the secret's local host path";
    };

    mkPrintSecret = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = pkgs:
        pkgs.callPackage ./mkPrintSecret.nix ({
            inherit name;
            storePath = config._fileStorePath;
            existsInStore = config._fileExistsInStore;
          }
          // lib.optionalAttrs (!config._fileExistsInStore) {
            findLocalSecretBin = pkgs.callPackage ./mkFindLocalSecret.nix {
              inherit name;
              relPath = config._fileRelativePath;
            };
          });
      description = "Operation: validates and prints the decrypted secret";
    };
  };
}
