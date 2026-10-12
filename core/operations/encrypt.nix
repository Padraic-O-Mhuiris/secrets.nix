# Encrypt operation
# Encrypts content from --input to the secret file. Needs only public keys,
# so it is always available regardless of whether the secret exists.
{
  name,
  config,
  ops,
  ...
}: pkgs:
ops.mkOperation {
  inherit pkgs;
  op = "encrypt";
  summary = "Encrypt content to a secret file";
  usage = "--input <path> [OPTIONS]";
  description = ''
    Encrypts plaintext from --input to the SOPS-encrypted secret '${name}'
    for the recipients declared in the flake. Replaces an existing secret.
    Use 'edit' for interactive editing.'';
  options = [
    {
      flag = "--input";
      metavar = "<path>";
      var = "INPUT_FILE";
      help = ''
        (Required) Read plaintext from this file. Process substitution
        works, keeping content out of shell history: --input <(pass show x)'';
    }
  ];
  output = "secret";
  allowStdout = true;
  outputHelp = ''
    Override output location: a directory (expected filename appended),
    a path ending in ${config._fileName}, or /dev/stdout.
    Default: ${config._projectOutPath} in the project's git repository.'';
  examples = ''
    # From file
    encrypt-${name} --input ./plaintext-secret.txt

    # From a command, without the plaintext touching disk
    encrypt-${name} --input <(pass show my-secret)

    # Print encrypted output instead of writing it
    encrypt-${name} --input ./secret.txt --output /dev/stdout'';
  body = ''
    [[ -n "$INPUT_FILE" ]] || die "--input is required (run with --help for usage)"
    [[ -r "$INPUT_FILE" ]] || die "cannot read input: $INPUT_FILE"
    sops_run -e "$INPUT_FILE" > "$OUT_TMP"
    commit_output Encrypted
  '';
}
