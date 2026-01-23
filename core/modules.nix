# Module builders for sops-nix integration
# These produce NixOS, Home-Manager, and Darwin module fragments
# that configure sops.secrets with the correct sopsFile/format/key
{lib}: let
  # Map our format names to sops-nix format names
  sopsFormat = {
    bin = "binary";
    json = "json";
    yaml = "yaml";
    env = "dotenv";
  };

  # NixOS secret options (excluding sopsFile, format, key, name, sopsFileHash)
  # https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix
  mkNixosModule = {
    name,
    secretCfg,
  }: {
    path ? null,
    mode ? "0400",
    owner ? null,
    uid ? 0,
    group ? null,
    gid ? 0,
    restartUnits ? [],
    reloadUnits ? [],
    neededForUsers ? false,
  }: {
    sops.secrets.${name} =
      {
        # Controlled - derived from secret definition
        sopsFile = secretCfg._path;
        format = sopsFormat.${secretCfg.format};
        key =
          if secretCfg.format == "bin"
          then ""
          else name;

        # User configurable
        inherit mode owner uid group gid restartUnits reloadUnits neededForUsers;
      }
      // lib.optionalAttrs (path != null) {inherit path;};
  };

  # Home-Manager secret options (excluding sopsFile, format, key, name)
  # https://github.com/Mic92/sops-nix/blob/master/modules/home-manager/sops.nix
  mkHomeManagerModule = {
    name,
    secretCfg,
  }: {
    path ? null,
    mode ? "0400",
  }: {
    sops.secrets.${name} =
      {
        # Controlled - derived from secret definition
        sopsFile = secretCfg._path;
        format = sopsFormat.${secretCfg.format};
        key =
          if secretCfg.format == "bin"
          then ""
          else name;

        # User configurable
        inherit mode;
      }
      // lib.optionalAttrs (path != null) {inherit path;};
  };

  # Darwin secret options (excluding sopsFile, format, key, name, sopsFileHash)
  # https://github.com/Mic92/sops-nix/blob/master/modules/nix-darwin/default.nix
  mkDarwinModule = {
    name,
    secretCfg,
  }: {
    path ? null,
    mode ? "0400",
    owner ? "root",
    uid ? 0,
    group ? "staff",
    gid ? 0,
    neededForUsers ? false,
  }: {
    sops.secrets.${name} =
      {
        # Controlled - derived from secret definition
        sopsFile = secretCfg._path;
        format = sopsFormat.${secretCfg.format};
        key =
          if secretCfg.format == "bin"
          then ""
          else name;

        # User configurable
        inherit mode owner uid group gid neededForUsers;
      }
      // lib.optionalAttrs (path != null) {inherit path;};
  };
in {
  inherit mkNixosModule mkHomeManagerModule mkDarwinModule;
}
