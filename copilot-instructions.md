# 🧠 MASTER COPILOT INSTRUCTIONS — zGaming (INSTITUTIONAL GRADE)

## ⚠️ SYSTEM CLASSIFICATION

This repository is a:

> **Real-money financial + gaming system**

All generated code MUST satisfy:

* financial correctness
* auditability
* exploit resistance
* deterministic execution

Failure = **real monetary loss + regulatory breach**

---

# 🔒 GLOBAL ENFORCEMENT RULES

## ❌ NEVER DO

* Use floating point for money
* Update/delete ledger entries
* Skip transactions for wallet operations
* Trust external input (API/webhook)
* Log secrets (keys, passwords)
* Introduce non-idempotent operations
* Use in-memory state for financial logic

## ✅ ALWAYS DO

* Use append-only ledger
* Enforce idempotency
* Use transactions + row locks
* Validate all inputs strictly
* Use environment variables
* Log every critical action
* Design for replay safety

---

# 💰 FINANCIAL CORRECTNESS (CRITICAL)

## Ledger Rules

* Ledger = **source of truth**
* Balance = derived ONLY

### Required invariants:

* sum(ledger) == wallet balance
* no negative balance
* no duplicate ref_id per user

---

## Transaction Rules

Every wallet operation MUST:

1. Check idempotency
2. Lock row (`FOR UPDATE`)
3. Apply change
4. Insert ledger record
5. Commit

---

## Money Handling

* Use BCMath ONLY
* All amounts stored as string DECIMAL
* Never use float/double

---

# 🔐 SECURITY CONSTRAINTS

## Authentication

* JWT must be:

  * signed
  * short-lived (<5 min)
  * verified for issuer

## Webhooks

* MUST verify:

  * HMAC signature
  * timestamp window
  * idempotency key

## Secrets

* NEVER in code
* ONLY via env / secret manager

---

# 🧱 ENGINEERING DISCIPLINE

## Code Requirements

* deterministic
* idempotent
* testable
* observable

## Error Handling

* fail fast
* no silent failures
* structured logs (JSON)

---

# 🐳 DEVOPS DISCIPLINE

## Scripts

All bash scripts MUST:

```bash
set -Eeuo pipefail
IFS=$'\n\t'
```

## Requirements

* idempotent execution
* dependency checks
* readiness checks

---

## Docker

* no hardcoded credentials
* healthchecks required
* services must start cleanly

---

# 🧾 COMPLIANCE EXPECTATIONS

System MUST support:

## AML

* transaction monitoring
* suspicious activity detection

## KYC

* required before withdrawal

## Audit

* append-only logs
* hash chain integrity

---

# 🔴 RED TEAM AWARENESS

Copilot MUST assume attacker mindset:

### Always check:

* race conditions
* replay attacks
* signature bypass
* privilege escalation
* double-spend scenarios

---

# 🧪 STATIC ANALYSIS RULES

## ESLint (TypeScript)

Enforce:

* no `any` in financial modules
* required input validation
* no direct DB access in API layer

## PHPStan

Level: max

Custom rules:

* forbid float in wallet code
* enforce transaction usage
* forbid direct SQL outside services

---

# 🔐 PRE-COMMIT HOOK (MANDATORY)

## File: `.git/hooks/pre-commit`

```bash
#!/usr/bin/env bash
set -e

echo "🔍 Running pre-commit security checks..."

# 1. Secret scan
if grep -r "PRIVATE_KEY\|SECRET\|API_KEY" .; then
  echo "❌ Secret detected"
  exit 1
fi

# 2. Float usage in wallet
if grep -r "float" backend/wallet; then
  echo "❌ Float usage in wallet"
  exit 1
fi

# 3. Ledger mutation check
if grep -r "UPDATE wallet_ledger\|DELETE FROM wallet_ledger" .; then
  echo "❌ Ledger mutation detected"
  exit 1
fi

# 4. Run lint
pnpm lint || exit 1

# 5. PHP lint
find backend -name "*.php" -exec php -l {} \; || exit 1

echo "✅ Pre-commit checks passed"
```

---

# 🧾 AUTOMATED AUDIT VERIFIER

## Script: `scripts/audit_verify.php`

Checks:

* ledger hash chain integrity
* balance consistency
* duplicate transactions

---

# 🔄 AUTOMATED RECONCILIATION CLI

## Script: `scripts/reconcile.php`

Must:

* compare ledger vs wallet
* detect mismatches
* output report

---

# 🛡️ RUNTIME PROTECTION LAYER

## Kill Switch

Env flag:

```
SYSTEM_MODE=read-only
```

Disables:

* withdrawals
* settlements

---

## Auto Block System

Trigger on:

* abnormal transaction rate
* balance anomalies
* fraud score spike

Action:

* freeze account
* log event

---

# 🔥 CHAOS TESTING

## Goal

Break system safely.

## Examples

* kill DB during transaction
* duplicate callbacks
* crash worker mid-processing

System MUST:

* recover safely
* not lose money

---

# 🤖 FRAUD DETECTION (ADVANCED)

## Features

* transaction velocity
* bet size anomaly
* session behavior

## Model Types

* rule-based (baseline)
* anomaly detection (z-score)
* future: ML classifier

---

# 📊 OBSERVABILITY

Logs MUST include:

* user_id
* transaction_id
* service
* timestamp

---

# 🧠 FINAL RULE

Copilot must optimize for:

> **safety > correctness > performance > convenience**

If unsure:

* block the operation
* log it
* require verification

---

# 🎯 END GOAL

All generated code must move system toward:

> **bank-grade, audit-compliant, exploit-resistant financial platform**

---


# 🧠 Copilot Instructions — zGaming Monorepo

## 📌 Overview

This repository implements a **real-money casino / fintech platform**.

It includes:

- Wallet + ledger system (financial core)
- Settlement queue
- AML / KYC logic
- Audit logging (tamper-evident)
- Docker-based infrastructure
- Bash-based orchestration (meta-master + phases)

⚠️ **This is a high-risk system**. Any incorrect code may result in:

- financial loss
- security breaches
- regulatory violations

## 🚨 NON-NEGOTIABLE RULES

### 1. NEVER BREAK FINANCIAL CORRECTNESS

- Wallet must be **ledger-first**
- Ledger must be **append-only**
- NEVER:
  - update or delete ledger entries
  - bypass idempotency checks
  - use floating point for money

✅ Always:

- use BCMath (PHP) or string math
- enforce idempotency keys
- wrap financial operations in DB transactions

### 2. NO DOUBLE-SPEND CONDITIONS

All financial operations MUST:

- be idempotent
- use `SELECT ... FOR UPDATE`
- check existing `ref_id` BEFORE applying changes

### 3. NO HARD-CODED SECRETS

NEVER generate code that:

- embeds passwords
- embeds API keys
- prints secrets in logs

ALWAYS use:

- environment variables (`.env`)
- secure loading in scripts

### 4. BASH SCRIPTS MUST BE SAFE

All scripts in `generator/phases`:

- must be **idempotent**
- must be safe to re-run
- must fail fast (`set -Eeuo pipefail`)
- must validate dependencies before execution

NEVER:

- assume services are running
- skip error handling
- run destructive commands without checks

### 5. DOCKER / INFRA RULES

- No hardcoded ports without justification
- No hardcoded credentials
- Must support clean restart

Always:

- use env variables
- add healthchecks where possible

### 6. API SECURITY

All APIs must:

- validate input strictly
- authenticate requests (JWT or HMAC)
- prevent replay attacks (nonce/timestamp)

NEVER:

- trust client input
- expose internal errors

### 7. WEBHOOK / CALLBACK SAFETY

All callbacks must:

- verify signature (HMAC)
- validate timestamp (±5 minutes)
- enforce idempotency

### 8. AUDIT LOGGING IS MANDATORY

Every critical action MUST log:

- actor (user/admin/system)
- action
- entity affected
- timestamp
- hash linkage (`prev_hash → hash`)

Audit logs must be:

- append-only
- tamper-evident

### 9. QUEUE-BASED PROCESSING ONLY

Do NOT introduce direct execution for:

- settlements
- payouts
- withdrawals

Use:

- DB-backed queue (`SELECT ... FOR UPDATE SKIP LOCKED`)

### 10. ZERO-TRUST SERVICE COMMUNICATION

All internal services must:

- authenticate using signed tokens
- validate issuer + expiry

NEVER:

- trust internal network blindly

## 🧩 ARCHITECTURE PRINCIPLES

### Source of Truth

- Ledger = source of truth
- Balance = derived/cache

### Idempotency

- All external-facing operations must be replay-safe

### Determinism

- Scripts must produce same result every run

### Isolation

- Wallet signing must be abstracted (HSM-ready)

## 🛠️ CODING GUIDELINES

### PHP (Wallet / Backend)

- Use strict types where possible
- Use transactions for financial ops
- Use BCMath for money

### TypeScript (API)

- Validate all inputs (zod or equivalent)
- Never trust request body

### Bash

Always include:

```bash
set -Eeuo pipefail
IFS=$'\n\t'
```

## 🔐 SECURITY CHECKLIST (MANDATORY)

Before suggesting code, ensure:

- [ ] No secrets exposed
- [ ] No SQL injection risk
- [ ] No race condition
- [ ] No replay attack vector
- [ ] Idempotency enforced
- [ ] Logging does not leak sensitive data

## 💣 HIGH-RISK AREAS (BE EXTRA CAREFUL)

- `backend/wallet/*`
- `modules/wallet/*`
- `modules/game-engine/*`
- `api/gateway/*`
- `generator/phases/*`

## 🚫 DO NOT SUGGEST

- Floating point arithmetic for money
- Direct DB mutations bypassing services
- Disabling transactions
- Skipping validation
- “Quick fixes” that break invariants

## ✅ PREFERRED PATTERNS

- Append-only logs
- Idempotent APIs
- Explicit validation
- Retry-safe operations
- Hash-linked audit trails

## 🎯 GOAL

All generated code must move the system toward:

> **secure, deterministic, audit-ready financial infrastructure**

NOT:

> “just working code”

## 🧠 FINAL RULE

If unsure:

- choose safety over convenience
- choose correctness over performance
