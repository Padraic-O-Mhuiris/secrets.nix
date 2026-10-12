# Rotate operation
# Re-encrypts the secret with a new data key (sops rotate). Content unchanged.
# Only available when secret exists.
{
  name,
  config,
  ops,
  ...
}: {keyCmd ? null}: pkgs:
ops.mkOperation {
  inherit pkgs keyCmd;
  op = "rotate";
  summary = "Rotate the data encryption key";
  description = ''
    Rotates the data encryption key for the SOPS-encrypted secret '${name}'
    using 'sops rotate'. The content is unchanged. The secret file is
    replaced only after rotation succeeds.'';
  output = "secret";
  outputHelp = ''
    Override output location: a directory (expected filename appended)
    or a path ending in ${config._fileName}.
    Default: ${config._projectOutPath} in the project's git repository.'';
  needsKey = true;
  examples = ''
    # Rotate data key in place
    rotate-${name}

    # Rotate with specific key command
    rotate-${name} --sopsAgeKeyCmd "pass show age-key"'';
  body = ''
    sops_run rotate "$SECRET_PATH" > "$OUT_TMP"
    commit_output Rotated
  '';
}
