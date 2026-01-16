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

## Practical Risk Assessment

### How Alarming Is the Threat Model?

Honestly? Not very, for most use cases.

sops-nix, agenix, and similar tools are widely used in the NixOS community. The "secrets in git" model is the de facto standard because:

1. **The threat is theoretical for most teams** - It requires:
   - A key compromise (already a bad day)
   - AND attacker having repo access (or it going public)
   - AND historical secrets still being valuable

2. **Practical mitigations exist** - Rotate secrets periodically, and the historical exposure becomes "old passwords that no longer work"

3. **The alternative is significantly more complex** - Remote storage, sync tooling, credential management for the storage layer... all for a marginal security improvement

4. **Real-world breaches rarely come from git history** - They come from leaked `.env` files, hardcoded credentials, misconfigured S3 buckets, phishing, etc.

### Why Keep Secrets in the Repo?

Storing encrypted secrets in the repository has significant practical benefits for Nix workflows:

```nix
# This just works when secrets are in the repo:
nixosConfigurations.server1 = {
  sops.secrets.api-key.sopsFile = ./secrets/production/api-key.yaml;
};

# With remote storage, you'd need:
# 1. Fetch from S3 at build time? (impure, breaks Nix model)
# 2. Fetch at activation time? (delays boot, needs credentials on target)
# 3. Pre-fetch and vendor? (back to storing in repo anyway)
```

The Nix model wants deterministic, pure builds. Encrypted files in the repo are:

- Always available at eval time
- Packaged into closures naturally
- No runtime dependencies on external services

### Realistic Stance

Keep secrets in the repo. Accept that:

1. **Compromised key = rotate all affected secrets** - This is true regardless of where you store them
2. **Git history is a risk** - But a manageable one with rotation discipline
3. **KMS can reduce blast radius** - If you add KMS support later, the master key can't leak the same way an age key can

The threat model is "known and accepted" rather than "alarming." sops-nix has thousands of users; if it were catastrophically insecure, we'd know by now.

### What Actually Matters

Focus energy on:

- **Not committing plaintext secrets** (pre-commit hooks, CI checks)
- **Key hygiene** (don't share private keys over Slack)
- **Rotation procedures** (documented runbook for when things go wrong)
- **Least privilege** (the admin/target split handles this well)

The remote storage approach solves a theoretical problem while creating practical ones. Unless you have specific compliance requirements demanding it, keep it simple.
