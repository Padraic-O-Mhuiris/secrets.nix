{
  writeShellApplication,
  jq,
  sops,
  name,
  storePath,
  existsInStore,
  findLocalSecretBin ? null,
}:
assert !existsInStore -> findLocalSecretBin != null; let
  validateAndPrint =
    # bash
    ''
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
in
  writeShellApplication {
    name = "print-secret-${name}";
    runtimeInputs = [jq sops];
    text =
      if existsInStore
      then
        # bash
        ''
          secret_path="${storePath}"
        ''
        + validateAndPrint
      else
        # bash
        ''
          secret_path="$(${findLocalSecretBin}/bin/find-local-secret-${name})"
        ''
        + validateAndPrint;
  }
