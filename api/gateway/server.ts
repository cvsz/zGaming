import Fastify from "fastify";
import rateLimit from "@fastify/rate-limit";
import jwt from "@fastify/jwt";
import { z } from "zod";

const app = Fastify({ logger: true });
const jwtSecret = process.env.JWT_SECRET;

if (!jwtSecret || jwtSecret === "change-me") {
  throw new Error("JWT_SECRET must be set to a strong non-default value");
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

app.decorate("auth", async (request, reply) => {
  try {
    await request.jwtVerify();
  } catch {
    return reply.code(401).send({ error: "Unauthorized" });
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
