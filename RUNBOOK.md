# 🚨 RUNBOOK — zGaming Incident Response

## 📌 GOAL

Provide immediate actions for:
- financial incidents
- security breaches
- system failures

## 🔴 SEVERITY LEVELS

### P0 — CRITICAL
- funds at risk
- active exploit
- wallet inconsistency

### P1 — HIGH
- failed withdrawals
- settlement stuck

### P2 — MEDIUM
- degraded service

## 🧯 IMMEDIATE ACTIONS (P0)

### 1. FREEZE SYSTEM

```bash
export SYSTEM_MODE=read-only
```

Disable:

- withdrawals
- settlements

### 2. FREEZE WALLET

Set global flag:

```sql
UPDATE system_flags SET wallet_frozen=1;
```

### 3. IDENTIFY IMPACT

Run:

```bash
php scripts/reconcile.php
```

Check:

- balance mismatches
- duplicate transactions

### 4. ISOLATE SERVICE

Stop affected service:

```bash
docker compose stop api
```

### 5. PRESERVE LOGS

- DO NOT restart DB
- export logs immediately

## 🔍 INVESTIGATION

Check:

- audit_events
- wallet_ledger
- settlement_queue

Look for:

- duplicate ref_id
- abnormal spikes
- replayed callbacks

## 🔁 RECOVERY

- fix root cause
- replay failed jobs (queue)
- DO NOT manually adjust balances

## 🚫 NEVER DO

- manual DB edits on balances
- delete ledger entries
- restart blindly

## 📢 POST-MORTEM

After incident include:

- timeline
- root cause
- financial impact
- prevention steps
