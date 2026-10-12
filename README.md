# secrets.nix

> **Beta**: This project is in active development. APIs may change.

Declarative SOPS secrets management for Nix flakes.

## Overview

secrets.nix turns a declaration of each secret (its recipients and format) into Nix constructions for its whole lifecycle:

- **Operations**: `encrypt`, `edit`, `decrypt`, `rotate`, `rekey` and `env` packages, each with `--help`
- **Consumption**: `mkNixosModule`, `mkHomeManagerModule` and `mkDarwinModule` fragments for [sops-nix](https://github.com/Mic92/sops-nix)

Each secret is a single encrypted file. There is no `.sops.yaml`: each operation generates its SOPS configuration from the declaration.

## Quick Start

### With flake-parts

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    secrets-nix.url = "github:Padraic-O-Mhuiris/secrets.nix";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [inputs.secrets-nix.flakeModule];
      systems = ["x86_64-linux"];

      secrets = let
        recipients = {
          alice = {
            key = "age1abc...";
            decryptPkg = pkgs:
              pkgs.writeShellScriptBin "get-alice-key" ''
                ${pkgs.pass}/bin/pass show age/alice
              '';
          };
          server1.key = "age1srv...";
        };
      in {
        api-key = {
          dir = ./secrets;
          inherit recipients;
          format = "json";
        };
        db-password = {
          dir = ./secrets;
          inherit recipients; # format defaults to "bin"
        };
      };
    };
}
```

The module exposes:

- `flake.secrets.<name>`: the evaluated secret, including the module builders
- `packages.<system>.secrets`: the operation packages, as `secrets.<name>.<operation>`

`secrets` may be defined in several modules; the definitions are merged.

### Without flake-parts

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    secrets-nix.url = "github:Padraic-O-Mhuiris/secrets.nix";
  };

  outputs = {nixpkgs, secrets-nix, ...}: let
    inherit (secrets-nix.lib) mkSecrets mkSecretsPackages;
    secrets = mkSecrets {
      api-key = {
        dir = ./secrets;
        recipients.alice.key = "age1abc...";
        format = "json";
      };
    };
  in {
    inherit secrets;
    packages.x86_64-linux.secrets =
      mkSecretsPackages secrets nixpkgs.legacyPackages.x86_64-linux;
  };
}
```

## Secret Definition

| Option | Description |
|--------|-------------|
| `dir` | Directory holding the encrypted file. The file is `<dir>/<name><extension>`. |
| `recipients.<name>.key` | The recipient's age public key. |
| `recipients.<name>.decryptPkg` | Optional `pkgs: drv` whose program prints the recipient's private key. Enables `<operation>.recipient.<name>`. |
| `format` | `bin` (default), `json`, `yaml` or `env`. |

| Format | Extension | sops type |
|--------|-----------|-----------|
| `bin`  | (none)    | `binary`  |
| `json` | `.json`   | `json`    |
| `yaml` | `.yaml`   | `yaml`    |
| `env`  | `.env`    | `dotenv`  |

Declarations are validated at evaluation:

- Secret and recipient names must match `[A-Za-z][A-Za-z0-9._-]*`. They become file, command and environment variable names.
- Names must not collide once mapped to environment variables (`foo-bar` and `foo_bar` both become `FOO_BAR`).
- Every secret needs at least one recipient.
- Secret names must not be derivation attributes such as `name`, `meta`, `outPath` or `drvPath`.

## Operations

`nix run .#secrets` lists every secret and recipient; `nix run .#secrets.<name>` shows one secret.

| Operation | Available | Needs private key |
|-----------|-----------|-------------------|
| `encrypt` | always | no |
| `edit` | always (decrypts first if the secret exists) | if the secret exists |
| `env` | always | no |
| `decrypt` | once the secret exists | yes |
| `rotate` | once the secret exists | yes |
| `rekey` | once the secret exists | yes |

A flake only sees files tracked by git, so a new secret counts as existing once it is `git add`ed.

### encrypt: encrypt content to the secret file

```bash
# From a command, without the plaintext touching disk or shell history
nix run .#secrets.api-key.encrypt -- --input <(pass show my-api-key)

# From a plaintext file
nix run .#secrets.api-key.encrypt -- --input ./plaintext.txt

# Print the encrypted file instead of writing it
nix run .#secrets.api-key.encrypt -- --input ./plaintext.txt --output /dev/stdout
```

### edit: create or modify a secret in $EDITOR

```bash
# New secret: opens an empty editor
nix run .#secrets.db-password.edit

# Existing secret: decrypts, opens $EDITOR, re-encrypts if the content changed
nix run .#secrets.api-key.edit.recipient.alice
```

### decrypt: print the plaintext

```bash
nix run .#secrets.api-key.decrypt.recipient.alice

# To a file (mode 0600)
nix run .#secrets.api-key.decrypt.recipient.alice -- --output ./plaintext.json

# Key supplied at runtime
nix run .#secrets.api-key.decrypt -- --sopsAgeKeyCmd "pass show age/alice"
```

The output is the plaintext byte for byte; pipe it to `jq` or `yq` for formatting.

### rotate: new data key, same content

```bash
nix run .#secrets.api-key.rotate.recipient.alice
```

### rekey: update recipients to match the declaration

```bash
# After adding or removing recipients
nix run .#secrets.api-key.rekey.recipient.alice
```

### env: print a key-configuration template

```bash
nix run .#secrets.api-key.env -- --recipient alice >> .envrc.local
```

### Where operations write

`encrypt`, `edit`, `rotate` and `rekey` write the secret file:

- **Default target**: the declared path, located from the root of the git repository you run the command in, so it works from any subdirectory. Outside a git repository, pass `--output`.
- **`--output <dir>/`** or **`--output <path>/<expected filename>`** picks another location.
- **Atomic**: output goes to a temporary file next to the target and replaces it only after the operation succeeds. A failed operation leaves the existing secret untouched.
- **Guarded**: an existing default target that differs from the secret the command was evaluated from is not overwritten. That usually means you are in the wrong repository.
- Secret files are written with mode `0644`.

## Consuming Secrets with sops-nix

Each evaluated secret provides module builders that set `sopsFile`, `format` and `key` for you:

```nix
# A NixOS configuration (sops-nix's module must be imported too)
{self, ...}: {
  imports = [
    (self.secrets.api-key.mkNixosModule {
      owner = "nginx";
      restartUnits = ["nginx.service"];
    })
  ];
}
```

| Builder | Options |
|---------|---------|
| `mkNixosModule` | `path`, `mode`, `owner`, `uid`, `group`, `gid`, `restartUnits`, `reloadUnits`, `neededForUsers` |
| `mkHomeManagerModule` | `path`, `mode` |
| `mkDarwinModule` | `path`, `mode`, `owner`, `uid`, `group`, `gid`, `neededForUsers` |

## Key Configuration

Operations that decrypt (`decrypt`, `edit` on an existing secret, `rotate`, `rekey`) need an age private key.

### Resolution order

First match wins:

1. `--sopsAgeKey`, `--sopsAgeKeyFile` or `--sopsAgeKeyCmd`
2. `<SECRET>__<RECIPIENT>__AGE_KEY[_FILE|_CMD]`: this secret only, e.g. `API_KEY__ALICE__AGE_KEY_CMD`
3. `<RECIPIENT>__AGE_KEY[_FILE|_CMD]`: every secret for that recipient, e.g. `ALICE__AGE_KEY_CMD`
4. `SOPS_AGE_KEY`, `SOPS_AGE_KEY_FILE` or `SOPS_AGE_KEY_CMD`
5. The key command built into the package (`.recipient.<name>` or a builder method)

Names map to variables by upper-casing and replacing `-` and `.` with `_`. At levels 2 and 3, only one recipient may be set; several is an error. `env` prints the variables for a secret.

`--sopsAgeKey` and `SOPS_AGE_KEY` put the key in the process list or environment; prefer a command or file.

### Built-in key commands

`decryptPkg` on a recipient gives every decrypting operation a `.recipient.<name>` package. For one-off packages, chain a builder method:

```nix
let
  secretsPkgs = mkSecretsPackages secrets pkgs; # or config.packages.secrets
in {
  # Command string, run by sops
  decrypt-op = secretsPkgs.api-key.decrypt.withSopsAgeKeyCmd "op read op://vault/age-key/secret";

  # Package whose main program prints the key
  decrypt-pkg = secretsPkgs.api-key.decrypt.withSopsAgeKeyCmdPkg myKeyPkg;

  # Function building that package from pkgs
  decrypt-ssh = secretsPkgs.api-key.decrypt.buildSopsAgeKeyCmdPkg (pkgs:
    pkgs.writeShellScriptBin "get-key" ''
      ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i ~/.ssh/id_ed25519
    '');
}
```

A key command must print the private key to stdout, write prompts and errors to stderr, and exit non-zero on failure.

### Common key sources

```nix
# Password store (pass)
decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" ''
  ${pkgs.pass}/bin/pass show age/mykey
'';

# 1Password CLI
decryptPkg = pkgs: pkgs.writeShellScriptBin "get-key" ''
  ${pkgs._1password-cli}/bin/op read "op://vault/age-key/secret"
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

## DevShell Integration

```nix
perSystem = {config, pkgs, ...}: {
  devShells.default = pkgs.mkShell {
    packages = [
      config.packages.secrets.api-key.decrypt.recipient.alice
      config.packages.secrets.api-key.edit.recipient.alice
    ];
  };
};
```

The commands are named `<operation>-<secret>`:

```bash
API_KEY=$(decrypt-api-key)
edit-api-key
```

## Development

```bash
nix flake check      # unit tests, end-to-end tests against sops, lints
nix run .#unit-tests
nix fmt
```

The example secrets in `examples/` use test-only keys whose private halves are committed.

## Roadmap

Planned lifecycle work is tracked in [issue #20](https://github.com/Padraic-O-Mhuiris/secrets.nix/issues/20), including shared recipient sets with admin and backup keys, grouped modules per host, verify, bulk operations and retiring secrets. Further SOPS key types (GPG, cloud KMS, Vault Transit) are not planned yet.

## Links

- [SOPS](https://github.com/getsops/sops)
- [age](https://github.com/FiloSottile/age)
- [sops-nix](https://github.com/Mic92/sops-nix)
