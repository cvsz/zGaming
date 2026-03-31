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

/**
 * Helper for non-hardcoded secret loading from environment.
 * Accepts a map of keyId => env var name.
 */
export function createEnvBackedHmacProvider(keyEnvMap: Record<string, string>): HmacSignProvider {
  const keyMap: Record<string, string> = {};

  for (const [keyId, envName] of Object.entries(keyEnvMap)) {
    const value = process.env[envName];
    if (!value) {
      throw new Error(`Missing signing secret env var: ${envName} for keyId=${keyId}`);
    }
    keyMap[keyId] = value;
  }

  return new HmacSignProvider(keyMap);
}

export class StatelessSigner {
  constructor(private readonly provider: SignProvider) {}

  sign(keyId: string, payload: Uint8Array): Promise<Uint8Array> {
    return this.provider.sign({ keyId, payload });
  }
}
