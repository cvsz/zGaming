# zGaming Production Readiness Audit — 2026-03-31

## 1) Top Critical Risks (Top 10)
1. **Privilege-escalation token minting in API gateway** (`/auth/token` accepted arbitrary `role` from unauthenticated caller).
2. **Webhook replay attacks** due to missing event-id deduplication storage.
3. **Login nonce replay window** in PHP auth path (nonce format-check existed, but nonce reuse was previously not consumed).
4. **Provably fair seed disclosure risk** (raw server seed leaked in audit trace, enabling forward prediction if revealed before round finalization).
5. **Runtime signing model not safe for funds** (`HmacSignProvider` uses app-layer secrets rather than KMS/HSM with transaction-domain separation).
6. **Phase orchestration non-resumable** (no durable phase completion state, reruns can reapply infrastructure mutations).
7. **Hardcoded NGINX host port and single-instance assumptions** (`:80` conflict and startup fragility).
8. **Weak separation between stacks** (TS gateway + PHP auth implement overlapping identity semantics and claim issuance policies).
9. **No durable idempotency contract for financial side-effects** (webhook and settlement workflows can be repeated under transient failures).
10. **Missing hard fail on secret quality lifecycle** (defaults and runtime-generated secrets still present in bootstrap scripts).

## 2) Security Vulnerabilities (with exploits + fixes)

### A. Auth bypass / privilege escalation
- **Where:** `api/gateway/server.ts`.
- **Exploit scenario:** attacker posts `{ "userId":"x", "role":"admin" }` to `/auth/token`, gets signed admin token.
- **Fix implemented:**
  - Added `INTERNAL_ADMIN_TOKEN` requirement.
  - Added `x-internal-auth` guard for privileged role minting.
  - Kept player mint path but blocks admin/operator without internal secret.

### B. Webhook replay attack
- **Where:** `api/gateway/webhook-auth.ts`, `api/gateway/server.ts`.
- **Exploit scenario:** intercepted valid signed payload replayed multiple times within timestamp tolerance to duplicate ledger-affecting actions.
- **Fix implemented:**
  - Require `x-internal-event-id`.
  - Validate strict event-id format in signature verifier path.
  - Add in-memory replay cache with TTL; duplicate event id returns `409`.
- **Remaining hardening:** move dedupe store to Redis/Postgres for multi-instance deployments.

### C. PHP login replay
- **Where:** `backend/api/login.php`.
- **Exploit scenario:** attacker replays same signed wallet login payload within TTL to mint multiple valid tokens.
- **Fix implemented:**
  - Added file-backed nonce consume with `flock` lock and expiry pruning.
  - Reject reused nonce hash as `NONCE_REPLAY_DETECTED`.

### D. Provably fair forward-prediction risk
- **Where:** `modules/game-engine/provably-fair.ts` + engine seed-trace usage.
- **Exploit scenario:** if seed trace leaks raw `serverSeed` before reveal point, player can reconstruct deterministic RNG outcomes.
- **Fix implemented:**
  - `buildSeedTrace()` now emits `sha256(serverSeed)` instead of raw seed.

### E. Signing boundary weakness (not fully fixed in this patch)
- **Where:** `modules/wallet/signer.ts`, `modules/wallet/eth.ts`, `modules/wallet/sol.ts`.
- **Exploit scenario:** application compromise exposes HMAC key material and allows arbitrary transfer signing outside MPC/KMS controls.
- **Code-level remediation target:**
  - Replace `HmacSignProvider` with KMS-backed asymmetric signer.
  - Include chain-specific domain separator + typed structured payload signing.
  - Enforce policy engine pre-sign checks (asset allow-list, amount caps, per-key role).

## 3) Architecture Problems
- **Identity split-brain:** gateway and PHP backend both mint/validate auth semantics without a single trust authority.
- **Cross-language duplication:** wallet/auth logic duplicated across TS and PHP increases divergence risk.
- **State model mismatch:** deterministic game/wallet modules are stateless in code but operational workflows (replay prevention, idempotency) require persistent shared state.
- **Orchestrator coupling:** generator phases assume mutable global host state and direct Docker CLI side effects.

## 4) DevOps / Docker Fixes
- Added explicit Linux credsStore bug detection (already in some phases) and normalized port conflict safety in NGINX phase.
- NGINX phase now supports `NGINX_HOST_PORT` and fail-fasts when port is occupied by non-managed process.
- Added restart policy (`unless-stopped`) for better crash recovery consistency.
- Recommended follow-up:
  - Add compose healthchecks and `depends_on: condition: service_healthy`.
  - Run `docker compose config` in guard phase to catch unresolved env vars.

## 5) Generator System Redesign
- **Implemented now:** persistent phase completion state in `.meta-master-state/` and skip-on-rerun behavior (`MM_FORCE_RUN_ALL=1` override).
- **Target design:**
  1. Add explicit `PHASE_DEPS` DAG.
  2. Validate DAG acyclic graph pre-run.
  3. Store per-phase checksum + version for drift detection.
  4. Resume from failed phase with invariant checks.
  5. Transactional phase contracts (`plan`, `apply`, `verify`).

## 6) Code Bugs (specific files/functions)
- `api/gateway/server.ts` — role minting trust bug, webhook replay missing dedupe, privileged paths lacked internal auth gate.
- `api/gateway/webhook-auth.ts` — replay/identity signal incomplete without event-id validation.
- `backend/api/login.php` — anti-replay comment did not match behavior prior to nonce consumption logic.
- `modules/game-engine/provably-fair.ts` — seed trace leaked sensitive entropy.
- `generator/phases/70-nginx.sh` — fixed host-port hardcoding and non-idempotent restart behavior.
- `generator/meta-master.sh` — lacked resumable execution state and rerun controls.

## 7) Step-by-step Stabilization Plan
1. **P0 now:** deploy this patch, rotate JWT/internal webhook/admin provisioning secrets.
2. **P0 now:** enforce single auth authority (gateway delegates token issuance to backend auth service or vice versa).
3. **P0 now:** move webhook/event replay cache to shared Redis with strict TTL and unique constraint.
4. **P0 now:** implement idempotency keys for all wallet/settlement callbacks with DB uniqueness constraints.
5. **P1:** migrate wallet signing to HSM/KMS with per-chain key segregation and policy controls.
6. **P1:** add deterministic integration tests for replay, role escalation, and nonce reuse.
7. **P1:** introduce compose health checks, service dependency health gating, and preflight port/env checks in phase 00.
8. **P2:** refactor generator into DAG with state backend + verification hooks.
9. **P2:** unify audit trail schema (wallet, game-engine, auth, callbacks) with tamper-evident ledger hashing.
10. **Release gate:** block production launch until external pen test confirms no privilege escalation/replay vectors.
