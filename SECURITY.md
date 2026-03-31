# 🔐 SECURITY POLICY — zGaming

## 📌 Overview

zGaming is a real-money gaming / fintech platform.

Security vulnerabilities may result in:
- financial loss
- user compromise
- regulatory violations

We take security seriously.

## 🚨 REPORTING A VULNERABILITY

DO NOT open public issues for security bugs.

Instead:

- Email: security@yourdomain.com
- Include:
  - description
  - reproduction steps
  - impact assessment

We will respond within 48 hours.

## 🎯 SCOPE

### In Scope
- Wallet / ledger logic
- Authentication / JWT
- API endpoints
- Webhooks / callbacks
- Settlement system
- RNG / provably fair

### Out of Scope
- UI bugs
- non-security config issues

## 🔥 CRITICAL AREAS

### Wallet
- double-spend
- race conditions
- negative balance bypass

### Ledger
- mutation (UPDATE/DELETE)
- integrity break

### Auth
- JWT forgery
- privilege escalation

### Callbacks
- replay attacks
- signature bypass

## 🛡️ SECURITY GUARANTEES

System is designed to ensure:

- append-only ledger
- idempotent transactions
- cryptographic audit logs
- HSM-based signing (abstracted)

## 🧪 TESTING GUIDELINES

Researchers should attempt:

- replay attacks
- concurrent requests
- malformed payloads
- signature tampering

## 💰 REWARD (OPTIONAL)

If running a bounty:

- Critical: $$$$
- High: $$$
- Medium: $$
- Low: $

## ⚠️ LEGAL

Do NOT:
- access other users’ data
- perform destructive actions

Stay within safe testing boundaries.
