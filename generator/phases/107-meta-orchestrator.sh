#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail

# ============================================================
# PHASE 107 – META ORCHESTRATOR SCAFFOLD (2026)
# ============================================================

echo "[PHASE 107] META ORCHESTRATOR – Core/Modules/API/Observability bootstrap"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

mkdir -p \
  "$ROOT/core/orchestrator" \
  "$ROOT/core/plugin-loader" \
  "$ROOT/core/config" \
  "$ROOT/core/lifecycle" \
  "$ROOT/modules/ai-engine" \
  "$ROOT/modules/anti-cheat" \
  "$ROOT/modules/risk-engine" \
  "$ROOT/modules/wallet" \
  "$ROOT/modules/game-engine" \
  "$ROOT/modules/user-system" \
  "$ROOT/modules/notification" \
  "$ROOT/api/gateway" \
  "$ROOT/api/rest" \
  "$ROOT/api/graphql" \
  "$ROOT/api/websocket" \
  "$ROOT/observability/tracing" \
  "$ROOT/automation/ci" \
  "$ROOT/automation/cd" \
  "$ROOT/automation/auto-heal" \
  "$ROOT/automation/rollback" \
  "$ROOT/security/audit" \
  "$ROOT/scripts"

if [[ ! -f "$ROOT/core/orchestrator/kernel.ts" ]]; then
  cat > "$ROOT/core/orchestrator/kernel.ts" <<'TS'
import { EventEmitter } from "node:events";

export type RuntimeModule = {
  name: string;
  init(): Promise<void>;
  shutdown(): Promise<void>;
};

export class Kernel {
  private readonly modules = new Map<string, RuntimeModule>();
  private readonly bus = new EventEmitter();

  register(module: RuntimeModule): void {
    if (this.modules.has(module.name)) {
      throw new Error(`Duplicate module registration: ${module.name}`);
    }

    this.modules.set(module.name, module);
    this.bus.emit("module:registered", module.name);
  }

  async boot(): Promise<void> {
    for (const module of this.modules.values()) {
      try {
        await module.init();
        this.bus.emit("module:started", module.name);
      } catch (error) {
        this.bus.emit("module:error", module.name, error);
        throw error;
      }
    }
  }

  async shutdown(): Promise<void> {
    const startedModules = [...this.modules.values()].reverse();

    for (const module of startedModules) {
      await module.shutdown();
      this.bus.emit("module:stopped", module.name);
    }
  }

  getBus(): EventEmitter {
    return this.bus;
  }
}
TS
fi

if [[ ! -f "$ROOT/core/plugin-loader/loader.ts" ]]; then
  cat > "$ROOT/core/plugin-loader/loader.ts" <<'TS'
import { readdir } from "node:fs/promises";
import path from "node:path";

export async function loadModules(directory: string): Promise<unknown[]> {
  const entries = await readdir(directory, { withFileTypes: true });
  const modules: unknown[] = [];

  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.endsWith(".js")) {
      continue;
    }

    const modulePath = path.resolve(directory, entry.name);
    const mod = await import(modulePath);

    if (!mod.default) {
      throw new Error(`Invalid plugin module (missing default export): ${entry.name}`);
    }

    modules.push(mod.default);
  }

  return modules;
}
TS
fi

if [[ ! -f "$ROOT/api/gateway/server.ts" ]]; then
  cat > "$ROOT/api/gateway/server.ts" <<'TS'
import Fastify from "fastify";
import rateLimit from "@fastify/rate-limit";
import jwt from "@fastify/jwt";
import { z } from "zod";

const app = Fastify({ logger: true });

await app.register(rateLimit, {
  max: 100,
  timeWindow: "1 minute",
});

await app.register(jwt, {
  secret: process.env.JWT_SECRET ?? "change-me",
});

const loginSchema = z.object({
  userId: z.string().min(1),
  role: z.enum(["player", "admin", "operator"]),
});

app.decorate("auth", async (request, reply) => {
  try {
    await request.jwtVerify();
  } catch {
    reply.code(401).send({ error: "Unauthorized" });
  }
});

app.get("/health", async () => ({ status: "ok", service: "api-gateway" }));

app.post("/auth/token", async (request) => {
  const payload = loginSchema.parse(request.body);
  const token = await request.server.jwt.sign(payload, { expiresIn: "15m" });

  return {
    accessToken: token,
    tokenType: "Bearer",
  };
});

app.get("/secure", { preHandler: [app.auth] }, async () => ({ data: "protected" }));

await app.listen({ port: 3000, host: "0.0.0.0" });
TS
fi

if [[ ! -f "$ROOT/observability/tracing/README.md" ]]; then
  cat > "$ROOT/observability/tracing/README.md" <<'MD'
# Observability Tracing Bootstrap

This directory is reserved for distributed tracing bootstrap (e.g., OpenTelemetry + Jaeger).

Minimum rollout checklist:

1. Add request trace IDs at API Gateway boundary.
2. Propagate trace context across module boundaries.
3. Export traces to collector with retry + backoff.
4. Alert on elevated error-rate and p99 latency.
MD
fi

if [[ ! -f "$ROOT/scripts/healthcheck.sh" ]]; then
  cat > "$ROOT/scripts/healthcheck.sh" <<'EOF_HEALTH'
#!/usr/bin/env bash
set -Eeuo pipefail

API_URL="${API_URL:-http://localhost:3000/health}"
TIMEOUT="${TIMEOUT:-5}"

if curl -fsS --max-time "$TIMEOUT" "$API_URL" >/dev/null; then
  echo "HEALTHCHECK_OK api=$API_URL"
else
  echo "HEALTHCHECK_FAIL api=$API_URL" >&2
  exit 1
fi
EOF_HEALTH
  chmod +x "$ROOT/scripts/healthcheck.sh"
fi

echo "✅ Phase 107 scaffold complete"
