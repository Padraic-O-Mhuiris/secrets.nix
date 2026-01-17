{
  writeShellApplication,
  coreutils,
  sops,
  name,
  encryptedSecretPathBin,
  relPath,
  local ? false,
}:
writeShellApplication {
  name =
    if local
    then "local-edit-encrypted-secret-${name}"
    else "edit-encrypted-secret-${name}";
  runtimeInputs = [coreutils sops];
  text = let
    binName =
      if local
      then "local-encrypted-secret-path-${name}"
      else "encrypted-secret-path-${name}";
  in
    # bash
    ''
      secret_path="$(${encryptedSecretPathBin}/bin/${binName})"
      output_path="''${1:-}"

      if [[ -z "$output_path" ]]; then
        # Default to local relative path when no argument provided
        output_path="${relPath}"
      fi

      # Create temp file with same extension
      extension="''${secret_path##*.}"
      temp_file="$(mktemp --suffix=".$extension")"
      trap 'rm -f "$temp_file"' EXIT

      # Copy source to temp file
      cp "$secret_path" "$temp_file"

      # Edit the secret in temp location
      if sops "$temp_file"; then
        # Ensure output directory exists
        mkdir -p "$(dirname "$output_path")"
        # Copy to output path on success
        cp "$temp_file" "$output_path"
        echo "Secret written to $output_path"
      else
        echo "Error: sops edit failed, output not written" >&2
        exit 1
      fi
    '';
}
