# Env operation
# Outputs env var template for configuring decryption keys.
# Always available regardless of whether secret exists.
{
  lib,
  name,
  ops,
  ...
}: pkgs: let
  inherit (ops) recipientNamesList secretEnvName toEnvVar;

  recipientVars = r: ''
    # --- Secret-specific (${name} + ${r}) ---
    # ${secretEnvName}__${toEnvVar r}__AGE_KEY=""
    # ${secretEnvName}__${toEnvVar r}__AGE_KEY_FILE=""
    # ${secretEnvName}__${toEnvVar r}__AGE_KEY_CMD=""

    # --- Recipient-level (${r}, all secrets) ---
    # ${toEnvVar r}__AGE_KEY=""
    # ${toEnvVar r}__AGE_KEY_FILE=""
    # ${toEnvVar r}__AGE_KEY_CMD=""
  '';

  header = ''
    #
    # Resolution order (first match wins):
    #   1. CLI flags (--sopsAgeKey, --sopsAgeKeyFile, --sopsAgeKeyCmd)
    #   2. Secret-specific recipient vars (${secretEnvName}__<RECIPIENT>__AGE_KEY*)
    #   3. Recipient-level vars (<RECIPIENT>__AGE_KEY*)
    #   4. Global SOPS vars (SOPS_AGE_KEY*)
    #   5. Builder-configured key command (if any)
    #
  '';

  globalVars = ''
    # --- Global (any secret, any recipient) ---
    # SOPS_AGE_KEY=""
    # SOPS_AGE_KEY_FILE=""
    # SOPS_AGE_KEY_CMD=""
  '';

  allTemplate = pkgs.writeText "env-${name}-all" (lib.concatStringsSep "\n" ([
      "# Environment variables for decrypting '${name}'"
      header
      "# Recipients: ${lib.concatStringsSep ", " recipientNamesList}\n#\n"
    ]
    ++ map recipientVars recipientNamesList
    ++ [globalVars]));

  recipientTemplate = r:
    pkgs.writeText "env-${name}-${r}" (lib.concatStringsSep "\n" [
      "# Environment variables for decrypting '${name}' as recipient '${r}'"
      header
      (recipientVars r)
      globalVars
    ]);
in
  ops.mkOperation {
    inherit pkgs;
    op = "env";
    summary = "Output environment variable template for decryption";
    description = ''
      Outputs commented environment variable assignments that configure
      decryption keys for the '${name}' secret. Redirect to a file, then
      uncomment and fill in your recipient.'';
    options = [
      {
        flag = "--recipient";
        metavar = "<name>";
        var = "RECIPIENT";
        help = "Only output variables for this recipient (${lib.concatStringsSep ", " recipientNamesList}).";
      }
    ];
    examples = ''
      # Output all env vars for this secret
      env-${name}

      # Append one recipient's vars to an env file
      env-${name} --recipient ${lib.head recipientNamesList} >> .envrc.local'';
    body = ''
      case "$RECIPIENT" in
        "")
          cat ${allTemplate}
          ;;
        ${lib.concatMapStringsSep "\n" (r: ''
        ${lib.escapeShellArg r})
          cat ${recipientTemplate r}
          ;;'')
      recipientNamesList}
        *)
          die "unknown recipient: $RECIPIENT (valid: ${lib.concatStringsSep ", " recipientNamesList})"
          ;;
      esac
    '';
  }
