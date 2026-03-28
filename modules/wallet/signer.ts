import { createHmac } from "node:crypto";
import type { SignProvider, SignRequest } from "./types";

/**
 * Development-only signer provider.
 * Production should replace this with AWS KMS, GCP KMS, Azure KeyVault, or HSM.
 */
export class HmacSignProvider implements SignProvider {
  constructor(private readonly keyMap: Record<string, string>) {}

  async sign(request: SignRequest): Promise<Uint8Array> {
    const secret = this.keyMap[request.keyId];

    if (!secret) {
      throw new Error(`Unknown keyId: ${request.keyId}`);
    }

    return createHmac("sha256", secret).update(request.payload).digest();
  }
}

export class StatelessSigner {
  constructor(private readonly provider: SignProvider) {}

  sign(keyId: string, payload: Uint8Array): Promise<Uint8Array> {
    return this.provider.sign({ keyId, payload });
  }
}
