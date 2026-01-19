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
| `false` | `init` only |
| `true` | `decrypt`, `edit`, `rotate`, `rekey` |

### Overview

| Operation | Input Source | Output | Needs Private Key? |
|-----------|--------------|--------|-------------------|
| `decrypt` | `_path` | stdout | Yes |
| `edit` | `_path` | `./<_fileName>` | Yes |
| `rotate` | `_path` + new content | `./<_fileName>` | Yes |
| `rekey` | `_path` | `./<_fileName>` | Yes |
| `init` | new content | `./<_fileName>` | No |

All write operations output to the **current directory** with the derived filename. The user is responsible for moving the file to the correct location (`dir`) and committing to git.

### decrypt

Decrypts the secret and outputs to stdout.

```bash
# Basic usage
nix run .#secrets.my-secret.decrypt

# With key command
nix run .#secrets.my-secret.decrypt.withSopsAgeKeyCmd "op read op://vault/age-key"
```

- **Input**: Encrypted file from `_path`
- **Output**: Decrypted content to stdout, piped through format-specific tool (jq/yq)
- **Requires**: Private key access

### edit

Decrypts the secret, opens in `$EDITOR`, and re-encrypts.

```bash
# Opens editor, saves to ./my-secret.json in current directory
nix run .#secrets.my-secret.edit
```

- **Input**: Encrypted file from `_path`
- **Output**: Re-encrypted file at `./<_fileName>`
- **Requires**: Private key access, `$EDITOR`

### rotate

Accepts new content and encrypts.

```bash
# From stdin
echo '{"key": "new-value"}' | nix run .#secrets.my-secret.rotate

# From argument
nix run .#secrets.my-secret.rotate '{"key": "new-value"}'

# From file
nix run .#secrets.my-secret.rotate ./new-content.json
```

- **Input**: Encrypted file from `_path` + new content (stdin/arg/file)
- **Output**: Re-encrypted file at `./<_fileName>`
- **Requires**: Private key access

### rekey

Decrypts the secret and re-encrypts with the current recipient configuration. Content unchanged.

```bash
# Re-encrypts with current recipients
nix run .#secrets.my-secret.rekey
```

Use case: Recipients have changed in the nix configuration, and you need to update the encrypted file to reflect the new access list.

- **Input**: Encrypted file from `_path`
- **Output**: Re-encrypted file at `./<_fileName>` with updated recipients
- **Requires**: Private key access

### init

Creates a new encrypted secret. Does not require decryption. Only available when the secret file doesn't exist yet.

```bash
# Preview encrypted output (no file created)
nix run .#secrets.my-secret.init -- '{"key": "value"}'

# Write to file
nix run .#secrets.my-secret.init -- --outpath ./secrets/ '{"key": "value"}'

# Opens $EDITOR if run directly with TTY (not via nix run)
./result/bin/secret-init-my-secret
./result/bin/secret-init-my-secret --outpath ./secrets/

# Can also specify full path (filename must match)
nix run .#secrets.my-secret.init -- --outpath ./secrets/my-secret.json '{"key": "value"}'
```

- **Input**: Content as positional argument, or opens `$EDITOR` (via sops) if run with TTY
- **Output**: Stdout by default, or file at `<outpath>/<_fileName>` if `--outpath` specified
- **Requires**: Only public keys (recipients)

Options:
- `--outpath` - Output directory or file path. If not specified, outputs to stdout.

The `--outpath` argument can be:
- A directory (e.g., `./secrets/`) - filename is derived automatically
- A full path (e.g., `./secrets/my-secret.json`) - filename must match `_fileName`

Note: `$EDITOR` mode requires a TTY, so it only works when running the command directly (not via `nix run`). Build and run directly for editor support:

```bash
nix build .#secrets.my-secret.init && ./result/bin/secret-init-my-secret --outpath ./secrets/
```

```bash
# Create and commit a new secret
nix run .#secrets.my-secret.init -- --outpath ./secrets/ '{"key": "value"}'
git add secrets/my-secret.json
git commit -m "add my-secret"
```

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

All write operations output to the current directory with the derived filename (`./<_fileName>`).

The user workflow is:
1. Run the operation (outputs to current directory)
2. Move the file to the correct location (`dir`)
3. Commit to git

```bash
# Example: create and commit a new secret
echo '{"key": "value"}' | nix run .#secrets.my-secret.init
mv my-secret.json secrets/
git add secrets/my-secret.json
git commit -m "add my-secret"
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
# Create a new secret (only available when secret doesn't exist)
nix run .#secrets.api-key.init -- --outpath ./secrets/ '{"api_key": "secret123"}'
git add secrets/api-key.json

# Or use editor for content
nix run .#secrets.api-key.init -- --outpath ./secrets/
git add secrets/api-key.json

# Edit an existing secret
nix run .#secrets.api-key.edit
mv api-key.json secrets/
git add secrets/api-key.json

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
nix run .#secrets.api-key.rekey
mv api-key.json secrets/
git add secrets/api-key.json
git commit -m "rekey api-key with updated recipients"
```

### Rotating Secret Values

```bash
# Generate new secret and rotate
NEW_KEY=$(openssl rand -hex 32)
echo "{\"api_key\": \"$NEW_KEY\"}" | nix run .#secrets.api-key.rotate
mv api-key.json secrets/
git add secrets/api-key.json
```
