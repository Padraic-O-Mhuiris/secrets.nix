# Edit operations
# Two variants:
# - mkEditNew: Opens $EDITOR with empty content, encrypts result (for new secrets)
# - mkEditExisting: Decrypts secret, opens in $EDITOR, re-encrypts only if the
#   content changed (for existing secrets)
{
  name,
  config,
  ops,
  ...
}: let
  outputHelp = ''
    Override output location: a directory (expected filename appended)
    or a path ending in ${config._fileName}.
    Default: ${config._projectOutPath} in the project's git repository.'';

  # Plaintext lives in a private temp dir, named after the secret so editors
  # pick the right syntax.
  editPlaintext = ''
    PLAINTEXT="$WORK_DIR/$EXPECTED_FILENAME"
    ''${EDITOR:-vi} "$PLAINTEXT"
  '';
in {
  mkEditNew = pkgs:
    ops.mkOperation {
      inherit pkgs outputHelp;
      op = "edit";
      summary = "Create a new secret interactively";
      description = ''
        Opens $EDITOR to compose the new SOPS-encrypted secret '${name}',
        encrypted for the recipients declared in the flake.'';
      output = "secret";
      examples = ''
        # Open editor, save to the project path
        edit-${name}

        # Override output directory
        edit-${name} --output ./secrets/'';
      body = ''
        : > "$WORK_DIR/$EXPECTED_FILENAME"
        ${editPlaintext}
        [[ -s "$PLAINTEXT" ]] || die "aborted: no content saved"
        sops_run -e "$PLAINTEXT" > "$OUT_TMP"
        commit_output Created
      '';
    };

  mkEditExisting = {keyCmd ? null}: pkgs:
    ops.mkOperation {
      inherit pkgs keyCmd outputHelp;
      op = "edit";
      summary = "Edit an existing secret interactively";
      description = ''
        Decrypts the SOPS-encrypted secret '${name}', opens it in $EDITOR and
        re-encrypts the result. Nothing is written if the content is unchanged.'';
      output = "secret";
      needsKey = true;
      examples = ''
        # Edit secret, save to the project path
        edit-${name}

        # Edit with specific key command
        edit-${name} --sopsAgeKeyCmd "pass show age-key"'';
      body = ''
        sops_run -d "$SECRET_PATH" > "$WORK_DIR/$EXPECTED_FILENAME"
        cp "$WORK_DIR/$EXPECTED_FILENAME" "$WORK_DIR/original"
        ${editPlaintext}
        if cmp -s "$PLAINTEXT" "$WORK_DIR/original"; then
          echo "No changes: $OUTPUT_PATH left as is" >&2
          exit 0
        fi
        sops_run -e "$PLAINTEXT" > "$OUT_TMP"
        commit_output Updated
      '';
    };
}
