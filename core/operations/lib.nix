# Shared building blocks for secret operations.
#
# Every operation is produced by `mkOperation`, which owns the parts all
# operations share: argument parsing, help text, key resolution, output path
# resolution and atomic writes. An operation only declares what differs.
{
  lib,
  name,
  config,
}: let
  inherit (lib) concatMapStringsSep concatStringsSep escapeShellArg optionalString optionals;

  fileName = config._fileName;
  # Interpolating copies the encrypted file into the store as a dependency of
  # the operation, so the package works wherever its closure is copied.
  storePath =
    if config._exists
    then "${config._path}"
    else toString config._path;
  projectOutPath = config._projectOutPath;
  exists = config._exists;

  inherit (import ../names.nix {inherit lib;}) toEnvVar;
  secretEnvName = toEnvVar name;
  recipientNamesList = builtins.attrNames config.recipients;
  recipientNames = concatStringsSep ", " recipientNamesList;

  sopsFormat =
    {
      bin = "binary";
      json = "json";
      yaml = "yaml";
      env = "dotenv";
    }.${
      config.format
    };

  # .sops.yaml content for this secret (public keys only)
  sopsConfig = let
    ageKeys = map (r: r.key) (builtins.attrValues config.recipients);
    ageKeysList = concatStringsSep "\n          - " ageKeys;
  in ''
    creation_rules:
      - path_regex: .*
        key_groups:
          - age:
              - ${ageKeysList}
  '';

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
    else throw "secrets.nix: unknown keyCmd type '${keyCmd.type}'";

  # Indent every non-empty line of `s` by `n` spaces
  indent = n: s: let
    pad = lib.fixedWidthString n " " "";
  in
    concatMapStringsSep "\n" (l:
      if l == ""
      then l
      else pad + l) (lib.splitString "\n" (lib.removeSuffix "\n" s));

  # Value-taking CLI option: { flag, metavar, var, help }
  renderOptionHelp = o: "    ${o.flag} ${o.metavar}\n${indent 8 o.help}";
  renderOptionCase = o: ''
    ${o.flag})
      [[ $# -ge 2 ]] || die "${o.flag} requires a value"
      ${o.var}="$2"
      shift 2
      ;;
    ${o.flag}=*)
      ${o.var}="''${1#*=}"
      shift
      ;;
  '';

  keyOptions = [
    {
      flag = "--sopsAgeKey";
      metavar = "<key>";
      var = "CLI_AGE_KEY";
      help = "Use this age secret key directly.\nWARNING: visible in the process list. Prefer --sopsAgeKeyCmd.";
    }
    {
      flag = "--sopsAgeKeyFile";
      metavar = "<path>";
      var = "CLI_AGE_KEY_FILE";
      help = "Read the age secret key from this file.";
    }
    {
      flag = "--sopsAgeKeyCmd";
      metavar = "<cmd>";
      var = "CLI_AGE_KEY_CMD";
      help = "Run this command to get the age secret key.";
    }
  ];

  keyEnvironmentHelp =
    ''
      Key resolution order (first match wins):
        1. --sopsAgeKey / --sopsAgeKeyFile / --sopsAgeKeyCmd
        2. ${secretEnvName}__<RECIPIENT>__AGE_KEY[_FILE|_CMD]   (this secret only)
        3. <RECIPIENT>__AGE_KEY[_FILE|_CMD]   (all secrets for a recipient)
        4. SOPS_AGE_KEY[_FILE|_CMD]   (global)
        5. Key command built into this package (.recipient.<name>, .with*)

      Recipient variable prefixes for this secret:
    ''
    + concatMapStringsSep "\n" (r: "  ${r}: ${secretEnvName}__${toEnvVar r}__AGE_KEY*, ${toEnvVar r}__AGE_KEY*") recipientNamesList;

  # Resolve <SECRET>__<RECIPIENT>__AGE_KEY* then <RECIPIENT>__AGE_KEY*.
  # Exactly one recipient may be configured per level.
  recipientKeyResolution = ''
    resolve_recipient_key() {
      local level r rname renv prefix kind var found found_kind found_value conflicts
      for level in secret recipient; do
        found=""
        found_kind=""
        found_value=""
        conflicts=""
        for r in ${concatMapStringsSep " " (r: escapeShellArg "${r}:${toEnvVar r}") recipientNamesList}; do
          rname="''${r%%:*}"
          renv="''${r#*:}"
          if [[ "$level" == secret ]]; then
            prefix="${secretEnvName}__$renv"
          else
            prefix="$renv"
          fi
          for kind in KEY KEY_FILE KEY_CMD; do
            var="''${prefix}__AGE_$kind"
            if [[ -n "''${!var:-}" ]]; then
              if [[ -n "$found" ]]; then
                conflicts="$conflicts $rname"
              else
                found="$rname"
                found_kind="$kind"
                found_value="''${!var}"
              fi
              break
            fi
          done
        done
        if [[ -n "$conflicts" ]]; then
          die "key variables are set for several recipients at the $level level ($found$conflicts). Set only one, or use ${secretEnvName}__<RECIPIENT>__AGE_KEY* to choose."
        fi
        if [[ -n "$found" ]]; then
          export "SOPS_AGE_$found_kind=$found_value"
          return 0
        fi
      done
      return 1
    }
  '';

  keyResolution = builtinKeyCmd: ''
    if [[ -n "$CLI_AGE_KEY" ]]; then
      export SOPS_AGE_KEY="$CLI_AGE_KEY"
    elif [[ -n "$CLI_AGE_KEY_FILE" ]]; then
      export SOPS_AGE_KEY_FILE="$CLI_AGE_KEY_FILE"
    elif [[ -n "$CLI_AGE_KEY_CMD" ]]; then
      export SOPS_AGE_KEY_CMD="$CLI_AGE_KEY_CMD"
    elif resolve_recipient_key; then
      :
    elif [[ -z "''${SOPS_AGE_KEY:-}''${SOPS_AGE_KEY_FILE:-}''${SOPS_AGE_KEY_CMD:-}" ]]; then
      ${
      if builtinKeyCmd == null
      then ":"
      # The command is stored literally; sops runs it.
      else "# shellcheck disable=SC2016\n  export SOPS_AGE_KEY_CMD=${escapeShellArg builtinKeyCmd}"
    }
    fi
  '';

  # Default write target. A path inside the flake source is located relative
  # to the git repository root at runtime, so the cwd does not matter.
  defaultSecretTarget =
    if lib.hasPrefix "./" projectOutPath
    then ''
      PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
        || die "not inside a git repository, so ${projectOutPath} cannot be located. Run from the project that defines '${name}', or pass --output."
      OUTPUT_PATH="$PROJECT_ROOT/${lib.removePrefix "./" projectOutPath}"
    ''
    else ''
      OUTPUT_PATH=${escapeShellArg projectOutPath}
    '';

  # output = "secret": writes the encrypted secret file.
  #   --output takes a directory or a path ending in the expected filename.
  # output = "plain": writes plaintext anywhere; defaults to stdout.
  outputResolution = {
    output,
    allowStdout,
  }:
    (
      if output == "secret"
      then ''
        ${optionalString exists "DEFAULT_TARGET=0"}
        if [[ -z "$OUTPUT_ARG" ]]; then
          ${optionalString exists "DEFAULT_TARGET=1"}
          ${defaultSecretTarget}
        ${optionalString allowStdout ''
          elif [[ "$OUTPUT_ARG" == /dev/stdout ]]; then
            OUTPUT_PATH=/dev/stdout
        ''}
        elif [[ -d "$OUTPUT_ARG" || "$OUTPUT_ARG" == */ ]]; then
          OUTPUT_PATH="''${OUTPUT_ARG%/}/$EXPECTED_FILENAME"
        else
          GIVEN_FILENAME="$(basename "$OUTPUT_ARG")"
          [[ "$GIVEN_FILENAME" == "$EXPECTED_FILENAME" ]] \
            || die "filename mismatch: expected $EXPECTED_FILENAME, got $GIVEN_FILENAME. Pass a directory instead: --output $(dirname "$OUTPUT_ARG")/"
          OUTPUT_PATH="$OUTPUT_ARG"
        fi
      ''
      else ''
        OUTPUT_PATH="''${OUTPUT_ARG:-/dev/stdout}"
      ''
    )
    + ''
      if [[ "$OUTPUT_PATH" == /dev/stdout ]]; then
        OUT_TMP=/dev/stdout
      else
        OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
        [[ -d "$OUTPUT_DIR" ]] || die "directory does not exist: $OUTPUT_DIR"
        ${optionalString (output == "secret" && exists) ''
        # Only overwrite the default target if it is the file this package was
        # built from; otherwise we are in the wrong project or it has diverged.
        if [[ "$DEFAULT_TARGET" == 1 && -e "$OUTPUT_PATH" ]] && ! cmp -s "$OUTPUT_PATH" "$SECRET_PATH"; then
          die "$OUTPUT_PATH differs from the secret this command was built from ($SECRET_PATH). Refusing to overwrite it. Re-run from the project that defines '${name}', or pass --output."
        fi
      ''}
        OUT_TMPDIR="$(mktemp -d -p "$OUTPUT_DIR" ".secrets-nix.XXXXXX")"
        OUT_TMP="$OUT_TMPDIR/$(basename "$OUTPUT_PATH")"
      fi

      # Move the finished output into place. Nothing touches OUTPUT_PATH
      # until the operation has fully succeeded.
      commit_output() {
        if [[ "$OUTPUT_PATH" == /dev/stdout ]]; then
          return 0
        fi
        ${optionalString (output == "secret") ''chmod 0644 "$OUT_TMP"''}
        mv -f "$OUT_TMP" "$OUTPUT_PATH"
        echo "$1: $OUTPUT_PATH" >&2
      }
    '';

  mkOperation = {
    pkgs,
    op,
    summary,
    usage ? "[OPTIONS]",
    description,
    # null | "secret" | "plain"
    output ? null,
    allowStdout ? false,
    outputHelp ? "",
    # Operation decrypts the evaluated secret and needs a private key
    needsKey ? false,
    keyCmd ? null,
    options ? [],
    examples,
    runtimeInputs ? [],
    body,
  }: let
    cmdName = "${op}-${name}";
    resolved = resolveKeyCmd pkgs keyCmd;
    sopsConfigFile = pkgs.writeText "${name}-sops.yaml" sopsConfig;
    outputOption = {
      flag = "--output";
      metavar = "<path>";
      var = "OUTPUT_ARG";
      help = outputHelp;
    };
    allOptions =
      options
      ++ optionals (output != null) [outputOption]
      ++ optionals needsKey keyOptions;
    help = pkgs.writeText "${cmdName}-help" ''
      ${cmdName} - ${summary}

      USAGE
          ${cmdName} ${usage}

      DESCRIPTION
      ${indent 4 description}

      OPTIONS
      ${concatMapStringsSep "\n\n" renderOptionHelp allOptions}${optionalString (allOptions != []) "\n\n"}    -h, --help
              Show this help message.

      EXAMPLES
      ${indent 4 examples}
      ${optionalString needsKey ''

        ENVIRONMENT
        ${indent 4 keyEnvironmentHelp}
      ''}
      NOTES
          Secret:     ${name}
          Format:     ${sopsFormat}
          Recipients: ${recipientNames}
          Project:    ${projectOutPath}${optionalString exists "\n    Source:     ${storePath}"}
    '';
  in
    pkgs.writeShellApplication {
      name = cmdName;
      runtimeInputs =
        [pkgs.sops pkgs.coreutils pkgs.diffutils]
        ++ optionals (output == "secret" && lib.hasPrefix "./" projectOutPath) [pkgs.git]
        ++ optionals (resolved.pkg != null) [resolved.pkg]
        ++ runtimeInputs;
      text = ''
        umask 077

        die() {
          echo "Error: $*" >&2
          exit 1
        }

        # Shared prelude: not every operation uses every variable.
        # shellcheck disable=SC2034
        EXPECTED_FILENAME=${escapeShellArg fileName}
        # shellcheck disable=SC2034
        SECRET_PATH=${escapeShellArg storePath}
        WORK_DIR="$(mktemp -d)"
        OUT_TMPDIR=""
        cleanup() {
          rm -rf "$WORK_DIR"
          if [[ -n "$OUT_TMPDIR" ]]; then
            rm -rf "$OUT_TMPDIR"
          fi
        }
        trap cleanup EXIT

        sops_run() {
          sops --config ${sopsConfigFile} --input-type ${sopsFormat} --output-type ${sopsFormat} "$@"
        }

        ${concatMapStringsSep "\n" (o: "${o.var}=\"\"") allOptions}
        ${optionalString needsKey recipientKeyResolution}

        while [[ $# -gt 0 ]]; do
          case "$1" in
            -h|--help)
              cat ${help}
              exit 0
              ;;
            ${concatMapStringsSep "\n" renderOptionCase allOptions}
            *)
              die "unknown argument: $1 (run with --help for usage)"
              ;;
          esac
        done

        ${optionalString needsKey (keyResolution resolved.cmd)}
        ${optionalString (output != null) (outputResolution {inherit output allowStdout;})}
        ${body}
      '';
    };

  # Builder pattern wrapper for operations that need .withSopsAgeKeyCmd etc
  mkBuilderPkg = mkOpFn: currentOpts: pkgs: let
    pkg = mkOpFn currentOpts pkgs;
    withKeyCmd = type: value:
      mkBuilderPkg mkOpFn (currentOpts // {keyCmd = {inherit type value;};}) pkgs;
  in
    pkg.overrideAttrs (old: {
      passthru =
        (old.passthru or {})
        // {
          # .withSopsAgeKeyCmd "command" - string command
          withSopsAgeKeyCmd = withKeyCmd "string";
          # .withSopsAgeKeyCmdPkg drv - derivation
          withSopsAgeKeyCmdPkg = withKeyCmd "pkg";
          # .buildSopsAgeKeyCmdPkg (pkgs: drv) - function
          buildSopsAgeKeyCmdPkg = withKeyCmd "build";
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
    toEnvVar
    secretEnvName
    recipientNamesList
    sopsFormat
    sopsConfig
    resolveKeyCmd
    mkOperation
    mkBuilderPkg
    mkWithRecipients
    ;
}
