# secrets.nix flake-parts module
#
# Usage:
#   flake-parts.lib.mkFlake { inherit inputs; } {
#     imports = [ inputs.secrets-nix.flakeModule ];
#
#     secrets = {
#       api-key = {
#         dir = ./secrets;
#         recipients.alice.key = "age1...";
#         format = "json";
#       };
#     };
#   };
#
# This exposes:
#   - flake.secrets: evaluated secrets configuration
#   - perSystem.packages.secrets: per-system packages for secret operations
{
  lib,
  config,
  ...
}: let
  inherit (import ./core {inherit lib;}) secretModule validateSecrets mkSecretsPackages;
  cfg = config.secrets;
  hasSecrets = cfg != {};
in {
  options.secrets = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule secretModule);
    default = {};
    description = "Secrets, keyed by name. Definitions from several modules are merged.";
  };

  config = lib.mkIf hasSecrets {
    flake.secrets = validateSecrets cfg;

    perSystem = {pkgs, ...}: {
      packages.secrets = mkSecretsPackages config.flake.secrets pkgs;
    };
  };
}
