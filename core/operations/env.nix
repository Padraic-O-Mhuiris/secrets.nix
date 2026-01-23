# Env operation
# Outputs env var template for configuring decryption keys.
# Always available regardless of whether secret exists.
{
  lib,
  name,
  config,
  ops,
}: pkgs: let
  recipientNames = builtins.attrNames config.recipients;
  recipientEnvNames = map ops.toEnvVar recipientNames;
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
        echo "#   2. Secret-specific recipient vars (${ops.secretEnvName}__<RECIPIENT>__AGE_KEY*)"
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
        echo "# ${ops.secretEnvName}__''${r_env}__AGE_KEY=\"\""
        echo "# ${ops.secretEnvName}__''${r_env}__AGE_KEY_FILE=\"\""
        echo "# ${ops.secretEnvName}__''${r_env}__AGE_KEY_CMD=\"\""
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
          ${builtins.concatStringsSep "\n          " (lib.zipListsWith (r: rEnv: ''          ${r})
                output_recipient_vars "${r}" "${rEnv}"
                ;;'')
        recipientNames
        recipientEnvNames)}
        esac
      else
        # Output for all recipients
        ${builtins.concatStringsSep "\n        " (lib.zipListsWith (r: rEnv: ''
          output_recipient_vars "${r}" "${rEnv}"'')
        recipientNames
        recipientEnvNames)}
      fi

      output_global_vars
    '';
  }
