# secrets.nix

A flake-parts module for secrets management

### Purpose

The goal here is to build on top of the good work of [sops-nix](https://github.com/Mic92/sops-nix/tree/master) and provide a flake-parts module which allows for a granular secrets management approach which extends beyond nixosConfigurations and homeManager configurations.

Sops is a simple and flexible tool for managing secrets using a variety of key management solutions. We will focus on age first as it's the most modern.

Traditionally, `.sops.yaml` is the orchestration tool used to provide creation and management rules and commonly populates many nix projects as a static file. The alteration that occurs here is that the `.sops.yaml` is dynamically configured through nix evaluation. Additionally, the creation rules are specified that such that secrets are decoupled to one file per secret.

### Guarded secrets

Secrets access is stringently by forced runtime constructions. What this means is that the user informs a runtime command used in order to securely provide the private key.

#### Example

Suppose a secret `my_secret` which has three named recipients, alice, bob and charlie. For a given "operation" that `my_secret` is to be used, an environment variable corresponding with at least one of the keys must be in scope in order to inform the script at runtime where it can access the private key. This could be specified in user's `.envrc.local` which is common convention.

- Alice

  ```bash
  ALICE__ACCESS_CMD="pass show age/alice"  
  ```

- Bob

  ```bash
  BOB__ACCESS_CMD="ssh-to-age -private-key -i ~/.ssh/id_ed25519"
  ```

- Charlie

  ```bash
  CHARLIE__ACCESS_CMD="echo <AGE_PRIVATE_KEY>" # Unsecure, would end up in nix-store
  ```

On the basis of the recipients list, any resulting context for which access to the secret is needed it will attempt to detect one of these recipient access commands. If none are found, the script will exit informing the user of the lack of an access command. If an access command environment variable is detected, it outputs the secret:

```bash

local detect_secret
```

### Future work

- Potentially this could also integrate agenix
- GPG key functionality is also missing.

### Links

- https://linus.schreibt.jetzt/posts/shell-secrets.html
