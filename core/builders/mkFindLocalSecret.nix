{
  writeShellApplication,
  name,
  relPath,
}:
writeShellApplication {
  name = "find-local-secret-${name}";
  text = ''
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
    if [[ -f "$secret_path" ]]; then
      echo "$secret_path"
      exit 0
    else
      echo "Error: Secret not found at $secret_path" >&2
      exit 1
    fi
  '';
}
