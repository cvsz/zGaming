export type Chain = "eth" | "sol";

export interface TransferRequest {
  chain: Chain;
  from: string;
  to: string;
  amountAtomic: bigint;
  asset: string;
  nonce: string;
}

export interface SignedTx {
  chain: Chain;
  txHash: string;
  rawTx: string;
  signerKeyId: string;
}

export interface SignRequest {
  keyId: string;
  payload: Uint8Array;
}

export interface SignProvider {
  sign(request: SignRequest): Promise<Uint8Array>;
}
