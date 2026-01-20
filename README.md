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
        decryptPkg = pkgs: pkgs.writeShellScriptBin "get-alice-key" ''
          pass show age/alice
        '';
      };
      bob = {
        key = "age1xyz...";  # bob's public key
        decryptPkg = pkgs: pkgs.writeShellScriptBin "get-bob-key" ''
          cat ~/.config/sops/age/keys.txt
        '';
      };
      server1 = {
        key = "age1srv...";  # server's public key
        # no decryptPkg - this is a deploy target, not a developer
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

## Builder Pattern

For Nix-level composition, use the builder pattern:

```nix
{
  # Pre-configured decrypt package
  my-decrypt = secrets.api-key.decrypt.withSopsAgeKeyCmd "pass show age/key";

  # Or with a package
  my-decrypt = secrets.api-key.decrypt.withSopsAgeKeyCmdPkg myKeyPkg;

  # Or build at evaluation time
  my-decrypt = secrets.api-key.decrypt.buildSopsAgeKeyCmdPkg (pkgs:
    pkgs.writeShellScriptBin "get-key" "pass show age/key"
  );
}
```

## Environment Variables

The decrypt operation respects these environment variables (in order of precedence):

1. `SOPS_AGE_KEY` - Direct key value
2. `SOPS_AGE_KEY_FILE` - Path to key file
3. `SOPS_AGE_KEY_CMD` - Command to retrieve key

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

- GPG key support
- agenix integration
- flake-parts module

## Links

- [SOPS](https://github.com/getsops/sops)
- [age](https://github.com/FiloSottile/age)
- [sops-nix](https://github.com/Mic92/sops-nix)
