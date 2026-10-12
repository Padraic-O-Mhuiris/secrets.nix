# Rekey operation
# Updates the recipients of the secret to match the flake (sops updatekeys).
# Data key and content unchanged. Only available when secret exists.
{
  name,
  config,
  ops,
  ...
}: {keyCmd ? null}: pkgs:
ops.mkOperation {
  inherit pkgs keyCmd;
  op = "rekey";
  summary = "Update recipients for a secret";
  description = ''
    Updates the recipients of the SOPS-encrypted secret '${name}' to match
    the current flake configuration using 'sops updatekeys'. The content and
    data key are unchanged. Run after adding or removing recipients.'';
  output = "secret";
  outputHelp = ''
    Override output location: a directory (expected filename appended)
    or a path ending in ${config._fileName}.
    Default: ${config._projectOutPath} in the project's git repository.'';
  needsKey = true;
  examples = ''
    # Update recipients in place
    rekey-${name}

    # Rekey with specific key command
    rekey-${name} --sopsAgeKeyCmd "pass show age-key"'';
  body = ''
    # updatekeys only works in place: rekey a private copy of the source.
    cat "$SECRET_PATH" > "$OUT_TMP"
    sops_run updatekeys -y "$OUT_TMP"
    commit_output Rekeyed
  '';
}
