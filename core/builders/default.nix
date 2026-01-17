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
      description = "Builder: package that finds and prints the secret's local host path";
    };
  };
}
