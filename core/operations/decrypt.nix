# Decrypt operation with builder methods
#
# Builder methods:
#   .withSopsAgeKeyCmd "command"           - string command for SOPS_AGE_KEY_CMD
#   .withSopsAgeKeyCmdPkg drv              - derivation for SOPS_AGE_KEY_CMD
#   .buildSopsAgeKeyCmdPkg (pkgs: drv)     - function (pkgs -> drv) for SOPS_AGE_KEY_CMD
#
{
  lib,
  name,
  sopsConfig,
  secretExistsContext,
}: let
  # Key command can be: null | { type = "string"; value = "cmd"; } | { type = "pkg"; value = drv; } | { type = "build"; value = pkgs -> drv; }
  mkDecrypt = {
    keyCmd ? null,
  }: pkgs: let
    # Resolve the key command based on type
    resolvedKeyCmd =
      if keyCmd == null
      then null
      else if keyCmd.type == "string"
      then keyCmd.value
      else if keyCmd.type == "pkg"
      then "${keyCmd.value}/bin/${keyCmd.value.meta.mainProgram or keyCmd.value.pname or keyCmd.value.name}"
      else if keyCmd.type == "build"
      then let pkg = keyCmd.value pkgs; in "${pkg}/bin/${pkg.meta.mainProgram or pkg.pname or pkg.name}"
      else null;

    # Get the package for runtimeInputs if applicable
    keyCmdPkg =
      if keyCmd == null
      then null
      else if keyCmd.type == "pkg"
      then keyCmd.value
      else if keyCmd.type == "build"
      then keyCmd.value pkgs
      else null;

    keySetup =
      if resolvedKeyCmd != null
      then ''
        export SOPS_AGE_KEY_CMD="${resolvedKeyCmd}"
      ''
      else "";
  in
    pkgs.writeShellApplication {
      name = "secret-decrypt-${name}";
      runtimeInputs = [pkgs.sops] ++ (lib.optional (keyCmdPkg != null) keyCmdPkg);
      text = ''
        ${secretExistsContext pkgs}

        ${keySetup}

        sops --config <(cat <<'SOPS_CONFIG'
        ${sopsConfig}SOPS_CONFIG
        ) -d --input-type binary --output-type binary "$SECRET_PATH"
      '';
    };

  # Create a derivation with builder methods in passthru
  mkBuilderPkg = currentOpts: pkgs: let
    pkg = mkDecrypt currentOpts pkgs;
  in
    pkg.overrideAttrs (old: {
      passthru =
        (old.passthru or {})
        // {
          # .withSopsAgeKeyCmd "command" - string command
          withSopsAgeKeyCmd = cmd:
            mkBuilderPkg
            (currentOpts // {keyCmd = {type = "string"; value = cmd;};})
            pkgs;

          # .withSopsAgeKeyCmdPkg drv - derivation
          withSopsAgeKeyCmdPkg = pkg:
            mkBuilderPkg
            (currentOpts // {keyCmd = {type = "pkg"; value = pkg;};})
            pkgs;

          # .buildSopsAgeKeyCmdPkg (pkgs: drv) - function
          buildSopsAgeKeyCmdPkg = fn:
            mkBuilderPkg
            (currentOpts // {keyCmd = {type = "build"; value = fn;};})
            pkgs;
        };
    });
in
  # Entry point: pkgs -> derivation with builder methods
  pkgs: mkBuilderPkg {keyCmd = null;} pkgs
