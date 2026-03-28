export type GameSymbol = "A" | "B" | "C" | "D" | "WILD" | "SCATTER";

export type GridCell = GameSymbol | null;
export type Grid = GridCell[][];

export interface Match {
  symbol: Exclude<GameSymbol, "WILD" | "SCATTER">;
  positions: Array<[row: number, col: number]>;
  payoutMultiplier: number;
}

export interface CascadeResult {
  index: number;
  matches: Match[];
  cascadeWin: number;
  appliedMultiplier: number;
  gridAfter: Grid;
}

export interface SpinResult {
  grid: Grid;
  cascades: CascadeResult[];
  totalWin: number;
  finalMultiplier: number;
  seedTrace: string;
  auditEvents: string[];
}

export interface ReelWeight {
  symbol: GameSymbol;
  weight: number;
}

export interface SpinConfig {
  rows: number;
  cols: number;
  minCluster: number;
  maxCascades: number;
  baseMultiplier: number;
  multiplierStep: number;
}
