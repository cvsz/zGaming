import Fastify from "fastify";
import rateLimit from "@fastify/rate-limit";
import jwt from "@fastify/jwt";
import { randomUUID, createHash } from "node:crypto";
import { z } from "zod";
import { Pool } from "pg";
import { verifyWebhookSignature } from "./webhook-auth";

async function startServer(): Promise<void> {
  const app = Fastify({ logger: true });
  const jwtSecret = process.env.JWT_SECRET;
  const internalWebhookSecret = process.env.INTERNAL_WEBHOOK_SECRET;
  const adminProvisioningSecret = process.env.INTERNAL_ADMIN_TOKEN;
  const jwtIssuer = process.env.JWT_ISSUER;
  const jwtAudience = process.env.JWT_AUDIENCE;
  const pool = process.env.DATABASE_URL ? new Pool({ connectionString: process.env.DATABASE_URL }) : null;
  const seenWebhookEvents = new Map<string, number>();

  if (!jwtSecret || jwtSecret === "change-me") {
    throw new Error("JWT_SECRET must be set to a strong non-default value");
  }

  if (!internalWebhookSecret) {
    throw new Error("INTERNAL_WEBHOOK_SECRET must be configured");
  }
  if (!adminProvisioningSecret) {
    throw new Error("INTERNAL_ADMIN_TOKEN must be configured");
  }
  if (!jwtIssuer) {
    throw new Error("JWT_ISSUER must be configured");
  }
  if (!jwtAudience) {
    throw new Error("JWT_AUDIENCE must be configured");
  }

  await app.register(rateLimit, {
    max: 100,
    timeWindow: "1 minute",
  });

  await app.register(jwt, {
    secret: jwtSecret,
  });

  if (pool) {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS webhook_events (
        event_id TEXT PRIMARY KEY,
        payload_hash CHAR(64) NOT NULL,
        received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
  }

  const loginSchema = z.object({
    userId: z.string().min(1),
    role: z.enum(["player", "admin", "operator"]),
  });

  app.get("/health", async () => ({ status: "ok", service: "api-gateway" }));

  app.post("/auth/token", async (request: any) => {
    const payload = loginSchema.parse(request.body);
    const internalAuthHeader = request.headers["x-internal-auth"];
    const isPrivilegedRole = payload.role !== "player";

    if (isPrivilegedRole && internalAuthHeader !== adminProvisioningSecret) {
      const err: Error & { statusCode?: number } = new Error(
        "privileged role minting requires x-internal-auth",
      );
      err.statusCode = 401;
      throw err;
    }
    const token = await request.server.jwt.sign(payload, {
      expiresIn: "15m",
      issuer: jwtIssuer,
      audience: jwtAudience,
      jti: randomUUID(),
      sub: payload.userId,
    });

    return {
      accessToken: token,
      tokenType: "Bearer",
    };
  });

  app.post("/internal/webhook", async (request: any, reply: any) => {
    const signature = request.headers["x-internal-signature"];
    const timestamp = request.headers["x-internal-timestamp"];
    const eventId = request.headers["x-internal-event-id"];

    if (typeof signature !== "string" || typeof timestamp !== "string" || typeof eventId !== "string") {
      return reply.code(401).send({ error: "Missing webhook signature headers" });
    }

    const payload = typeof request.body === "string" ? request.body : JSON.stringify(request.body ?? {});
    const valid = verifyWebhookSignature({
      payload,
      timestamp,
      signature,
      secret: internalWebhookSecret,
      eventId,
      maxAgeMs: 5 * 60 * 1000,
    });

    if (!valid) {
      return reply.code(401).send({ error: "Invalid webhook signature" });
    }

    const payloadHash = createHash("sha256").update(payload).digest("hex");

    if (pool) {
      const inserted = await pool.query(
        `INSERT INTO webhook_events (event_id, payload_hash)
         VALUES ($1, $2)
         ON CONFLICT (event_id) DO NOTHING
         RETURNING event_id`,
        [eventId, payloadHash],
      );

      if ((inserted.rowCount ?? 0) === 0) {
        return reply.code(409).send({ error: "Replay detected for webhook event id" });
      }
    } else {
      const now = Date.now();
      const ttlMs = 10 * 60 * 1000;
      const existingTs = seenWebhookEvents.get(eventId);
      if (existingTs && now - existingTs < ttlMs) {
        return reply.code(409).send({ error: "Replay detected for webhook event id" });
      }
      seenWebhookEvents.set(eventId, now);
      for (const [id, ts] of seenWebhookEvents.entries()) {
        if (now - ts > ttlMs) {
          seenWebhookEvents.delete(id);
        }
      }
    }

    return { accepted: true, idempotent: true };
  });

  app.get(
    "/secure",
    {
      preHandler: async (request: any, reply: any) => {
        try {
          await request.jwtVerify({
            allowedIss: jwtIssuer,
            allowedAud: jwtAudience,
          });
        } catch {
          return reply.code(401).send({ error: "Unauthorized" });
        }
      },
    },
    async () => ({ data: "protected", requestId: randomUUID() }),
  );

  await app.listen({ port: 3000, host: "0.0.0.0" });
}

void startServer();
