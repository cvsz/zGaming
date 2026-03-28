import { createHash } from "node:crypto";
import type { SignedTx, TransferRequest } from "./types";
import { StatelessSigner } from "./signer";

function hex(input: Uint8Array): string {
  return Buffer.from(input).toString("hex");
}

function hashHex(input: string): string {
  return createHash("sha256").update(input).digest("hex");
}

export class EthWallet {
  constructor(
    private readonly signer: StatelessSigner,
    private readonly keyId: string,
  ) {}

  async transfer(request: TransferRequest): Promise<SignedTx> {
    if (request.chain !== "eth") {
      throw new Error(`EthWallet received chain ${request.chain}`);
    }

    const canonical = `eth|${request.from}|${request.to}|${request.asset}|${request.amountAtomic}|${request.nonce}`;
    const sig = await this.signer.sign(this.keyId, Buffer.from(canonical));
    const rawTx = `0x${hex(sig)}${hashHex(canonical).slice(0, 64)}`;

    return {
      chain: "eth",
      rawTx,
      txHash: `0x${hashHex(rawTx)}`,
      signerKeyId: this.keyId,
    };
  }
}
