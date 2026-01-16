# Per-system packages for secrets management
# Provides: nix run .#secrets.<group>.<secret>.<cmd>
{flake}: {
  lib,
  ...
}: let
  inherit (lib) mapAttrs attrNames concatStringsSep concatMapStringsSep;

  # Available commands for each secret
  commandNames = ["path" "recipients" "rule"];

  # Build command packages for a secret
  mkSecretCommands = groupName: secretName: secretConfig: pkgs:
    mapAttrs (cmdName: script:
      pkgs.writeShellApplication {
        name = "secrets-${groupName}-${secretName}-${cmdName}";
        text = script;
      })
    {
      path = ''
        echo "${secretConfig._path}"
      '';
      recipients = ''
        echo "Recipients for ${groupName}/${secretName}:"
        ${concatMapStringsSep "\n" (r: ''echo "  ${r}"'') (attrNames secretConfig.recipients)}
      '';
      rule = ''
        cat <<'EOF'
        ${secretConfig._creationRule}
        EOF
      '';
    };

  # Build a secret info package that displays metadata
  mkSecretPackage = groupName: secretName: secretConfig: pkgs: let
    recipientNames = attrNames secretConfig.recipients;
    commands = mkSecretCommands groupName secretName secretConfig pkgs;

    base = pkgs.writeShellApplication {
      name = "secrets-${groupName}-${secretName}";
      text = ''
        echo "Secret: ${groupName}/${secretName}"
        echo ""
        echo "Path: ${secretConfig._path}"
        echo ""
        echo "Recipients: ${if recipientNames == [] then "(none)" else concatStringsSep ", " recipientNames}"
        echo ""
        echo "Available commands:"
        ${concatMapStringsSep "\n" (cmd: ''echo "  nix run .#secrets.${groupName}.${secretName}.${cmd}"'') commandNames}
      '';
    };
  in
    base.overrideAttrs (old: {
      passthru = (old.passthru or {}) // commands;
    });

  # Build a group package with secrets as passthru
  mkGroupPackage = groupName: groupSecrets: pkgs: let
    secretNames = attrNames groupSecrets;

    secrets = mapAttrs (secretName: secretConfig:
      mkSecretPackage groupName secretName secretConfig pkgs)
    groupSecrets;

    base = pkgs.writeShellApplication {
      name = "secrets-${groupName}";
      text = ''
        echo "Secrets group: ${groupName}"
        echo ""
        echo "Secrets:"
        ${concatMapStringsSep "\n" (s: ''echo "  - ${s}"'') secretNames}
        echo ""
        echo "Usage:"
        echo "  nix run .#secrets.${groupName}.<secret>        Show secret info"
        echo "  nix run .#secrets.${groupName}.<secret>.<cmd>  Run command"
        echo ""
        echo "Commands: ${concatStringsSep ", " commandNames}"
      '';
    };
  in
    base.overrideAttrs (old: {
      passthru = (old.passthru or {}) // secrets;
    });

  # Build the top-level secrets package
  mkSecretsPackage = secretsGroups: pkgs: let
    groupNames = attrNames secretsGroups;

    groups = mapAttrs (groupName: groupSecrets:
      mkGroupPackage groupName groupSecrets pkgs)
    secretsGroups;

    base = pkgs.writeShellApplication {
      name = "secrets";
      text = ''
        echo "Secrets Management"
        echo ""
        echo "Groups:"
        ${concatMapStringsSep "\n" (g: ''echo "  - ${g}"'') groupNames}
        echo ""
        echo "Usage:"
        echo "  nix run .#secrets.<group>                  Show group info"
        echo "  nix run .#secrets.<group>.<secret>         Show secret info"
        echo "  nix run .#secrets.<group>.<secret>.<cmd>   Run command"
        echo ""
        echo "Commands: ${concatStringsSep ", " commandNames}"
      '';
    };
  in
    base.overrideAttrs (old: {
      passthru = (old.passthru or {}) // groups;
    });
in {
  perSystem = {pkgs, ...}: {
    packages.secrets = mkSecretsPackage flake.secrets pkgs;
  };
}
