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
#
{lib}: evaluatedSecrets: pkgs: let
  inherit (lib) mapAttrs attrNames concatStringsSep;

  # Get operation names for display
  operationNames = secret: attrNames secret.__operations;

  # Build operation packages from __operations for a single secret
  buildOperationPackages = secret:
    mapAttrs (_name: builderFn: builderFn pkgs) secret.__operations;

  # Create a secret package with passthru to its operations
  mkSecretPackage = secretName: secret: let
    operations = buildOperationPackages secret;
    opNames = operationNames secret;
    existsStatus = if secret._exists then "exists" else "not created";

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
  secretPackages = mapAttrs mkSecretPackage evaluatedSecrets;
  secretNames = attrNames evaluatedSecrets;

  # Top-level secrets package
  base = pkgs.writeShellApplication {
    name = "secrets";
    text = ''
      echo "Secrets Management"
      echo ""
      echo "Secrets:"
      ${concatStringsSep "\n" (map (s: ''echo "  - ${s}"'') secretNames)}
      echo ""
      echo "Usage:"
      echo "  nix run .#secrets.<name>              Show secret info"
      echo "  nix run .#secrets.<name>.init         Create new secret"
      echo "  nix run .#secrets.<name>.decrypt      Decrypt to stdout"
      echo "  nix run .#secrets.<name>.edit         Edit secret"
      echo "  nix run .#secrets.<name>.rotate       Rotate secret value"
      echo "  nix run .#secrets.<name>.rekey        Re-encrypt with current recipients"
    '';
  };
in
  base.overrideAttrs (old: {
    passthru = (old.passthru or {}) // secretPackages;
  })
