# Secrets Management Architecture

## Project Overview

This project provides a declarative secrets management solution using Nix flake-parts with SOPS as the encryption backend. The core design:

```nix
flake.secrets.<group> = {
  recipients = {
    admins = [ { name = "alice"; key = "age1..."; } ];  # Access to all secrets
    targets = [ { name = "server1"; key = "age1..."; } ];  # Per-secret access
  };
  secret.apiKey = {
    admins = ["alice"];      # Defaults to all admins
    targets = ["server1"];   # Explicit selection, or ["*"] for all
  };
};
```

Key features:

- **Admin/target separation** - Admins get all secrets by default (key rotation, management), targets are opt-in per-secret (principle of least privilege)
- **Validation** - Target/admin names validated against defined recipients via `types.enum`
- **Computed `_recipients`** - Automatically combines selected admins + targets
- **Generated `_creationRule`** - SOPS-compatible YAML fragment per secret
- **Group isolation** - Supports environment segregation (dev/staging/prod)

## How SOPS Works

### Envelope Encryption

1. A random **Data Key** encrypts your secret values
2. **Master Key(s)** (age, KMS, etc.) encrypt the Data Key
3. Both are stored in the file - any single master key can decrypt

### Partial Encryption

```yaml
database:
  host: ENC[AES256_GCM,data:7a3b2c...]    # Value encrypted
  password: ENC[AES256_GCM,data:9x8y7z...]
# Keys/structure remain readable - useful for diffs and reviews
```

### Creation Rules

The Nix config generates `.sops.yaml` rules like:

```yaml
- path_regex: secrets/example/apiKey\.yaml$
  age:
    - age1v9z267...  # alice (admin)
    - age1dpnznv...  # server1 (target)
```

SOPS uses these rules to determine which keys encrypt each file.

## Local vs Remote Key Schemes

| Aspect | Local (age/PGP) | Remote (AWS KMS, GCP KMS, Azure Key Vault) |
|--------|-----------------|-------------------------------------------|
| **Key storage** | On disk | HSM-backed cloud service |
| **Network** | None required | API call per operation |
| **Revocation** | Re-encrypt everything | Instant IAM permission change |
| **Audit** | Git history only | Full cloud audit logs |
| **Compromise impact** | Permanent access to encrypted data | Revoke access; master key never leaked |

### Hybrid Approach (Recommended)

Use both age (offline/backup) and KMS (primary) - SOPS encrypts the data key for all master keys.

The design supports mixed key types:

```nix
recipients = {
  admins = [
    { name = "alice"; age = "age1..."; }
    { name = "ci"; kms = "arn:aws:kms:..."; }
  ];
  targets = [
    { name = "server1"; age = "age1..."; }
    { name = "prod"; azureKeyvault = "https://vault.azure.net/keys/..."; }
  ];
};
```

## Industry Best Practices

From OWASP, AWS, and enterprise guidance:

1. **Principle of least privilege** - The admin/target split implements this
2. **Environment segregation** - The `flake.secrets.<group>` structure supports this
3. **Automated rotation** - Enterprise solutions rotate automatically; this solution requires manual re-encryption
4. **Audit logging** - Git provides change history; KMS adds access logs
5. **Key groups/threshold** - SOPS supports N-of-M keys via Shamir's Secret Sharing
6. **Eliminate long-lived secrets** - Prefer short-lived tokens where possible
7. **Centralized management** - The Nix config is the single source of truth

### What Enterprise Solutions Add

- Dynamic/ephemeral secrets (generated on demand, auto-expire)
- Just-in-time access (temporary credentials)
- Instant revocation
- Automatic rotation

## Threat Model & Exposure

### The Fundamental Limitation

Secrets stored in git have no forward secrecy.

```
Timeline:
────────────────────────────────────────────────────────────►
  Commit A            Commit B           Key Compromised
  (secret X)          (secret Y)              │
     │                   │                    │
     └───────────────────┴────────────────────┘
                         │
         All historical secrets decryptable
```

### Compromise Scenarios

**If an admin key is compromised:**

- Attacker can decrypt ALL secrets in that group (current and historical)
- Mitigation: Rotate all secrets, re-encrypt with new key, remove compromised key
- Git history still contains old encrypted blobs decryptable with leaked key

**If a target key is compromised:**

- Attacker can decrypt only secrets that included that target
- Blast radius limited by per-secret targeting
- Still need to rotate affected secrets

### Key Concerns

| Issue | Impact | Mitigation |
|-------|--------|------------|
| **No forward secrecy** | Historical secrets exposed | Frequent rotation, limit secret lifetime |
| **No authentication** | age doesn't verify integrity; attackers with write access can modify | SOPS adds MAC |
| **Not post-quantum safe** | Future quantum computers could decrypt | Rotate secrets that must remain confidential long-term |
| **Git history persistence** | Old encrypted blobs remain | History rewriting (loses audit), or don't store in git |

### Realistic Threat Scenarios

| Threat | Git history matters? | Notes |
|--------|---------------------|-------|
| Accidental public repo | Yes | Immediate full exposure |
| Compromised developer laptop | Yes | They have full clone |
| Compromised CI/CD | Maybe | Depends on clone depth |
| Insider threat | Yes | Current access = historical access |
| External attacker (no repo access) | No | Need repo first |

## Mitigations for Forward Secrecy

1. **Frequent rotation** - Limits exposure window (but history still vulnerable)
2. **KMS as master key** - age keys can leak; KMS keys in HSM cannot. Historical data encrypted with KMS remains protected.
3. **Shallow clones** - CI/CD doesn't need full history
4. **Separate secrets repo** - Aggressive history pruning after rotation (loses audit)
5. **Don't store secrets in git** - Git holds only `.sops.yaml` (access policy); actual secrets in S3/Vault/Secrets Manager with deletable versions
6. **Ephemeral secrets** - Short-lived tokens that expire before historical exposure matters

## Where This Solution Fits

### Comparable To

agenix, sops-nix - the standard "encrypted secrets in git" model for NixOS

### Strengths

- Declarative, version-controlled access policy
- Clean admin/target separation with validation
- SOPS backend adds integrity (MAC) that raw age lacks
- Group isolation for environment segregation
- Generates `.sops.yaml` from Nix - single source of truth

### Limitations (Inherent to the Model)

- Manual rotation/re-encryption on compromise
- Git history exposure risk
- No dynamic secrets or automatic rotation

### Appropriate For

- Infrastructure secrets (API keys, database passwords)
- Teams comfortable with the git history trade-off
- Environments where KMS can provide additional protection for high-value secrets

### Not Ideal For

- Secrets requiring instant revocation
- Highly regulated environments needing full audit trails
- Secrets that must remain confidential for decades (post-quantum concern)
