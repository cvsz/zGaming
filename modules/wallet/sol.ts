import { createHash } from "node:crypto";
import type { ChainRuntimeConfig, SignedTx, TransferRequest } from "./types";
import { StatelessSigner } from "./signer";
import { RpcEndpointPool } from "./rpc";
import { validateChainId } from "./chain-validation";
import { simulateTransfer } from "./simulation";

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
    private readonly config: ChainRuntimeConfig,
  ) {}

  async transfer(request: TransferRequest): Promise<SignedTx> {
    if (request.chain !== "sol") {
      throw new Error(`SolWallet received chain ${request.chain}`);
    }

    validateChainId("sol", request.chainId, this.config);

    const simulation = simulateTransfer(request, this.config);
    if (!simulation.ok) {
      throw new Error(`SOL simulation failed: ${simulation.reason}`);
    }

    const rpcPool = new RpcEndpointPool(this.config.rpcEndpoints);
    const rpcResolution = rpcPool.resolve(this.config.startRpcAttempt ?? 0);

    const canonical = `sol|${request.chainId}|${request.from}|${request.to}|${request.asset}|${request.amountAtomic}|${request.nonce}`;
    const sig = await this.signer.sign(this.keyId, Buffer.from(canonical));
    const rawTx = base58Like(sig);

    return {
      chain: "sol",
      chainId: request.chainId,
      rawTx,
      txHash: hashHex(rawTx),
      signerKeyId: this.keyId,
      rpcEndpoint: rpcResolution.endpoint,
      rpcAttempt: rpcResolution.attempt,
      simulation,
      intent: {
        summary: `Transfer ${request.amountAtomic} ${request.asset} on SOL:${request.chainId}`,
        amountAtomic: request.amountAtomic.toString(),
        asset: request.asset,
        from: request.from,
        to: request.to,
        chain: "sol",
        chainId: request.chainId,
      },
    };
  }
}
