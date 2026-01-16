{flake}: {
  lib,
  flake-parts-lib,
  ...
}: let
  packagesModule = import ./packages.nix {inherit flake;};
in {
  imports = [packagesModule];
}
// (let
  inherit (lib) mkOption types mapAttrsToList;
  inherit (flake-parts-lib) mkSubmoduleOptions;

  # Age public key regex pattern
  ageKeyPattern = "age1[a-z0-9]{58}";

  # Secret type - each secret has its own recipients and path
  mkSecretType = groupName:
    types.submodule ({name, config, ...}: let
      defaultPath =
        if groupName == "default"
        then "secrets/${name}.yaml"
        else "secrets/${groupName}/${name}.yaml";
    in {
      options = {
        # Recipients as attrset: { alice = "age1..."; server1 = "age1..."; }
        recipients = mkOption {
          type = types.attrsOf (types.strMatching ageKeyPattern);
          default = {};
          description = "Recipients who can decrypt this secret (name = age public key)";
        };

        # Path to the secret file (relative to flake root)
        path = mkOption {
          type = types.str;
          default = defaultPath;
          description = "Path to the encrypted secret file (relative to flake root)";
        };

        # SOPS creation rule for this secret
        _creationRule = mkOption {
          type = types.lines;
          internal = true;
          readOnly = true;
          default = let
            # Escape dots and special chars for regex
            escapedPath = builtins.replaceStrings ["." "/"] ["\\." "\\/"] config.path;
            ageKeys = mapAttrsToList (n: k: "      - ${k}  # ${n}") config.recipients;
          in ''
            - path_regex: ${escapedPath}$
              age:
            ${builtins.concatStringsSep "\n" ageKeys}'';
          description = "SOPS creation rule YAML fragment for this secret";
        };
      };
    });

  # Group type - an attrset of secrets
  mkSecretsGroupType = groupName: types.attrsOf (mkSecretType groupName);
in {
  options.flake = mkSubmoduleOptions {
    secrets = mkOption {
      type = types.lazyAttrsOf (types.submodule ({name, ...}: {
        freeformType = mkSecretsGroupType name;
      }));
      default = {};
      description = ''
        Secrets management configuration.

        Structure: flake.secrets.<group>.<secret>
        Group "default" stores secrets at `secrets/<name>.yaml`.
        Other groups store secrets at `secrets/<group>/<name>.yaml`.

        Example:
          let
            admins = { alice = "age1..."; bob = "age1..."; };
            targets = { server1 = "age1..."; laptop = "age1..."; };
          in {
            flake.secrets.default.api-key.recipients = admins // { inherit (targets) server1; };
            flake.secrets.prod.db-password.recipients = admins // targets;
          }
      '';
    };
  };
})
