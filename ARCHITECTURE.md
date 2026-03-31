# 🏗️ ARCHITECTURE — zGaming

## 📌 Overview

zGaming is a financial-grade gaming platform with:

- ledger-based wallet
- queue-based settlement
- AML/KYC integration
- audit logging
- HSM abstraction

## 💰 WALLET SYSTEM

### Design

- ledger = source of truth
- balance = derived

### Guarantees

- append-only
- idempotent
- ACID transactions

## 🔄 SETTLEMENT ENGINE

- DB-backed queue
- idempotent workers
- retry-safe

Flow:

deposit → queue → process → ledger

## 🔐 SECURITY MODEL

### HSM Abstraction
- no private keys in app
- signing externalized

### Zero Trust
- all services authenticate
- signed tokens

## 🧾 AUDIT SYSTEM

- append-only logs
- hash chain integrity

## ⚠️ FRAUD / AML

- rule-based detection
- STR generation

## 🌍 SCALING

- stateless services
- DB = source of truth
- idempotent operations

## 🔗 TRACEABILITY

Every transaction has:
- transaction_id

Traceable across:
- wallet
- settlement
- audit logs

## 🚨 FAILURE MODES

System is designed to:

- fail safe (no money loss)
- detect inconsistencies
- allow reconciliation
