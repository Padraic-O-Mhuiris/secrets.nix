# Secrets Management Architecture

## Project Overview

Declarative SOPS/age secrets for Nix flakes. Each secret is declared in Nix with its own recipients, and every action on it (create, edit, decrypt, rotate, rekey) is a package generated from that declaration. See [secret-api.md](secret-api.md) for the reference.

```nix
secrets.api-key = {
  dir = ./secrets;
  format = "json";
  recipients = {
    alice.key = "age1...";
    server1.key = "age1...";
  };
};
```

Current model:

- **Per-secret recipients** - each secret lists every age public key that can decrypt it; there are no roles or groups.
- **Validation at evaluation** - names, env var collisions, age key format, at least one recipient.
- **Generated sops config** - each operation carries a `.sops.yaml` built from the secret's recipients; none is kept in the repo.
- **Operations as packages** - `packages.secrets.<name>.<op>`, with key commands configurable through env vars, CLI flags or Nix builders.
- **sops-nix modules** - `mkNixosModule`, `mkHomeManagerModule`, `mkDarwinModule` per secret.

Not built (tracked): shared recipient sets and automatic admin/backup recipients (#14), per-target grouped modules (#15). Earlier designs are in [design-history/](design-history/).

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

Each operation passes sops a generated config (via `--config`) containing one key group with all of the secret's recipients:

```yaml
creation_rules:
  - path_regex: .*
    key_groups:
      - age:
          - age1v9z267...  # alice
          - age1dpnznv...  # server1
```

SOPS uses this rule to determine which keys encrypt the file.

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

Only age recipients are supported today (`recipients.<r>.type` is fixed to `"age"`). Mixed key types (KMS, Azure Key Vault, PGP) are future work.

## Industry Best Practices

From OWASP, AWS, and enterprise guidance:

1. **Principle of least privilege** - Recipients are chosen per secret
2. **Environment segregation** - Use separate secrets (and recipients) per environment; there is no group construct (#14)
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

**If a key on many secrets is compromised (e.g. a personal admin key):**

- Attacker can decrypt every secret that lists it (current and historical)
- Mitigation: remove the key from the recipients, `rekey` and `rotate` affected secrets, and change the underlying secret values
- Git history still contains old encrypted blobs decryptable with the leaked key

**If a key on few secrets is compromised (e.g. a host key):**

- Attacker can decrypt only secrets that list that recipient
- Blast radius limited by per-secret recipients
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
- Per-secret recipients, validated at evaluation
- SOPS backend adds integrity (MAC) that raw age lacks
- `.sops.yaml` generated from Nix - single source of truth
- Secret lifecycle actions are Nix-built packages

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
3. **KMS can reduce blast radius** - If KMS support is added (not yet supported), the master key can't leak the same way an age key can

The threat model is "known and accepted" rather than "alarming." sops-nix has thousands of users; if it were catastrophically insecure, we'd know by now.

### What Actually Matters

Focus energy on:

- **Not committing plaintext secrets** (pre-commit hooks, CI checks)
- **Key hygiene** (don't share private keys over Slack)
- **Rotation procedures** (documented runbook for when things go wrong)
- **Least privilege** (list only the recipients that need each secret)

The remote storage approach solves a theoretical problem while creating practical ones. Unless you have specific compliance requirements demanding it, keep it simple.
