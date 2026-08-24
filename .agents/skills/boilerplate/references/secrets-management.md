# Secrets Management & Ingestion Architecture

Standards for secret storage, multi-backend keystores, hierarchical `fnox`
injection, cloud KMS resolution, and memory safety.

---

## 1. The Core Separation Invariant

Secrets (API tokens, private keys, database passwords, certificates) are
governed by distinct policy constraints and ingestion patterns compared to
standard configuration:

| Attribute | Configuration (`config.toml`, `mise.toml`) | Secrets (Credentials, Keys, Tokens) |
| :--- | :--- | :--- |
| **Visibility** | Public / Transparent: safe to log, debug, diff, and commit to VCS. | Zero-Trust Confidential: must never be committed, logged, or diffed in plaintext. |
| **Lifecycle** | Static or reloaded on deploy / `SIGHUP`. | Ephemeral, frequently rotated, dynamic leases, short TTLs. |
| **Storage Medium** | Plaintext files on disk, standard heap strings. | Hardware/OS keychains, RAM tmpfs (`/run/secrets`), encrypted stores, zeroized memory. |

---

## 2. Policy Invariants for Secrets

1. **CLI Argument Ban**: Passing raw secrets via command-line arguments (e.g.,
   `--password secret123`) is strictly forbidden.  Argument vectors are visible
   to all unprivileged host users via `/proc/$PID/cmdline` and process inspection
   tools (`ps`, `top`).  Input must use file pointers, environment variables, or
   standard input pipes (`--password-file`, `--password-stdin`).
2. **Repository Exclusion**: Plaintext secrets must never be committed to
   version control.  Local developer secrets must be encrypted at rest (e.g.
   `fnox` with age keys), stored in platform keychains, or isolated in
   gitignored `*.local.*` files.
3. **In-Memory Protection**: Applications must hold secret values in memory
   wrappers that prevent accidental exposure in stack traces, `Debug` formatting,
   or telemetry logs, and zeroize the memory buffer upon deallocation or exit
   (`zeroize`, `secrecy::Secret<T>`, or native memory scrubbers).

---

## 3. Standard Ingestion Patterns

Applications select one of three standardized patterns depending on deployment
tier and organizational policy:

### Pattern 1: The `_file` / `_env` Dual-Pointer Convention (Universal Baseline)

To keep application binaries lean and decoupled from heavy cloud SDKs, sensitive
configuration keys accept path pointers or environment variable names:

```toml
# config.toml (Committed to Git)
[database]
host = "db.internal.net"
port = 5432
username = "app_user"

# Resolution Priority:
# 1. password_file (Reads /run/secrets/db_pass or $CREDENTIALS_DIRECTORY/db_pass)
# 2. password_env  (Reads $DB_PASSWORD from process environment)
# 3. password      (Raw value - permitted only in local testing)
password_file = "/run/secrets/database_password"
```

*Advantages*: Works uniformly across local development, Linux systemd daemons,
Docker containers, and Kubernetes pods using standard library file I/O.

### Pattern 2: Process Wrapper & Hierarchical fnox Injection (12-Factor Decoupled)

The application reads standard environment variables or files, while `fnox`
resolves credentials hierarchically from diverse backends before process launch:

```
~/.config/fnox/config.toml (Global personal tokens & default providers)
      ↓
<project>/fnox.toml (Project-level shared providers: age, vault, 1password)
      ↓
<project>/fnox.local.toml (Uncommitted developer host-local overrides)
      ↓
<project>/services/<svc>/fnox.toml (Service-specific scoped secrets)
      ↓
<project>/services/<svc>/fnox.local.toml (Uncommitted service overrides)
```

- **Supported Backends in `fnox`**:
  - **OS Keychains & Hardware**: `keychain` (`libsecret` on Linux, macOS
    Keychain, Windows Credential Manager), `yubikey`, `fido2`.
  - **Asymmetric Encryption**: `age` recipient public keys for safe git storage.
  - **Cloud KMS**: `vault`, `aws-sm`, `aws-kms`, `azure-sm`, `gcp-sm`.
  - **Password Managers**: `1password`, `bitwarden`, `doppler`, `infisical`.
- **Injection Mechanisms**:
  - `fnox exec [--profile <env>] -- <cmd>`: Spawns the process with decrypted
    secrets populated directly in RAM.
  - Shell activation (`eval "$(fnox activate bash)"`): Auto-exports and scrubs
    secrets on directory traversal (`cd`).

### Pattern 3: Direct In-Process Cloud KMS Client (Dynamic Leases)

When security policy mandates workload identity verification (SPIFFE, AWS
IAM Roles for Service Accounts, Azure Managed Identity) and real-time lease
management:

```toml
[secrets.vault]
address = "https://vault.internal.corp:8200"
auth_method = "approle" # or "kubernetes", "aws", "oidc"
role = "backend-service"

[database]
vault_secret_path = "database/creds/readwrite-role"
```

*Application Invariant*: The application authenticates via ambient workload
identity, fetches short-lived dynamic credentials directly from the KMS API
(HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, CyberArk Conjur), and
handles renewal heartbeats in-process.

---

## 4. Environment Mapping Matrix

| Deployment Tier | Tooling / Source | Storage Medium | Access Protocol |
| :--- | :--- | :--- | :--- |
| **Local Dev (Workstation)** | **`fnox`** (OS Keychain / `libsecret` / macOS Keychain / Age / `fnox.local.toml`) | OS Keystore / RAM / uncommitted disk (`0600`) | Process wrapper (`fnox exec`), shell activation, or file pointer. |
| **CI / CD** | GitHub Actions Secrets / OIDC | Ephemeral runner memory | Injected step environment with short TTLs. |
| **Systemd Services** | `systemd-creds` / `LoadCredential=` | RAM tmpfs (`$CREDENTIALS_DIRECTORY`, `0400`) | Standard file pointer (`_file`). |
| **Containers / K8s** | Kubernetes Secrets / Vault CSI | RAM tmpfs (`/run/secrets/`, `0444`) | Standard file pointer (`_file`). |
| **Cloud** | Vault / AWS SM / Azure KV / Conjur | In-memory with zeroization | Workload identity SDK with dynamic leasing. |
