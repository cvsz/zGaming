# Deep Source Code Audit — March 31, 2026

## Scope & Methodology
- Ran deterministic repository logic scan (`npm run -s audit:logic`).
- Ran unit/integration test suite (`npm test -- --test-reporter=spec`).
- Ran dependency vulnerability scan (`npm audit --audit-level=high --json`).
- Reviewed authentication, webhook verification, signer, and generated backend phase scripts for high-risk trust boundaries.
- Performed pattern scans for dangerous execution sinks and secret handling references.

## Executive Summary
- **Overall posture:** Good baseline for dependency hygiene and deterministic tooling checks.
- **Most important risks:**
  1. **Token minting endpoint allows caller-selected privilege claims** in `api/gateway/server.ts`.
  2. **Webhook signature validation is time-bounded but replayable** inside window.
  3. **SIWE-like login flow states anti-replay, but does not persist nonce usage**.
- **Immediate recommendation:** Prioritize auth hardening in API gateway before production exposure.

## Findings

### 1) Critical — Privilege claim injection via `/auth/token`
**Evidence**
- `POST /auth/token` accepts `userId` and `role` directly from request body and signs JWT without authenticating caller identity first.
- Allowed roles include `admin` and `operator`.

**Impact**
- Any unauthenticated caller can mint a valid bearer token with elevated role claims.
- This is an account/authorization boundary break and should be treated as release-blocking.

**Recommended Fix**
- Require prior authentication challenge (wallet/signature or upstream IdP assertion) before token issuance.
- Remove caller-controlled `role`; derive role from authoritative server-side identity store.
- Add issuer/audience verification middleware across protected routes and rotate secrets if exposed.

### 2) High — Webhook replay is still possible within validity window
**Evidence**
- Signature check validates HMAC and timestamp freshness (`maxAgeMs` default 5 minutes), but no nonce/idempotency key store is used.

**Impact**
- Captured signed payloads can be replayed repeatedly during valid window, potentially re-triggering side effects.

**Recommended Fix**
- Require event ID + timestamp + signature and enforce one-time use in a short-lived store (Redis/Postgres).
- Bind signature to canonical headers and content-type to reduce ambiguity.

### 3) Medium — Claimed anti-replay in login endpoint is format-only
**Evidence**
- `backend/api/login.php` comments claim deterministic anti-replay.
- Nonce is format-validated and included in signature, but nonce uniqueness is never persisted/checked.

**Impact**
- Identical signed login payload can be replayed until `SESSION_TTL_SECONDS` expires.

**Recommended Fix**
- Store nonce hash (or JTI) and reject reuse until expiration.
- Consider per-wallet nonce issuance and server challenge flow.

### 4) Medium — Test coverage appears very narrow for repo size
**Evidence**
- Root `npm test` executes only 5 tests across two files under `tests/`.

**Impact**
- High chance of logic regressions in untested modules (gateway/auth/ops scripts/generator outputs).

**Recommended Fix**
- Add minimum coverage gate and CI targets for gateway auth/webhook and backend login paths.
- Add negative tests for privilege escalation and replay attempts.

### 5) Low — Generator phase scripts contain duplicated shell preamble / inconsistent strictness
**Evidence**
- Some phase scripts include duplicate shebang + both guarded and local strict mode preambles (`set -Eeuo pipefail` and `set -euo pipefail`).

**Impact**
- Low direct security impact, but increases maintenance drift and static analysis noise.

**Recommended Fix**
- Normalize phase template preamble to one source-of-truth guard style.

## Positive Signals
- `npm audit` reports **0 known vulnerabilities** at `high+` level in current dependency graph.
- Logic scan reports no failing checks.
- Gateway and backend include secret checks and HMAC-based signing primitives.

## Prioritized Remediation Plan
- **P0 (this sprint):** lock down `/auth/token` issuance flow and remove client-controlled privileged claims.
- **P0 (this sprint):** implement webhook replay protection with idempotency key persistence.
- **P1:** enforce nonce/JTI one-time usage in login endpoint.
- **P1:** add auth threat-model tests to CI.
- **P2:** clean generator phase preambles and standardize shell safety headers.

## Commands Executed
- `npm run -s audit:logic`
- `npm test -- --test-reporter=spec`
- `npm audit --audit-level=high --json`
- `npm run -s lint`
- `rg -n "(eval\(|new Function\(|child_process|exec\()" --glob '!node_modules/**'`
- `rg -n "(TODO|FIXME|HACK|XXX)" --glob '!node_modules/**'`
- `rg -n "(password|secret|api[_-]?key|token)\s*[:=]" --glob '!node_modules/**'`
