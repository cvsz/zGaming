export type Chain = "eth" | "sol";

export interface TransferRequest {
  chain: Chain;
  chainId: number;
  from: string;
  to: string;
  amountAtomic: bigint;
  asset: string;
  nonce: string;
}

export interface SignedTx {
  chain: Chain;
  chainId: number;
  txHash: string;
  rawTx: string;
  signerKeyId: string;
  rpcEndpoint: string;
  rpcAttempt: number;
  intent: HumanReadableIntent;
}

export interface HumanReadableIntent {
  summary: string;
  amountAtomic: string;
  asset: string;
  from: string;
  to: string;
  chain: Chain;
  chainId: number;
}

export interface SignRequest {
  keyId: string;
  payload: Uint8Array;
}

export interface SignProvider {
  sign(request: SignRequest): Promise<Uint8Array>;
}

export interface ChainRuntimeConfig {
  supportedChainIds: number[];
  rpcEndpoints: string[];
  startRpcAttempt?: number;
}
