# secrets.nix

> **Beta**: This project is in active development. APIs may change.

Declarative SOPS secrets management for Nix flakes.

## Overview

secrets.nix provides a pure Nix approach to managing encrypted secrets using SOPS and age. Each secret is:

- Declared in your flake with explicit recipients
- Stored as a single encrypted file (one file per secret)
- Managed through generated shell scripts with full `--help` documentation

No `.sops.yaml` file needed - configuration is derived from your Nix expressions.

## Quick Start

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    secrets-nix.url = "github:your/secrets.nix";
  };

  outputs = { nixpkgs, secrets-nix, ... }: let
    inherit (secrets-nix) mkSecrets mkSecretsPackages;

    recipients = {
      alice = {
        key = "age1abc...";  # alice's public key
      };
      bob = {
        key = "age1xyz...";  # bob's public key
      };
      server1 = {
        key = "age1srv...";  # server's public key
        decryptPkg = pkgs: pkgs.writeShellScriptBin "get-server1-key" ''
          ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key
        '';
      };
    };

    secrets = mkSecrets {
      api-key = {
        dir = ./secrets;
        inherit recipients;
      };
      db-password = {
        dir = ./secrets;
        inherit recipients;
        format = "bin";  # default
      };
      service-account = {
        dir = ./secrets;
        inherit recipients;
        format = "json";
      };
    };
  in {
    packages.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      secretsPkgs = mkSecretsPackages secrets pkgs;
    in {
      inherit secretsPkgs;
    };
  };
}
```

## Operations

### init - Create a new secret

```bash
# Interactive (opens $EDITOR)
nix run .#secrets.api-key.init

# From file (secure - content not in shell history)
nix run .#secrets.api-key.init -- --input <(pass show my-api-key)

# Override output location
nix run .#secrets.api-key.init -- --output ./other-dir/

# See all options
nix run .#secrets.api-key.init -- --help
```

### decrypt - Decrypt a secret

```bash
# To stdout (default)
nix run .#secrets.api-key.decrypt.recipient.alice

# To file
nix run .#secrets.api-key.decrypt.recipient.alice -- --output ./plaintext.txt

# With runtime key override
nix run .#secrets.api-key.decrypt -- --sopsAgeKeyCmd "pass show age/alice"
nix run .#secrets.api-key.decrypt -- --sopsAgeKeyFile ~/.config/sops/age/keys.txt

# Pipe to other commands
nix run .#secrets.service-account.decrypt.recipient.alice | jq .field

# See all options
nix run .#secrets.api-key.decrypt -- --help
```

### edit - Modify an existing secret

```bash
nix run .#secrets.api-key.edit.recipient.alice
```

### rotate - Replace secret content

```bash
nix run .#secrets.api-key.rotate.recipient.alice -- --input <(pass show new-api-key)
```

### rekey - Re-encrypt with updated recipients

```bash
nix run .#secrets.api-key.rekey.recipient.alice
```

## Recipient Configuration

Each recipient needs a public key. Optionally, provide a `decryptPkg` function to enable `decrypt.recipient.<name>`:

```nix
recipients = {
  # Developer with decrypt capability
  alice = {
    key = "age1...";
    decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" ''
      pass show age/alice
    '';
  };

  # Deploy target (encrypt-only, no decryptPkg)
  production = {
    key = "age1...";
  };
};
```

## Formats

Supported secret formats:

| Format | Extension | Use case |
|--------|-----------|----------|
| `bin`  | (none)    | Binary/text secrets (default) |
| `json` | `.json`   | Structured JSON data |
| `yaml` | `.yaml`   | Structured YAML data |
| `env`  | `.env`    | Environment files |

## Key Configuration

There are multiple ways to provide the age secret key for decryption, at both build time (Nix evaluation) and runtime (shell execution).

### Build-time Configuration

Configure the key source when building packages in your flake:

#### 1. Per-recipient packages (recommended)

Define `decryptPkg` in your recipients to get `decrypt.recipient.<name>`:

```nix
recipients = {
  alice = {
    key = "age1...";
    decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" ''
      pass show age/alice
    '';
  };
};

# Then use:
packages.decrypt-secret = secrets.api-key.decrypt.recipient.alice;
```

#### 2. Builder pattern

Chain builder methods for one-off configurations:

```nix
{
  # String command (executed at runtime)
  my-decrypt = secrets.api-key.decrypt.withSopsAgeKeyCmd "pass show age/key";

  # Pre-built package (must output key to stdout)
  my-decrypt = secrets.api-key.decrypt.withSopsAgeKeyCmdPkg myKeyPkg;

  # Build function (pkgs -> derivation)
  my-decrypt = secrets.api-key.decrypt.buildSopsAgeKeyCmdPkg (pkgs:
    pkgs.writeShellScriptBin "get-key" ''
      ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i ~/.ssh/id_ed25519
    ''
  );
}
```

### Runtime Configuration

Override or provide key configuration when running the command:

#### 1. Command-line flags

```bash
# Command that outputs the key (most secure)
nix run .#secrets.api-key.decrypt -- --sopsAgeKeyCmd "pass show age/key"

# Path to key file
nix run .#secrets.api-key.decrypt -- --sopsAgeKeyFile ~/.config/sops/age/keys.txt

# Direct key value (visible in ps - use only for testing)
nix run .#secrets.api-key.decrypt -- --sopsAgeKey "AGE-SECRET-KEY-1..."
```

#### 2. Environment variables

```bash
# Command that outputs the key
export SOPS_AGE_KEY_CMD="pass show age/key"
nix run .#secrets.api-key.decrypt

# Path to key file
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
nix run .#secrets.api-key.decrypt

# Direct key value
export SOPS_AGE_KEY="AGE-SECRET-KEY-1..."
nix run .#secrets.api-key.decrypt
```

#### 3. Using direnv

Add to `.envrc` for automatic key configuration per-project:

```bash
# .envrc
export SOPS_AGE_KEY_CMD="pass show age/myproject"
```

### Key Resolution Order

When decrypting, keys are resolved in this order (first match wins):

1. `--sopsAgeKey` flag
2. `--sopsAgeKeyFile` flag
3. `--sopsAgeKeyCmd` flag
4. `SOPS_AGE_KEY` environment variable
5. `SOPS_AGE_KEY_FILE` environment variable
6. `SOPS_AGE_KEY_CMD` environment variable
7. Build-time configured key (from `decryptPkg` or builder pattern)

### Common Key Sources

```nix
# Password store (pass)
decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" ''
  ${pkgs.pass}/bin/pass show age/mykey
'';

# 1Password CLI
decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" ''
  ${pkgs._1password}/bin/op read "op://vault/age-key/secret"
'';

# SSH key via ssh-to-age
decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" ''
  ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i ~/.ssh/id_ed25519
'';

# HashiCorp Vault
decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" ''
  ${pkgs.vault}/bin/vault kv get -field=key secret/age
'';

# AWS Secrets Manager
decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" ''
  ${pkgs.awscli2}/bin/aws secretsmanager get-secret-value \
    --secret-id age-key --query SecretString --output text
'';

# Bitwarden CLI
decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" ''
  ${pkgs.bitwarden-cli}/bin/bw get password age-key
'';

# macOS Keychain
decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" ''
  security find-generic-password -s "age-key" -w
'';

# Plain file (least secure, but simple)
decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" ''
  cat ~/.config/sops/age/keys.txt
'';
```

## Project Structure

```
your-project/
├── flake.nix          # Secret definitions
└── secrets/
    ├── api-key        # Encrypted secret (binary format)
    ├── db-password    # Encrypted secret
    └── service-account.json  # Encrypted secret (json format)
```

## Future Work

- Additional SOPS key types:
  - GPG keys
  - AWS KMS
  - GCP KMS
  - Azure Key Vault
  - HashiCorp Vault Transit
- sopsnix/agenix integration
- flake-parts module

## Links

- [SOPS](https://github.com/getsops/sops)
- [age](https://github.com/FiloSottile/age)
- [sops-nix](https://github.com/Mic92/sops-nix)
