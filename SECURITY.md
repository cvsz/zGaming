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


## 📦 Dependency Security Snapshot (April 3, 2026)

The repository currently resolves `@fastify/jwt@10.0.0` which pulls in `fast-jwt@6.1.0`.

Verification commands run in project root:

- `pnpm update fast-jwt` → already up to date
- `pnpm why fast-jwt` → `@fastify/jwt 10.0.0 -> fast-jwt 6.1.0`
- `pnpm audit` → reports GHSA-mvf2-f6gm-w987 affecting `fast-jwt <= 6.1.0`

### Current Risk Posture

As of April 3, 2026, `pnpm audit` still flags a critical advisory for `fast-jwt` with no patched version published in the advisory feed.

Because this project depends on `@fastify/jwt`, remediation may require either:

1. an upstream `@fastify/jwt` release that adopts a patched `fast-jwt`, or
2. temporary risk controls (strict algorithm allowlisting, strong claim validation, and key-rotation controls) until a patched release is available.

Track: <https://github.com/advisories/GHSA-mvf2-f6gm-w987>
