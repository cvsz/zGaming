import { EthWallet } from "./eth";
import { SolWallet } from "./sol";
import { StatelessSigner } from "./signer";
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

  constructor(config: OmniWalletConfig) {
    const signer = new StatelessSigner(config.signerProvider);
    this.eth = new EthWallet(signer, config.ethKeyId, config.eth);
    this.sol = new SolWallet(signer, config.solKeyId, config.sol);
  }

  transfer(request: TransferRequest): Promise<SignedTx> {
    return request.chain === "eth" ? this.eth.transfer(request) : this.sol.transfer(request);
  }

  simulateTransfer(request: TransferRequest): string {
    return `${request.chain.toUpperCase()} transfer ${request.amountAtomic.toString()} ${request.asset} from ${request.from} to ${request.to} on chainId ${request.chainId}`;
  }
}

export * from "./types";
export * from "./signer";
export * from "./eth";
export * from "./sol";
export * from "./rpc";
