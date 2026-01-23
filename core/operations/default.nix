# Secret operations module
#
# Implements the secret-api.md specification:
# - decrypt: outputs secret to stdout
# - edit: decrypt -> $EDITOR -> re-encrypt
# - rotate: rotates data encryption key (sops rotate), content unchanged
# - rekey: updates recipients to match config (sops updatekeys), data key unchanged
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

  # Generate full key resolution code for edit/rotate/rekey operations
  # Includes recipient env var resolution + builtin fallback
  keyResolutionCode = builtinKeyCmd: ''
    ${recipientEnvVarResolution}

    # Key resolution: check recipient env vars first, then builtin
    if [[ -z "''${SOPS_AGE_KEY:-}" ]] && [[ -z "''${SOPS_AGE_KEY_FILE:-}" ]] && [[ -z "''${SOPS_AGE_KEY_CMD:-}" ]]; then
      if ! resolve_recipient_key; then
        ${
      if builtinKeyCmd != null
      then ''export SOPS_AGE_KEY_CMD="${builtinKeyCmd}"''
      else ":  # No builtin key command configured"
    }
      fi
    fi
  '';

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

  # ============================================================================
  # INIT OPERATION
  # Creates a new encrypted secret. Does not require decryption.
  # Requires --outpath flag for output location.
  # Content from stdin, positional arg, or $EDITOR (via sops) if neither.
  # ============================================================================
  mkInit = pkgs:
    pkgs.writeShellApplication {
      name = "init-${name}";
      runtimeInputs = [pkgs.sops];
      text = ''
                ${sopsConfigSetup}

                EXPECTED_FILENAME="${fileName}"
                DEFAULT_OUTPUT_PATH="${projectOutPath}"
                OUTPUT_ARG=""
                INPUT_FILE=""

                show_help() {
                  cat <<'HELP'
        init-${name} - Create a new encrypted secret

        USAGE
            init-${name} [OPTIONS]

        DESCRIPTION
            Creates a new SOPS-encrypted secret file for '${name}'.

            Without --input, opens $EDITOR to compose the secret interactively.
            The secret is encrypted using age keys defined in the flake configuration.

        OPTIONS
            --input <path>    Read plaintext content from file or process substitution.
                              Supports /dev/fd paths for secure secret passing.

            --output <path>   Override output location. Can be:
                              - A directory (appends expected filename)
                              - A full file path (must match filename: ${fileName})
                              - /dev/stdout to print encrypted output to screen
                              Default: ${projectOutPath}

            -h, --help        Show this help message.

        EXAMPLES
            # Interactive: open $EDITOR to enter secret
            init-${name}

            # From file
            init-${name} --input ./plaintext-secret.txt

            # Secure: use process substitution (content never in shell history/ps)
            init-${name} --input <(cat ./plaintext-secret.txt)
            init-${name} --input <(pass show my-secret)
            init-${name} --input <(vault kv get -field=value secret/foo)

            # Override output directory
            init-${name} --output ./secrets/

            # Print encrypted output to screen (for inspection/piping)
            init-${name} --input ./secret.txt --output /dev/stdout

        NOTES
            - The output directory must already exist
            - Fails if the secret file already exists (use edit/rotate instead)
            - Format: ${sopsFormat}
            - Recipients: ${builtins.concatStringsSep ", " (builtins.attrNames config.recipients)}
        HELP
                }

                # Parse arguments
                while [[ $# -gt 0 ]]; do
                  case "$1" in
                    -h|--help)
                      show_help
                      exit 0
                      ;;
                    --output)
                      OUTPUT_ARG="$2"
                      shift 2
                      ;;
                    --output=*)
                      OUTPUT_ARG="''${1#*=}"
                      shift
                      ;;
                    --input)
                      INPUT_FILE="$2"
                      shift 2
                      ;;
                    --input=*)
                      INPUT_FILE="''${1#*=}"
                      shift
                      ;;
                    *)
                      echo "Error: Unknown argument: $1" >&2
                      echo "Run with --help for usage information." >&2
                      exit 1
                      ;;
                  esac
                done

                # Determine output path (default to project path)
                if [[ "$OUTPUT_ARG" == "/dev/stdout" ]]; then
                  OUTPUT_PATH="/dev/stdout"
                elif [[ -n "$OUTPUT_ARG" ]]; then
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
                      echo "Hint: Use a directory path instead: --output $(dirname "$OUTPUT_ARG")/" >&2
                      exit 1
                    fi
                    OUTPUT_PATH="$OUTPUT_ARG"
                  fi
                else
                  # Default to project output path
                  OUTPUT_PATH="$DEFAULT_OUTPUT_PATH"
                fi

                # Validation for file output (skip for stdout)
                if [[ "$OUTPUT_PATH" != "/dev/stdout" ]]; then
                  # Check if file already exists
                  if [[ -f "$OUTPUT_PATH" ]]; then
                    echo "Error: Secret file already exists: $OUTPUT_PATH" >&2
                    exit 1
                  fi

                  # Check parent directory exists
                  OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
                  if [[ ! -d "$OUTPUT_DIR" ]]; then
                    echo "Error: Directory does not exist: $OUTPUT_DIR" >&2
                    exit 1
                  fi
                fi

                # Encrypt and write
                if [[ -n "$INPUT_FILE" ]]; then
                  # Read content from file (supports process substitution)
                  if sops --config <(echo "$SOPS_CONFIG") \
                       --input-type ${sopsFormat} --output-type ${sopsFormat} \
                       -e "$INPUT_FILE" > "$OUTPUT_PATH"; then
                    [[ "$OUTPUT_PATH" != "/dev/stdout" ]] && echo "Created: $OUTPUT_PATH" >&2
                  else
                    [[ "$OUTPUT_PATH" != "/dev/stdout" ]] && [[ -f "$OUTPUT_PATH" ]] && rm -f "$OUTPUT_PATH"
                    echo "Error: Failed to encrypt secret" >&2
                    exit 1
                  fi
                else
                  # Use editor
                  if sops --config <(echo "$SOPS_CONFIG") \
                       --input-type ${sopsFormat} --output-type ${sopsFormat} \
                       "$OUTPUT_PATH"; then
                    [[ "$OUTPUT_PATH" != "/dev/stdout" ]] && echo "Created: $OUTPUT_PATH" >&2
                  else
                    [[ "$OUTPUT_PATH" != "/dev/stdout" ]] && [[ -f "$OUTPUT_PATH" ]] && rm -f "$OUTPUT_PATH"
                    echo "Error: Failed to create secret" >&2
                    exit 1
                  fi
                fi
      '';
    };

  # ============================================================================
  # DECRYPT OPERATION
  # Decrypts secret from store path and outputs to stdout or file.
  # ============================================================================
  mkDecrypt = {keyCmd ? null}: pkgs: let
    resolved = resolveKeyCmd pkgs keyCmd;
    fmtCfg = formatConfig pkgs;
    # Build-time key command (from builder pattern)
    builtinKeyCmd =
      if resolved.cmd != null
      then "\"${resolved.cmd}\""
      else "";
    # Generate recipient env var examples for help text
    recipientEnvExamples = lib.concatMapStringsSep "\n    " (rName: let
      envName = toEnvVar rName;
    in ''
      ${secretEnvName}__${envName}__AGE_KEY_CMD   Secret-specific for ${rName}
          ${envName}__AGE_KEY_CMD                 All secrets for ${rName}'')
    recipientNamesList;
  in
    assert config._exists || throw "Secret '${name}' does not exist at ${storePath}. Create it with init first.";
      pkgs.writeShellApplication {
        name = "decrypt-${name}";
        runtimeInputs = [pkgs.sops] ++ fmtCfg.runtimeInputs ++ (lib.optional (resolved.pkg != null) resolved.pkg);
        text = ''
                  ${sopsConfigSetup}
                  ${recipientEnvVarResolution}

                  INPUT_PATH="${storePath}"
                  OUTPUT_PATH="/dev/stdout"
                  BUILTIN_KEY_CMD=${builtinKeyCmd}

                  show_help() {
                    cat <<'HELP'
          decrypt-${name} - Decrypt a secret

          USAGE
              decrypt-${name} [OPTIONS]

          DESCRIPTION
              Decrypts the SOPS-encrypted secret '${name}' and outputs the plaintext.

              By default outputs to stdout.
              Key resolution order (first match wins):
                1. --sopsAgeKey (direct key value)
                2. --sopsAgeKeyFile (path to key file)
                3. --sopsAgeKeyCmd (command that outputs key)
                4. ${secretEnvName}__<RECIPIENT>__AGE_KEY[_FILE|_CMD] (secret-specific)
                5. <RECIPIENT>__AGE_KEY[_FILE|_CMD] (recipient-level)
                6. SOPS_AGE_KEY[_FILE|_CMD] (global)
                7. Builder-configured key command (if any)

          OPTIONS
              --output <path>       Write plaintext to file instead of stdout.
                                    Default: /dev/stdout

              --sopsAgeKey <key>    Use this age secret key directly.
                                    WARNING: Visible in process list. Prefer --sopsAgeKeyCmd.

              --sopsAgeKeyFile <path>
                                    Read age secret key from this file.

              --sopsAgeKeyCmd <cmd> Run this command to get the age secret key.
                                    Recommended for security (e.g., fetch from keyring).

              -h, --help            Show this help message.

          EXAMPLES
              # Decrypt to stdout (default)
              decrypt-${name}

              # Decrypt to file
              decrypt-${name} --output ./plaintext.txt

              # Use key from command (secure)
              decrypt-${name} --sopsAgeKeyCmd "pass show age-key"

              # Use key from file
              decrypt-${name} --sopsAgeKeyFile ~/.config/sops/age/keys.txt

              # Pipe to another command
              decrypt-${name} | jq .

          ENVIRONMENT
              Recipient-specific env vars (for this secret's recipients):
              ${recipientEnvExamples}

              Global env vars:
              SOPS_AGE_KEY          Age secret key (direct value)
              SOPS_AGE_KEY_FILE     Path to age secret key file
              SOPS_AGE_KEY_CMD      Command to retrieve age secret key

              Example .envrc.local (gitignored):
                export BOB__AGE_KEY_CMD="pass show age/bob-key"

          RECIPIENTS
              ${builtins.concatStringsSep ", " recipientNamesList}

          NOTES
              - Format: ${sopsFormat}
              - Source: ${storePath}
          HELP
                  }

                  # Parse arguments
                  while [[ $# -gt 0 ]]; do
                    case "$1" in
                      -h|--help)
                        show_help
                        exit 0
                        ;;
                      --output)
                        OUTPUT_PATH="$2"
                        shift 2
                        ;;
                      --output=*)
                        OUTPUT_PATH="''${1#*=}"
                        shift
                        ;;
                      --sopsAgeKey)
                        export SOPS_AGE_KEY="$2"
                        shift 2
                        ;;
                      --sopsAgeKey=*)
                        export SOPS_AGE_KEY="''${1#*=}"
                        shift
                        ;;
                      --sopsAgeKeyFile)
                        export SOPS_AGE_KEY_FILE="$2"
                        shift 2
                        ;;
                      --sopsAgeKeyFile=*)
                        export SOPS_AGE_KEY_FILE="''${1#*=}"
                        shift
                        ;;
                      --sopsAgeKeyCmd)
                        export SOPS_AGE_KEY_CMD="$2"
                        shift 2
                        ;;
                      --sopsAgeKeyCmd=*)
                        export SOPS_AGE_KEY_CMD="''${1#*=}"
                        shift
                        ;;
                      *)
                        echo "Error: Unknown argument: $1" >&2
                        echo "Run with --help for usage information." >&2
                        exit 1
                        ;;
                    esac
                  done

                  # Key resolution: CLI flags already set SOPS_AGE_* above if provided
                  # Now check recipient env vars if no CLI flags were used
                  if [[ -z "''${SOPS_AGE_KEY:-}" ]] && [[ -z "''${SOPS_AGE_KEY_FILE:-}" ]] && [[ -z "''${SOPS_AGE_KEY_CMD:-}" ]]; then
                    # Try recipient-based env var resolution
                    if ! resolve_recipient_key; then
                      # No recipient env vars found, try builtin key command
                      if [[ -n "$BUILTIN_KEY_CMD" ]]; then
                        export SOPS_AGE_KEY_CMD="$BUILTIN_KEY_CMD"
                      fi
                    fi
                  fi

                  # Decrypt
                  if [[ "$OUTPUT_PATH" == "/dev/stdout" ]]; then
                    sops --config <(echo "$SOPS_CONFIG") \
                         --input-type ${sopsFormat} --output-type ${sopsFormat} \
                         -d "$INPUT_PATH"${fmtCfg.pipe}
                  else
                    if sops --config <(echo "$SOPS_CONFIG") \
                         --input-type ${sopsFormat} --output-type ${sopsFormat} \
                         -d "$INPUT_PATH"${fmtCfg.pipe} > "$OUTPUT_PATH"; then
                      echo "Decrypted: $OUTPUT_PATH" >&2
                    else
                      [[ -f "$OUTPUT_PATH" ]] && rm -f "$OUTPUT_PATH"
                      echo "Error: Failed to decrypt secret" >&2
                      exit 1
                    fi
                  fi
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
      name = "edit-${name}";
      runtimeInputs = [pkgs.sops] ++ (lib.optional (resolved.pkg != null) resolved.pkg);
      text = ''
        ${sopsConfigSetup}
        ${keyResolutionCode resolved.cmd}

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
  # Rotates the data encryption key for a secret using sops rotate.
  # Decrypts and re-encrypts with a new data key. Content unchanged.
  # ============================================================================
  mkRotate = {keyCmd ? null}: pkgs: let
    resolved = resolveKeyCmd pkgs keyCmd;
    builtinKeyCmd =
      if resolved.cmd != null
      then "\"${resolved.cmd}\""
      else "";
    # Generate recipient env var examples for help text
    recipientEnvExamples = lib.concatMapStringsSep "\n    " (rName: let
      envName = toEnvVar rName;
    in ''
      ${secretEnvName}__${envName}__AGE_KEY_CMD   Secret-specific for ${rName}
          ${envName}__AGE_KEY_CMD                 All secrets for ${rName}'')
    recipientNamesList;
  in
    pkgs.writeShellApplication {
      name = "rotate-${name}";
      runtimeInputs = [pkgs.sops] ++ (lib.optional (resolved.pkg != null) resolved.pkg);
      text = ''
                ${sopsConfigSetup}
                ${recipientEnvVarResolution}

                EXPECTED_FILENAME="${fileName}"
                DEFAULT_OUTPUT_PATH="${projectOutPath}"
                SECRET_PATH="${storePath}"
                OUTPUT_ARG=""
                BUILTIN_KEY_CMD=${builtinKeyCmd}

                show_help() {
                  cat <<'HELP'
        rotate-${name} - Rotate the data encryption key

        USAGE
            rotate-${name} [OPTIONS]

        DESCRIPTION
            Rotates the data encryption key for the SOPS-encrypted secret '${name}'.

            Uses 'sops rotate' to decrypt and re-encrypt with a new data key.
            The secret content remains unchanged; only the encryption key is rotated.

        OPTIONS
            --output <path>   Override output location. Can be:
                              - A directory (appends expected filename)
                              - A full file path (must match filename: ${fileName})
                              Default: ${projectOutPath}

            --sopsAgeKey <key>
                              Use this age secret key directly for decryption.
                              WARNING: Visible in process list. Prefer --sopsAgeKeyCmd.

            --sopsAgeKeyFile <path>
                              Read age secret key from this file.

            --sopsAgeKeyCmd <cmd>
                              Run this command to get the age secret key.

            -h, --help        Show this help message.

        EXAMPLES
            # Rotate data key, output to project path
            rotate-${name}

            # Rotate with specific key command
            rotate-${name} --sopsAgeKeyCmd "pass show age-key"

            # Override output directory
            rotate-${name} --output ./secrets/

        ENVIRONMENT
            Recipient-specific env vars (for this secret's recipients):
            ${recipientEnvExamples}

            Global env vars:
            SOPS_AGE_KEY          Age secret key (direct value)
            SOPS_AGE_KEY_FILE     Path to age secret key file
            SOPS_AGE_KEY_CMD      Command to retrieve age secret key

        RECIPIENTS
            ${builtins.concatStringsSep ", " recipientNamesList}

        NOTES
            - Format: ${sopsFormat}
            - Source: ${storePath}
        HELP
                }

                # Parse arguments
                while [[ $# -gt 0 ]]; do
                  case "$1" in
                    -h|--help)
                      show_help
                      exit 0
                      ;;
                    --output)
                      OUTPUT_ARG="$2"
                      shift 2
                      ;;
                    --output=*)
                      OUTPUT_ARG="''${1#*=}"
                      shift
                      ;;
                    --sopsAgeKey)
                      export SOPS_AGE_KEY="$2"
                      shift 2
                      ;;
                    --sopsAgeKey=*)
                      export SOPS_AGE_KEY="''${1#*=}"
                      shift
                      ;;
                    --sopsAgeKeyFile)
                      export SOPS_AGE_KEY_FILE="$2"
                      shift 2
                      ;;
                    --sopsAgeKeyFile=*)
                      export SOPS_AGE_KEY_FILE="''${1#*=}"
                      shift
                      ;;
                    --sopsAgeKeyCmd)
                      export SOPS_AGE_KEY_CMD="$2"
                      shift 2
                      ;;
                    --sopsAgeKeyCmd=*)
                      export SOPS_AGE_KEY_CMD="''${1#*=}"
                      shift
                      ;;
                    *)
                      echo "Error: Unknown argument: $1" >&2
                      echo "Run with --help for usage information." >&2
                      exit 1
                      ;;
                  esac
                done

                # Verify secret exists
                if [[ ! -f "$SECRET_PATH" ]]; then
                  echo "Error: Secret '${name}' does not exist at $SECRET_PATH" >&2
                  echo "Use init to create a new secret." >&2
                  exit 1
                fi

                # Key resolution
                if [[ -z "''${SOPS_AGE_KEY:-}" ]] && [[ -z "''${SOPS_AGE_KEY_FILE:-}" ]] && [[ -z "''${SOPS_AGE_KEY_CMD:-}" ]]; then
                  if ! resolve_recipient_key; then
                    if [[ -n "$BUILTIN_KEY_CMD" ]]; then
                      export SOPS_AGE_KEY_CMD="$BUILTIN_KEY_CMD"
                    fi
                  fi
                fi

                # Determine output path
                if [[ -n "$OUTPUT_ARG" ]]; then
                  if [[ -d "$OUTPUT_ARG" ]] || [[ "$OUTPUT_ARG" == */ ]]; then
                    OUTPUT_PATH="''${OUTPUT_ARG%/}/$EXPECTED_FILENAME"
                  else
                    GIVEN_FILENAME=$(basename "$OUTPUT_ARG")
                    if [[ "$GIVEN_FILENAME" != "$EXPECTED_FILENAME" ]]; then
                      echo "Error: Filename mismatch." >&2
                      echo "  Expected: $EXPECTED_FILENAME" >&2
                      echo "  Given:    $GIVEN_FILENAME" >&2
                      echo "Hint: Use a directory path instead: --output $(dirname "$OUTPUT_ARG")/" >&2
                      exit 1
                    fi
                    OUTPUT_PATH="$OUTPUT_ARG"
                  fi
                else
                  OUTPUT_PATH="$DEFAULT_OUTPUT_PATH"
                fi

                # Validation for file output
                OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
                if [[ ! -d "$OUTPUT_DIR" ]]; then
                  echo "Error: Directory does not exist: $OUTPUT_DIR" >&2
                  exit 1
                fi

                # Copy secret to output path first, then rotate in place
                cp "$SECRET_PATH" "$OUTPUT_PATH"

                if sops --config <(echo "$SOPS_CONFIG") \
                     --input-type ${sopsFormat} --output-type ${sopsFormat} \
                     rotate -i "$OUTPUT_PATH"; then
                  echo "Rotated: $OUTPUT_PATH" >&2
                else
                  rm -f "$OUTPUT_PATH"
                  echo "Error: Failed to rotate secret" >&2
                  exit 1
                fi
      '';
    };

  # ============================================================================
  # REKEY OPERATION
  # Updates master keys (recipients) to match current config using sops updatekeys.
  # Data key unchanged, content unchanged. Only recipient list is updated.
  # ============================================================================
  mkRekey = {keyCmd ? null}: pkgs: let
    resolved = resolveKeyCmd pkgs keyCmd;
    builtinKeyCmd =
      if resolved.cmd != null
      then "\"${resolved.cmd}\""
      else "";
    # Generate recipient env var examples for help text
    recipientEnvExamples = lib.concatMapStringsSep "\n    " (rName: let
      envName = toEnvVar rName;
    in ''
      ${secretEnvName}__${envName}__AGE_KEY_CMD   Secret-specific for ${rName}
          ${envName}__AGE_KEY_CMD                 All secrets for ${rName}'')
    recipientNamesList;
  in
    pkgs.writeShellApplication {
      name = "rekey-${name}";
      runtimeInputs = [pkgs.sops] ++ (lib.optional (resolved.pkg != null) resolved.pkg);
      text = ''
                ${sopsConfigSetup}
                ${recipientEnvVarResolution}

                EXPECTED_FILENAME="${fileName}"
                DEFAULT_OUTPUT_PATH="${projectOutPath}"
                SECRET_PATH="${storePath}"
                OUTPUT_ARG=""
                BUILTIN_KEY_CMD=${builtinKeyCmd}

                show_help() {
                  cat <<'HELP'
        rekey-${name} - Update recipients for a secret

        USAGE
            rekey-${name} [OPTIONS]

        DESCRIPTION
            Updates the master keys (recipients) for the SOPS-encrypted secret '${name}'
            to match the current flake configuration.

            Uses 'sops updatekeys' to add/remove recipients without changing the data key.
            The secret content and data encryption key remain unchanged.

            Use this after modifying the recipients list in your flake configuration
            to grant or revoke access to the secret.

        OPTIONS
            --output <path>   Override output location. Can be:
                              - A directory (appends expected filename)
                              - A full file path (must match filename: ${fileName})
                              Default: ${projectOutPath}

            --sopsAgeKey <key>
                              Use this age secret key directly for decryption.
                              WARNING: Visible in process list. Prefer --sopsAgeKeyCmd.

            --sopsAgeKeyFile <path>
                              Read age secret key from this file.

            --sopsAgeKeyCmd <cmd>
                              Run this command to get the age secret key.

            -h, --help        Show this help message.

        EXAMPLES
            # Update recipients, output to project path
            rekey-${name}

            # Rekey with specific key command
            rekey-${name} --sopsAgeKeyCmd "pass show age-key"

            # Override output directory
            rekey-${name} --output ./secrets/

        ENVIRONMENT
            Recipient-specific env vars (for this secret's recipients):
            ${recipientEnvExamples}

            Global env vars:
            SOPS_AGE_KEY          Age secret key (direct value)
            SOPS_AGE_KEY_FILE     Path to age secret key file
            SOPS_AGE_KEY_CMD      Command to retrieve age secret key

        RECIPIENTS (current config)
            ${builtins.concatStringsSep ", " recipientNamesList}

        NOTES
            - Format: ${sopsFormat}
            - Source: ${storePath}
        HELP
                }

                # Parse arguments
                while [[ $# -gt 0 ]]; do
                  case "$1" in
                    -h|--help)
                      show_help
                      exit 0
                      ;;
                    --output)
                      OUTPUT_ARG="$2"
                      shift 2
                      ;;
                    --output=*)
                      OUTPUT_ARG="''${1#*=}"
                      shift
                      ;;
                    --sopsAgeKey)
                      export SOPS_AGE_KEY="$2"
                      shift 2
                      ;;
                    --sopsAgeKey=*)
                      export SOPS_AGE_KEY="''${1#*=}"
                      shift
                      ;;
                    --sopsAgeKeyFile)
                      export SOPS_AGE_KEY_FILE="$2"
                      shift 2
                      ;;
                    --sopsAgeKeyFile=*)
                      export SOPS_AGE_KEY_FILE="''${1#*=}"
                      shift
                      ;;
                    --sopsAgeKeyCmd)
                      export SOPS_AGE_KEY_CMD="$2"
                      shift 2
                      ;;
                    --sopsAgeKeyCmd=*)
                      export SOPS_AGE_KEY_CMD="''${1#*=}"
                      shift
                      ;;
                    *)
                      echo "Error: Unknown argument: $1" >&2
                      echo "Run with --help for usage information." >&2
                      exit 1
                      ;;
                  esac
                done

                # Verify secret exists
                if [[ ! -f "$SECRET_PATH" ]]; then
                  echo "Error: Secret '${name}' does not exist at $SECRET_PATH" >&2
                  echo "Use init to create a new secret." >&2
                  exit 1
                fi

                # Key resolution
                if [[ -z "''${SOPS_AGE_KEY:-}" ]] && [[ -z "''${SOPS_AGE_KEY_FILE:-}" ]] && [[ -z "''${SOPS_AGE_KEY_CMD:-}" ]]; then
                  if ! resolve_recipient_key; then
                    if [[ -n "$BUILTIN_KEY_CMD" ]]; then
                      export SOPS_AGE_KEY_CMD="$BUILTIN_KEY_CMD"
                    fi
                  fi
                fi

                # Determine output path
                if [[ -n "$OUTPUT_ARG" ]]; then
                  if [[ -d "$OUTPUT_ARG" ]] || [[ "$OUTPUT_ARG" == */ ]]; then
                    OUTPUT_PATH="''${OUTPUT_ARG%/}/$EXPECTED_FILENAME"
                  else
                    GIVEN_FILENAME=$(basename "$OUTPUT_ARG")
                    if [[ "$GIVEN_FILENAME" != "$EXPECTED_FILENAME" ]]; then
                      echo "Error: Filename mismatch." >&2
                      echo "  Expected: $EXPECTED_FILENAME" >&2
                      echo "  Given:    $GIVEN_FILENAME" >&2
                      echo "Hint: Use a directory path instead: --output $(dirname "$OUTPUT_ARG")/" >&2
                      exit 1
                    fi
                    OUTPUT_PATH="$OUTPUT_ARG"
                  fi
                else
                  OUTPUT_PATH="$DEFAULT_OUTPUT_PATH"
                fi

                # Validation for file output
                OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
                if [[ ! -d "$OUTPUT_DIR" ]]; then
                  echo "Error: Directory does not exist: $OUTPUT_DIR" >&2
                  exit 1
                fi

                # Copy secret to output path first, then updatekeys in place
                cp "$SECRET_PATH" "$OUTPUT_PATH"

                # updatekeys needs a real file for config (not process substitution)
                SOPS_CONFIG_FILE=$(mktemp)
                trap 'rm -f "$SOPS_CONFIG_FILE"' EXIT
                echo "$SOPS_CONFIG" > "$SOPS_CONFIG_FILE"

                if sops --config "$SOPS_CONFIG_FILE" \
                     --input-type ${sopsFormat} --output-type ${sopsFormat} \
                     updatekeys -y "$OUTPUT_PATH"; then
                  echo "Rekeyed: $OUTPUT_PATH" >&2
                else
                  rm -f "$OUTPUT_PATH"
                  echo "Error: Failed to rekey secret" >&2
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

  # ============================================================================
  # ENV OPERATION
  # Outputs env var template for configuring decryption keys
  # ============================================================================
  mkEnv = pkgs: let
    recipientNames = builtins.attrNames config.recipients;
    recipientEnvNames = map toEnvVar recipientNames;
  in
    pkgs.writeShellApplication {
      name = "env-${name}";
      text = ''
                RECIPIENT=""

                show_help() {
                  cat <<'HELP'
        env-${name} - Output environment variable template for decryption

        USAGE
            env-${name} [OPTIONS]

        DESCRIPTION
            Outputs commented environment variable assignments that can be used
            to configure decryption keys for the '${name}' secret.

            Pipe or redirect to a file, then uncomment and configure your recipient.

        OPTIONS
            --recipient <name>    Filter output to a specific recipient
            -h, --help            Show this help message

        RECIPIENTS
            ${builtins.concatStringsSep ", " recipientNames}

        EXAMPLES
            # Output all env vars for this secret
            env-${name}

            # Output env vars for specific recipient
            env-${name} --recipient alice

            # Append to an env file
            env-${name} --recipient alice >> .envrc.secret

        HELP
                }

                output_header() {
                  if [[ -n "$RECIPIENT" ]]; then
                    echo "# Environment variables for decrypting '${name}' as recipient '$RECIPIENT'"
                  else
                    echo "# Environment variables for decrypting '${name}'"
                  fi
                  echo "#"
                  echo "# Resolution order (first match wins):"
                  echo "#   1. CLI flags (--sopsAgeKey, --sopsAgeKeyFile, --sopsAgeKeyCmd)"
                  echo "#   2. Secret-specific recipient vars (${secretEnvName}__<RECIPIENT>__AGE_KEY*)"
                  echo "#   3. Recipient-level vars (<RECIPIENT>__AGE_KEY*)"
                  echo "#   4. Global SOPS vars (SOPS_AGE_KEY*)"
                  echo "#   5. Builder-configured key command (if any)"
                  echo "#"
                  if [[ -z "$RECIPIENT" ]]; then
                    echo "# Recipients: ${builtins.concatStringsSep ", " recipientNames}"
                    echo "#"
                  fi
                  echo ""
                }

                output_recipient_vars() {
                  local r="$1"
                  local r_env="$2"

                  echo "# --- Secret-specific (${name} + $r) ---"
                  echo "# ${secretEnvName}__''${r_env}__AGE_KEY=\"\""
                  echo "# ${secretEnvName}__''${r_env}__AGE_KEY_FILE=\"\""
                  echo "# ${secretEnvName}__''${r_env}__AGE_KEY_CMD=\"\""
                  echo ""
                  echo "# --- Recipient-level ($r, all secrets) ---"
                  echo "# ''${r_env}__AGE_KEY=\"\""
                  echo "# ''${r_env}__AGE_KEY_FILE=\"\""
                  echo "# ''${r_env}__AGE_KEY_CMD=\"\""
                  echo ""
                }

                output_global_vars() {
                  echo "# --- Global (any secret, any recipient) ---"
                  echo "# SOPS_AGE_KEY=\"\""
                  echo "# SOPS_AGE_KEY_FILE=\"\""
                  echo "# SOPS_AGE_KEY_CMD=\"\""
                }

                # Parse arguments
                while [[ $# -gt 0 ]]; do
                  case "$1" in
                    -h|--help)
                      show_help
                      exit 0
                      ;;
                    --recipient)
                      RECIPIENT="$2"
                      shift 2
                      ;;
                    --recipient=*)
                      RECIPIENT="''${1#*=}"
                      shift
                      ;;
                    *)
                      echo "Error: Unknown argument: $1" >&2
                      echo "Run with --help for usage information." >&2
                      exit 1
                      ;;
                  esac
                done

                # Validate recipient if specified
                if [[ -n "$RECIPIENT" ]]; then
                  case "$RECIPIENT" in
                    ${builtins.concatStringsSep "|" recipientNames})
                      ;;
                    *)
                      echo "Error: Unknown recipient: $RECIPIENT" >&2
                      echo "Valid recipients: ${builtins.concatStringsSep ", " recipientNames}" >&2
                      exit 1
                      ;;
                  esac
                fi

                output_header

                if [[ -n "$RECIPIENT" ]]; then
                  # Output for specific recipient
                  case "$RECIPIENT" in
                    ${builtins.concatStringsSep "\n            " (lib.zipListsWith (r: rEnv: ''            ${r})
                          output_recipient_vars "${r}" "${rEnv}"
                          ;;'')
          recipientNames
          recipientEnvNames)}
                  esac
                else
                  # Output for all recipients
                  ${builtins.concatStringsSep "\n          " (lib.zipListsWith (r: rEnv: ''
            output_recipient_vars "${r}" "${rEnv}"'')
          recipientNames
          recipientEnvNames)}
                fi

                output_global_vars
      '';
    };

  # Entry points for operations that need the builder pattern
  decryptPkg = pkgs: let
    basePkg = mkBuilderPkg mkDecrypt {keyCmd = null;} pkgs;
    # Build recipient-specific decrypt packages for those with decryptPkg
    recipientsWithDecrypt = lib.filterAttrs (_: r: r.decryptPkg != null) config.recipients;
    recipientPkgs =
      lib.mapAttrs (
        _recipientName: recipient:
          mkBuilderPkg mkDecrypt {
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
  editPkg = pkgs: mkBuilderPkg mkEdit {keyCmd = null;} pkgs;

  rotatePkg = pkgs: let
    basePkg = mkBuilderPkg mkRotate {keyCmd = null;} pkgs;
    # Build recipient-specific rotate packages for those with decryptPkg
    recipientsWithDecrypt = lib.filterAttrs (_: r: r.decryptPkg != null) config.recipients;
    recipientPkgs =
      lib.mapAttrs (
        _recipientName: recipient:
          mkBuilderPkg mkRotate {
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

  rekeyPkg = pkgs: let
    basePkg = mkBuilderPkg mkRekey {keyCmd = null;} pkgs;
    # Build recipient-specific rekey packages for those with decryptPkg
    recipientsWithDecrypt = lib.filterAttrs (_: r: r.decryptPkg != null) config.recipients;
    recipientPkgs =
      lib.mapAttrs (
        _recipientName: recipient:
          mkBuilderPkg mkRekey {
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
    }
    # Operations available ALWAYS (regardless of secret existence)
    // {
      env = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        default = mkEnv;
        description = "Outputs environment variable template for configuring decryption keys.";
      };
    };
}
