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
#   - flake.secrets: evaluated secrets configuration (via mkSecrets)
#   - perSystem.packages.secrets: per-system packages for secret operations
{
  lib,
  config,
  ...
}: let
  inherit (import ./core {inherit lib;}) mkSecrets mkSecretsPackages;
  cfg = config.secrets;
  hasSecrets = cfg != {};
in {
  options.secrets = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    description = "Secrets configuration passed to mkSecrets";
  };

  config = lib.mkIf hasSecrets {
    flake.secrets = mkSecrets cfg;

    perSystem = {pkgs, ...}: {
      packages.secrets = mkSecretsPackages config.flake.secrets pkgs;
    };
  };
}
