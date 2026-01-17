{
  writeShellApplication,
  sops,
  name,
  storePath,
  existsInStore,
  findLocalSecretBin ? null,
}:
assert !existsInStore -> findLocalSecretBin != null;
  writeShellApplication {
    name = "print-secret-${name}";
    runtimeInputs = [sops];
    text =
      if existsInStore
      then
        # bash
        ''
          secret_path="${storePath}"

          # Validate it's a sops file by checking for sops metadata
          if ! grep -q '"sops":\|^sops:' "$secret_path" 2>/dev/null; then
            echo "Error: File does not appear to be a valid sops-encrypted file" >&2
            exit 1
          fi

          # Print the decrypted secret
          sops -d "$secret_path"
        ''
      else
        # bash
        ''
          secret_path="$(${findLocalSecretBin}/bin/find-local-secret-${name})"

          # Validate it's a sops file by checking for sops metadata
          if ! grep -q '"sops":\|^sops:' "$secret_path" 2>/dev/null; then
            echo "Error: File does not appear to be a valid sops-encrypted file" >&2
            exit 1
          fi

          # Print the decrypted secret
          sops -d "$secret_path"
        '';
  }
