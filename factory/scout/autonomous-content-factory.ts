import type { RenderJob } from "../render/stateless-render-farm";

export interface TrendSignal {
  signalId: string;
  score: number;
  topic: string;
}

export function autonomousContentFactoryLoop(signals: readonly TrendSignal[]): RenderJob[] {
  return signals
    .filter((signal) => signal.score >= 0.8)
    .map((signal, index) => ({
      jobId: `${signal.signalId}-${index}`,
      prompt: `Create content for ${signal.topic}`,
      frameCount: Math.max(30, Math.round(signal.score * 100)),
    }));
}
