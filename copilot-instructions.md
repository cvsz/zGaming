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
