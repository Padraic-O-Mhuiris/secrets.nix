{
  lib,
  name,
  config,
  settings,
}: let
  inherit (lib) mkOption types;

  # Code block that sets up the secret path context
  # Sets SECRET_ROOT_DIR (or configured env var) and SECRET_PATH
  secretPathContext = pkgs: let
    rootPkg = settings.root.mkPackage pkgs;
  in ''
    ${settings.root.envVarName}="$(${rootPkg}/bin/secret-root)"

    if [[ ! -d "''$${settings.root.envVarName}" ]]; then
      echo "Error: Root directory does not exist: ''$${settings.root.envVarName}" >&2
      exit 1
    fi

    SECRET_PATH="''$${settings.root.envVarName}/${config.dir}/${config._fileName}"
  '';

  resolvePkg = pkgs:
    pkgs.writeShellApplication {
      name = "secret-resolve-${name}";
      text = ''
        ${secretPathContext pkgs}
        echo "$SECRET_PATH"
      '';
    };

  # Code block that layers on secretPathContext and validates file exists
  secretExistsContext = pkgs: ''
    ${secretPathContext pkgs}

    if [[ ! -f "$SECRET_PATH" ]]; then
      echo "Error: Secret file not found: $SECRET_PATH" >&2
      exit 1
    fi
  '';

  existsPkg = pkgs:
    pkgs.writeShellApplication {
      name = "secret-exists-${name}";
      text = ''
        ${secretExistsContext pkgs}
        echo "exists"
      '';
    };

  statusPkg = pkgs:
    pkgs.writeShellApplication {
      name = "secret-status-${name}";
      runtimeInputs = [pkgs.sops pkgs.jq];
      text = ''
        ${secretExistsContext pkgs}

        if ! status=$(sops filestatus "$SECRET_PATH" 2>/dev/null); then
          echo "not encrypted"
          exit 1
        fi

        if [[ "$(echo "$status" | jq -r '.encrypted')" == "true" ]]; then
          echo "encrypted"
          exit 0
        else
          echo "not encrypted"
          exit 1
        fi
      '';
    };
in {
  options = {
    resolve = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = resolvePkg;
      description = "Operation: prints the fully qualified local path to the secret file";
    };

    exists = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = existsPkg;
      description = "Operation: checks if the secret file exists";
    };

    status = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = statusPkg;
      description = "Operation: checks if the secret file is properly encrypted";
    };
  };
}
