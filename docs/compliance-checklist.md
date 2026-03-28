# zGaming Compliance Checklist (2026)

## Deterministic Build Controls
- [x] `installer/zgaming-ultra-installer.sh` generates immutable manifests (`repo-manifest.sha256`).
- [x] Release packaging uses normalized zip metadata (`zip -X`) and `SOURCE_DATE_EPOCH`.
- [x] `SHA256SUMS` + signature artifact generated in `installer/artifacts/release/`.

## Security Baseline
- [x] PHP login endpoint enforces nonce format, signature validation, chainId capture, and short-lived JWT.
- [x] Kubernetes deployment uses non-root, read-only filesystem, dropped Linux capabilities.
- [x] ConfigMap/Secret split for operational values and sensitive credentials.
- [x] NetworkPolicy baseline deny configured for API pods.

## Wallet & Ledger Controls
- [x] Multi-chain wallet adapters (ETH/SOL) enforce `chainId` allow-list.
- [x] Stateless signer abstraction maintained for KMS/HSM replacement.
- [x] Idempotent ledger writes produce immutable SHA256 ledger hash.
- [x] Callback replay resistance validated via chaos callback storm test script.

## Observability & Reliability
- [x] Healthcheck validates app endpoint and OTEL collector reachability.
- [x] Chaos script simulates double-callback and retry-storm behavior.
- [x] Installer emits structured JSONL logs + audit metadata.

## Reporting Artifacts
- [x] Compliance JSON: `installer/reports/compliance-report.json`
- [x] Audit JSON: `installer/reports/audit-report.json`
- [x] SBOM-lite SPDX: `installer/artifacts/sbom-lite.spdx.json`
- [x] Workflow plan: `installer/artifacts/workflow-plan.txt`
