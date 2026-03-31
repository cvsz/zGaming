# 🧠 MASTER COPILOT INSTRUCTIONS — zGaming (INSTITUTIONAL GRADE)

---

# ⚠️ SYSTEM CLASSIFICATION

zGaming is a:

> **Real-money gaming + fintech system**

This system must operate with guarantees equivalent to:

* payment processors
* crypto custody platforms
* regulated casino backends

⚠️ Failure results in:

* financial loss
* regulatory violations
* security breaches

---

# 🚨 CORE PRINCIPLE

> **CORRECTNESS > SECURITY > AUDITABILITY > PERFORMANCE**

Never optimize before correctness is proven.

---

# 💰 FINANCIAL CORRECTNESS (NON-NEGOTIABLE)

## Ledger Model

* Ledger = **source of truth (append-only)**
* Balance = **derived state**

## ❌ FORBIDDEN

* UPDATE or DELETE on `wallet_ledger`
* Floating point arithmetic
* Skipping idempotency
* Direct DB mutation bypassing services

## ✅ REQUIRED

* BCMath / string-based money handling
* Global `transaction_id` (UUID)
* Idempotency keys
* ACID transactions

---

## DOUBLE-SPEND PREVENTION

Every financial operation MUST:

1. Check idempotency
2. Lock row:

   ```sql
   SELECT ... FOR UPDATE
   ```
3. Validate balance
4. Apply mutation
5. Insert ledger entry
6. Commit

---

## INVARIANTS (MUST ALWAYS HOLD)

* `SUM(ledger) == wallet.balance`
* No negative balances
* No duplicate `(ref_type, ref_id)`

---

# 🔐 SECURITY CONSTRAINTS

## Secrets

* NEVER hardcode
* NEVER log
* ALWAYS use env / secret manager

## Authentication

JWT must be:

* signed
* short-lived (<5 min)
* issuer-validated

## Webhooks

MUST verify:

* HMAC signature
* timestamp window (±5 min)
* nonce / idempotency key

---

# 🔴 RED TEAM ASSUMPTION

Assume attacker will:

* replay requests
* race concurrent calls
* forge callbacks
* tamper payloads
* escalate privileges

### Therefore ALWAYS:

* enforce idempotency
* validate inputs strictly
* log all financial actions
* reject duplicates

---

# 🧱 ENGINEERING DISCIPLINE

All code MUST be:

* deterministic
* idempotent
* testable
* observable

## Error Handling

* fail fast
* no silent failures
* structured logs (JSON)

---

# ⚙️ DEVOPS DISCIPLINE

## Bash Scripts (generator/phases)

All scripts MUST:

```bash
set -Eeuo pipefail
IFS=$'\n\t'
```

### Requirements

* idempotent
* resumable
* dependency-aware
* environment-validated

### NEVER

* assume services are ready
* skip error handling
* execute destructive ops blindly

---

## Docker Rules

* no hardcoded credentials
* no public DB exposure
* required healthchecks
* clean restart capability

---

# 🏦 COMPLIANCE EXPECTATIONS

System MUST support:

## AML

* transaction monitoring
* suspicious activity detection (STR)

## KYC

* mandatory before withdrawals

## Audit

* full traceability
* tamper-evident logs

---

# 🧾 AUDIT SYSTEM (MANDATORY)

Every critical action logs:

* actor
* action
* entity
* timestamp
* hash chain (`prev_hash → hash`)

Logs must be:

* append-only
* verifiable
* immutable

---

# 🧪 STATIC ANALYSIS RULES

## TypeScript (ESLint)

* no `any` in financial modules
* strict null checks
* mandatory input validation
* no direct DB access in API layer

## PHP (PHPStan)

* max level
* forbid:

  * float usage for money
  * untyped DB operations
  * SQL outside service layer

---

# 🔍 CUSTOM LINT ENFORCEMENT

Reject code if:

* float used for money
* no transaction wrapper
* missing idempotency
* missing audit logging

---

# 🔐 PRE-COMMIT HOOK (MANDATORY)

File: `.git/hooks/pre-commit`

```bash
#!/usr/bin/env bash
set -e

echo "🔍 Running pre-commit security checks..."

# Secret scan
if grep -r "PRIVATE_KEY\|SECRET\|API_KEY" .; then
  echo "❌ Secret detected"
  exit 1
fi

# Float usage in wallet
if grep -r "float" backend/wallet; then
  echo "❌ Float usage in wallet"
  exit 1
fi

# Ledger mutation
if grep -r "UPDATE wallet_ledger\|DELETE FROM wallet_ledger" .; then
  echo "❌ Ledger mutation detected"
  exit 1
fi

# Lint
pnpm lint || exit 1

# PHP lint
find backend -name "*.php" -exec php -l {} \; || exit 1

echo "✅ Pre-commit passed"
```

---

# 🤖 CI GUARDRAIL BOT

CI MUST reject PRs if:

* unsafe wallet logic
* missing idempotency
* missing audit logging
* secrets detected

---

# 🔄 AUTOMATED RECONCILIATION

Daily:

```bash
php scripts/reconcile.php
```

Must verify:

* ledger == wallet balance
* no inconsistencies

---

# 🔎 AUDIT VERIFIER

Must:

* validate hash chain
* detect tampering
* fail on mismatch

---

# 🛡️ RUNTIME PROTECTION LAYER

## Kill Switch

Env:

```
SYSTEM_MODE=read-only
```

Disables:

* withdrawals
* settlements

## Auto-Block

Trigger:

* abnormal velocity
* balance anomalies
* fraud spikes

Action:

* freeze account
* log event

---

# 🧪 CHAOS TESTING

System MUST survive:

* duplicate callbacks
* worker crashes
* partial failures

Never lose or duplicate money.

---

# 🤖 FRAUD DETECTION (ADVANCED)

Must include:

* velocity checks
* anomaly detection (z-score)
* behavioral patterns

Future:

* ML-based scoring

---

# 📡 REAL-TIME RISK ENGINE

* stream processing
* per-transaction scoring
* block high-risk actions

---

# 🔄 SETTLEMENT SYSTEM (KAFKA-STYLE)

Requirements:

* exactly-once processing
* idempotent consumers
* replay-safe execution

---

# 🔐 HSM INTEGRATION

* NO private keys in code
* use signer abstraction

Support:

* AWS KMS
* Fireblocks

---

# 🌍 MULTI-REGION CONSISTENCY

* global transaction IDs
* idempotent operations
* conflict-safe writes

---

# 🏦 BANK RECONCILIATION

* PSP vs internal ledger
* mismatch detection
* reporting

---

# 🔁 ATTACK REPLAY SYSTEM

* record real traffic
* replay safely
* validate defenses

---

# 🧪 AUDIT SIMULATOR

* simulate regulator inspection
* export full transaction trace

---

# 🚫 NEVER ALLOW

* bypassing wallet service
* direct DB mutation
* skipping validation
* unsafe retries

---

# ✅ ALWAYS PREFER

* append-only systems
* idempotent APIs
* explicit validation
* deterministic execution

---

# 🎯 FINAL GOAL

Every change must move the system toward:

> **bank-grade, regulator-compliant, attack-resistant financial infrastructure**

---

# 🧠 FINAL RULE

If uncertain:

* choose safety
* choose determinism
* choose auditability
* reject unsafe execution

---
custom ESLint plugin (detect unsafe wallet code)
PHPStan rules (block financial bugs)
CI guard bot (auto PR rejection engine)
