---
name: license-compliance
description: |
  Audit, classify, and validate third-party software dependencies and source
  code licenses.  Invoke when evaluating new dependencies, editing lockfiles,
  importing code snippets, or running builds.
user-invokable: false
---

# License Compliance Skill

This skill governs how to evaluate and validate software licenses for third-party packages, libraries, binaries, and code snippets across Rust, TypeScript, Python, POSIX Shell/Bash, and Mojo projects.

---

## 1. Scope & Execution Strategy

You act as a **Read-Only Compliance Auditor**. Do not write or alter project-level scanner configurations (e.g., do not edit `deny.toml` or `package.json` scripts)—defer configuration setup to repository scaffolding workflows.

When evaluating license compliance, follow this two-stage decision tree:

### Stage 1: Native Scanner Check (Fast Path)
Before manually inspecting metadata, check for native project scanner tools:

*   **Rust:** If `deny.toml` exists, run `cargo deny check licenses`.
*   **TypeScript / Node:** If `package.json` contains a `license-check` script, run `npm/pnpm run license-check` (or execute `npx license-checker-rseidelsohn --summary`).
*   **Python:** If `pyproject.toml` or `requirements.txt` exists with `pip-licenses` installed, run `pip-licenses --summary`.
*   **Shell / Mojo / Polyglot:** If `.reuse/` exists, run `reuse lint`.

*Rule:* If the native scanner runs and **passes**, the dependency check is complete and auto-approved. If the native scanner **fails**, halt and report the scanner's output to the user.

### Stage 2: Manual LLM Audit (Slow Path)
If no native tooling or configuration file exists in the repository, manually inspect the package's SPDX identifier or `LICENSE` file against the **5 Policy Tiers** and **SPDX Parsing Rules** below.

---

## 2. Policy Tiers

Every license belongs strictly to one tier. Choose actions based on the tier classification:

### Tier 1: Permissive (Auto-Approve)
*   **Agent Action:** Approved for automatic selection, installation, and import.
*   **Licenses:** `MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `ISC`, `Unlicense`, `CC0-1.0`.
*   **Preference:** Prefer explicit patent protection licenses (`Apache-2.0`) for core runtime components when alternatives are equivalent.

### Tier 2: Weak Copyleft (Notify & Log)
*   **Agent Action:** Permitted, but log the package name and license in your task summary.
*   **Licenses:** `LGPL-2.1-only`, `LGPL-3.0-only`, `MPL-2.0`, `CDDL-1.1`, `EPL-2.0`.
*   **Condition:** Must be consumed as an unmodified external library or dynamic link target.

### Tier 3: Strong Copyleft (Require User Confirmation)
*   **Agent Action:** **STOP and prompt the user for explicit permission** before adding to lockfiles, build scripts, or codebases.
*   **Licenses:** `GPL-2.0-only`, `GPL-3.0-only`.
*   **CLI Exception:** Standalone CLI tools (e.g., compilers, linters, formatters) licensed under GPL are treated as **Tier 1 (Auto-Approved)** provided no GPL code is linked into or distributed with the project binary.

### Tier 4: Network Copyleft & Source-Available (Require User Confirmation)
*   **Agent Action:** **STOP and prompt the user for explicit permission.**
*   **Licenses:** `AGPL-3.0-only`, `GPL-2.0-or-later`, `GPL-3.0-or-later`, `AGPL-3.0-or-later`, `SSPL-1.0`, `BUSL-1.1`, `BSL-1.1`, `RSALv2`, `EUPL-1.2`, "Commons Clause".
*   **Open-Core Check:** Verify whether the specific sub-module/package requested is part of the open-source core or a commercial/source-available tier.

### Tier 5: Strictly Prohibited (Hard Failure)
*   **Agent Action:** **REJECT IMMEDIATELY.** Do not write code, add imports, or pull in dependencies under these terms. Cite this rule and require human intervention.
*   **Licenses & Categories:**
    *   Unlicensed code (no `LICENSE` file present; defaults to "All Rights Reserved").
    *   Non-commercial restrictions: `CC-BY-NC-4.0`, `PolyForm Noncommercial`.
    *   No-derivatives restrictions: `CC-BY-ND-4.0`.
    *   Custom, non-standard, or ad-hoc proprietary EULAs without verified written team consent.
*   **Code Snippet Rule:** Never paste raw code snippets from third-party sites (e.g., StackOverflow, Gists) unless confirmed as public domain (`CC0-1.0`, `Unlicense`) or permissively licensed.

---

## 3. SPDX Parsing & Resolution Rules

When parsing package metadata, evaluate complex or flexible license strings using these exact rules:

### Dual-Licensing Operators
*   **Disjunctive (`LICENSE-A OR LICENSE-B`):** **AUTO-PASS if ANY option is permitted.** Select the lowest-numbered tier among the options and log the choice (e.g., given `MIT OR GPL-3.0-only`, choose `MIT` under Tier 1).
*   **Conjunctive (`LICENSE-A AND LICENSE-B`):** **FAIL FAST if ANY option is restricted.** Must satisfy both licenses simultaneously. Classify the package under the strictest tier among the listed components.

### Tag Escalation (`-or-later` / `+`)
*   **Strictest Escalation Rule:** Evaluate components tagged with `-or-later` or `+` against the **highest/strictest tier** possible under the license upgrade path.
*   *Example:* Because `GPL-2.0-or-later` grants downstream rights to adopt `GPL-3.0-only` (Tier 3) or future network versions, treat `GPL-2.0-or-later` as **Tier 4**.

### Common License Exceptions
Recognized exceptions downgrade/modify the base license tier as follows:

| License Expression | Effective Tier | Reason / Scope |
| :--- | :--- | :--- |
| `GPL-2.0-only WITH Classpath-exception-2.0` | **Tier 2 (Weak Copyleft)** | Linking non-GPL binaries to this library does not infect the host application. |
| `Apache-2.0 WITH LLVM-exception` | **Tier 1 (Permissive)** | Waives binary attribution/notice obligations for compiled output. |
| `GPL-3.0-only WITH GCC-exception-3.1` | **Tier 1 (Permissive)** | Allows proprietary code compilation via GCC runtime interfaces. |

---

## 4. Multi-Language Verification Quick Reference

Use these reference methods during Stage 1/Stage 2 checks depending on the stack:

*   **Rust:** Check `Cargo.toml` / `Cargo.lock`. Run `cargo deny check licenses` if `deny.toml` exists.
*   **TypeScript / Node:** Inspect `package.json` license fields. Audit transitive dependencies with `npx license-checker-rseidelsohn --summary`.
*   **Python:** Inspect `pyproject.toml` or `pip list`. Audit with `pip-licenses --summary`.
*   **POSIX Shell / Bash:** Inspect file header comments for `SPDX-License-Identifier: <ID>` tags or run `reuse lint`.
*   **Mojo:** Inspect package `pixi.toml` / `environment.yml` dependencies, check source file SPDX headers, or run `reuse lint`.
