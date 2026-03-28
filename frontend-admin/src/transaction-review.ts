import type { TxIntent } from "../../frontend-player/src/intent-simulation";

export function validateIntent(intent: TxIntent): string[] {
  const errors: string[] = [];
  if (intent.from === intent.to) errors.push("sender and receiver must differ");
  if (!/^\d+$/.test(intent.amountAtomic)) errors.push("amountAtomic must be an integer string");
  if (intent.chain === "eth" && intent.chainId <= 0) errors.push("invalid ETH chainId");
  if (intent.chain === "sol" && intent.chainId <= 0) errors.push("invalid SOL chainId");
  return errors;
}
