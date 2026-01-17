{flake}: {
  lib,
  flake-parts-lib,
  self,
  ...
}: let
  packagesModule = import ./packages {inherit flake;};
in {
  imports = [packagesModule];
}
// (let
  inherit (lib) mkOption types mapAttrsToList;
  inherit (flake-parts-lib) mkSubmoduleOptions;

  # Age public key regex pattern
  ageKeyPattern = "age1[a-z0-9]{58}";

  # Recipient type - age key + decryption configuration
  recipientType = types.submodule ({name, config, ...}: {
    options = {
      key = mkOption {
        type = types.strMatching ageKeyPattern;
        description = "Age public key for this recipient";
      };

      decryption = {
        command = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Command to retrieve the private key. If null, the
            <RECIPIENT_NAME>__DECRYPT_CMD environment variable can be used
            at runtime. The command must print the private key to stdout.
          '';
        };

        withPackages = mkOption {
          type = types.functionTo (types.listOf types.package);
          default = pkgs: [];
          description = ''
            Function that takes pkgs and returns a list of packages
            to include in PATH when running the decrypt command.
            Example: pkgs: [ pkgs.pass pkgs.gnupg ]
          '';
        };
      };

      # Computed: environment variable name for this recipient
      _envVar = mkOption {
        type = types.str;
        internal = true;
        readOnly = true;
        default = "${lib.toUpper (builtins.replaceStrings ["-"] ["_"] name)}__DECRYPT_CMD";
        description = "Environment variable name for decrypt command override";
      };
    };
  });

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
        # Recipients as attrset with decryption configuration
        recipients = mkOption {
          type = types.attrsOf recipientType;
          default = {};
          description = "Recipients who can decrypt this secret";
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

        # Whether the secret file exists
        _exists = mkOption {
          type = types.bool;
          internal = true;
          readOnly = true;
          default = builtins.pathExists (self + "/${config._relPath}");
          description = "Whether the encrypted secret file exists";
        };

        # SOPS creation rule for this secret
        _creationRule = mkOption {
          type = types.lines;
          internal = true;
          readOnly = true;
          default = let
            # Escape dots and special chars for regex
            escapedPath = builtins.replaceStrings ["." "/"] ["\\." "\\/"] config._relPath;
            ageKeys = mapAttrsToList (n: r: "      - ${r.key}  # ${n}") config.recipients;
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
            alice = {
              key = "age1...";
              # No command - uses ALICE__DECRYPT_CMD env var at runtime
            };
            server1 = {
              key = "age1...";
              decryption = {
                command = "ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key";
                withPackages = pkgs: [ pkgs.ssh-to-age ];
              };
            };
          in {
            flake.secrets.default.api-key.recipients = { inherit alice server1; };
            flake.secrets.prod.db-password.recipients = { inherit server1; };
          }
      '';
    };
  };
})
