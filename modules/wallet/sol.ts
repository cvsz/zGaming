import { createHash } from "node:crypto";
import type { SignedTx, TransferRequest } from "./types";
import { StatelessSigner } from "./signer";

function base58Like(input: Uint8Array): string {
  return Buffer.from(input).toString("base64url");
}

function hashHex(input: string): string {
  return createHash("sha256").update(input).digest("hex");
}

export class SolWallet {
  constructor(
    private readonly signer: StatelessSigner,
    private readonly keyId: string,
  ) {}

  async transfer(request: TransferRequest): Promise<SignedTx> {
    if (request.chain !== "sol") {
      throw new Error(`SolWallet received chain ${request.chain}`);
    }

    const canonical = `sol|${request.from}|${request.to}|${request.asset}|${request.amountAtomic}|${request.nonce}`;
    const sig = await this.signer.sign(this.keyId, Buffer.from(canonical));
    const rawTx = base58Like(sig);

    return {
      chain: "sol",
      rawTx,
      txHash: hashHex(rawTx),
      signerKeyId: this.keyId,
    };
  }
}
