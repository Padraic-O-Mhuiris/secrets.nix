# Encrypt operation
# Encrypts content to a secret file. Does not require decryption.
# Always available regardless of whether secret exists.
# Requires --input flag.
{
  name,
  config,
  ops,
  ...
}: pkgs:
pkgs.writeShellApplication {
  name = "encrypt-${name}";
  runtimeInputs = [pkgs.sops];
  text = ''
    ${ops.sopsConfigSetup}

    EXPECTED_FILENAME="${ops.fileName}"
    DEFAULT_OUTPUT_PATH="${ops.projectOutPath}"
    OUTPUT_ARG=""
    INPUT_FILE=""

    show_help() {
      cat <<'HELP'
    encrypt-${name} - Encrypt content to a secret file

    USAGE
        encrypt-${name} --input <path> [OPTIONS]

    DESCRIPTION
        Encrypts plaintext content to a SOPS-encrypted secret file for '${name}'.

        The --input flag is required. Use 'edit' for interactive editing.
        The secret is encrypted using age keys defined in the flake configuration.

    OPTIONS
        --input <path>    (Required) Read plaintext content from file or process
                          substitution. Supports /dev/fd paths for secure secret passing.

        --output <path>   Override output location. Can be:
                          - A directory (appends expected filename)
                          - A full file path (must match filename: ${ops.fileName})
                          - /dev/stdout to print encrypted output to screen
                          Default: ${ops.projectOutPath}

        -h, --help        Show this help message.

    EXAMPLES
        # From file
        encrypt-${name} --input ./plaintext-secret.txt

        # Secure: use process substitution (content never in shell history/ps)
        encrypt-${name} --input <(cat ./plaintext-secret.txt)
        encrypt-${name} --input <(pass show my-secret)
        encrypt-${name} --input <(vault kv get -field=value secret/foo)

        # Override output directory
        encrypt-${name} --input ./secret.txt --output ./secrets/

        # Print encrypted output to screen (for inspection/piping)
        encrypt-${name} --input ./secret.txt --output /dev/stdout

    NOTES
        - The output directory must already exist
        - Will overwrite existing secret file
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

    # Require --input
    if [[ -z "$INPUT_FILE" ]]; then
      echo "Error: --input is required" >&2
      echo "Run with --help for usage information." >&2
      exit 1
    fi

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
      # Check parent directory exists
      OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
      if [[ ! -d "$OUTPUT_DIR" ]]; then
        echo "Error: Directory does not exist: $OUTPUT_DIR" >&2
        exit 1
      fi
    fi

    # Encrypt and write
    if sops --config <(echo "$SOPS_CONFIG") \
         --input-type ${ops.sopsFormat} --output-type ${ops.sopsFormat} \
         -e "$INPUT_FILE" > "$OUTPUT_PATH"; then
      [[ "$OUTPUT_PATH" != "/dev/stdout" ]] && echo "Encrypted: $OUTPUT_PATH" >&2
    else
      [[ "$OUTPUT_PATH" != "/dev/stdout" ]] && [[ -f "$OUTPUT_PATH" ]] && rm -f "$OUTPUT_PATH"
      echo "Error: Failed to encrypt secret" >&2
      exit 1
    fi
  '';
}
