# zGaming Upgrade Architecture (2026)

```mermaid
flowchart LR
  A[React Player/Admin UI] -->|Intent + Simulation| B[API Gateway/Auth]
  B -->|JWT + Nonce + chainId| C[Wallet Orchestrator]
  C --> D[ETH Adapter]
  C --> E[SOL Adapter]
  D --> F[(RPC Primary/Fallback)]
  E --> F
  B --> G[Ledger Primitives]
  G -->|Serializable TX + Idempotency| H[(Postgres Ledger)]
  I[Provider Callback] -->|Idempotency Key| G
  J[Installer] --> K[Compliance JSON]
  J --> L[SBOM-lite SPDX]
  J --> M[SHA256SUMS + Signature]
  N[Observability] --> B
  N --> G
```

## Notes
- Wallet orchestration remains stateless at API layer; signing key material is abstracted via provider interface.
- Ledger path is append-only with immutable transaction hash to support post-incident forensics.
- Installer pipeline emits auditable artifacts for regulator handover.
