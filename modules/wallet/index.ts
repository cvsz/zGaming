import { EthWallet } from "./eth";
import { SolWallet } from "./sol";
import { StatelessSigner } from "./signer";
import { simulateTransfer } from "./simulation";
import type { ChainRuntimeConfig, SignProvider, SignedTx, TransferRequest } from "./types";

export interface OmniWalletConfig {
  signerProvider: SignProvider;
  ethKeyId: string;
  solKeyId: string;
  eth: ChainRuntimeConfig;
  sol: ChainRuntimeConfig;
}

export class OmniWallet {
  private readonly eth: EthWallet;
  private readonly sol: SolWallet;
  private readonly ethConfig: ChainRuntimeConfig;
  private readonly solConfig: ChainRuntimeConfig;

  constructor(config: OmniWalletConfig) {
    const signer = new StatelessSigner(config.signerProvider);
    this.eth = new EthWallet(signer, config.ethKeyId, config.eth);
    this.sol = new SolWallet(signer, config.solKeyId, config.sol);
    this.ethConfig = config.eth;
    this.solConfig = config.sol;
  }

  transfer(request: TransferRequest): Promise<SignedTx> {
    return request.chain === "eth" ? this.eth.transfer(request) : this.sol.transfer(request);
  }

  simulateTransfer(request: TransferRequest): string {
    const config = request.chain === "eth" ? this.ethConfig : this.solConfig;
    const result = simulateTransfer(request, config);
    return result.ok
      ? `${request.chain.toUpperCase()} simulation passed with estimatedGas=${result.estimatedGas.toString()} predictedFee=${result.predictedFee.toString()}`
      : `${request.chain.toUpperCase()} simulation failed: ${result.reason}`;
  }
}

export * from "./types";
export * from "./signer";
export * from "./eth";
export * from "./sol";
export * from "./rpc";
export * from "./simulation";
export * from "./chain-validation";
export * from "./wagmi-viem";
