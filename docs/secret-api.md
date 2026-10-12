# Secret API

Reference for the current API. Source of truth: `core/`.

## Declaring secrets

Directly:

```nix
secrets = inputs.secrets-nix.lib.mkSecrets {
  api-key = {
    dir = ./secrets;                      # directory holding the encrypted file
    format = "json";                      # bin (default) | json | yaml | env
    recipients.alice = {
      key = "age1...";                    # age public key
      decryptPkg = pkgs: pkgs.writeShellApplication {   # optional
        name = "alice-key";
        runtimeInputs = [pkgs.pass];
        text = "pass show age/alice";
      };
    };
  };
};
secretsPkgs = inputs.secrets-nix.lib.mkSecretsPackages secrets pkgs;
```

Or with the flake-parts module:

```nix
imports = [inputs.secrets-nix.flakeModule];
secrets.api-key = { dir = ./secrets; recipients.alice.key = "age1..."; };
```

The module option `secrets` is `attrsOf submodule`, so definitions from several modules merge. It exposes:

- `flake.secrets`: the evaluated, validated secrets
- `perSystem.packages.secrets`: `mkSecretsPackages config.flake.secrets pkgs`

Nothing is exposed when `secrets` is empty.

### Options

| Option | Type | Default | Notes |
|--------|------|---------|-------|
| `dir` | path | — | Directory of the encrypted file |
| `format` | `bin` \| `json` \| `yaml` \| `env` | `bin` | sops input/output type |
| `recipients.<r>.key` | string matching `age1[a-z0-9]{58}` | — | Public key |
| `recipients.<r>.type` | `"age"` | `"age"` | Read-only; only age is supported |
| `recipients.<r>.decryptPkg` | null or `pkgs -> derivation` | `null` | Key command package; enables `.recipient.<r>` |

### Derived (read-only)

| Attribute | Value |
|-----------|-------|
| `_fileName` | `<name><ext>` |
| `_path` | `dir + "/" + _fileName` |
| `_projectOutPath` | `./<path>` relative to the flake source root, or the absolute path when `dir` is outside the store |
| `_exists` | `builtins.pathExists _path` |

### Formats

| Format | Extension | sops type |
|--------|-----------|-----------|
| `bin` | (none) | `binary` |
| `json` | `.json` | `json` |
| `yaml` | `.yaml` | `yaml` |
| `env` | `.env` | `dotenv` |

### Validation

Checked at evaluation; the first failure throws:

- Secret and recipient names match `[A-Za-z][A-Za-z0-9._-]*`.
- Secret names are not reserved derivation attributes: `name meta passthru text type out outPath drvPath outputs outputName all args builder system overrideAttrs inputDerivation drvAttrs`.
- No two secret names, and no two recipient names within a secret, map to the same env var name (uppercase, `-` and `.` → `_`; e.g. `foo-bar` and `foo.bar`).
- Each secret has at least one recipient.
- Recipient keys match the age public key pattern (option type).

## Packages

```
secretsPkgs                  # lists secrets, recipients and usage
secretsPkgs.<name>           # prints format, paths, status, recipients, operations
secretsPkgs.<name>.encrypt   # always
secretsPkgs.<name>.edit      # always
secretsPkgs.<name>.env       # always
secretsPkgs.<name>.decrypt   # only if _exists
secretsPkgs.<name>.rotate    # only if _exists
secretsPkgs.<name>.rekey     # only if _exists
```

From the CLI: `nix run .#secrets.<name>.<op> -- [args]`. Each binary is named `<op>-<name>` and has `--help`.

| Operation | Does | Needs private key |
|-----------|------|-------------------|
| `encrypt` | Encrypts `--input <path>` (required) to the secret file; replaces an existing one | No |
| `edit` | New: opens `$EDITOR` on an empty file, aborts if nothing saved. Existing: decrypts, opens `$EDITOR`, re-encrypts | Only if exists |
| `decrypt` | Writes the plaintext, byte for byte, to stdout or `--output` | Yes |
| `rotate` | `sops rotate`: new data key, same content | Yes |
| `rekey` | `sops updatekeys`: recipients updated to match the flake, same data key | Yes |
| `env` | Prints a commented template of the key env vars; `--recipient <r>` limits it to one recipient | No |

Encryption uses a `.sops.yaml` generated in the store from the declared recipients (one age key group with every recipient), passed with `--config`. No `.sops.yaml` is needed in the repo.

Decrypting operations read the copy of the encrypted file in the Nix store (captured at evaluation), not the working tree. A built package therefore works wherever its closure is copied, e.g. `nix run github:user/repo#secrets.x.decrypt`.

## Writes

Applies to `encrypt`, `edit`, `rotate`, `rekey` (write the encrypted file) and `decrypt --output` (writes plaintext).

- **Default target** (no `--output`): `_projectOutPath`. A `./…` path is resolved from `git rev-parse --show-toplevel`, so the current directory inside the repo does not matter; outside a git repo the command fails and asks for `--output`. `decrypt` defaults to stdout.
- **`--output`** for encrypted files: a directory (existing, or ending in `/`; the expected filename is appended) or a path whose basename is `_fileName`; otherwise it fails. `encrypt` also accepts `/dev/stdout`. `decrypt --output` takes any path. The parent directory must exist.
- **Overwrite guard**: when the secret exists and the default target is used, the command refuses to overwrite a file at the target that differs from the store copy it was built from (wrong project, or the file changed since evaluation).
- **Atomic**: output is written to a temp file in the target directory and `mv`'d into place only after the operation succeeds.
- **Modes**: commands run with `umask 077`; encrypted files are written `0644`; `decrypt --output` files are `0600`.
- **`edit` on an existing secret** writes nothing when the content is unchanged.
- Plaintext for `edit` lives in a private temp dir named `<_fileName>` (so editors pick syntax) and is removed on exit.

## Key resolution

For `decrypt`, `edit` (existing), `rotate`, `rekey`. First match wins:

1. `--sopsAgeKey <key>` / `--sopsAgeKeyFile <path>` / `--sopsAgeKeyCmd <cmd>`
2. `<SECRET>__<RECIPIENT>__AGE_KEY`, `…_AGE_KEY_FILE`, `…_AGE_KEY_CMD` (this secret only)
3. `<RECIPIENT>__AGE_KEY`, `…_AGE_KEY_FILE`, `…_AGE_KEY_CMD` (every secret for that recipient)
4. `SOPS_AGE_KEY`, `SOPS_AGE_KEY_FILE`, `SOPS_AGE_KEY_CMD`
5. Key command built into the package (`.recipient.<r>` or a `.with*`/`.build*` builder); used only when no `SOPS_AGE_KEY*` is set

`<SECRET>` and `<RECIPIENT>` are the env var forms of the names (`api-key` → `API_KEY`). Within one level, the first of `KEY`, `KEY_FILE`, `KEY_CMD` that is set is used; if variables are set for more than one recipient at the same level, the command fails. The chosen value is exported as the matching `SOPS_AGE_*` variable for sops. If nothing is set, sops' own defaults apply.

`--sopsAgeKey` is visible in the process list; prefer `--sopsAgeKeyCmd` or a file.

`env` prints the exact variable names for a secret:

```bash
nix run .#secrets.api-key.env -- --recipient alice >> .envrc.local
```

## Key command builders

`decrypt`, `rotate`, `rekey` and `edit` (existing secrets only) are builder packages:

| Attribute | Argument | Effect |
|-----------|----------|--------|
| `.withSopsAgeKeyCmd` | string | Command stored literally and run by sops |
| `.withSopsAgeKeyCmdPkg` | derivation | Runs its `meta.mainProgram` (or `pname`/`name`); added to `runtimeInputs` |
| `.buildSopsAgeKeyCmdPkg` | `pkgs -> derivation` | As above, built with the operation's `pkgs` |
| `.recipient.<r>` | — | `.buildSopsAgeKeyCmdPkg recipients.<r>.decryptPkg`; present only for recipients with `decryptPkg` |

Each builder returns a package with the same builders, so the last call wins.

```nix
let
  secretsPkgs = self.packages.${system}.secrets;   # or mkSecretsPackages secrets pkgs
in {
  decrypt-op = secretsPkgs.api-key.decrypt.withSopsAgeKeyCmd "op read op://vault/age-key";

  decrypt-pass = secretsPkgs.api-key.decrypt.withSopsAgeKeyCmdPkg (pkgs.writeShellApplication {
    name = "get-key";
    runtimeInputs = [pkgs.pass];
    text = "pass show age/my-key";
  });

  rotate-file = secretsPkgs.api-key.rotate.buildSopsAgeKeyCmdPkg (pkgs:
    pkgs.writeShellApplication {
      name = "get-key";
      text = "cat ~/.age/key.txt";
    });

  edit-alice = secretsPkgs.api-key.edit.recipient.alice;
}
```

A key command prints the age private key to stdout, writes prompts and errors to stderr, and exits non-zero on failure.

Only decryption needs the private key; re-encryption uses the public keys in the generated sops config.

## sops-nix modules

Each evaluated secret has `mkNixosModule`, `mkHomeManagerModule` and `mkDarwinModule`. Each takes an attrset of options and returns `{ sops.secrets.<name> = …; }` with `sopsFile = _path`, `format` mapped to the sops-nix name, and `key = ""` for `bin` or `key = <name>` otherwise.

| Builder | Options (defaults) |
|---------|--------------------|
| `mkNixosModule` | `path` (unset), `mode` (`"0400"`), `owner` (null), `uid` (0), `group` (null), `gid` (0), `restartUnits` ([]), `reloadUnits` ([]), `neededForUsers` (false) |
| `mkHomeManagerModule` | `path` (unset), `mode` (`"0400"`) |
| `mkDarwinModule` | `path` (unset), `mode` (`"0400"`), `owner` (`"root"`), `uid` (0), `group` (`"staff"`), `gid` (0), `neededForUsers` (false) |

```nix
nixosConfigurations.server1 = nixpkgs.lib.nixosSystem {
  modules = [
    sops-nix.nixosModules.sops
    (self.secrets.api-key.mkNixosModule {owner = "app";})
  ];
};
```

## Workflow

```bash
nix run .#secrets.api-key.edit                                   # create
nix run .#secrets.api-key.encrypt -- --input <(pass show api-key) # create/replace from a command
nix run .#secrets.api-key.edit.recipient.alice                   # edit
nix run .#secrets.api-key.decrypt -- --sopsAgeKeyCmd "pass show age/alice"
nix run .#secrets.api-key.rekey.recipient.alice                  # after changing recipients
nix run .#secrets.api-key.rotate.recipient.alice                 # new data key
git add secrets/api-key.json
```

After writing a secret, re-evaluate (the packages embed the store copy from evaluation time); the overwrite guard rejects a stale package whose source differs from the file on disk.
