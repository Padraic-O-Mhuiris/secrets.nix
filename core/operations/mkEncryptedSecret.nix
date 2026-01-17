{
  writeShellApplication,
  jq,
  sops,
  name,
  encryptedSecretPathBin,
  local ? false,
}:
writeShellApplication {
  name =
    if local
    then "local-encrypted-secret-${name}"
    else "encrypted-secret-${name}";
  runtimeInputs = [jq sops];
  text = let
    binName =
      if local
      then "local-encrypted-secret-path-${name}"
      else "encrypted-secret-path-${name}";
  in
    # bash
    ''
      secret_path="$(${encryptedSecretPathBin}/bin/${binName})"

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
