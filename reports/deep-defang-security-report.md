# Deep Defang & Security Hardening Report

Generated: 2026-03-31 (UTC)

## Scope
- Secret exposure/hardcoded credentials patterns
- Custody model validation
- RPC abstraction with fallback
- Internal webhook authenticity
- Least-privilege posture at service boundaries

## Actions Executed

1. **Neutralized hardcoded-secret risk path**
   - Replaced direct key map usage pattern in wallet construction with injected `SignProvider`.
   - Added `createEnvBackedHmacProvider` helper to enforce env-based secret loading.

2. **Non-custodial alignment**
   - Wallet orchestration now accepts abstract signer provider; backend no longer requires direct private-key material in object config.
   - Design supports KMS/HSM providers through `SignProvider` interface.

3. **RPC abstraction with fallback**
   - Added `RpcEndpointPool` abstraction and deterministic fallback selection.
   - ETH/SOL wallet modules now resolve endpoint via pool instead of direct index access.

4. **Internal webhook signing hardening**
   - Added HMAC signature verification with timestamp freshness checks and constant-time comparison.
   - Added `/internal/webhook` route that rejects unsigned/expired/invalid requests.

5. **Least-privilege service behavior**
   - JWT and internal webhook secret are required at startup.
   - Gateway route validation blocks unauthenticated access before business handling.

## Residual Risks / Follow-ups

- Demo HMAC signing remains development-only and should be replaced by cloud KMS/HSM provider in production.
- Need repo-wide secret scanning in CI (e.g., gitleaks/trufflehog) for continuous enforcement.
- Fine-grained service identities (mTLS + per-service key rotation) should be added for full zero-trust posture.
