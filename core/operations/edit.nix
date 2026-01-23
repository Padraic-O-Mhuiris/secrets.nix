# Edit operations
# Two variants:
# - mkEditNew: Opens $EDITOR with empty content, encrypts result (for new secrets)
# - mkEditExisting: Decrypts secret, opens in $EDITOR, re-encrypts (for existing secrets)
{
  lib,
  name,
  config,
  ops,
}: {
  # Edit for NEW secrets - no decryption needed
  mkEditNew = pkgs:
    pkgs.writeShellApplication {
      name = "edit-${name}";
      runtimeInputs = [pkgs.sops];
      text = ''
        ${ops.sopsConfigSetup}

        EXPECTED_FILENAME="${ops.fileName}"
        DEFAULT_OUTPUT_PATH="${ops.projectOutPath}"
        OUTPUT_ARG=""

        show_help() {
          cat <<'HELP'
        edit-${name} - Create a new secret interactively

        USAGE
            edit-${name} [OPTIONS]

        DESCRIPTION
            Opens $EDITOR to compose a new SOPS-encrypted secret for '${name}'.

            The secret is encrypted using age keys defined in the flake configuration.

        OPTIONS
            --output <path>   Override output location. Can be:
                              - A directory (appends expected filename)
                              - A full file path (must match filename: ${ops.fileName})
                              Default: ${ops.projectOutPath}

            -h, --help        Show this help message.

        EXAMPLES
            # Open editor, save to default location
            edit-${name}

            # Override output directory
            edit-${name} --output ./secrets/

        NOTES
            - The output directory must already exist
            - Format: ${ops.sopsFormat}
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
            *)
              echo "Error: Unknown argument: $1" >&2
              echo "Run with --help for usage information." >&2
              exit 1
              ;;
          esac
        done

        # Determine output path (default to project path)
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

        # Create empty temp file for editor
        TEMP_FILE=$(mktemp)
        trap 'rm -f "$TEMP_FILE"' EXIT

        # Open in editor
        ''${EDITOR:-vi} "$TEMP_FILE"

        # Check if user saved content
        if [[ ! -s "$TEMP_FILE" ]]; then
          echo "Aborted: No content saved" >&2
          exit 1
        fi

        # Encrypt
        if sops --config <(echo "$SOPS_CONFIG") \
             --input-type ${ops.sopsFormat} --output-type ${ops.sopsFormat} \
             -e "$TEMP_FILE" > "$OUTPUT_PATH"; then
          echo "Created: $OUTPUT_PATH" >&2
        else
          [[ -f "$OUTPUT_PATH" ]] && rm -f "$OUTPUT_PATH"
          echo "Error: Failed to encrypt secret" >&2
          exit 1
        fi
      '';
    };

  # Edit for EXISTING secrets - requires decryption key
  mkEditExisting = {keyCmd ? null}: pkgs: let
    resolved = ops.resolveKeyCmd pkgs keyCmd;
    builtinKeyCmd =
      if resolved.cmd != null
      then "\"${resolved.cmd}\""
      else "";
    # Generate recipient env var examples for help text
    recipientEnvExamples = lib.concatMapStringsSep "\n    " (rName: let
      envName = ops.toEnvVar rName;
    in ''
      ${ops.secretEnvName}__${envName}__AGE_KEY_CMD   Secret-specific for ${rName}
          ${envName}__AGE_KEY_CMD                 All secrets for ${rName}'')
    ops.recipientNamesList;
  in
    pkgs.writeShellApplication {
      name = "edit-${name}";
      runtimeInputs = [pkgs.sops] ++ (lib.optional (resolved.pkg != null) resolved.pkg);
      text = ''
        ${ops.sopsConfigSetup}
        ${ops.recipientEnvVarResolution}

        EXPECTED_FILENAME="${ops.fileName}"
        DEFAULT_OUTPUT_PATH="${ops.projectOutPath}"
        SECRET_PATH="${ops.storePath}"
        OUTPUT_ARG=""
        BUILTIN_KEY_CMD=${builtinKeyCmd}

        show_help() {
          cat <<'HELP'
        edit-${name} - Edit an existing secret interactively

        USAGE
            edit-${name} [OPTIONS]

        DESCRIPTION
            Decrypts the SOPS-encrypted secret '${name}', opens it in $EDITOR,
            and re-encrypts the result.

        OPTIONS
            --output <path>   Override output location. Can be:
                              - A directory (appends expected filename)
                              - A full file path (must match filename: ${ops.fileName})
                              Default: ${ops.projectOutPath}

            --sopsAgeKey <key>
                              Use this age secret key directly for decryption.
                              WARNING: Visible in process list. Prefer --sopsAgeKeyCmd.

            --sopsAgeKeyFile <path>
                              Read age secret key from this file.

            --sopsAgeKeyCmd <cmd>
                              Run this command to get the age secret key.

            -h, --help        Show this help message.

        EXAMPLES
            # Edit secret, save to default location
            edit-${name}

            # Edit with specific key command
            edit-${name} --sopsAgeKeyCmd "pass show age-key"

            # Override output directory
            edit-${name} --output ./secrets/

        ENVIRONMENT
            Recipient-specific env vars (for this secret's recipients):
            ${recipientEnvExamples}

            Global env vars:
            SOPS_AGE_KEY          Age secret key (direct value)
            SOPS_AGE_KEY_FILE     Path to age secret key file
            SOPS_AGE_KEY_CMD      Command to retrieve age secret key

        RECIPIENTS
            ${builtins.concatStringsSep ", " ops.recipientNamesList}

        NOTES
            - Format: ${ops.sopsFormat}
            - Source: ${ops.storePath}
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

        # Key resolution
        if [[ -z "''${SOPS_AGE_KEY:-}" ]] && [[ -z "''${SOPS_AGE_KEY_FILE:-}" ]] && [[ -z "''${SOPS_AGE_KEY_CMD:-}" ]]; then
          if ! resolve_recipient_key; then
            if [[ -n "$BUILTIN_KEY_CMD" ]]; then
              export SOPS_AGE_KEY_CMD="$BUILTIN_KEY_CMD"
            fi
          fi
        fi

        # Determine output path (default to project path)
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

        # Decrypt to temp file
        TEMP_FILE=$(mktemp)
        trap 'rm -f "$TEMP_FILE"' EXIT

        sops --config <(echo "$SOPS_CONFIG") \
             --input-type ${ops.sopsFormat} --output-type ${ops.sopsFormat} \
             -d "$SECRET_PATH" > "$TEMP_FILE"

        # Open in editor
        ''${EDITOR:-vi} "$TEMP_FILE"

        # Re-encrypt
        if sops --config <(echo "$SOPS_CONFIG") \
             --input-type ${ops.sopsFormat} --output-type ${ops.sopsFormat} \
             -e "$TEMP_FILE" > "$OUTPUT_PATH"; then
          echo "Updated: $OUTPUT_PATH" >&2
        else
          [[ -f "$OUTPUT_PATH" ]] && rm -f "$OUTPUT_PATH"
          echo "Error: Failed to re-encrypt secret" >&2
          exit 1
        fi
      '';
    };
}
