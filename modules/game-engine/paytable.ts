import type { GameSymbol, Match } from "./types";

export const PAYTABLE: Record<GameSymbol, Record<number, number>> = {
  A: { 8: 1, 10: 2, 12: 5, 15: 8 },
  B: { 8: 1, 10: 2, 12: 4, 15: 7 },
  C: { 8: 1, 10: 2, 12: 3, 15: 6 },
  D: { 8: 1, 10: 2, 12: 2, 15: 4 },
  WILD: {},
  SCATTER: {},
};

export function payoutForCluster(symbol: Match["symbol"], clusterSize: number): number {
  const table = PAYTABLE[symbol];
  const sortedThresholds = Object.keys(table)
    .map(Number)
    .sort((a, b) => a - b);

  let payout = 0;

  for (const threshold of sortedThresholds) {
    if (clusterSize >= threshold) {
      payout = table[threshold] ?? payout;
    }
  }

  return payout;
}
