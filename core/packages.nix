# Create a "secrets" package with nested passthru: secrets.<secret>.<operation>
#
# Structure:
#   secrets                         # Top-level package (lists all secrets)
#   secrets.<name>                  # Secret info package
#   secrets.<name>.decrypt          # Decrypt operation
#   secrets.<name>.edit             # Edit operation
#   secrets.<name>.rotate           # Rotate operation
#   secrets.<name>.rekey            # Rekey operation
#   secrets.<name>.init             # Init operation
#   secrets.<name>.env              # Env var template output
#
{lib}: secrets: pkgs: let
  inherit (lib) mapAttrs attrNames concatStringsSep filterAttrs;

  # Reserved names that cannot be used as secret names
  # These conflict with derivation attributes or reserved sub-packages
  reservedNames = [
    # Common derivation attributes that would conflict with passthru
    "name"
    "meta"
    "passthru"
    "text"
    "type"
    "out"
    "outPath"
    "drvPath"
    "outputs"
    "outputName"
    "all"
    "args"
    "builder"
    "system"
    "overrideAttrs"
    "inputDerivation"
    "drvAttrs"
  ];

  # Validate secret names
  invalidNames = filterAttrs (name: _: builtins.elem name reservedNames) secrets;
  invalidNamesList = attrNames invalidNames;
  validatedSecrets =
    if invalidNamesList != []
    then throw "Invalid secret name(s): ${concatStringsSep ", " invalidNamesList}. These names are reserved: ${concatStringsSep ", " reservedNames}"
    else secrets;

  # Get operation names for display
  operationNames = secret: attrNames secret.__operations;

  # Build operation packages from __operations for a single secret
  buildOperationPackages = secret:
    mapAttrs (_name: builderFn: builderFn pkgs) secret.__operations;

  # Create a secret package with passthru to its operations
  mkSecretPackage = secretName: secret: let
    operations = buildOperationPackages secret;
    opNames = operationNames secret;
    existsStatus =
      if secret._exists
      then "exists"
      else "not created";

    base = pkgs.writeShellApplication {
      name = "secret-${secretName}";
      text = ''
        echo "Secret: ${secretName}"
        echo ""
        echo "Format: ${secret.format}"
        echo "File: ${secret._fileName}"
        echo "Dir: ${toString secret.dir}"
        echo "Path: ${toString secret._path}"
        echo "Status: ${existsStatus}"
        echo ""
        echo "Recipients: ${concatStringsSep ", " (attrNames secret.recipients)}"
        echo ""
        echo "Available operations:"
        ${concatStringsSep "\n" (map (cmd: ''echo "  nix run .#secrets.${secretName}.${cmd}"'') opNames)}
      '';
    };
  in
    base.overrideAttrs (old: {
      passthru = (old.passthru or {}) // operations;
    });

  # All secret packages
  secretPackages = mapAttrs mkSecretPackage validatedSecrets;
  secretNames = attrNames validatedSecrets;

  # Collect all unique recipients across all secrets
  allRecipients = lib.unique (lib.flatten (
    lib.mapAttrsToList (_: secret: attrNames secret.recipients) validatedSecrets
  ));

  # Top-level secrets package
  base = pkgs.writeShellApplication {
    name = "secrets";
    text = ''
      echo "Secrets Management"
      echo ""
      echo "Secrets:"
      ${concatStringsSep "\n" (map (s: ''echo "  - ${s}"'') secretNames)}
      echo ""
      echo "Recipients:"
      ${concatStringsSep "\n" (map (r: ''echo "  - ${r}"'') allRecipients)}
      echo ""
      echo "Usage:"
      echo "  nix run .#secrets.<name>              Show secret info"
      echo "  nix run .#secrets.<name>.init         Create new secret"
      echo "  nix run .#secrets.<name>.decrypt      Decrypt to stdout"
      echo "  nix run .#secrets.<name>.edit         Edit secret"
      echo "  nix run .#secrets.<name>.rotate       Rotate secret value"
      echo "  nix run .#secrets.<name>.rekey        Re-encrypt with current recipients"
      echo "  nix run .#secrets.<name>.env          Output env var template"
    '';
  };
in
  base.overrideAttrs (old: {
    passthru = (old.passthru or {}) // secretPackages;
  })
