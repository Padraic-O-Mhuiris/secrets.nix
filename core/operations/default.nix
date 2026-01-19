# Secret operations module
#
# Implements the secret-api.md specification:
# - decrypt: outputs secret to stdout
# - edit: decrypt -> $EDITOR -> re-encrypt
# - rotate: decrypt -> new content -> re-encrypt
# - rekey: decrypt -> re-encrypt (same content, updated recipients)
# - init: create new encrypted secret (no decryption needed)
#
# All decrypt-dependent operations share the same builder pattern:
# - .withSopsAgeKeyCmd "command"
# - .withSopsAgeKeyCmdPkg drv
# - .buildSopsAgeKeyCmdPkg (pkgs: drv)
#
{
  lib,
  name,
  config,
}: let
  inherit (lib) mkOption types;

  # Use derived properties from config
  fileName = config._fileName;
  storePath = toString config._path;

  # Map short format names to sops format names
  sopsFormat = {
    bin = "binary";
    json = "json";
    yaml = "yaml";
    env = "dotenv";
  }.${config.format};

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
  formatConfig = pkgs: {
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
  }.${config.format};

  # Resolve key command configuration to actual command string and package
  resolveKeyCmd = pkgs: keyCmd:
    if keyCmd == null
    then {cmd = null; pkg = null;}
    else if keyCmd.type == "string"
    then {cmd = keyCmd.value; pkg = null;}
    else if keyCmd.type == "pkg"
    then {
      cmd = "${keyCmd.value}/bin/${keyCmd.value.meta.mainProgram or keyCmd.value.pname or keyCmd.value.name}";
      pkg = keyCmd.value;
    }
    else if keyCmd.type == "build"
    then let p = keyCmd.value pkgs; in {
      cmd = "${p}/bin/${p.meta.mainProgram or p.pname or p.name}";
      pkg = p;
    }
    else {cmd = null; pkg = null;};

  # Generate key setup bash code
  keySetupCode = resolvedCmd:
    if resolvedCmd != null
    then ''export SOPS_AGE_KEY_CMD="${resolvedCmd}"''
    else "";

  # Shared SOPS config setup
  sopsConfigSetup = ''
    SOPS_CONFIG=$(cat <<'SOPS_CONFIG_EOF'
    ${sopsConfig}SOPS_CONFIG_EOF
    )
  '';

  # ============================================================================
  # INIT OPERATION
  # Creates a new encrypted secret. Does not require decryption.
  # Requires --outpath flag for output location.
  # Content from stdin, positional arg, or $EDITOR (via sops) if neither.
  # ============================================================================
  mkInit = pkgs:
    pkgs.writeShellApplication {
      name = "secret-init-${name}";
      runtimeInputs = [pkgs.sops];
      text = ''
        ${sopsConfigSetup}

        EXPECTED_FILENAME="${fileName}"
        OUTPUT_ARG=""
        CONTENT=""
        USE_EDITOR=false

        # Parse arguments
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --outpath|--outPath)
              OUTPUT_ARG="$2"
              shift 2
              ;;
            --outpath=*|--outPath=*)
              OUTPUT_ARG="''${1#*=}"
              shift
              ;;
            *)
              # Positional argument is content
              CONTENT="$1"
              shift
              ;;
          esac
        done

        # Determine output path (empty means stdout)
        OUTPUT_PATH=""
        if [[ -n "$OUTPUT_ARG" ]]; then
          # Determine if output arg is a directory or file path
          if [[ -d "$OUTPUT_ARG" ]] || [[ "$OUTPUT_ARG" == */ ]]; then
            # It's a directory (exists or ends with /)
            OUTPUT_PATH="''${OUTPUT_ARG%/}/$EXPECTED_FILENAME"
          else
            # It's a file path - validate the filename matches
            GIVEN_FILENAME=$(basename "$OUTPUT_ARG")
            if [[ "$GIVEN_FILENAME" != "$EXPECTED_FILENAME" ]]; then
              echo "Error: Filename mismatch." >&2
              echo "  Expected: $EXPECTED_FILENAME" >&2
              echo "  Given:    $GIVEN_FILENAME" >&2
              echo "Hint: Use a directory path instead: $(dirname "$OUTPUT_ARG")/" >&2
              exit 1
            fi
            OUTPUT_PATH="$OUTPUT_ARG"
          fi

          # Check if file already exists
          if [[ -f "$OUTPUT_PATH" ]]; then
            echo "Error: Secret file already exists: $OUTPUT_PATH" >&2
            exit 1
          fi

          # Ensure parent directory exists
          mkdir -p "$(dirname "$OUTPUT_PATH")"
        fi

        # Determine content source: argument > stdin > editor
        if [[ -n "$CONTENT" ]]; then
          # Content already set from positional argument
          :
        elif [[ -t 0 ]]; then
          # Stdin is a TTY - use editor
          USE_EDITOR=true
        else
          # Stdin is not a TTY - try to read from it
          CONTENT=$(cat)
          if [[ -z "$CONTENT" ]]; then
            # No content from stdin either - show usage
            echo "Error: No content provided." >&2
            echo "Usage: nix run .#secrets.${name}.init -- [content]" >&2
            echo "       nix run .#secrets.${name}.init -- --outpath ./secrets/ [content]" >&2
            echo "       echo 'content' | nix run .#secrets.${name}.init -- --outpath ./secrets/" >&2
            echo "Run directly (not via nix run) to use \$EDITOR" >&2
            exit 1
          fi
        fi

        # Encrypt and write
        if [[ "$USE_EDITOR" == "true" ]]; then
          if [[ -z "$OUTPUT_PATH" ]]; then
            # No outpath with editor - create temp, let sops edit, then cat and remove
            TEMP_FILE=$(mktemp)
            trap 'rm -f "$TEMP_FILE"' EXIT

            if sops --config <(echo "$SOPS_CONFIG") \
                 --input-type ${sopsFormat} --output-type ${sopsFormat} \
                 "$TEMP_FILE"; then
              cat "$TEMP_FILE"
            else
              echo "Error: Failed to create secret" >&2
              exit 1
            fi
          else
            # With outpath - let sops handle everything securely
            if sops --config <(echo "$SOPS_CONFIG") \
                 --input-type ${sopsFormat} --output-type ${sopsFormat} \
                 "$OUTPUT_PATH"; then
              echo "Created: $OUTPUT_PATH" >&2
            else
              [[ -f "$OUTPUT_PATH" ]] && rm -f "$OUTPUT_PATH"
              echo "Error: Failed to create secret" >&2
              exit 1
            fi
          fi
        elif [[ -z "$OUTPUT_PATH" ]]; then
          # No outpath - output to stdout
          echo -n "$CONTENT" | sops --config <(echo "$SOPS_CONFIG") \
               --input-type ${sopsFormat} --output-type ${sopsFormat} \
               -e /dev/stdin
        else
          # Write to file
          if echo -n "$CONTENT" | sops --config <(echo "$SOPS_CONFIG") \
               --input-type ${sopsFormat} --output-type ${sopsFormat} \
               -e /dev/stdin > "$OUTPUT_PATH"; then
            echo "Created: $OUTPUT_PATH" >&2
          else
            [[ -f "$OUTPUT_PATH" ]] && rm -f "$OUTPUT_PATH"
            echo "Error: Failed to encrypt secret" >&2
            exit 1
          fi
        fi
      '';
    };

  # ============================================================================
  # DECRYPT OPERATION
  # Decrypts secret from store path and outputs to stdout.
  # ============================================================================
  mkDecrypt = {keyCmd ? null}: pkgs: let
    resolved = resolveKeyCmd pkgs keyCmd;
    fmtCfg = formatConfig pkgs;
  in
    pkgs.writeShellApplication {
      name = "secret-decrypt-${name}";
      runtimeInputs = [pkgs.sops] ++ fmtCfg.runtimeInputs ++ (lib.optional (resolved.pkg != null) resolved.pkg);
      text = ''
        ${keySetupCode resolved.cmd}
        ${sopsConfigSetup}

        if [[ ! -f "${storePath}" ]]; then
          echo "Error: Secret '${name}' does not exist at ${storePath}. Create it with the init operation first." >&2
          exit 1
        fi

        sops --config <(echo "$SOPS_CONFIG") \
             --input-type ${sopsFormat} --output-type ${sopsFormat} \
             -d "${storePath}"${fmtCfg.pipe}
      '';
    };

  # ============================================================================
  # EDIT OPERATION
  # Decrypts secret, opens in $EDITOR, re-encrypts to local file.
  # Outputs to current directory with filename only.
  # ============================================================================
  mkEdit = {keyCmd ? null}: pkgs: let
    resolved = resolveKeyCmd pkgs keyCmd;
  in
    pkgs.writeShellApplication {
      name = "secret-edit-${name}";
      runtimeInputs = [pkgs.sops] ++ (lib.optional (resolved.pkg != null) resolved.pkg);
      text = ''
        ${keySetupCode resolved.cmd}
        ${sopsConfigSetup}

        if [[ ! -f "${storePath}" ]]; then
          echo "Error: Secret '${name}' does not exist at ${storePath}. Create it with the init operation first." >&2
          exit 1
        fi

        OUTPUT_PATH="./${fileName}"

        # Decrypt to temp file
        TEMP_FILE=$(mktemp)
        trap 'rm -f "$TEMP_FILE"' EXIT

        sops --config <(echo "$SOPS_CONFIG") \
             --input-type ${sopsFormat} --output-type ${sopsFormat} \
             -d "${storePath}" > "$TEMP_FILE"

        # Open in editor
        ''${EDITOR:-vi} "$TEMP_FILE"

        # Re-encrypt
        if sops --config <(echo "$SOPS_CONFIG") \
             --input-type ${sopsFormat} --output-type ${sopsFormat} \
             -e "$TEMP_FILE" > "$OUTPUT_PATH"; then
          echo "Updated: $OUTPUT_PATH" >&2
        else
          echo "Error: Failed to re-encrypt secret" >&2
          exit 1
        fi
      '';
    };

  # ============================================================================
  # ROTATE OPERATION
  # Accepts new content and encrypts to local file.
  # Outputs to current directory with filename only.
  # ============================================================================
  mkRotate = {keyCmd ? null}: pkgs: let
    resolved = resolveKeyCmd pkgs keyCmd;
  in
    pkgs.writeShellApplication {
      name = "secret-rotate-${name}";
      runtimeInputs = [pkgs.sops] ++ (lib.optional (resolved.pkg != null) resolved.pkg);
      text = ''
        ${keySetupCode resolved.cmd}
        ${sopsConfigSetup}

        if [[ ! -f "${storePath}" ]]; then
          echo "Error: Secret '${name}' does not exist at ${storePath}. Create it with the init operation first." >&2
          exit 1
        fi

        OUTPUT_PATH="./${fileName}"
        CONTENT=""

        # Priority: stdin > file arg > string arg
        if [[ ! -t 0 ]]; then
          # Read from stdin
          CONTENT=$(cat)
        elif [[ $# -gt 0 ]]; then
          FIRST_ARG="$1"

          # Check if first arg is a file
          if [[ -f "$FIRST_ARG" ]]; then
            CONTENT=$(cat "$FIRST_ARG")
          else
            # First arg is content string
            CONTENT="$FIRST_ARG"
          fi
        else
          echo "Error: No content provided." >&2
          echo "Usage: echo 'content' | nix run .#secrets.${name}.rotate" >&2
          echo "       nix run .#secrets.${name}.rotate 'content'" >&2
          echo "       nix run .#secrets.${name}.rotate ./file.json" >&2
          exit 1
        fi

        # Encrypt new content
        if echo -n "$CONTENT" | sops --config <(echo "$SOPS_CONFIG") \
             --input-type ${sopsFormat} --output-type ${sopsFormat} \
             -e /dev/stdin > "$OUTPUT_PATH"; then
          echo "Rotated: $OUTPUT_PATH" >&2
        else
          echo "Error: Failed to encrypt secret" >&2
          exit 1
        fi
      '';
    };

  # ============================================================================
  # REKEY OPERATION
  # Decrypts secret, re-encrypts with current recipients. Content unchanged.
  # Outputs to current directory with filename only.
  # ============================================================================
  mkRekey = {keyCmd ? null}: pkgs: let
    resolved = resolveKeyCmd pkgs keyCmd;
  in
    pkgs.writeShellApplication {
      name = "secret-rekey-${name}";
      runtimeInputs = [pkgs.sops] ++ (lib.optional (resolved.pkg != null) resolved.pkg);
      text = ''
        ${keySetupCode resolved.cmd}
        ${sopsConfigSetup}

        if [[ ! -f "${storePath}" ]]; then
          echo "Error: Secret '${name}' does not exist at ${storePath}. Create it with the init operation first." >&2
          exit 1
        fi

        OUTPUT_PATH="./${fileName}"

        # Decrypt from store
        DECRYPTED=$(sops --config <(echo "$SOPS_CONFIG") \
             --input-type ${sopsFormat} --output-type ${sopsFormat} \
             -d "${storePath}")

        # Re-encrypt with current recipients
        if echo -n "$DECRYPTED" | sops --config <(echo "$SOPS_CONFIG") \
             --input-type ${sopsFormat} --output-type ${sopsFormat} \
             -e /dev/stdin > "$OUTPUT_PATH"; then
          echo "Rekeyed: $OUTPUT_PATH" >&2
        else
          echo "Error: Failed to re-encrypt secret" >&2
          exit 1
        fi
      '';
    };

  # ============================================================================
  # BUILDER PATTERN
  # Wraps operation packages with .withSopsAgeKeyCmd etc methods
  # ============================================================================
  mkBuilderPkg = mkOpFn: currentOpts: pkgs: let
    pkg = mkOpFn currentOpts pkgs;
  in
    pkg.overrideAttrs (old: {
      passthru = (old.passthru or {}) // {
        # .withSopsAgeKeyCmd "command" - string command
        withSopsAgeKeyCmd = cmd:
          mkBuilderPkg mkOpFn
          (currentOpts // {keyCmd = {type = "string"; value = cmd;};})
          pkgs;

        # .withSopsAgeKeyCmdPkg drv - derivation
        withSopsAgeKeyCmdPkg = pkg:
          mkBuilderPkg mkOpFn
          (currentOpts // {keyCmd = {type = "pkg"; value = pkg;};})
          pkgs;

        # .buildSopsAgeKeyCmdPkg (pkgs: drv) - function
        buildSopsAgeKeyCmdPkg = fn:
          mkBuilderPkg mkOpFn
          (currentOpts // {keyCmd = {type = "build"; value = fn;};})
          pkgs;
      };
    });

  # Entry points for operations that need the builder pattern
  decryptPkg = pkgs: mkBuilderPkg mkDecrypt {keyCmd = null;} pkgs;
  editPkg = pkgs: mkBuilderPkg mkEdit {keyCmd = null;} pkgs;
  rotatePkg = pkgs: mkBuilderPkg mkRotate {keyCmd = null;} pkgs;
  rekeyPkg = pkgs: mkBuilderPkg mkRekey {keyCmd = null;} pkgs;

  # Conditional operation options based on whether secret exists
  # When secret exists: decrypt, edit, rotate, rekey available
  # When secret doesn't exist: only init available
  exists = config._exists;

in {
  options =
    # Operations available when secret EXISTS (decrypt, edit, rotate, rekey)
    lib.optionalAttrs exists {
      decrypt = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        default = decryptPkg;
        description = "Decrypts secret from store and outputs to stdout. Supports builder methods: .withSopsAgeKeyCmd, .withSopsAgeKeyCmdPkg, .buildSopsAgeKeyCmdPkg";
      };

      edit = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        default = editPkg;
        description = "Decrypts secret, opens in $EDITOR, re-encrypts to current directory. Supports builder methods.";
      };

      rotate = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        default = rotatePkg;
        description = "Accepts new content and encrypts to current directory. Supports builder methods.";
      };

      rekey = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        default = rekeyPkg;
        description = "Decrypts and re-encrypts with current recipients. Content unchanged. Supports builder methods.";
      };
    }
    # Operation available when secret DOES NOT EXIST (init only)
    // lib.optionalAttrs (!exists) {
      init = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        default = mkInit;
        description = "Creates a new encrypted secret. Does not require decryption - only uses public keys.";
      };
    };
}
