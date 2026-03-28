import type { Grid, GameSymbol, ReelWeight } from "./types";
import { DeterministicRng } from "./rng";

export const DEFAULT_WEIGHTS: ReelWeight[] = [
  { symbol: "A", weight: 30 },
  { symbol: "B", weight: 25 },
  { symbol: "C", weight: 20 },
  { symbol: "D", weight: 15 },
  { symbol: "WILD", weight: 5 },
  { symbol: "SCATTER", weight: 5 },
];

export function weightedChoice(rng: DeterministicRng, weights: ReelWeight[]): GameSymbol {
  const total = weights.reduce((sum, current) => sum + current.weight, 0);

  if (total <= 0) {
    throw new Error("Invalid symbol weights: total must be > 0");
  }

  const point = rng.nextFloat() * total;
  let running = 0;

  for (const item of weights) {
    running += item.weight;
    if (point < running) {
      return item.symbol;
    }
  }

  return weights[weights.length - 1].symbol;
}

export function generateGrid(
  rng: DeterministicRng,
  rows: number,
  cols: number,
  weights: ReelWeight[] = DEFAULT_WEIGHTS,
): Grid {
  const grid: Grid = [];

  for (let row = 0; row < rows; row++) {
    const line: GameSymbol[] = [];
    for (let col = 0; col < cols; col++) {
      line.push(weightedChoice(rng, weights));
    }
    grid.push(line);
  }

  return grid;
}
