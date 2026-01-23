# Shared utilities for secret operations
{
  lib,
  name,
  config,
}: let
  # Use derived properties from config
  fileName = config._fileName;
  storePath = toString config._path;
  projectOutPath = config._projectOutPath;

  # Normalize name to env var format: api-key -> API_KEY
  toEnvVar = s: lib.toUpper (builtins.replaceStrings ["-"] ["_"] s);
  secretEnvName = toEnvVar name;
  recipientEnvNames = lib.mapAttrs (rName: _: toEnvVar rName) config.recipients;
  recipientNamesList = builtins.attrNames config.recipients;

  # Map short format names to sops format names
  sopsFormat =
    {
      bin = "binary";
      json = "json";
      yaml = "yaml";
      env = "dotenv";
    }.${
      config.format
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

  # Format-specific configuration
  formatConfig = pkgs:
    {
      bin = {
        runtimeInputs = [];
        pipe = "";
      };
      json = {
        runtimeInputs = [pkgs.jq];
        pipe = " | jq";
      };
      yaml = {
        runtimeInputs = [pkgs.yq-go];
        pipe = " | yq";
      };
      env = {
        runtimeInputs = [];
        pipe = "";
      };
    }.${
      config.format
    };

  # Resolve key command configuration to actual command string and package
  resolveKeyCmd = pkgs: keyCmd:
    if keyCmd == null
    then {
      cmd = null;
      pkg = null;
    }
    else if keyCmd.type == "string"
    then {
      cmd = keyCmd.value;
      pkg = null;
    }
    else if keyCmd.type == "pkg"
    then {
      cmd = "${keyCmd.value}/bin/${keyCmd.value.meta.mainProgram or keyCmd.value.pname or keyCmd.value.name}";
      pkg = keyCmd.value;
    }
    else if keyCmd.type == "build"
    then let
      p = keyCmd.value pkgs;
    in {
      cmd = "${p}/bin/${p.meta.mainProgram or p.pname or p.name}";
      pkg = p;
    }
    else {
      cmd = null;
      pkg = null;
    };

  # Generate bash code for recipient-based env var resolution
  # Checks: <SECRET>__<RECIPIENT>__AGE_KEY* then <RECIPIENT>__AGE_KEY* for each recipient
  recipientEnvVarResolution = let
    recipientEnvList =
      lib.mapAttrsToList (rName: envName: {
        name = rName;
        env = envName;
      })
      recipientEnvNames;
  in ''
    # Recipient-based env var resolution
    # Priority: secret-specific > recipient-level > global SOPS_AGE_* > builtin
    resolve_recipient_key() {
      local found_recipient=""
      local found_key_type=""
      local found_key_value=""
      local conflict_recipients=""

      # First pass: check for secret-specific env vars (<SECRET>__<RECIPIENT>__AGE_KEY*)
      ${lib.concatMapStringsSep "\n      " (r: ''
        if [[ -n "''${${secretEnvName}__${r.env}__AGE_KEY:-}" ]]; then
          if [[ -n "$found_recipient" ]]; then
            conflict_recipients="$conflict_recipients ${r.name}"
          else
            found_recipient="${r.name}"
            found_key_type="key"
            found_key_value="''${${secretEnvName}__${r.env}__AGE_KEY}"
          fi
        elif [[ -n "''${${secretEnvName}__${r.env}__AGE_KEY_FILE:-}" ]]; then
          if [[ -n "$found_recipient" ]]; then
            conflict_recipients="$conflict_recipients ${r.name}"
          else
            found_recipient="${r.name}"
            found_key_type="file"
            found_key_value="''${${secretEnvName}__${r.env}__AGE_KEY_FILE}"
          fi
        elif [[ -n "''${${secretEnvName}__${r.env}__AGE_KEY_CMD:-}" ]]; then
          if [[ -n "$found_recipient" ]]; then
            conflict_recipients="$conflict_recipients ${r.name}"
          else
            found_recipient="${r.name}"
            found_key_type="cmd"
            found_key_value="''${${secretEnvName}__${r.env}__AGE_KEY_CMD}"
          fi
        fi
      '')
      recipientEnvList}

      # If we found a secret-specific key, use it (no conflicts at this level - most specific wins)
      if [[ -n "$found_recipient" ]] && [[ -z "$conflict_recipients" ]]; then
        case "$found_key_type" in
          key)  export SOPS_AGE_KEY="$found_key_value" ;;
          file) export SOPS_AGE_KEY_FILE="$found_key_value" ;;
          cmd)  export SOPS_AGE_KEY_CMD="$found_key_value" ;;
        esac
        return 0
      fi

      # Error if multiple secret-specific vars found
      if [[ -n "$conflict_recipients" ]]; then
        echo "Error: Multiple secret-specific key env vars set for recipients:$conflict_recipients $found_recipient" >&2
        echo "Only one recipient's key should be configured at the secret-specific level." >&2
        exit 1
      fi

      # Second pass: check for recipient-level env vars (<RECIPIENT>__AGE_KEY*)
      found_recipient=""
      found_key_type=""
      found_key_value=""
      conflict_recipients=""

      ${lib.concatMapStringsSep "\n      " (r: ''
        if [[ -n "''${${r.env}__AGE_KEY:-}" ]]; then
          if [[ -n "$found_recipient" ]]; then
            conflict_recipients="$conflict_recipients ${r.name}"
          else
            found_recipient="${r.name}"
            found_key_type="key"
            found_key_value="''${${r.env}__AGE_KEY}"
          fi
        elif [[ -n "''${${r.env}__AGE_KEY_FILE:-}" ]]; then
          if [[ -n "$found_recipient" ]]; then
            conflict_recipients="$conflict_recipients ${r.name}"
          else
            found_recipient="${r.name}"
            found_key_type="file"
            found_key_value="''${${r.env}__AGE_KEY_FILE}"
          fi
        elif [[ -n "''${${r.env}__AGE_KEY_CMD:-}" ]]; then
          if [[ -n "$found_recipient" ]]; then
            conflict_recipients="$conflict_recipients ${r.name}"
          else
            found_recipient="${r.name}"
            found_key_type="cmd"
            found_key_value="''${${r.env}__AGE_KEY_CMD}"
          fi
        fi
      '')
      recipientEnvList}

      # Error if multiple recipient-level vars found
      if [[ -n "$conflict_recipients" ]]; then
        echo "Error: Multiple recipient-level key env vars set for recipients:$conflict_recipients $found_recipient" >&2
        echo "Use secret-specific env vars to disambiguate:" >&2
        echo "  ${secretEnvName}__<RECIPIENT>__AGE_KEY_CMD" >&2
        exit 1
      fi

      # If we found a recipient-level key, use it
      if [[ -n "$found_recipient" ]]; then
        case "$found_key_type" in
          key)  export SOPS_AGE_KEY="$found_key_value" ;;
          file) export SOPS_AGE_KEY_FILE="$found_key_value" ;;
          cmd)  export SOPS_AGE_KEY_CMD="$found_key_value" ;;
        esac
        return 0
      fi

      # No recipient env vars found, fall through to global/builtin
      return 1
    }
  '';

  # Shared SOPS config setup
  sopsConfigSetup = ''
    SOPS_CONFIG=$(cat <<'SOPS_CONFIG_EOF'
    ${sopsConfig}SOPS_CONFIG_EOF
    )
  '';

  # Builder pattern wrapper for operations that need .withSopsAgeKeyCmd etc
  mkBuilderPkg = mkOpFn: currentOpts: pkgs: let
    pkg = mkOpFn currentOpts pkgs;
  in
    pkg.overrideAttrs (old: {
      passthru =
        (old.passthru or {})
        // {
          # .withSopsAgeKeyCmd "command" - string command
          withSopsAgeKeyCmd = cmd:
            mkBuilderPkg mkOpFn
            (currentOpts
              // {
                keyCmd = {
                  type = "string";
                  value = cmd;
                };
              })
            pkgs;

          # .withSopsAgeKeyCmdPkg drv - derivation
          withSopsAgeKeyCmdPkg = pkg:
            mkBuilderPkg mkOpFn
            (currentOpts
              // {
                keyCmd = {
                  type = "pkg";
                  value = pkg;
                };
              })
            pkgs;

          # .buildSopsAgeKeyCmdPkg (pkgs: drv) - function
          buildSopsAgeKeyCmdPkg = fn:
            mkBuilderPkg mkOpFn
            (currentOpts
              // {
                keyCmd = {
                  type = "build";
                  value = fn;
                };
              })
            pkgs;
        };
    });

  # Helper to add recipient packages to an operation
  mkWithRecipients = mkOpFn: pkgs: let
    basePkg = mkBuilderPkg mkOpFn {keyCmd = null;} pkgs;
    recipientsWithDecrypt = lib.filterAttrs (_: r: r.decryptPkg != null) config.recipients;
    recipientPkgs =
      lib.mapAttrs (
        _recipientName: recipient:
          mkBuilderPkg mkOpFn {
            keyCmd = {
              type = "build";
              value = recipient.decryptPkg;
            };
          }
          pkgs
      )
      recipientsWithDecrypt;
  in
    basePkg.overrideAttrs (old: {
      passthru =
        (old.passthru or {})
        // {
          recipient = recipientPkgs;
        };
    });
in {
  inherit
    fileName
    storePath
    projectOutPath
    toEnvVar
    secretEnvName
    recipientEnvNames
    recipientNamesList
    sopsFormat
    sopsConfig
    formatConfig
    resolveKeyCmd
    recipientEnvVarResolution
    sopsConfigSetup
    mkBuilderPkg
    mkWithRecipients
    ;
}
