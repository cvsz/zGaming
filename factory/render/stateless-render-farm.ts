export interface RenderJob {
  jobId: string;
  prompt: string;
  frameCount: number;
}

export interface RenderNodeResult {
  jobId: string;
  nodeId: string;
  costMs: number;
  artifactUri: string;
}

/**
 * Stateless scheduler: all inputs come from job payload and deterministic node list.
 */
export class StatelessRenderFarm {
  constructor(private readonly nodeIds: readonly string[]) {
    if (nodeIds.length === 0) {
      throw new Error("at least one render node is required");
    }
  }

  dispatch(job: RenderJob): RenderNodeResult {
    if (job.frameCount <= 0) {
      throw new Error("frameCount must be positive");
    }

    const nodeId = this.nodeIds[job.frameCount % this.nodeIds.length];
    const costMs = job.frameCount * 12;

    return {
      jobId: job.jobId,
      nodeId,
      costMs,
      artifactUri: `s3://render-artifacts/${job.jobId}.mp4`,
    };
  }

  hpaTargetMetrics() {
    return {
      queueDepthPerPod: 5,
      cpuUtilization: 70,
      memoryUtilization: 75,
    };
  }
}
