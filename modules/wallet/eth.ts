import { createHash } from "node:crypto";
import type { ChainRuntimeConfig, SignedTx, TransferRequest } from "./types";
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
    private readonly config: ChainRuntimeConfig,
  ) {}

  async transfer(request: TransferRequest): Promise<SignedTx> {
    if (request.chain !== "eth") {
      throw new Error(`EthWallet received chain ${request.chain}`);
    }

    if (!this.config.supportedChainIds.includes(request.chainId)) {
      throw new Error(`Unsupported ETH chainId ${request.chainId}`);
    }

    const rpcEndpoint = this.config.rpcEndpoints[0];
    if (!rpcEndpoint) {
      throw new Error("ETH rpcEndpoints is empty");
    }

    const canonical = `eth|${request.chainId}|${request.from}|${request.to}|${request.asset}|${request.amountAtomic}|${request.nonce}`;
    const sig = await this.signer.sign(this.keyId, Buffer.from(canonical));
    const rawTx = `0x${hex(sig)}${hashHex(canonical).slice(0, 64)}`;

    return {
      chain: "eth",
      chainId: request.chainId,
      rawTx,
      txHash: `0x${hashHex(rawTx)}`,
      signerKeyId: this.keyId,
      rpcEndpoint,
      intent: {
        summary: `Transfer ${request.amountAtomic} ${request.asset} on ETH:${request.chainId}`,
        amountAtomic: request.amountAtomic.toString(),
        asset: request.asset,
        from: request.from,
        to: request.to,
        chain: "eth",
        chainId: request.chainId,
      },
    };
  }
}
