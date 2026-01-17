{
  writeShellApplication,
  name,
  relPath,
  storePath,
  local ? false,
}:
writeShellApplication {
  name =
    if local
    then "local-encrypted-secret-path-${name}"
    else "encrypted-secret-path-${name}";
  text =
    if local
    then
      # bash
      ''
        find_flake_root() {
          local dir="$PWD"
          while [[ "$dir" != / ]]; do
            if [[ -f "$dir/flake.nix" ]]; then
              echo "$dir"
              return 0
            fi
            dir="$(dirname "$dir")"
          done
          return 1
        }

        flake_root="$(find_flake_root)" || {
          echo "Error: Unable to locate flake.nix" >&2
          exit 1
        }

        secret_path="$flake_root/${relPath}"
        echo "$secret_path"
      ''
    else
      # bash
      ''
        echo "${storePath}"
      '';
}
