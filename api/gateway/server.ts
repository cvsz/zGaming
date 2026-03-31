import Fastify from "fastify";
import rateLimit from "@fastify/rate-limit";
import jwt from "@fastify/jwt";
import { z } from "zod";
import { verifyWebhookSignature } from "./webhook-auth";

async function startServer(): Promise<void> {
  const app = Fastify({ logger: true });
  const jwtSecret = process.env.JWT_SECRET;
  const internalWebhookSecret = process.env.INTERNAL_WEBHOOK_SECRET;

  if (!jwtSecret || jwtSecret === "change-me") {
    throw new Error("JWT_SECRET must be set to a strong non-default value");
  }

  if (!internalWebhookSecret) {
    throw new Error("INTERNAL_WEBHOOK_SECRET must be configured");
  }

  await app.register(rateLimit, {
    max: 100,
    timeWindow: "1 minute",
  });

  await app.register(jwt, {
    secret: jwtSecret,
  });

  const loginSchema = z.object({
    userId: z.string().min(1),
    role: z.enum(["player", "admin", "operator"]),
  });

  app.get("/health", async () => ({ status: "ok", service: "api-gateway" }));

  app.post("/auth/token", async (request: any) => {
    const payload = loginSchema.parse(request.body);
    const token = await request.server.jwt.sign(payload, { expiresIn: "15m" });

    return {
      accessToken: token,
      tokenType: "Bearer",
    };
  });

  app.post("/internal/webhook", async (request: any, reply: any) => {
    const signature = request.headers["x-internal-signature"];
    const timestamp = request.headers["x-internal-timestamp"];

    if (typeof signature !== "string" || typeof timestamp !== "string") {
      return reply.code(401).send({ error: "Missing webhook signature headers" });
    }

    const payload = typeof request.body === "string" ? request.body : JSON.stringify(request.body ?? {});
    const valid = verifyWebhookSignature({
      payload,
      timestamp,
      signature,
      secret: internalWebhookSecret,
    });

    if (!valid) {
      return reply.code(401).send({ error: "Invalid webhook signature" });
    }

    return { accepted: true };
  });

  app.get(
    "/secure",
    {
      preHandler: async (request: any, reply: any) => {
        try {
          await request.jwtVerify();
        } catch {
          return reply.code(401).send({ error: "Unauthorized" });
        }
      },
    },
    async () => ({ data: "protected" }),
  );

  await app.listen({ port: 3000, host: "0.0.0.0" });
}

void startServer();
