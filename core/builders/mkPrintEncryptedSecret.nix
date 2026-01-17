{
  writeShellApplication,
  jq,
  sops,
  name,
  findEncryptedSecretBin,
}:
writeShellApplication {
  name = "print-encrypted-secret-${name}";
  runtimeInputs = [jq sops];
  text =
    # bash
    ''
      secret_path="$(${findEncryptedSecretBin}/bin/find-encrypted-secret-${name})"

      # Validate it's a valid sops-encrypted file
      if ! status=$(sops filestatus "$secret_path" 2>/dev/null); then
        echo "Error: File is not a valid sops file" >&2
        exit 1
      fi

      # Check that it's actually encrypted
      if [[ "$(echo "$status" | jq -r '.encrypted')" != "true" ]]; then
        echo "Error: File exists but is not encrypted" >&2
        exit 1
      fi

      # Print the encrypted secret
      cat "$secret_path"
    '';
}
