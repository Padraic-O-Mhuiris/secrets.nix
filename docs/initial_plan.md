# SOPS Flake Module - Architecture Plan

A flake-parts module for declarative SOPS secrets management with auto-generated NixOS/home-manager module constructors and CLI tooling.

## Overview

This module provides:
1. Declarative key and secret definitions in flake configuration
2. Auto-generated CLI tools for secret management (edit, rekey, show)
3. Module constructors (`mkNixosModule`, `mkHomeModule`) for consuming secrets
4. Grouped module constructors per target (host/user) for convenience
5. Automatic key inclusion based on role (admin/backup always included)

## Key Architecture

### Key Roles

Keys are categorized by their role in the secrets lifecycle:

| Role | Purpose | Auto-included | Example |
|------|---------|---------------|---------|
| `admin` | Primary management, encrypt/decrypt all secrets | Yes, in all secrets | Personal age key |
| `backup` | Recovery if admin key lost | Yes, in all secrets | Yubikey, offline key |
| `target` | Runtime consumers (hosts/users) | No, explicit per-secret | Host SSH-derived key, user age key |

### Key Definition Schema

```nix
flake.sops.keys = {
  <key-name> = {
    # Required: The age public key
    key = "age1...";

    # Required: Role determines auto-inclusion behavior
    # "admin" | "backup" | "target"
    role = "target";

    # Optional: Description for documentation/CLI output
    description = "Oxygen host key (SSH-derived)";
  };
};
```

### Example Key Definitions

```nix
flake.sops.keys = {
  # Administrative key - always included in all secrets
  admin = {
    key = "age1ewfw6eekkvdu0yj56pcd6hf368xy0yuln5xafaadm4rm5hk29pvstz5y2j";
    role = "admin";
    description = "Primary admin key";
  };

  # Backup keys - always included for recovery
  yk14244920 = {
    key = "age1yubikey1q2muf06ye7utkhcsxqv49xxsre6ul2a2ct45sg7zxl9367phzpdljkkfj93";
    role = "backup";
    description = "Yubikey 14244920";
  };

  yk20655177 = {
    key = "age1yubikey1qvn5jgywpv3de28nyt8ll5jvxstwjr9lha9z54sdelmfxulau25f2ns742y";
    role = "backup";
    description = "Yubikey 20655177";
  };

  # Target keys - explicitly referenced per-secret
  Oxygen = {
    key = "age1...";
    role = "target";
    description = "Oxygen host (SSH-derived from /persist/etc/ssh/ssh_host_ed25519_key)";
  };

  Hydrogen = {
    key = "age1...";
    role = "target";
    description = "Hydrogen host (SSH-derived)";
  };

  padraic = {
    key = "age1sartew6ntahhyg06p72rpy77xuyw0gh28zp76ynl3na3v73l7ufqjm5sd5";
    role = "target";
    description = "padraic user key";
  };
};
```

## Secret Architecture

### Secret Definition Schema

```nix
flake.sops.secrets = [
  {
    # Required: Unique identifier, used in CLI and module paths
    name = "hetzner_floating_ip";

    # Required: List of target key names that can decrypt at runtime
    # Admin + backup keys are auto-appended for encryption
    targets = ["Oxygen"];

    # Optional: Secret file format
    # "yaml" (default) | "json" | "binary" | "dotenv" | "ini"
    format = "yaml";

    # Optional: Path relative to secrets root directory
    # Default: "" (secrets root)
    # Results in: <repo>/secrets/<path>/<name>.<format-extension>
    path = "infrastructure/hetzner";

    # Optional: Description for documentation/CLI
    description = "Hetzner floating IP for ingress";
  }
];
```

### File Path Resolution

Given a secret definition:
```nix
{
  name = "hetzner_floating_ip";
  path = "infrastructure/hetzner";
  format = "yaml";
}
```

The file path resolves to:
```
<flake-root>/secrets/infrastructure/hetzner/hetzner_floating_ip.yaml
```

With default path:
```nix
{
  name = "atuin_key";
  format = "yaml";
  # path defaults to ""
}
```

Resolves to:
```
<flake-root>/secrets/atuin_key.yaml
```

### Encryption Keys Computation

For each secret, the encryption keys are computed as:

```
encryption_keys = admin_keys ++ backup_keys ++ target_keys
```

Where:
- `admin_keys` = all keys where `role = "admin"`
- `backup_keys` = all keys where `role = "backup"`
- `target_keys` = keys referenced in the secret's `targets` list

### Example Secret Definitions

```nix
flake.sops.secrets = [
  # Host-specific secret
  {
    name = "hetzner_floating_ip";
    targets = ["Oxygen"];
    format = "yaml";
    path = "infrastructure/hetzner";
    description = "Floating IP from Hetzner terraform output";
  }

  # User secret with multiple targets (user key + yubikeys for interactive decrypt)
  {
    name = "atuin_key";
    targets = ["padraic"];
    format = "yaml";
    description = "Atuin sync encryption key";
  }

  # Multi-host secret
  {
    name = "shared_api_key";
    targets = ["Oxygen" "Hydrogen"];
    format = "yaml";
    path = "services";
    description = "API key needed by multiple hosts";
  }

  # JSON format (e.g., from terraform output)
  {
    name = "cluster_kubeconfig";
    targets = ["Oxygen"];
    format = "json";
    path = "infrastructure/kubernetes";
  }
];
```

## Generated Outputs

### Package Structure

Each secret generates a package with passthru commands:

```
flake.packages.<system>.secrets.<secret-name>.edit
flake.packages.<system>.secrets.<secret-name>.rekey
flake.packages.<system>.secrets.<secret-name>.show
```

Usage:
```bash
nix run .#secrets.hetzner_floating_ip.edit
nix run .#secrets.hetzner_floating_ip.rekey
nix run .#secrets.hetzner_floating_ip.show
```

Additionally, a root `secrets` package lists all available commands:
```bash
nix run .#secrets
# Outputs list of all secrets and available commands
```

### CLI Command Behavior

#### `edit`
- Creates temporary `.sops.yaml` with correct creation rules
- Opens secret file in `$EDITOR` via `sops`
- Uses admin key from configured source (e.g., `pass show systems/age/admin.private.age`)

#### `rekey`
- Re-encrypts secret with current key list
- Used after adding/removing targets from a secret
- Uses `sops updatekeys`

#### `show`
- Decrypts and displays secret contents to stdout
- For debugging/verification

### Module Constructor Structure

#### Per-Secret Module Constructors

Each secret generates module constructors:

```nix
flake.secrets.<secret-name> = {
  # Metadata
  name = "<secret-name>";
  path = "/absolute/path/to/secret.yaml";
  format = "yaml";
  targets = ["Oxygen"];

  # CLI packages
  edit = <derivation>;
  rekey = <derivation>;
  show = <derivation>;

  # Module constructors
  mkNixosModule = {
    # sops.age configuration
    sshKeyPaths ? [],
    keyFile ? null,
    generateKey ? false,

    # sops.secrets.<name> configuration
    owner ? "root",
    group ? "root",
    mode ? "0400",
    restartUnits ? [],
    reloadUnits ? [],
    path ? null,  # override runtime path
    ...
  }: { config, ... }: {
    sops.age = {
      inherit sshKeyPaths keyFile generateKey;
    };
    sops.secrets.<secret-name> = {
      sopsFile = <path-to-secret-file>;
      format = "<format>";
      inherit owner group mode restartUnits reloadUnits;
    } // (if path != null then { inherit path; } else {});
  };

  mkHomeModule = {
    sshKeyPaths ? [],
    keyFile ? null,
    ...
  }: { config, ... }: {
    sops.age = {
      inherit sshKeyPaths keyFile;
    };
    sops.secrets.<secret-name> = {
      sopsFile = <path-to-secret-file>;
      format = "<format>";
    };
  };
};
```

#### Per-Target Grouped Module Constructors

Each target generates grouped module constructors containing all secrets for that target:

```nix
flake.secrets.targets.<target-name> = {
  # List of secret names this target can access
  secrets = ["hetzner_floating_ip" "other_secret"];

  # Grouped NixOS module constructor
  mkNixosModule = {
    sshKeyPaths ? [],
    keyFile ? null,
    generateKey ? false,

    # Per-secret overrides
    secretOverrides ? {},
    # e.g., { hetzner_floating_ip = { owner = "nginx"; }; }
    ...
  }: { config, ... }: {
    sops.age = {
      inherit sshKeyPaths keyFile generateKey;
    };
    sops.secrets = {
      hetzner_floating_ip = {
        sopsFile = <path>;
        format = "yaml";
      } // (secretOverrides.hetzner_floating_ip or {});

      other_secret = {
        sopsFile = <path>;
        format = "yaml";
      } // (secretOverrides.other_secret or {});
    };
  };

  # Grouped home-manager module constructor
  mkHomeModule = { ... }: { ... };
};
```

### Usage Examples

#### Individual Secret Import

```nix
# hosts/Oxygen/default.nix
{ self, ... }: {
  imports = [
    (self.secrets.hetzner_floating_ip.mkNixosModule {
      sshKeyPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];
      owner = "nginx";
      group = "nginx";
      restartUnits = ["nginx.service"];
    })
  ];

  # Access at runtime: config.sops.secrets.hetzner_floating_ip.path
  services.nginx.virtualHosts."example.com" = {
    # ...
  };
}
```

#### Grouped Target Import

```nix
# hosts/Oxygen/default.nix
{ self, ... }: {
  imports = [
    (self.secrets.targets.Oxygen.mkNixosModule {
      sshKeyPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];
      secretOverrides = {
        hetzner_floating_ip = {
          owner = "nginx";
          restartUnits = ["nginx.service"];
        };
      };
    })
  ];
}
```

#### Home-Manager Import

```nix
# home/padraic.nix
{ self, ... }: {
  imports = [
    (self.secrets.targets.padraic.mkHomeModule {
      sshKeyPaths = ["${config.home.homeDirectory}/.ssh/id_ed25519"];
    })
  ];

  # Access: config.sops.secrets.atuin_key.path
}
```

## Configuration Options

### Global Configuration

```nix
flake.sops = {
  # Root directory for secrets files (relative to flake root)
  # Default: "secrets"
  secretsDir = "secrets";

  # Source for admin private key (used by CLI commands)
  # Supports: pass, file, env
  adminKeySource = {
    type = "pass";
    path = "systems/age/admin.private.age";
  };
  # OR
  adminKeySource = {
    type = "file";
    path = "/path/to/admin.age";
  };
  # OR
  adminKeySource = {
    type = "env";
    variable = "SOPS_AGE_KEY";
  };

  # Keys and secrets defined separately (see above)
  keys = { ... };
  secrets = [ ... ];
};
```

## Integration with Terraform/Terranix

### Workflow

1. Terraform produces sensitive output (e.g., floating IP, API token)
2. Post-apply script encrypts output to SOPS file with specified targets
3. Flake module auto-generates the consumption interface
4. NixOS configuration imports the module and accesses the secret at runtime

### Example: Hetzner Floating IP

```nix
# In terranix/infrastructure configuration
{
  resource.hcloud_floating_ip.ingress = {
    type = "ipv4";
    home_location = "fsn1";
  };

  output.floating_ip = {
    value = "\${hcloud_floating_ip.ingress.ip_address}";
    sensitive = true;
  };
}
```

Post-apply script:
```bash
#!/usr/bin/env bash
FLOATING_IP=$(terraform output -raw floating_ip)

# Create/update the SOPS secret
echo "floating_ip: $FLOATING_IP" | sops --encrypt --input-type yaml \
  --output secrets/infrastructure/hetzner/hetzner_floating_ip.yaml \
  /dev/stdin
```

Flake secret definition:
```nix
{
  name = "hetzner_floating_ip";
  targets = ["Oxygen"];
  format = "yaml";
  path = "infrastructure/hetzner";
}
```

NixOS consumption:
```nix
{ self, config, ... }: {
  imports = [
    (self.secrets.hetzner_floating_ip.mkNixosModule {
      sshKeyPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];
    })
  ];

  # Read the IP at runtime
  systemd.services.my-service = {
    script = ''
      FLOATING_IP=$(cat ${config.sops.secrets.hetzner_floating_ip.path})
      # use $FLOATING_IP
    '';
  };
}
```

## File Structure

```
<new-repo>/
├── flake.nix
├── flake-module.nix      # Main flake-parts module
├── lib/
│   ├── keys.nix          # Key processing utilities
│   ├── secrets.nix       # Secret processing utilities
│   ├── modules.nix       # Module constructor generators
│   └── cli.nix           # CLI package generators
├── modules/
│   ├── nixos.nix         # NixOS module template
│   └── home.nix          # home-manager module template
└── README.md
```

## Flake Interface

```nix
{
  inputs.sops-flake.url = "github:user/sops-flake";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      inputs.sops-flake.flakeModules.default
    ];

    flake.sops = {
      keys = { ... };
      secrets = [ ... ];
    };
  };
}
```

## Open Questions / Future Considerations

1. **Secret templating**: Should secrets support templating (e.g., Jinja-style) for generated content?

2. **Validation**: Should the module validate that target keys exist before generating outputs?

3. **Secret dependencies**: Should secrets be able to depend on other secrets?

4. **Automatic creation**: Should `edit` create the file if it doesn't exist?

5. **Key rotation**: CLI command for rotating a specific key across all secrets?

6. **Integration testing**: How to test that secrets are correctly encrypted/decrypted?

7. **Binary secrets**: Special handling for binary format (certificates, etc.)?

8. **Nested secrets**: Support for secrets with nested keys (e.g., `sops.secrets."foo/bar"`)?
