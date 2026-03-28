import { EthWallet } from "./eth";
import { SolWallet } from "./sol";
import { HmacSignProvider, StatelessSigner } from "./signer";
import type { SignedTx, TransferRequest } from "./types";

export interface OmniWalletConfig {
  keyMap: Record<string, string>;
  ethKeyId: string;
  solKeyId: string;
}

export class OmniWallet {
  private readonly eth: EthWallet;
  private readonly sol: SolWallet;

  constructor(config: OmniWalletConfig) {
    const signer = new StatelessSigner(new HmacSignProvider(config.keyMap));
    this.eth = new EthWallet(signer, config.ethKeyId);
    this.sol = new SolWallet(signer, config.solKeyId);
  }

  transfer(request: TransferRequest): Promise<SignedTx> {
    return request.chain === "eth" ? this.eth.transfer(request) : this.sol.transfer(request);
  }
}

export * from "./types";
export * from "./signer";
export * from "./eth";
export * from "./sol";
