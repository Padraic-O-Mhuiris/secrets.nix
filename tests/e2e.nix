# End-to-end tests: run the generated operations against real sops.
#
# Uses the example secrets (test-only keys) from examples/default.nix:
#   api-key          json, exists (secrets/api-key.json)
#   db-password      bin, not created
#   service-account  json, not created
# plus rekey-me (tests/fixtures/e2e), encrypted to alice only but declared
# for alice and bob, so rekey has real work to do.
{
  lib,
  pkgs,
  core,
  secretsPkg,
  secrets,
}: let
  s = secretsPkg;
  exe = lib.getExe;
  inherit (secrets.api-key.recipients) alice bob;
  aliceKeyCmd = exe (alice.decryptPkg pkgs);
  bobKeyCmd = exe (bob.decryptPkg pkgs);
  apiKeySource = "${secrets.api-key._path}";

  rekeySecrets = core.mkSecrets {
    rekey-me = {
      dir = ./fixtures/e2e;
      format = "json";
      recipients = {
        alice = {inherit (alice) key decryptPkg;};
        bob = {inherit (bob) key;};
      };
    };
  };
  r = core.mkSecretsPackages rekeySecrets pkgs;
  rekeySource = "${rekeySecrets.rekey-me._path}";
  rekeyTarget = "$PROJECT/${lib.removePrefix "./" rekeySecrets.rekey-me._projectOutPath}";

  script = pkgs.writeShellApplication {
    name = "secrets-nix-e2e";
    runtimeInputs = [pkgs.git pkgs.sops pkgs.age pkgs.diffutils pkgs.coreutils];
    text = ''
      fail() {
        echo "FAIL: $*" >&2
        exit 1
      }
      pass() {
        echo "ok: $*"
      }
      expect_fail() {
        if "$@" >"$WORK/stdout" 2>"$WORK/stderr"; then
          fail "expected failure: $*"
        fi
      }
      mode() {
        stat -c %a "$1"
      }
      sops_dec() {
        SOPS_AGE_KEY="$ALICE_KEY" sops -d --input-type "$1" --output-type "$1" "$2"
      }
      no_leftovers() {
        local leftovers=("$PROJECT"/secrets/.secrets-nix.*)
        if [[ ''${#leftovers[@]} -gt 0 ]]; then
          fail "temporary output left behind: ''${leftovers[*]}"
        fi
      }
      reset_api_key() {
        cat ${apiKeySource} > "$PROJECT/secrets/api-key.json"
        chmod 0644 "$PROJECT/secrets/api-key.json"
      }

      shopt -s nullglob
      WORK="$(mktemp -d)"
      export HOME="$WORK/home"
      mkdir -p "$HOME"
      unset SOPS_AGE_KEY SOPS_AGE_KEY_FILE SOPS_AGE_KEY_CMD
      ALICE_KEY="$(${aliceKeyCmd})"
      WRONG_KEY="$(age-keygen 2>/dev/null | grep '^AGE-SECRET-KEY')"

      PROJECT="$WORK/project"
      mkdir -p "$PROJECT/secrets" "$PROJECT/sub/dir"
      git -C "$PROJECT" init -q
      reset_api_key
      # Run from a subdirectory: targets must resolve from the repo root
      cd "$PROJECT/sub/dir"

      # --- decrypt -------------------------------------------------------
      ${exe s.api-key.decrypt.recipient.alice} > "$WORK/plain.json"
      sops_dec json ${apiKeySource} > "$WORK/expected.json"
      cmp -s "$WORK/plain.json" "$WORK/expected.json" || fail "decrypt output is not byte-identical"
      pass "decrypt returns plaintext byte-identical"

      ${exe s.api-key.decrypt} --sopsAgeKeyCmd ${bobKeyCmd} --output "$WORK/out.json"
      [[ "$(mode "$WORK/out.json")" == 600 ]] || fail "decrypt --output mode is $(mode "$WORK/out.json")"
      cmp -s "$WORK/out.json" "$WORK/expected.json" || fail "decrypt --output content"
      pass "decrypt --output writes 0600 plaintext"

      # --- key resolution ------------------------------------------------
      ALICE__AGE_KEY="$ALICE_KEY" ${exe s.api-key.decrypt} > /dev/null
      pass "recipient-level env var key"

      API_KEY__ALICE__AGE_KEY="$ALICE_KEY" ALICE__AGE_KEY="$WRONG_KEY" ${exe s.api-key.decrypt} > /dev/null
      pass "secret-specific env var wins over recipient-level"

      expect_fail env API_KEY__ALICE__AGE_KEY="$ALICE_KEY" API_KEY__BOB__AGE_KEY="$ALICE_KEY" ${exe s.api-key.decrypt}
      grep -q "several recipients" "$WORK/stderr" || fail "conflict message: $(cat "$WORK/stderr")"
      pass "conflicting secret-specific env vars rejected"

      # --- encrypt -------------------------------------------------------
      printf 'hunter2\n' > "$WORK/pw"
      ${exe s.db-password.encrypt} --input "$WORK/pw"
      [[ -f "$PROJECT/secrets/db-password" ]] || fail "encrypt did not write to the project path"
      [[ "$(mode "$PROJECT/secrets/db-password")" == 644 ]] || fail "encrypt mode"
      sops_dec binary "$PROJECT/secrets/db-password" | cmp -s - "$WORK/pw" || fail "encrypt round trip"
      no_leftovers
      pass "encrypt writes to repo root from a subdirectory"

      ${exe s.service-account.encrypt} --input <(printf '{"a":1}') --output /dev/stdout > "$WORK/sa.json"
      sops_dec json "$WORK/sa.json" | grep -q '"a": 1' || fail "encrypt to stdout"
      pass "encrypt --output /dev/stdout"

      expect_fail ${exe s.db-password.encrypt}
      pass "encrypt requires --input"

      # --- edit ----------------------------------------------------------
      EDITOR=true ${exe s.api-key.edit.recipient.alice} 2> "$WORK/stderr"
      grep -q "No changes" "$WORK/stderr" || fail "unchanged edit: $(cat "$WORK/stderr")"
      cmp -s "$PROJECT/secrets/api-key.json" ${apiKeySource} || fail "unchanged edit rewrote the file"
      pass "edit without changes leaves the file untouched"

      cat > "$WORK/editor" <<'EOF'
      #!${pkgs.bash}/bin/bash
      printf '{"edited":true}\n' > "$1"
      EOF
      chmod +x "$WORK/editor"
      EDITOR="$WORK/editor" ${exe s.api-key.edit.recipient.alice}
      sops_dec json "$PROJECT/secrets/api-key.json" | grep -q edited || fail "edit did not apply"
      pass "edit re-encrypts changes"

      EDITOR="$WORK/editor" ${exe s.service-account.edit}
      sops_dec json "$PROJECT/secrets/service-account.json" | grep -q edited || fail "edit new"
      pass "edit creates a new secret"

      # --- overwrite guard -----------------------------------------------
      # api-key.json now differs from the evaluated source
      cp "$PROJECT/secrets/api-key.json" "$WORK/edited.json"
      expect_fail ${exe s.api-key.rotate.recipient.alice}
      grep -q "Refusing to overwrite" "$WORK/stderr" || fail "guard message: $(cat "$WORK/stderr")"
      cmp -s "$PROJECT/secrets/api-key.json" "$WORK/edited.json" || fail "guard modified the file"
      pass "refuses to overwrite a target that differs from the source"

      # --- rotate --------------------------------------------------------
      reset_api_key
      ${exe s.api-key.rotate.recipient.alice}
      cmp -s "$PROJECT/secrets/api-key.json" ${apiKeySource} && fail "rotate did not change the file"
      sops_dec json "$PROJECT/secrets/api-key.json" | cmp -s - "$WORK/expected.json" || fail "rotate changed content"
      [[ "$(mode "$PROJECT/secrets/api-key.json")" == 644 ]] || fail "rotate mode"
      pass "rotate in place"

      reset_api_key
      expect_fail ${exe s.api-key.rotate} --sopsAgeKey "$WRONG_KEY"
      cmp -s "$PROJECT/secrets/api-key.json" ${apiKeySource} || fail "failed rotate modified the secret"
      no_leftovers
      pass "failed rotate leaves the secret intact"

      mkdir "$WORK/rotated"
      ${exe s.api-key.rotate.recipient.alice} --output "$WORK/rotated/"
      [[ "$(mode "$WORK/rotated/api-key.json")" == 644 ]] || fail "rotate --output mode"
      sops_dec json "$WORK/rotated/api-key.json" | cmp -s - "$WORK/expected.json" || fail "rotate --output content"
      pass "rotate --output to a new directory"

      expect_fail ${exe s.api-key.rotate.recipient.alice} --output "$WORK/rotated/wrong-name.json"
      grep -q "filename mismatch" "$WORK/stderr" || fail "filename check"
      pass "rotate --output rejects a mismatched filename"

      # --- rekey ---------------------------------------------------------
      reset_api_key
      mkdir "$WORK/rekeyed"
      ${exe s.api-key.rekey.recipient.alice} --output "$WORK/rekeyed/"
      [[ "$(mode "$WORK/rekeyed/api-key.json")" == 644 ]] || fail "rekey --output mode"
      sops_dec json "$WORK/rekeyed/api-key.json" | cmp -s - "$WORK/expected.json" || fail "rekey content"
      pass "rekey --output to a new directory"

      mkdir -p "$(dirname "${rekeyTarget}")"
      cat ${rekeySource} > "${rekeyTarget}"
      expect_fail ${exe r.rekey-me.rekey} --sopsAgeKey "$WRONG_KEY"
      cmp -s "${rekeyTarget}" ${rekeySource} || fail "failed rekey modified the secret"
      pass "failed rekey leaves the secret intact"

      ${exe r.rekey-me.rekey.recipient.alice}
      SOPS_AGE_KEY="$(${bobKeyCmd})" sops -d --input-type json --output-type json "${rekeyTarget}" | grep -q rekey \
        || fail "bob cannot decrypt after rekey"
      pass "rekey adds a newly declared recipient"

      # --- outside the project -------------------------------------------
      mkdir "$WORK/elsewhere"
      cd "$WORK/elsewhere"
      expect_fail ${exe s.db-password.encrypt} --input "$WORK/pw"
      grep -q "not inside a git repository" "$WORK/stderr" || fail "outside-repo message: $(cat "$WORK/stderr")"
      pass "default target requires the project repository"

      # --- env -----------------------------------------------------------
      ${exe s.api-key.env} --recipient alice | grep -q '^# API_KEY__ALICE__AGE_KEY_CMD=""' || fail "env template"
      expect_fail ${exe s.api-key.env} --recipient nobody
      pass "env template"
    '';
  };
in
  pkgs.runCommand "e2e-tests" {} ''
    ${exe script}
    touch $out
  ''
