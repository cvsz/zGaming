# ⚙️ OPERATIONS — zGaming

## 📌 DAILY TASKS

- check logs for errors
- run reconciliation
- review AML flags

## 🧪 HEALTH CHECKS

```bash
curl /health
curl /ready
```

## 💾 BACKUPS

Run daily:

```bash
./scripts/backup.sh
```

Test restore weekly.

## 🔍 RECONCILIATION

```bash
php scripts/reconcile.php
```

Expected:

- 0 mismatch

## 🚨 ALERTS TO WATCH

- failed transactions
- queue backlog
- balance mismatch

## 🔄 DEPLOYMENT

- deploy to staging first
- run tests
- then production

## 🛑 EMERGENCY

- freeze withdrawals
- switch to read-only mode
