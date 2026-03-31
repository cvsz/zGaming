import { createHmac } from "node:crypto";

/**
 * Deterministic RNG using HMAC(serverSeed, clientSeed:nonce).
 * This is designed for replayability in audit/dispute pipelines.
 */
export class DeterministicRng {
  private nonce: number;

  constructor(
    private readonly serverSeed: string,
    private readonly clientSeed: string,
    startingNonce: number,
  ) {
    if (!Number.isInteger(startingNonce) || startingNonce < 0) {
      throw new Error(`Invalid starting nonce: ${startingNonce}`);
    }
    this.nonce = startingNonce;
  }

  nextFloat(): number {
    const message = `${this.clientSeed}:${this.nonce++}`;
    const digest = createHmac("sha256", this.serverSeed).update(message).digest();
    const int53 = Number((BigInt("0x" + digest.subarray(0, 8).toString("hex")) >> 11n) & 0x1fffffffffffffn);

    return int53 / Number(0x1fffffffffffffn);
  }

  nextInt(maxExclusive: number): number {
    if (!Number.isInteger(maxExclusive) || maxExclusive <= 0) {
      throw new Error(`Invalid maxExclusive: ${maxExclusive}`);
    }

    return Math.floor(this.nextFloat() * maxExclusive);
  }

  getCurrentNonce(): number {
    return this.nonce;
  }
}
