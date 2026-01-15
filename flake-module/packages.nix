# Per-system packages for secrets management
# Provides: nix run .#secrets.<group>.<cmd>
# For default group: nix run .#secrets.<cmd> (shorthand)
{flake}: {
  lib,
  ...
}: let
  inherit (lib) mapAttrs attrNames concatStringsSep concatMapStringsSep;

  # Available commands for each secrets group
  commandNames = ["workdir"];

  mkCommands = secretsConfig: {
    workdir = ''
      echo "$workdir"
    '';
  };

  # Build command packages for a secrets group
  mkGroupCommands = groupName: secretsConfig: pkgs:
    mapAttrs (cmdName: script:
      pkgs.writeShellApplication {
        name = "secrets-${groupName}-${cmdName}";
        text = ''
          ${secretsConfig._workdir}
          ${script}
        '';
      })
    (mkCommands secretsConfig);

  # Build a group info package that displays metadata
  mkGroupPackage = groupName: secretsConfig: pkgs: let
    adminRecipients = map (k: k.name) secretsConfig.recipients.admins;
    targetRecipients = map (k: k.name) secretsConfig.recipients.targets;
    commands = mkGroupCommands groupName secretsConfig pkgs;

    base = pkgs.writeShellApplication {
      name = "secrets-${groupName}";
      text = ''
        ${secretsConfig._workdir}
        echo "Secrets group: ${groupName}"
        echo ""
        echo "Workdir: $workdir"
        echo ""
        echo "Admin recipients: ${if adminRecipients == [] then "(none)" else concatStringsSep ", " adminRecipients}"
        echo "Target recipients: ${if targetRecipients == [] then "(none)" else concatStringsSep ", " targetRecipients}"
        echo ""
        echo "Available commands:"
        ${concatMapStringsSep "\n" (cmd: ''echo "  nix run .#secrets.${groupName}.${cmd}"'') commandNames}
      '';
    };
  in
    base.overrideAttrs (old: {
      passthru = (old.passthru or {}) // commands;
    });

  # Build the secrets package with nested passthru
  mkSecretsPackage = secretsConfigs: pkgs: let
    groupNames = attrNames secretsConfigs;

    # Build group packages (each with their own commands as passthru)
    groups = mapAttrs (groupName: secretsConfig:
      mkGroupPackage groupName secretsConfig pkgs)
    secretsConfigs;

    # Default group shortcuts (if exists)
    defaultCommands =
      if secretsConfigs ? default
      then mkGroupCommands "default" secretsConfigs.default pkgs
      else {};

    # Top-level package showing all groups
    base = pkgs.writeShellApplication {
      name = "secrets";
      text = ''
        echo "Secrets Management"
        echo ""
        echo "Groups:"
        ${concatMapStringsSep "\n" (g: ''echo "  - ${g}"'') groupNames}
        echo ""
        echo "Usage:"
        echo "  nix run .#secrets.<group>        Show group info"
        echo "  nix run .#secrets.<group>.<cmd>  Run command"
        ${lib.optionalString (secretsConfigs ? default) ''
          echo ""
          echo "Default group shortcuts:"
          ${concatMapStringsSep "\n" (cmd: ''echo "  nix run .#secrets.${cmd}"'') commandNames}
        ''}
      '';
    };
  in
    base.overrideAttrs (old: {
      passthru = (old.passthru or {}) // groups // defaultCommands;
    });
in {
  perSystem = {pkgs, ...}: {
    packages.secrets = mkSecretsPackage flake.secrets pkgs;
  };
}
