# Decrypt operation
# Decrypts the evaluated secret and writes the plaintext, byte for byte, to
# stdout or a file. Only available when the secret exists.
{
  name,
  config,
  ops,
  ...
}: {keyCmd ? null}: pkgs:
assert config._exists || throw "Secret '${name}' does not exist at ${toString config._path}. Create it with encrypt or edit first.";
  ops.mkOperation {
    inherit pkgs keyCmd;
    op = "decrypt";
    summary = "Decrypt a secret";
    description = ''
      Decrypts the SOPS-encrypted secret '${name}' and outputs the plaintext
      exactly as it was encrypted. Outputs to stdout by default.'';
    output = "plain";
    outputHelp = ''
      Write plaintext to this file (mode 0600) instead of stdout.
      The file is replaced only after decryption succeeds.'';
    needsKey = true;
    examples = ''
      # Decrypt to stdout
      decrypt-${name}

      # Decrypt to file
      decrypt-${name} --output ./plaintext.txt

      # Use key from command
      decrypt-${name} --sopsAgeKeyCmd "pass show age-key"'';
    body = ''
      sops_run -d "$SECRET_PATH" > "$OUT_TMP"
      commit_output Decrypted
    '';
  }
