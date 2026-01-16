{flake}: {
  lib,
  flake-parts-lib,
  self,
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

  # Directory path type - must not end with file extension
  dirType = types.addCheck types.str (s:
    let lastSegment = builtins.baseNameOf s;
    in !(builtins.match ".*\\.[a-zA-Z0-9]+$" lastSegment != null)
  ) // { description = "directory path (no file extension)"; };

  # File type options
  fileType = types.submodule ({...}: {
    options = {
      dir = mkOption {
        type = dirType;
        description = "Directory path (relative to flake root, no file extension)";
      };
      type = mkOption {
        type = types.enum ["yaml" "json"];
        default = "yaml";
        description = "File format for the secret";
      };
    };
  });

  # Secret type - each secret has its own recipients and path
  mkSecretType = groupName:
    types.submodule ({name, config, ...}: let
      defaultDir =
        if groupName == "default"
        then "secrets"
        else "secrets/${groupName}";
    in {
      options = {
        # Recipients as attrset: { alice = "age1..."; server1 = "age1..."; }
        recipients = mkOption {
          type = types.attrsOf (types.strMatching ageKeyPattern);
          default = {};
          description = "Recipients who can decrypt this secret (name = age public key)";
        };

        # File location settings
        file = mkOption {
          type = fileType;
          default = {
            dir = defaultDir;
            type = "yaml";
          };
          description = "File location and format settings";
        };

        # Computed relative path to the secret file
        _relPath = mkOption {
          type = types.str;
          internal = true;
          readOnly = true;
          default = "${config.file.dir}/${name}.${config.file.type}";
          description = "Relative path to the encrypted secret file";
        };

        # Nix store path to the secret file
        _storePath = mkOption {
          type = types.path;
          internal = true;
          readOnly = true;
          default = self + "/${config._relPath}";
          description = "Nix store path to the encrypted secret file";
        };

        # SOPS creation rule for this secret
        _creationRule = mkOption {
          type = types.lines;
          internal = true;
          readOnly = true;
          default = let
            # Escape dots and special chars for regex
            escapedPath = builtins.replaceStrings ["." "/"] ["\\." "\\/"] config._relPath;
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
