# Create a "secrets" package with nested passthru: secrets.<secret>.<operation>
{lib}: evaluatedSecrets: pkgs: let
  inherit (lib) mapAttrs mapAttrs' attrNames concatStringsSep nameValuePair;

  # Convert "mkFindLocalSecret" -> "findLocalSecret"
  uncapitalizeFirst = str: let
    first = lib.substring 0 1 str;
    rest = lib.substring 1 (-1) str;
  in (lib.toLower first) + rest;

  # Get operation names for display
  operationNames = secret:
    map (n: uncapitalizeFirst (lib.removePrefix "mk" n)) (attrNames secret.__operations);

  # Build operation packages from __operations for a single secret
  mkOperationPackages = secret:
    mapAttrs' (builderName: builderFn:
      nameValuePair
        (uncapitalizeFirst (lib.removePrefix "mk" builderName))
        (builderFn pkgs)
    ) secret.__operations;

  # Create a secret package with passthru to its operations
  mkSecretPackage = secretName: secret: let
    operations = mkOperationPackages secret;
    opNames = operationNames secret;

    base = pkgs.writeShellApplication {
      name = "secret-${secretName}";
      text = ''
        echo "Secret: ${secretName}"
        echo ""
        echo "Path: ${secret._fileRelativePath}"
        echo "Exists in store: ${if secret._fileExistsInStore then "yes" else "no"}"
        echo ""
        echo "Recipients: ${concatStringsSep ", " (attrNames secret.recipients)}"
        echo ""
        echo "Available commands:"
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
      echo "  nix run .#secrets.<secret>           Show secret info"
      echo "  nix run .#secrets.<secret>.<cmd>     Run command"
    '';
  };
in
  base.overrideAttrs (old: {
    passthru = (old.passthru or {}) // secretPackages;
  })
