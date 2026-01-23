# Decrypt operation
# Decrypts secret from store path and outputs to stdout or file.
# Only available when secret exists.
{
  lib,
  name,
  config,
  ops,
}: {keyCmd ? null}: pkgs: let
  resolved = ops.resolveKeyCmd pkgs keyCmd;
  fmtCfg = ops.formatConfig pkgs;
  # Build-time key command (from builder pattern)
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
  assert config._exists || throw "Secret '${name}' does not exist at ${ops.storePath}. Create it with init first.";
    pkgs.writeShellApplication {
      name = "decrypt-${name}";
      runtimeInputs = [pkgs.sops] ++ fmtCfg.runtimeInputs ++ (lib.optional (resolved.pkg != null) resolved.pkg);
      text = ''
        ${ops.sopsConfigSetup}
        ${ops.recipientEnvVarResolution}

        INPUT_PATH="${ops.storePath}"
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
              4. ${ops.secretEnvName}__<RECIPIENT>__AGE_KEY[_FILE|_CMD] (secret-specific)
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
               --input-type ${ops.sopsFormat} --output-type ${ops.sopsFormat} \
               -d "$INPUT_PATH"${fmtCfg.pipe}
        else
          if sops --config <(echo "$SOPS_CONFIG") \
               --input-type ${ops.sopsFormat} --output-type ${ops.sopsFormat} \
               -d "$INPUT_PATH"${fmtCfg.pipe} > "$OUTPUT_PATH"; then
            echo "Decrypted: $OUTPUT_PATH" >&2
          else
            [[ -f "$OUTPUT_PATH" ]] && rm -f "$OUTPUT_PATH"
            echo "Error: Failed to decrypt secret" >&2
            exit 1
          fi
        fi
      '';
    }
