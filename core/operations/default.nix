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
  projectOutPath = config._projectOutPath;

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
    builtinKeyCmd = if resolved.cmd != null then "\"${resolved.cmd}\"" else "";
  in
    assert config._exists || throw "Secret '${name}' does not exist at ${storePath}. Create it with init first.";
    pkgs.writeShellApplication {
      name = "decrypt-${name}";
      runtimeInputs = [pkgs.sops] ++ fmtCfg.runtimeInputs ++ (lib.optional (resolved.pkg != null) resolved.pkg);
      text = ''
        ${sopsConfigSetup}

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
      4. SOPS_AGE_KEY environment variable
      5. SOPS_AGE_KEY_FILE environment variable
      6. SOPS_AGE_KEY_CMD environment variable
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
    SOPS_AGE_KEY          Age secret key (direct value)
    SOPS_AGE_KEY_FILE     Path to age secret key file
    SOPS_AGE_KEY_CMD      Command to retrieve age secret key

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

        # Apply builtin key command if no runtime key config provided
        if [[ -z "''${SOPS_AGE_KEY:-}" ]] && [[ -z "''${SOPS_AGE_KEY_FILE:-}" ]] && [[ -z "''${SOPS_AGE_KEY_CMD:-}" ]]; then
          if [[ -n "$BUILTIN_KEY_CMD" ]]; then
            export SOPS_AGE_KEY_CMD="$BUILTIN_KEY_CMD"
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
      name = "rotate-${name}";
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
          echo "Usage: secret-rotate-${name} 'content'" >&2
          echo "       secret-rotate-${name} ./file.json" >&2
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
      name = "rekey-${name}";
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
  decryptPkg = pkgs: let
    basePkg = mkBuilderPkg mkDecrypt {keyCmd = null;} pkgs;
    # Build recipient-specific decrypt packages for those with decryptPkg
    recipientsWithDecrypt = lib.filterAttrs (_: r: r.decryptPkg != null) config.recipients;
    recipientPkgs = lib.mapAttrs (recipientName: recipient:
      mkBuilderPkg mkDecrypt {
        keyCmd = {
          type = "build";
          value = recipient.decryptPkg;
        };
      } pkgs
    ) recipientsWithDecrypt;
  in
    basePkg.overrideAttrs (old: {
      passthru = (old.passthru or {}) // {
        recipient = recipientPkgs;
      };
    });
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
