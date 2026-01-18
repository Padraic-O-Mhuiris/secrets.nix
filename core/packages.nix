# Create a "secrets" package with nested passthru: secrets.<secret>.ops.<operation>
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

    # Wrapper package for ops namespace
    opsPackage = pkgs.writeShellApplication {
      name = "secret-${secretName}-ops";
      text = ''
        echo "Operations for secret: ${secretName}"
        echo ""
        echo "Available:"
        ${concatStringsSep "\n" (map (cmd: ''echo "  - ${cmd}"'') opNames)}
      '';
    };

    ops = opsPackage.overrideAttrs (old: {
      passthru = (old.passthru or {}) // operations;
    });

    base = pkgs.writeShellApplication {
      name = "secret-${secretName}";
      text = ''
        echo "Secret: ${secretName}"
        echo ""
        # shellcheck disable=SC2016
        echo 'Path: ${secret._runtimePath}'
        echo ""
        echo "Recipients: ${concatStringsSep ", " (attrNames secret.recipients)}"
        echo ""
        echo "Operations: .ops.<cmd>"
        ${concatStringsSep "\n" (map (cmd: ''echo "  - ${cmd}"'') opNames)}
      '';
    };
  in
    base.overrideAttrs (old: {
      passthru = (old.passthru or {}) // { inherit ops; };
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
