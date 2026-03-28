import type { ReelWeight } from "./types";

export interface RtpSnapshot {
  targetRtp: number;
  currentRtp: number;
  drift: number;
}

/**
 * Bounded RTP controller:
 * - never sets direct wins
 * - only nudges symbol distribution within configured bounds.
 */
export class RtpController {
  private currentRtp: number;

  constructor(
    private readonly targetRtp = 0.96,
    private readonly adjustmentStep = 0.01,
    private readonly minWeightFactor = 0.9,
    private readonly maxWeightFactor = 1.1,
  ) {
    this.currentRtp = targetRtp;
  }

  snapshot(): RtpSnapshot {
    return {
      targetRtp: this.targetRtp,
      currentRtp: this.currentRtp,
      drift: this.currentRtp - this.targetRtp,
    };
  }

  update(win: number, bet: number): void {
    if (bet <= 0) {
      throw new Error("bet must be greater than zero");
    }

    const sample = win / bet;
    this.currentRtp = (this.currentRtp * 1000 + sample) / 1001;
  }

  adjust(baseWeights: ReelWeight[]): ReelWeight[] {
    const { drift } = this.snapshot();

    const factor = drift > 0
      ? Math.max(1 - this.adjustmentStep, this.minWeightFactor)
      : drift < 0
      ? Math.min(1 + this.adjustmentStep, this.maxWeightFactor)
      : 1;

    return baseWeights.map((entry) => {
      if (entry.symbol === "SCATTER" || entry.symbol === "WILD") {
        return { ...entry };
      }

      return {
        ...entry,
        weight: Math.max(1, entry.weight * factor),
      };
    });
  }
}
