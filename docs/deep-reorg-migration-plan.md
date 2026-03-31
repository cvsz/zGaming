# Deep Re-organization: Clean/Hexagonal Migration Plan

## Target Monorepo Layout (pnpm + Turbo)

```text
zGaming/
├── apps/
│   └── frontend-wallet/               # Stateless wallet-driven frontend (UI only)
├── services/
│   └── api-gateway/                   # Inbound adapters (HTTP/Webhook/Auth)
├── packages/
│   ├── domain-core/                   # Business entities, use-cases, policies
│   ├── wallet-domain/                 # Intent model + transaction policies
│   └── infrastructure-rpc/            # RPC adapters and fallback strategy
├── factory/
│   ├── scout/                         # Trend/content scouting module
│   ├── render/                        # Rendering orchestration module
│   └── publisher/                     # Distribution/publishing module
├── modules/                           # Transitional legacy modules
├── generator/                         # Existing deterministic generator
├── docs/
├── turbo.json
├── pnpm-workspace.yaml
└── package.json
```

## Clean Architecture Boundaries

- **Domain (pure):** no framework, no network calls, deterministic logic only.
- **Application services:** orchestrate domain use-cases using ports.
- **Inbound adapters:** HTTP/API/queue handlers mapped into commands.
- **Outbound adapters:** RPC, storage, provider SDK clients behind interfaces.

## Migration Plan

### Phase 1 — Workspace bootstrap
1. Introduce `pnpm-workspace.yaml`, `package.json`, `turbo.json`.
2. Create isolated roots for `apps`, `services`, `packages`, and `factory` modules.
3. Keep `modules/*` as compatibility bridge during migration.

### Phase 2 — Wallet decoupling
1. Move intent rendering and wallet DTOs into `packages/wallet-domain`.
2. Keep frontend stateless: wallet signatures only in user wallet context.
3. Prohibit private key handling in backend services.

### Phase 3 — RPC port/adapters
1. Define `RpcPort` in domain/application layer.
2. Implement fallback adapters in infrastructure package.
3. Route all chain interactions through `RpcEndpointPool` abstraction.

### Phase 4 — Autonomous Content Factory isolation
1. Split Scout, Render, Publisher into independent packages.
2. Define explicit contracts/events between modules.
3. Apply separate scaling and queue policies per module.

### Phase 5 — Legacy extraction
1. Migrate remaining logic from `modules/*` into `packages/*` + `services/*`.
2. Mark old paths deprecated and remove after parity tests.
3. Enforce import rules (`domain` cannot import `infra`).

## Expected Outcomes

- Strict separation of concerns with port/adapter boundaries.
- Faster incremental builds/tests via Turbo pipeline graph.
- Scalability readiness for independent factory module deployment.
