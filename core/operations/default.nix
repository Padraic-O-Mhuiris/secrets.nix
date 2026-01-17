{
  lib,
  name,
  config,
}: let
  inherit (lib) mkOption types;

  mkExamplePkg = pkgs:
    pkgs.writeShellApplication {
      name = "example-${name}";
      text = ''
        echo "Example operation for secret: ${name}"
        echo "Relative path: ${config._fileRelativePath}"
      '';
    };
in {
  options = {
    mkExample = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = mkExamplePkg;
      description = "Example operation (placeholder)";
    };
  };
}
