# Rekey operation
# Updates master keys (recipients) to match current config using sops updatekeys.
# Data key unchanged, content unchanged. Only recipient list is updated.
# Only available when secret exists.
{
  lib,
  name,
  ops,
  ...
}: {keyCmd ? null}: pkgs: let
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
    name = "rekey-${name}";
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
           --input-type ${ops.sopsFormat} --output-type ${ops.sopsFormat} \
           updatekeys -y "$OUTPUT_PATH"; then
        echo "Rekeyed: $OUTPUT_PATH" >&2
      else
        rm -f "$OUTPUT_PATH"
        echo "Error: Failed to rekey secret" >&2
        exit 1
      fi
    '';
  }
