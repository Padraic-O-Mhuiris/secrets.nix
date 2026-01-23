# Secret API

This document describes the mental model and API for secret operations.

## Core Concepts

### Secret Definition

A secret is defined declaratively with:

```nix
{
  my-secret = {
    dir = ./secrets;       # Directory where the secret file lives
    recipients = { ... };  # Who can decrypt
    format = "json";       # bin | json | yaml | env
  };
}
```

### Derived Properties

From the definition, several properties are computed:

| Property | Description | Example |
|----------|-------------|---------|
| `_fileName` | Name with format extension | `my-secret.json` |
| `_path` | Full path to encrypted file | `./secrets/my-secret.json` |
| `_exists` | Whether the file exists | `true` / `false` |

### Format Mapping

| Format | Extension | sops type | Output pipe |
|--------|-----------|-----------|-------------|
| `bin` | (none) | `binary` | - |
| `json` | `.json` | `json` | `jq` |
| `yaml` | `.yaml` | `yaml` | `yq` |
| `env` | `.env` | `dotenv` | - |

## Operations

### Conditional Availability

Operations are conditionally available based on whether the secret file exists:

| When `_exists` is... | Available Operations |
|----------------------|----------------------|
| `false` | `encrypt`, `edit` (no decrypt), `env` |
| `true` | `encrypt`, `edit` (with decrypt), `decrypt`, `rotate`, `rekey`, `env` |

### Overview

| Operation | Description | Needs Private Key? |
|-----------|-------------|-------------------|
| `encrypt` | Encrypts content from `--input` | No |
| `edit` | Interactive editor (empty if new, decrypts if exists) | Only if exists |
| `decrypt` | Outputs secret to stdout | Yes |
| `rotate` | Rotates data encryption key (`sops rotate`) | Yes |
| `rekey` | Updates recipients (`sops updatekeys`) | Yes |
| `env` | Outputs env var template | No |

All write operations output to the configured project path by default, overridable with `--output`.

### encrypt

Encrypts content from `--input` to a secret file. Always available regardless of whether secret exists.

```bash
# From file
nix run .#secrets.my-secret.encrypt -- --input ./plaintext.txt

# From process substitution (secure - content not in shell history)
nix run .#secrets.my-secret.encrypt -- --input <(pass show my-secret)

# Override output location
nix run .#secrets.my-secret.encrypt -- --input ./secret.txt --output ./other-dir/

# Print to stdout
nix run .#secrets.my-secret.encrypt -- --input ./secret.txt --output /dev/stdout
```

- **Input**: Content from `--input` flag (required)
- **Output**: Encrypted file at project path (default) or `--output` location
- **Requires**: Only public keys (recipients)

### edit

Interactive editor for secrets. Behavior depends on whether secret exists:

**When secret doesn't exist:**
```bash
# Opens $EDITOR with empty content
nix run .#secrets.new-secret.edit
```
- No decryption needed
- No builder pattern available

**When secret exists:**
```bash
# Decrypts, opens $EDITOR, re-encrypts
nix run .#secrets.my-secret.edit.recipient.alice

# With runtime key override
nix run .#secrets.my-secret.edit -- --sopsAgeKeyCmd "pass show age-key"
```
- Full decrypt flow with builder pattern
- Supports `.recipient.<name>` packages

### decrypt

Decrypts the secret and outputs to stdout. Only available when secret exists.

```bash
# Basic usage
nix run .#secrets.my-secret.decrypt.recipient.alice

# With key command
nix run .#secrets.my-secret.decrypt -- --sopsAgeKeyCmd "op read op://vault/age-key"

# To file
nix run .#secrets.my-secret.decrypt.recipient.alice -- --output ./plaintext.txt
```

- **Input**: Encrypted file from `_path`
- **Output**: Decrypted content to stdout, piped through format-specific tool (jq/yq)
- **Requires**: Private key access

### rotate

Rotates the data encryption key using `sops rotate`. Content remains unchanged. Only available when secret exists.

```bash
# Rotate data key
nix run .#secrets.my-secret.rotate.recipient.alice

# Override output
nix run .#secrets.my-secret.rotate.recipient.alice -- --output ./secrets/
```

Use case: Periodic key rotation for security compliance, or after a suspected key compromise.

- **Input**: Encrypted file from `_path`
- **Output**: Re-encrypted file with new data key
- **Requires**: Private key access

### rekey

Updates recipients to match the current flake configuration using `sops updatekeys`. Data key and content unchanged. Only available when secret exists.

```bash
# Update recipients
nix run .#secrets.my-secret.rekey.recipient.alice
```

Use case: After adding or removing recipients in your flake configuration.

- **Input**: Encrypted file from `_path`
- **Output**: Re-encrypted file with updated recipient list
- **Requires**: Private key access

## Key Configuration Builders

Operations that require decryption (`decrypt`, `edit`, `rotate`, `rekey`) expose builder methods for configuring how the private key is accessed.

### Builder Methods

| Method | Argument | Description |
|--------|----------|-------------|
| `.withSopsAgeKeyCmd` | `"command"` | Shell command string for `SOPS_AGE_KEY_CMD` |
| `.withSopsAgeKeyCmdPkg` | `derivation` | Derivation whose binary provides the key |
| `.buildSopsAgeKeyCmdPkg` | `pkgs: drv` | Function to build the key derivation |

### Examples

```nix
let
  pkgs = import <nixpkgs> {};
  secret = flake.secrets.my-secret;
in {
  # String command (resolved at runtime)
  decrypt-op = (secret.decrypt pkgs).withSopsAgeKeyCmd "op read op://vault/age-key";

  # Pre-built derivation
  decrypt-pass = (secret.decrypt pkgs).withSopsAgeKeyCmdPkg (pkgs.writeShellApplication {
    name = "get-key";
    runtimeInputs = [ pkgs.pass ];
    text = "pass show age/my-key";
  });

  # Lazily built derivation (uses same pkgs)
  decrypt-lazy = (secret.decrypt pkgs).buildSopsAgeKeyCmdPkg (pkgs:
    pkgs.writeShellApplication {
      name = "get-key";
      text = "cat ~/.age/key.txt";
    }
  );
}
```

### Key Command Contract

The key command (whether string, derivation, or built) must:

1. Print the age private key to stdout
2. Print errors/prompts to stderr
3. Exit non-zero on failure

## File Locations

### Input (Decryption Source)

All decrypt-dependent operations read from `_path` (which becomes a nix store path when evaluated). This enables:

- Distribution: `nix run github:user/repo#secrets.x.decrypt` works
- Caching: Content-addressed, deterministic
- Remote secrets: Store path can reference any flake

### Output (Encryption Target)

All write operations output to the project path by default (derived from `dir` + `_fileName`), overridable with `--output`.

```bash
# Default: outputs to project path
nix run .#secrets.my-secret.encrypt -- --input ./secret.txt
# -> writes to ./secrets/my-secret.json

# Override output directory
nix run .#secrets.my-secret.encrypt -- --input ./secret.txt --output ./other/

# Override full path (filename must match)
nix run .#secrets.my-secret.encrypt -- --input ./secret.txt --output ./other/my-secret.json

# Output to stdout
nix run .#secrets.my-secret.encrypt -- --input ./secret.txt --output /dev/stdout
```

## Decryption Strategy for Mutating Operations

The `edit`, `rotate`, and `rekey` operations all require decryption before they can re-encrypt. They share the same builder pattern as `decrypt`.

### Builder Chain

Each mutating operation exposes the same key configuration builders:

```nix
# All of these work identically:
(secret.decrypt pkgs).withSopsAgeKeyCmd "..."
(secret.edit pkgs).withSopsAgeKeyCmd "..."
(secret.rotate pkgs).withSopsAgeKeyCmd "..."
(secret.rekey pkgs).withSopsAgeKeyCmd "..."
```

### Operation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Key Configuration                         │
│  .withSopsAgeKeyCmd "cmd"                                       │
│  .withSopsAgeKeyCmdPkg drv                                      │
│  .buildSopsAgeKeyCmdPkg (pkgs: drv)                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Decrypt from Store                          │
│  sops -d --input-type <fmt> --output-type <fmt> <_path>         │
│                                                                  │
│  SOPS_AGE_KEY_CMD set from builder config                       │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┬───────────────┐
              ▼               ▼               ▼               ▼
         ┌────────┐     ┌──────────┐    ┌──────────┐    ┌──────────┐
         │decrypt │     │   edit   │    │  rotate  │    │  rekey   │
         │        │     │          │    │          │    │          │
         │ stdout │     │ $EDITOR  │    │ new      │    │ same     │
         │        │     │    ↓     │    │ content  │    │ content  │
         │        │     │ re-enc   │    │    ↓     │    │    ↓     │
         │        │     │    ↓     │    │ re-enc   │    │ re-enc   │
         │        │     │  file    │    │    ↓     │    │    ↓     │
         │        │     │          │    │  file    │    │  file    │
         └────────┘     └──────────┘    └──────────┘    └──────────┘
```

### No Key Needed for Encryption

Note that only the *decryption* phase needs the private key. The re-encryption phase uses only the public keys (recipients) which are baked into the sops config at build time.

```
decrypt: private key required
    ↓
[plaintext in memory]
    ↓
encrypt: public keys only (from recipients config)
```

### Fallback Behavior

If no builder is used, the operation relies on sops' default key resolution:

1. `SOPS_AGE_KEY_CMD` environment variable
2. `SOPS_AGE_KEY` environment variable
3. `~/.config/sops/age/keys.txt`

## Security Model

### Key Handling

Keys are passed via `SOPS_AGE_KEY_CMD`, which means:

- Key is fetched on-demand by sops
- Key never appears in argv (visible in `ps`)
- Key never stored in shell history
- Key exists only briefly in memory

### Store Path Security

The encrypted file in the nix store is safe:

- It's encrypted; that's the point
- Content-addressed and immutable
- Can be distributed/cached freely

## Usage Patterns

### Development Workflow

```bash
# Create a new secret interactively
nix run .#secrets.api-key.edit
git add secrets/api-key.json

# Or from a file/command
nix run .#secrets.api-key.encrypt -- --input <(pass show my-api-key)
git add secrets/api-key.json

# Edit an existing secret
nix run .#secrets.api-key.edit.recipient.alice
git add secrets/api-key.json

# Decrypt for use in scripts
API_KEY=$(nix run .#secrets.api-key.decrypt.recipient.alice | jq -r .api_key)
```

### CI/CD

```nix
# In flake.nix - bake the key command into a derivation
packages.deploy = pkgs.writeShellApplication {
  name = "deploy";
  text = ''
    DB_PASS=$(${lib.getExe (secrets.db-password.decrypt pkgs).withSopsAgeKeyCmd "cat /run/secrets/age-key"})
    deploy-app --db-password "$DB_PASS"
  '';
};
```

### Recipient Changes

```bash
# After updating recipients in nix config:
nix run .#secrets.api-key.rekey.recipient.alice
git add secrets/api-key.json
git commit -m "rekey api-key with updated recipients"
```

### Rotating Data Keys

```bash
# Rotate the data encryption key (content unchanged)
nix run .#secrets.api-key.rotate.recipient.alice
git add secrets/api-key.json
git commit -m "rotate api-key data key"
```

### Replacing Secret Values

```bash
# Replace with new content using encrypt
nix run .#secrets.api-key.encrypt -- --input <(echo '{"api_key": "new-value"}')
git add secrets/api-key.json
git commit -m "update api-key value"
```
