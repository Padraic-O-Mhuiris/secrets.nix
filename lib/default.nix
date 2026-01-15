{...}: let
in {
  # Inspired from https://github.com/srid/flake-root/blob/master/flake-module.nix
  buildWorkdirScript = path:
  #bash
  ''
    find_up() {
      ancestors=()
      while true; do
        if [[ -f $1 ]]; then
          echo "$PWD"
          return 0
        fi
        ancestors+=("$PWD")
        if [[ $PWD == / ]] || [[ $PWD == // ]]; then
          echo "ERROR: Unable to locate $1 in any of: ''${ancestors[*]@Q}" >&2
          return 1
        fi
        cd ..
      done
    }

    workdir="$(find_up "flake.nix")" || exit 1
    workdir="$workdir/${path}"
  '';
}
