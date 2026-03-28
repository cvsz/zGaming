export interface TxIntent {
  chain: "eth" | "sol";
  chainId: number;
  from: string;
  to: string;
  amountAtomic: string;
  asset: string;
}

export function renderIntent(intent: TxIntent): string {
  return `[SIMULATION] Send ${intent.amountAtomic} ${intent.asset} from ${intent.from} to ${intent.to} on ${intent.chain.toUpperCase()} (${intent.chainId})`;
}
