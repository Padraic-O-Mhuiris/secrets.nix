# Secret API

This document describes the mental model and API for secret operations.

## Core Concepts

### Secret Definition

A secret is defined declaratively with:

```nix
{
  my-secret = {
    recipients = { ... };  # Who can decrypt
    format = "json";       # bin | json | yaml | env
    dir = "secrets";       # Relative directory (for project operations)
  };
}
```

### Derived Properties

From the definition, several properties are computed:

| Property | Description | Example |
|----------|-------------|---------|
| `_fileName` | Name with format extension | `my-secret.json` |
| `_storePath` | Nix store path to encrypted file | `/nix/store/...-source/secrets/my-secret.json` |
| `_existsInStore` | Whether the file exists in store | `true` / `false` |

### Format Mapping

| Format | Extension | sops type | Output pipe |
|--------|-----------|-----------|-------------|
| `bin` | (none) | `binary` | - |
| `json` | `.json` | `json` | `jq` |
| `yaml` | `.yaml` | `yaml` | `yq` |
| `env` | `.env` | `dotenv` | - |

## Operations

### Overview

| Operation | Input Source | Output | Needs Private Key? |
|-----------|--------------|--------|-------------------|
| `decrypt` | store path | stdout | Yes |
| `edit` | store path | `<name>.<ext>` file | Yes |
| `rotate` | store path + new content | `<name>.<ext>` file | Yes |
| `rekey` | store path | `<name>.<ext>` file | Yes |
| `init` | new content | `<name>.<ext>` file | No |

### decrypt

Decrypts the secret from the nix store and outputs to stdout.

```bash
# Basic usage
nix run .#secrets.my-secret.decrypt

# With key command
nix run .#secrets.my-secret.decrypt.withSopsAgeKeyCmd "op read op://vault/age-key"
```

- **Input**: Encrypted file from `_storePath`
- **Output**: Decrypted content to stdout, piped through format-specific tool (jq/yq)
- **Requires**: Private key access

### edit

Decrypts the secret, opens in `$EDITOR`, and re-encrypts to a local file.

```bash
# Opens editor, saves to ./my-secret.json
nix run .#secrets.my-secret.edit

# Specify output directory
nix run .#secrets.my-secret.edit ./secrets/
```

- **Input**: Encrypted file from `_storePath`
- **Output**: Re-encrypted file at `<dir>/<name>.<ext>`
- **Requires**: Private key access, `$EDITOR`

### rotate

Decrypts the secret, accepts new content, and re-encrypts to a local file.

```bash
# From stdin
echo '{"key": "new-value"}' | nix run .#secrets.my-secret.rotate

# From argument
nix run .#secrets.my-secret.rotate '{"key": "new-value"}'

# From file
nix run .#secrets.my-secret.rotate ./new-content.json
```

- **Input**: Encrypted file from `_storePath` + new content (stdin/arg/file)
- **Output**: Re-encrypted file at `<dir>/<name>.<ext>`
- **Requires**: Private key access

### rekey

Decrypts the secret and re-encrypts with the current recipient configuration. Content unchanged.

```bash
# Re-encrypts with current recipients
nix run .#secrets.my-secret.rekey
```

Use case: Recipients have changed in the nix configuration, and you need to update the encrypted file to reflect the new access list.

- **Input**: Encrypted file from `_storePath`
- **Output**: Re-encrypted file at `<dir>/<name>.<ext>` with updated recipients
- **Requires**: Private key access

### init

Creates a new encrypted secret. Does not require decryption.

```bash
# From stdin
echo '{"key": "value"}' | nix run .#secrets.my-secret.init

# From argument
nix run .#secrets.my-secret.init '{"key": "value"}'

# Specify output directory
echo "content" | nix run .#secrets.my-secret.init ./secrets/
```

- **Input**: Plaintext content (stdin/arg)
- **Output**: Encrypted file at `<dir>/<name>.<ext>`
- **Requires**: Only public keys (recipients)

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

All decrypt-dependent operations read from the nix store path (`_storePath`). This enables:

- Distribution: `nix run github:user/repo#secrets.x.decrypt` works
- Caching: Content-addressed, deterministic
- Remote secrets: Store path can reference any flake

### Output (Encryption Target)

All write operations output to `<dir>/<name>.<ext>`:

- `<dir>`: Specified as argument, defaults to current directory
- `<name>`: Secret name from definition
- `<ext>`: Determined by format (`.json`, `.yaml`, `.env`, or none for `bin`)

```bash
# Outputs to ./my-secret.json
nix run .#secrets.my-secret.init '{"key": "value"}'

# Outputs to ./secrets/my-secret.json
nix run .#secrets.my-secret.init '{"key": "value"}' ./secrets/
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
│  sops -d --input-type <fmt> --output-type <fmt> <_storePath>    │
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

### Shared Decryption Logic

Internally, `edit`, `rotate`, and `rekey` can reuse the same decryption mechanism:

```bash
# Pseudocode for all mutating operations
decrypt_content() {
  sops --config <(echo "$SOPS_CONFIG") \
       --input-type "$FORMAT" \
       --output-type "$FORMAT" \
       -d "$STORE_PATH"
}

encrypt_to_file() {
  local content="$1"
  local output_path="$2"
  echo -n "$content" | sops --config <(echo "$SOPS_CONFIG") \
                            --input-type "$FORMAT" \
                            --output-type "$FORMAT" \
                            -e /dev/stdin > "$output_path"
}
```

### Why Same Builders?

1. **Consistency**: Same key works for reading and writing your secrets
2. **Simplicity**: One mental model for key configuration
3. **Composability**: Can build higher-level tooling that combines operations

### No Key Needed for Encryption

Note that only the *decryption* phase needs the private key. The re-encryption phase uses only the public keys (recipients) which are baked into the sops config at build time.

```
decrypt: private key required
    ↓
[plaintext in memory]
    ↓
encrypt: public keys only (from recipients config)
```

### Example: CI Rotation Script

```nix
packages.rotate-db-password = let
  secret = flake.secrets.db-password;
  keyCmd = "cat /run/secrets/ci-age-key";
in pkgs.writeShellApplication {
  name = "rotate-db-password";
  runtimeInputs = [ pkgs.openssl ];
  text = ''
    NEW_PASS=$(openssl rand -base64 32)
    echo "$NEW_PASS" | ${lib.getExe (secret.rotate pkgs).withSopsAgeKeyCmd keyCmd} ./secrets/
    echo "Rotated db-password"
  '';
};
```

### Example: Interactive Edit

```bash
# Developer uses their personal key command
export SOPS_AGE_KEY_CMD="op read op://Private/age-key/secret"
nix run .#secrets.api-config.edit ./secrets/

# Or inline
nix run '.#secrets.api-config.edit.withSopsAgeKeyCmd "pass show age/dev"' ./secrets/
```

### Fallback Behavior

If no builder is used, the operation relies on sops' default key resolution:

1. `SOPS_AGE_KEY_CMD` environment variable
2. `SOPS_AGE_KEY` environment variable
3. `~/.config/sops/age/keys.txt`

This allows flexible usage:

```bash
# Works if SOPS_AGE_KEY_CMD is set in environment
nix run .#secrets.my-secret.edit ./secrets/

# Or explicitly configured
nix run '.#secrets.my-secret.edit.withSopsAgeKeyCmd "..."' ./secrets/
```

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
# Create a new secret
echo '{"api_key": "secret123"}' | nix run .#secrets.api-key.init ./secrets/

# Edit an existing secret
nix run .#secrets.api-key.edit ./secrets/

# Decrypt for use in scripts
API_KEY=$(nix run .#secrets.api-key.decrypt | jq -r .api_key)
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
nix run .#secrets.api-key.rekey ./secrets/
git add secrets/api-key.json
git commit -m "rekey api-key with updated recipients"
```

### Rotating Secret Values

```bash
# Generate new secret and rotate
NEW_KEY=$(openssl rand -hex 32)
echo "{\"api_key\": \"$NEW_KEY\"}" | nix run .#secrets.api-key.rotate ./secrets/
```
