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

  # Code block that layers on secretPathContext and validates file does NOT exist
  secretNotExistsContext = pkgs: ''
    ${secretPathContext pkgs}

    if [[ -f "$SECRET_PATH" ]]; then
      echo "Error: Secret file already exists: $SECRET_PATH" >&2
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

  # Generate .sops.yaml content for this secret
  sopsConfig = let
    ageKeys = map (r: r.key) (builtins.attrValues config.recipients);
    ageKeysList = builtins.concatStringsSep "\n          - " ageKeys;
  in ''
    creation_rules:
      - path_regex: .*
        key_groups:
          - age:
              - ${ageKeysList}
  '';

  # Import decrypt operation (uses store path for distribution)
  decryptPkg = import ./decrypt.nix {
    inherit lib name sopsConfig;
    storePath = config._storePath;
    existsInStore = config._existsInStore;
    format = config.format;
  };

  # Map short format names to sops format names
  sopsFormat = {
    bin = "binary";
    json = "json";
    yaml = "yaml";
    env = "dotenv";
  }.${config.format};

  encryptPkg = pkgs:
    pkgs.writeShellApplication {
      name = "secret-encrypt-${name}";
      runtimeInputs = [pkgs.sops];
      text = ''
        ${secretNotExistsContext pkgs}

        # Ensure directory exists
        mkdir -p "$(dirname "$SECRET_PATH")"

        SOPS_CONFIG=$(cat <<'SOPS_CONFIG'
        ${sopsConfig}SOPS_CONFIG
        )

        if [[ -n "''${1:-}" ]]; then
          # Content provided as argument - encrypt directly
          if echo -n "$1" | sops --config <(echo "$SOPS_CONFIG") --input-type ${sopsFormat} --output-type ${sopsFormat} -e /dev/stdin > "$SECRET_PATH"; then
            echo "Secret created at $SECRET_PATH"
          else
            [[ -f "$SECRET_PATH" ]] && rm -f "$SECRET_PATH"
            echo "Error: Failed to create secret" >&2
            exit 1
          fi
        else
          # No argument - open editor
          if sops --config <(echo "$SOPS_CONFIG") --input-type ${sopsFormat} --output-type ${sopsFormat} "$SECRET_PATH"; then
            echo "Secret created at $SECRET_PATH"
          else
            [[ -f "$SECRET_PATH" ]] && rm -f "$SECRET_PATH"
            echo "Error: Failed to create secret" >&2
            exit 1
          fi
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

    encrypt = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = encryptPkg;
      description = "Operation: creates a new encrypted secret (fails if file already exists)";
    };

    decrypt = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = decryptPkg;
      description = "Operation: decrypts and outputs secret data to stdout. Supports: .withSopsAgeKeyCmd, .withSopsAgeKeyCmdPkg, .buildSopsAgeKeyCmdPkg";
    };
  };
}
