{
  lib,
  name,
  config,
  settings,
}: let
  inherit (lib) mkOption types;

  mkExamplePkg = pkgs: let
    rootPkg = settings.root.mkPackage pkgs;
  in
    pkgs.writeShellApplication {
      name = "example-${name}";
      text = ''
        export ${settings.root.envVarName}="$(${rootPkg}/bin/secret-root)"

        echo "Secret: ${name}"
        echo "Runtime path: ${config._runtimePath}"
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
