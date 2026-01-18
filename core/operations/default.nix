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
  settings,
}: let
  inherit (lib) mkOption types;

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
  # ============================================================================
  mkInit = pkgs: let
    rootPkg = settings.root.mkPackage pkgs;
  in
    pkgs.writeShellApplication {
      name = "secret-init-${name}";
      runtimeInputs = [pkgs.sops];
      text = ''
        ${sopsConfigSetup}

        # Determine output directory from argument or use configured default
        OUTPUT_DIR="''${1:-.}"

        # If output dir is relative, resolve against project root
        if [[ "$OUTPUT_DIR" != /* ]]; then
          ROOT_DIR="$(${rootPkg}/bin/secret-root)"
          OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
        fi

        OUTPUT_PATH="$OUTPUT_DIR/${config._fileName}"

        # Check if file already exists
        if [[ -f "$OUTPUT_PATH" ]]; then
          echo "Error: Secret file already exists: $OUTPUT_PATH" >&2
          exit 1
        fi

        # Ensure directory exists
        mkdir -p "$(dirname "$OUTPUT_PATH")"

        # Read content from stdin or argument
        if [[ -t 0 ]]; then
          # No stdin, check for content argument
          echo "Error: No content provided. Pipe content to stdin or provide as argument." >&2
          echo "Usage: echo 'content' | nix run .#secrets.${name}.init [output-dir]" >&2
          exit 1
        fi

        CONTENT=$(cat)

        # Encrypt and write
        if echo -n "$CONTENT" | sops --config <(echo "$SOPS_CONFIG") \
             --input-type ${sopsFormat} --output-type ${sopsFormat} \
             -e /dev/stdin > "$OUTPUT_PATH"; then
          echo "Created: $OUTPUT_PATH" >&2
        else
          [[ -f "$OUTPUT_PATH" ]] && rm -f "$OUTPUT_PATH"
          echo "Error: Failed to encrypt secret" >&2
          exit 1
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
    if !config._existsInStore
    then throw "Secret '${name}' does not exist at ${toString config._storePath}. Create it with the init operation first."
    else
      pkgs.writeShellApplication {
        name = "secret-decrypt-${name}";
        runtimeInputs = [pkgs.sops] ++ fmtCfg.runtimeInputs ++ (lib.optional (resolved.pkg != null) resolved.pkg);
        text = ''
          ${keySetupCode resolved.cmd}
          ${sopsConfigSetup}

          sops --config <(echo "$SOPS_CONFIG") \
               --input-type ${sopsFormat} --output-type ${sopsFormat} \
               -d "${config._storePath}"${fmtCfg.pipe}
        '';
      };

  # ============================================================================
  # EDIT OPERATION
  # Decrypts secret, opens in $EDITOR, re-encrypts to local file.
  # ============================================================================
  mkEdit = {keyCmd ? null}: pkgs: let
    resolved = resolveKeyCmd pkgs keyCmd;
    rootPkg = settings.root.mkPackage pkgs;
  in
    if !config._existsInStore
    then throw "Secret '${name}' does not exist at ${toString config._storePath}. Create it with the init operation first."
    else
      pkgs.writeShellApplication {
        name = "secret-edit-${name}";
        runtimeInputs = [pkgs.sops] ++ (lib.optional (resolved.pkg != null) resolved.pkg);
        text = ''
          ${keySetupCode resolved.cmd}
          ${sopsConfigSetup}

          # Determine output directory from argument or use configured default
          OUTPUT_DIR="''${1:-${config.dir}}"

          # If output dir is relative, resolve against project root
          if [[ "$OUTPUT_DIR" != /* ]]; then
            ROOT_DIR="$(${rootPkg}/bin/secret-root)"
            OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
          fi

          OUTPUT_PATH="$OUTPUT_DIR/${config._fileName}"

          # Ensure directory exists
          mkdir -p "$(dirname "$OUTPUT_PATH")"

          # Decrypt to temp file
          TEMP_FILE=$(mktemp)
          trap 'rm -f "$TEMP_FILE"' EXIT

          sops --config <(echo "$SOPS_CONFIG") \
               --input-type ${sopsFormat} --output-type ${sopsFormat} \
               -d "${config._storePath}" > "$TEMP_FILE"

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
  # Decrypts secret, accepts new content, re-encrypts to local file.
  # ============================================================================
  mkRotate = {keyCmd ? null}: pkgs: let
    resolved = resolveKeyCmd pkgs keyCmd;
    rootPkg = settings.root.mkPackage pkgs;
  in
    if !config._existsInStore
    then throw "Secret '${name}' does not exist at ${toString config._storePath}. Create it with the init operation first."
    else
      pkgs.writeShellApplication {
        name = "secret-rotate-${name}";
        runtimeInputs = [pkgs.sops] ++ (lib.optional (resolved.pkg != null) resolved.pkg);
        text = ''
          ${keySetupCode resolved.cmd}
          ${sopsConfigSetup}

          # Parse arguments: content from stdin/arg/file, output dir is last arg
          CONTENT=""
          OUTPUT_DIR="${config.dir}"

          # Priority: stdin > file arg > string arg
          if [[ ! -t 0 ]]; then
            # Read from stdin
            CONTENT=$(cat)
            OUTPUT_DIR="''${1:-${config.dir}}"
          elif [[ $# -gt 0 ]]; then
            FIRST_ARG="$1"

            # Check if first arg is a file
            if [[ -f "$FIRST_ARG" ]]; then
              CONTENT=$(cat "$FIRST_ARG")
              OUTPUT_DIR="''${2:-${config.dir}}"
            else
              # First arg is content string
              CONTENT="$FIRST_ARG"
              OUTPUT_DIR="''${2:-${config.dir}}"
            fi
          else
            echo "Error: No content provided." >&2
            echo "Usage: echo 'content' | nix run .#secrets.${name}.rotate [output-dir]" >&2
            echo "       nix run .#secrets.${name}.rotate 'content' [output-dir]" >&2
            echo "       nix run .#secrets.${name}.rotate ./file.json [output-dir]" >&2
            exit 1
          fi

          # If output dir is relative, resolve against project root
          if [[ "$OUTPUT_DIR" != /* ]]; then
            ROOT_DIR="$(${rootPkg}/bin/secret-root)"
            OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
          fi

          OUTPUT_PATH="$OUTPUT_DIR/${config._fileName}"

          # Ensure directory exists
          mkdir -p "$(dirname "$OUTPUT_PATH")"

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
  # ============================================================================
  mkRekey = {keyCmd ? null}: pkgs: let
    resolved = resolveKeyCmd pkgs keyCmd;
    rootPkg = settings.root.mkPackage pkgs;
  in
    if !config._existsInStore
    then throw "Secret '${name}' does not exist at ${toString config._storePath}. Create it with the init operation first."
    else
      pkgs.writeShellApplication {
        name = "secret-rekey-${name}";
        runtimeInputs = [pkgs.sops] ++ (lib.optional (resolved.pkg != null) resolved.pkg);
        text = ''
          ${keySetupCode resolved.cmd}
          ${sopsConfigSetup}

          # Determine output directory from argument or use configured default
          OUTPUT_DIR="''${1:-${config.dir}}"

          # If output dir is relative, resolve against project root
          if [[ "$OUTPUT_DIR" != /* ]]; then
            ROOT_DIR="$(${rootPkg}/bin/secret-root)"
            OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
          fi

          OUTPUT_PATH="$OUTPUT_DIR/${config._fileName}"

          # Ensure directory exists
          mkdir -p "$(dirname "$OUTPUT_PATH")"

          # Decrypt from store
          DECRYPTED=$(sops --config <(echo "$SOPS_CONFIG") \
               --input-type ${sopsFormat} --output-type ${sopsFormat} \
               -d "${config._storePath}")

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

in {
  options = {
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
      description = "Decrypts secret, opens in $EDITOR, re-encrypts to local file. Supports builder methods.";
    };

    rotate = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = rotatePkg;
      description = "Accepts new content and encrypts to local file. Supports builder methods.";
    };

    rekey = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = rekeyPkg;
      description = "Decrypts and re-encrypts with current recipients. Content unchanged. Supports builder methods.";
    };

    init = mkOption {
      type = types.functionTo types.package;
      readOnly = true;
      default = mkInit;
      description = "Creates a new encrypted secret. Does not require decryption - only uses public keys.";
    };
  };
}
