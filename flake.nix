{
  description = "Declarative SOPS secrets management with flake-parts";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs @ {
    flake-parts,
    self,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = inputs.nixpkgs.lib.systems.flakeExposed;
      perSystem = {pkgs, ...}: {
        devShells.default = pkgs.mkShell {
          packages = [pkgs.alejandra pkgs.sops pkgs.age];
          shellHook = ''
            find_flake_root() {
              local dir="$PWD"
              while [[ "$dir" != / ]]; do
                if [[ -f "$dir/flake.nix" ]]; then
                  echo "$dir"
                  return 0
                fi
                dir="$(dirname "$dir")"
              done
              echo "ERROR: Unable to locate flake.nix" >&2
              return 1
            }
            export FLAKE_ROOT="$(find_flake_root)"
          '';
        };
      };

      flake = let
        inherit (import ./core {inherit (inputs.nixpkgs) lib;}) mkSecrets;
      in {
        inherit mkSecrets;

        example = let
          admins = {
            # AGE-SECRET-KEY-1X6NC9SE3V4Z55LQDZCYASDMD0DCQFU9K3EDA5QKC3F5CTNLSZHJSC0JHWK
            alice = "age1v9z267t653yn0pklhy9v23hy3y430snqpeatzp48958utqnhedzq6uvtkd";
            # AGE-SECRET-KEY-1Z5E3JCXWWFMPQS9DFH6U2TFA7KZ4Z8DPSZ3Y7SVQSYFXAZQDXXVSR2298J
            bob = "age19t7cnvcpqxv5walahqwz7udv3rrelqm7enztwgk5pg3famr3sq7shzx0ry";
          };

          targets = {
            # AGE-SECRET-KEY-1WW7NT3FU3RMC5TJMD45TA4TWTPT4NXN9ZJR8UHU337W5ZEMWTFFQMW3L5V
            server1 = "age1dpnznv446qgzah35vndw5ys763frgz8h6exfmecn8cvnu394ty5q0cts7s";
          };

          # Helper to convert key strings to recipient attrsets
          mkRecipients = keys:
            builtins.mapAttrs (name: key: {inherit key;}) keys;
        in
          mkSecrets {inherit self;} {
            # Minimal: just recipients
            api-key.recipients = mkRecipients admins;

            # With custom dir
            db-password = {
              recipients = mkRecipients (admins // targets);
              dir = "secrets/prod";
            };

            # JSON format
            service-account = {
              recipients = mkRecipients admins;
              format = "json";
            };
          };
      };
    };
}
