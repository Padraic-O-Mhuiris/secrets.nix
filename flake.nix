{
  description = "Declarative SOPS secrets management with flake-parts";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs @ {
    flake-parts,
    self,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} ({flake-parts-lib, ...}: let
      flake-module = flake-parts-lib.importApply ./flake-module self;
    in {
      imports = [
        flake-module
        ./examples
      ];
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {
        config,
        pkgs,
        ...
      }: {
        packages.findProjectRoot = pkgs.writeShellApplication {
          name = "find-project-root";
          text = ''
            find_up() {
              ancestors=()
              while true; do
                if [[ -f $1 ]]; then
                  echo "$PWD"
                  exit 0
                fi
                ancestors+=("$PWD")
                if [[ $PWD == / ]] || [[ $PWD == // ]]; then
                  echo "ERROR: Unable to locate $1 in any of: ''${ancestors[*]@Q}" >&2
                  exit 1
                fi
                cd ..
              done
            }
            find_up "flake.nix"
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = [pkgs.alejandra pkgs.sops pkgs.age];
        };
      };
      flake = rec {
        inherit flake-module;
        flakeModules.default = flake-module;
      };
    });
}
