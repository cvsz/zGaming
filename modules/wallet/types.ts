export type Chain = "eth" | "sol";

export interface TransferRequest {
  chain: Chain;
  chainId: number;
  from: string;
  to: string;
  amountAtomic: bigint;
  asset: string;
  nonce: string;
  maxFeePerGas?: bigint;
  gasLimit?: bigint;
}

export interface SimulationReport {
  ok: boolean;
  chain: Chain;
  chainId: number;
  estimatedGas: bigint;
  predictedFee: bigint;
  warnings: string[];
  reason?: string;
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
  simulation: SimulationReport;
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
  supportedChainIds: readonly number[];
  rpcEndpoints: readonly string[];
  startRpcAttempt?: number;
  requiredChainId?: number;
  maxAllowedFeeAtomic?: bigint;
}

export interface ChainValidationResult {
  requestedChainId: number;
  normalizedChainId: number;
}
