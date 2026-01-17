{
  writeShellApplication,
  coreutils,
  sops,
  name,
  relPath,
  format,
  recipients,
}:
writeShellApplication {
  name = "create-encrypted-secret-${name}";
  runtimeInputs = [coreutils sops];
  text = let
    recipientArgs = builtins.concatStringsSep " " (
      map (r: "--age ${r.key}") (builtins.attrValues recipients)
    );
    template = {
      json = ''{"data": ""}'';
      yaml = "data:";
      env = "data=";
      ini = "[secrets]\ndata=";
    }.${format};
  in
    # bash
    ''
      output_path="''${1:-${relPath}}"

      if [[ -f "$output_path" ]]; then
        echo "Error: Secret already exists at $output_path" >&2
        exit 1
      fi

      # Create temp file with template
      temp_file="$(mktemp --suffix=".${format}")"
      trap 'rm -f "$temp_file"' EXIT

      echo '${template}' > "$temp_file"

      # Edit plaintext template
      "''${EDITOR:-vim}" "$temp_file"

      # Check if user actually added content
      if [[ ! -s "$temp_file" ]]; then
        echo "Error: Empty file, aborting" >&2
        exit 1
      fi

      # Encrypt the edited file
      if sops --encrypt --in-place ${recipientArgs} "$temp_file"; then
        # Ensure output directory exists
        mkdir -p "$(dirname "$output_path")"
        cp "$temp_file" "$output_path"
        echo "Secret created at $output_path"
      else
        echo "Error: Failed to encrypt secret" >&2
        exit 1
      fi
    '';
}
