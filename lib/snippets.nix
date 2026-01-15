{
  projectRoot =
    #bash
    ''
      find_project_root() {
        ancestors=()
        while true; do
          if [[ -f $1 ]]; then
            projectRoot="$PWD"
            return 0
          fi
          ancestors+=("$PWD")
          if [[ $PWD == / ]] || [[ $PWD == // ]]; then
            echo "ERROR: Unable to locate $1 in any of: ''${ancestors[*]@Q}" >&2
            exit 1
          fi
          cd ..
        done
      }
      project_root=$(find_project_root "flake.nix")
    '';
}
