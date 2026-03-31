import { createHash, randomBytes, timingSafeEqual, createHmac } from "node:crypto";

export interface SeedCommitment {
  serverSeed: string;
  serverSeedHash: string;
  createdAt: string;
}

export function createServerSeedCommitment(seedBytes = 32): SeedCommitment {
  const serverSeed = randomBytes(seedBytes).toString("hex");
  const serverSeedHash = sha256(serverSeed);

  return { serverSeed, serverSeedHash, createdAt: new Date().toISOString() };
}

export function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export function verifyServerSeedReveal(revealedSeed: string, committedHash: string): boolean {
  const calculated = Buffer.from(sha256(revealedSeed), "hex");
  const committed = Buffer.from(committedHash, "hex");

  if (calculated.length !== committed.length) {
    return false;
  }

  return timingSafeEqual(calculated, committed);
}

export function buildSeedTrace(serverSeed: string, clientSeed: string, nonce: number): string {
  return `${sha256(serverSeed)}:${clientSeed}:${nonce}`;
}

export function computeProvablyFairRoll(serverSeed: string, clientSeed: string, nonce: number): string {
  return createHmac("sha256", serverSeed).update(`${clientSeed}:${nonce}`).digest("hex");
}
