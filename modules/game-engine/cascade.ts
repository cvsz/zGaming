import { payoutForCluster } from "./paytable";
import { weightedChoice } from "./reels";
import { DeterministicRng } from "./rng";
import type { Grid, Match, GameSymbol, ReelWeight } from "./types";

const NEIGHBORS: Array<[number, number]> = [
  [1, 0],
  [-1, 0],
  [0, 1],
  [0, -1],
];

function isBaseMatchSymbol(symbol: GameSymbol | null): symbol is Exclude<GameSymbol, "WILD" | "SCATTER"> {
  return symbol === "A" || symbol === "B" || symbol === "C" || symbol === "D";
}

export function findClusters(grid: Grid, minCluster = 8): Match[] {
  if (grid.length === 0 || grid[0]?.length === 0) {
    return [];
  }

  const rows = grid.length;
  const cols = grid[0].length;
  const visited = new Set<string>();
  const matches: Match[] = [];

  const dfs = (
    row: number,
    col: number,
    target: Exclude<GameSymbol, "WILD" | "SCATTER">,
    cluster: Array<[number, number]>,
  ): void => {
    const key = `${row},${col}`;
    if (visited.has(key)) {
      return;
    }

    const current = grid[row]?.[col] ?? null;
    if (current !== target && current !== "WILD") {
      return;
    }

    visited.add(key);
    cluster.push([row, col]);

    for (const [dr, dc] of NEIGHBORS) {
      const nextRow = row + dr;
      const nextCol = col + dc;
      if (nextRow >= 0 && nextRow < rows && nextCol >= 0 && nextCol < cols) {
        dfs(nextRow, nextCol, target, cluster);
      }
    }
  };

  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      const symbol = grid[row][col];
      if (!isBaseMatchSymbol(symbol)) {
        continue;
      }

      const key = `${row},${col}`;
      if (visited.has(key)) {
        continue;
      }

      const cluster: Array<[number, number]> = [];
      dfs(row, col, symbol, cluster);

      if (cluster.length >= minCluster) {
        matches.push({
          symbol,
          positions: cluster,
          payoutMultiplier: payoutForCluster(symbol, cluster.length),
        });
      }
    }
  }

  return matches;
}

export function applyCascadeAndRefill(
  grid: Grid,
  matches: Match[],
  rng: DeterministicRng,
  weights: ReelWeight[],
): Grid {
  const rows = grid.length;
  const cols = grid[0]?.length ?? 0;

  const toRemove = new Set(matches.flatMap((m) => m.positions.map(([r, c]) => `${r},${c}`)));

  const next: Grid = grid.map((row) => [...row]);

  for (const key of toRemove) {
    const [row, col] = key.split(",").map(Number);
    next[row][col] = null;
  }

  for (let col = 0; col < cols; col++) {
    const existing: GameSymbol[] = [];

    for (let row = rows - 1; row >= 0; row--) {
      const cell = next[row][col];
      if (cell !== null) {
        existing.push(cell);
      }
    }

    while (existing.length < rows) {
      existing.push(weightedChoice(rng, weights));
    }

    for (let row = rows - 1; row >= 0; row--) {
      next[row][col] = existing[rows - 1 - row] ?? null;
    }
  }

  return next;
}
