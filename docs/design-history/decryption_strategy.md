# Decryption Distribution Strategy

## The Problem

Encryption is straightforward: public keys can be distributed freely, and sops handles the encryption workflow elegantly. The flake-module already solves this side of the problem with declarative recipient configuration and automatic creation rule generation.

Decryption is fundamentally different. For a given secret, it will have a deployment context—a remote server, a local devshell, a CI runner, a script. Each context requires secure access to the private key(s) for one or more recipients. This is a distribution problem:

- Many places need to decrypt secrets
- Runtime approaches vary by context
- Security properties differ (can prompt interactively? has filesystem access? ephemeral?)
- Key storage mechanisms differ (password manager, SSH agent, hardware key, file on disk)

The asymmetry is stark:
- **Encryption**: can happen anywhere with public keys (trivial distribution)
- **Decryption**: requires private keys in potentially hostile or constrained environments

## Design Goals

1. **Portable**: same configuration works across contexts (NixOS, devshell, CI, scripts)
2. **Secure**: private keys never appear in argv, shell history, or on disk unnecessarily
3. **Flexible**: users can bring their own key management (pass, 1Password, Bitwarden, etc.)
4. **Ergonomic**: sensible defaults, clear error messages, minimal configuration

## The Solution

### Recipient-Level Decryption Configuration

Each recipient declares how their private key can be accessed:

```nix
{ pkgs, ... }:
let
  # Reusable recipient definitions
  server1 = {
    publicKey = "age1server...";
    decryption = {
      packages = with pkgs; [ ssh-to-age ];
      cmd = "ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key";
    };
  };

  admin = {
    publicKey = "age1admin...";
    decryption = {
      packages = with pkgs; [ pass age ];
      cmd = null;  # requires ADMIN__DECRYPT_CMD at runtime
    };
  };
in
{
  flake.secrets.production = {
    secrets.api-token = {
      path = ./secrets/production/api-token.yaml;
      recipients = { inherit server1 admin; };
    };

    secrets.database-password = {
      path = ./secrets/production/db-pass.yaml;
      recipients = { inherit server1; };  # only server1 needs this
    };
  };
}
```

### Two Access Modes

**Baked command (`cmd` is a string)**

The decryption command is committed to the repository. Appropriate for:
- Host keys (path is known, deterministic)
- CI runners (key path is fixed)
- Team defaults where most users share a common key path

```nix
decryption = {
  packages = with pkgs; [ ssh-to-age ];
  cmd = "ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key";
};
```

**Runtime command (`cmd` is null)**

The decryption command must be provided via environment variable at runtime. Appropriate for:
- Human operators where everyone has their own key management
- Contexts where key access varies per-user
- Sensitive access methods that shouldn't be in git

```nix
decryption = {
  packages = with pkgs; [ pass ];
  cmd = null;  # enforces RECIPIENT__DECRYPT_CMD
};
```

When `cmd = null`, the user must set `<RECIPIENT_NAME>__DECRYPT_CMD`:

```bash
# Alice uses pass with YubiKey
export ALICE__DECRYPT_CMD="pass show keys/age/admin"

# Bob uses Bitwarden CLI
export BOB__DECRYPT_CMD="bw get notes age-admin-key"

# Charlie uses 1Password
export CHARLIE__DECRYPT_CMD="op read op://Private/age-key/password"
```

### Environment Variable Override

The `<RECIPIENT_NAME>__DECRYPT_CMD` environment variable always takes precedence over a baked `cmd`. This allows:

- A sensible default for most users, with escape hatch for exceptions
- Local overrides without modifying the flake

```nix
# Team default: most admins use pass with a standard path
recipients.admin = {
  publicKey = "age1...";
  decryption = {
    packages = with pkgs; [ pass ];
    cmd = "pass show company/age-admin-key";  # works for most
  };
};
```

Alice stores her key differently:

```bash
# Override the baked default
ADMIN__DECRYPT_CMD='pass show personal/age-key' nix run .#secrets.production.api-token.admin.decrypt
```

**Precedence**: env var wins if set, otherwise falls back to baked `cmd`, otherwise fails if `cmd = null`.

### The Contract

Both baked commands and environment variable commands must:

- Print the private key to stdout
- Print errors/prompts to stderr
- Exit non-zero on failure

That's it. No other requirements.

### The `packages` Field

The `packages` list ensures tools are available in PATH when the decrypt command runs:

```nix
decryption = {
  packages = with pkgs; [ pass gnupg ];  # pass needs gpg
  cmd = null;
};
```

This is critical for Nix derivations where PATH is controlled.

## Derivation Structure

### Per-Recipient Decrypt Commands

```
secrets.<group>.<secret>.<recipient>.decrypt
```

Each recipient gets their own derivation for each secret:

```bash
# Uses baked ssh-to-age command
nix run .#secrets.production.api-token.server1.decrypt

# Uses ADMIN__DECRYPT_CMD environment variable
ADMIN__DECRYPT_CMD='pass show keys/age' nix run .#secrets.production.api-token.admin.decrypt
```

### Secret-Level Decrypt (Try All Recipients)

```
secrets.<group>.<secret>.decrypt
```

Tries all recipients until one succeeds:

```bash
nix run .#secrets.production.api-token.decrypt
```

The order:
1. Check which `<RECIPIENT>__DECRYPT_CMD` environment variables are set (cheap)
2. Try those recipients first (user explicitly configured)
3. Fall back to recipients with baked commands

### Composable Recipient Selection

```nix
{ config, ... }:
let
  secrets = config.flake.secrets;
in
{
  # Produces a script that only tries the specified recipients
  packages.decrypt-api-token = (secrets.production.api-token.withRecipients ["admin" "ops"]).decrypt;
}
```

## Security Model

### Key Never Lands Anywhere Dangerous

The generated bash uses process substitution:

```bash
sops -d --age-key-file <(eval "$ADMIN__DECRYPT_CMD") "$secret_store_path"
```

The key exists only:
- In the subshell's stdout
- In the pipe buffer
- Briefly in sops' memory

Never in:
- A shell variable
- A file on disk
- An argument list (visible in `ps`)
- Shell history

### Encrypted Secret as Store Path

The encrypted file is copied to the Nix store at build time:

```nix
decrypt = pkgs.writeShellScript "decrypt" ''
  sops -d --age-key-file <(...) ${./secrets/api-token.yaml}
'';
```

Benefits:
- Content-addressed, cacheable
- Self-contained derivation
- Works remotely: `nix run github:user/repo#secrets.x.y.decrypt` fetches encrypted blob from store, runs key command locally

The ciphertext being in the store is fine—that's the point of encryption.

## Runtime UX

### Clear Error Messages

When a required environment variable is missing:

```
$ nix run .#secrets.production.api-token.admin.decrypt
Error: ADMIN__DECRYPT_CMD not set

Set ADMIN__DECRYPT_CMD to a command that prints your age private key.
Example: export ADMIN__DECRYPT_CMD='pass show keys/age/admin'
```

### Validation

At Nix eval time:
- Check `decryption.cmd` is a string or null
- Check `decryption.packages` is a list of derivations
- Ensure at least one recipient has a viable decryption path

At runtime:
- Check environment variable is set (for null cmd)
- Let sops validate the key—if wrong, "decryption failed"

## Context-Dependent Behavior

### Local Interactive (devshell)

User sets environment variables in `.envrc.local` or shell profile:

```bash
export ADMIN__DECRYPT_CMD='pass show keys/age/admin'
```

Then any decrypt command works:

```bash
nix run .#secrets.production.api-token.decrypt
```

### Deployed System (NixOS)

Recipient uses baked command with host key:

```nix
{ pkgs, ... }:
let
  web-server = {
    publicKey = "age1...";
    decryption = {
      packages = with pkgs; [ ssh-to-age ];
      cmd = "ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key";
    };
  };
in
{
  flake.secrets.production = {
    secrets.database-password = {
      path = ./secrets/production/db-pass.yaml;
      recipients = { inherit web-server; };
    };
  };
}
```

No environment variable needed—the derivation is self-contained.

### Remote Execution via SSH

```bash
ssh server1 'nix run .#secrets.production.api-token.server1.decrypt'
```

Works because `server1` has a baked command using the host's SSH key.

For human keys over SSH, the environment variable approach doesn't work well (the command runs remotely, needs remote access to your password manager). Use the host's own key instead.

### Composing in Scripts

```nix
{ config, pkgs, lib, ... }:
let
  # Access the generated decrypt derivation
  decryptApiToken = config.flake.secrets.production.api-token.admin.decrypt;
in
{
  packages.my-script = pkgs.writeShellScriptBin "my-script" ''
    api_token=$(${lib.getExe decryptApiToken})
    curl -H "Authorization: Bearer $api_token" https://api.example.com
  '';
}
```

The user runs:

```bash
ADMIN__DECRYPT_CMD='pass show keys/age' nix run .#my-script
```

Environment propagates through.

## Relationship to SOPS Key Groups

SOPS supports key groups with thresholds (e.g., "need 2 of 3 keys"). This design doesn't attempt to model that at the decryption configuration level.

If a secret uses key groups:
- SOPS handles the threshold logic
- The decrypt script needs to provide enough keys to satisfy the threshold
- Multiple recipients may need to be combined

This is left to future work. For most use cases, single-key decryption is sufficient.

## Summary

| Aspect | Baked (`cmd = "..."`) | Runtime (`cmd = null`) |
|--------|----------------------|------------------------|
| Key access logic | In git, auditable | User-controlled |
| Configuration | Deterministic | Per-user |
| Use case | Hosts, CI | Human operators |
| Env var needed | No | Yes (`RECIPIENT__DECRYPT_CMD`) |
| Remote execution | Works naturally | Needs remote key access |

The core insight: **decryption configuration is per-recipient metadata that describes key acquisition, not key storage**. The flake author decides *who* can decrypt. The user/deployer decides *how* their key is accessed.

## Recipient Resolution via Public Key Derivation

When multiple recipients exist for a secret, the decrypt script needs to determine which recipient the user's key corresponds to. Rather than guessing or trying each recipient sequentially, we can validate membership upfront.

### The Approach

1. Embed a lookup table of public keys → recipient names at build time
2. At runtime, derive the public key from the provided private key
3. Look up the public key in the table to identify the recipient
4. Only then attempt decryption

### Implementation

```bash
# Embedded at build time from recipient definitions
declare -A recipients=(
  ["age1adminpublickey..."]="admin"
  ["age1server1publickey..."]="server1"
)
declare -a env_vars=("ADMIN__DECRYPT_CMD" "SERVER1__DECRYPT_CMD")

# Find first set env var
decrypt_cmd=""
for var in "${env_vars[@]}"; do
  if [[ -n "${!var:-}" ]]; then
    decrypt_cmd="${!var}"
    break
  fi
done

if [[ -z "$decrypt_cmd" ]]; then
  echo "Error: no decrypt command set" >&2
  echo "Set one of: ${env_vars[*]}" >&2
  exit 1
fi

# Validate and decrypt in contained scope
eval "$decrypt_cmd" | {
  read -r private_key
  public_key=$(echo "$private_key" | age-keygen -y)

  # Validate membership
  if [[ -z "${recipients[$public_key]:-}" ]]; then
    echo "Error: provided key is not a recipient of this secret" >&2
    echo "Expected one of:" >&2
    for pk in "${!recipients[@]}"; do
      echo "  ${recipients[$pk]}: ${pk:0:20}..." >&2
    done
    exit 1
  fi

  recipient_name="${recipients[$public_key]}"
  echo "Decrypting as: $recipient_name" >&2

  # Decrypt
  echo "$private_key" | sops -d --age-key-file /dev/stdin "$secret_path"
}
status=$?

# Cleanup - unset all decrypt env vars to prevent leakage
for var in "${env_vars[@]}"; do
  unset "$var"
done

exit $status
```

The script:
1. Checks all recipient env vars, uses first one found
2. Derives public key and validates membership
3. Decrypts only if validation passes
4. Unsets all decrypt env vars post-decryption to prevent leakage in the shell session

### Benefits

- **Fail fast**: wrong key detected before hitting sops
- **Clear errors**: "Your key matches recipient 'admin'" or "Your key doesn't match any recipient"
- **No guessing**: when trying multiple recipients, you know exactly which one applies
- **Validation**: confirms the user has a legitimate key for this secret, not just any age key

### Limitations

This approach requires that a public identity is derivable from the private key output. This works for:

- **age**: `age-keygen -y` derives public key from private
- **age with SSH keys**: `ssh-to-age` can derive the age public key

This may not be available for other sops backends:

- **AWS KMS**: no local private key exists; decryption is an API call
- **GCP KMS**: same - key lives in cloud HSM
- **Azure Key Vault**: same
- **PGP**: possible via `gpg --list-keys` but more complex

For non-age backends, the validation step would need to be skipped or use a different mechanism (e.g., check if the user has the required IAM permissions before attempting decryption).
