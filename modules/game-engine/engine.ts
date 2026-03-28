import { applyCascadeAndRefill, findClusters } from "./cascade";
import { DeterministicRng } from "./rng";
import { generateGrid, DEFAULT_WEIGHTS } from "./reels";
import { RtpController } from "./rtp-controller";
import { buildSeedTrace } from "./provably-fair";
import type { SpinConfig, SpinResult } from "./types";

const DEFAULT_CONFIG: SpinConfig = {
  rows: 6,
  cols: 5,
  minCluster: 8,
  maxCascades: 20,
  baseMultiplier: 1,
  multiplierStep: 1,
};

export interface SpinRequest {
  serverSeed: string;
  clientSeed: string;
  nonce: number;
  bet: number;
}

export async function spin(
  request: SpinRequest,
  rtpController = new RtpController(),
  config: Partial<SpinConfig> = {},
): Promise<SpinResult> {
  const finalConfig = { ...DEFAULT_CONFIG, ...config };

  if (request.bet <= 0) {
    throw new Error("bet must be greater than zero");
  }

  const rng = new DeterministicRng(request.serverSeed, request.clientSeed, request.nonce);
  let multiplier = finalConfig.baseMultiplier;
  let totalWin = 0;

  const adjustedWeights = rtpController.adjust(DEFAULT_WEIGHTS);
  let grid = generateGrid(rng, finalConfig.rows, finalConfig.cols, adjustedWeights);

  const cascades: SpinResult["cascades"] = [];
  const auditEvents: string[] = [
    `spin:start nonce=${request.nonce}`,
    `rtp:target=${rtpController.snapshot().targetRtp.toFixed(4)}`,
  ];

  for (let index = 1; index <= finalConfig.maxCascades; index++) {
    const matches = findClusters(grid, finalConfig.minCluster);

    if (matches.length === 0) {
      auditEvents.push(`cascade:stop index=${index}`);
      break;
    }

    const cascadeWin = matches.reduce((sum, match) => sum + request.bet * match.payoutMultiplier, 0) * multiplier;

    totalWin += cascadeWin;

    grid = applyCascadeAndRefill(grid, matches, rng, adjustedWeights);

    cascades.push({
      index,
      matches,
      cascadeWin,
      appliedMultiplier: multiplier,
      gridAfter: grid.map((row) => [...row]),
    });

    auditEvents.push(
      `cascade:${index} win=${cascadeWin.toFixed(4)} matches=${matches.length} multiplier=${multiplier}`,
    );

    multiplier += finalConfig.multiplierStep;
  }

  rtpController.update(totalWin, request.bet);
  auditEvents.push(`rtp:current=${rtpController.snapshot().currentRtp.toFixed(4)}`);

  return {
    grid,
    cascades,
    totalWin,
    finalMultiplier: multiplier,
    seedTrace: buildSeedTrace(request.serverSeed, request.clientSeed, request.nonce),
    auditEvents,
  };
}
