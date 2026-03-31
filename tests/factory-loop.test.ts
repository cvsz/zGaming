import test from "node:test";
import assert from "node:assert/strict";
import { ResumableUploadCoordinator } from "../factory/publisher/resumable-upload";
import { StatelessRenderFarm } from "../factory/render/stateless-render-farm";
import { autonomousContentFactoryLoop } from "../factory/scout/autonomous-content-factory";

test("resumable uploads support out-of-order chunks", () => {
  const coordinator = new ResumableUploadCoordinator();
  coordinator.acceptChunk({ uploadId: "u1", index: 1, totalChunks: 2, payload: new Uint8Array([66]) });
  const progress = coordinator.acceptChunk({ uploadId: "u1", index: 0, totalChunks: 2, payload: new Uint8Array([65]) });

  assert.equal(progress.complete, true);
  const binary = coordinator.finalize("u1", 2);
  assert.deepEqual(Array.from(binary), [65, 66]);
});

test("render farm stays deterministic + stateless", () => {
  const farm = new StatelessRenderFarm(["node-a", "node-b"]);
  const first = farm.dispatch({ jobId: "j1", prompt: "hi", frameCount: 30 });
  const second = farm.dispatch({ jobId: "j1", prompt: "hi", frameCount: 30 });

  assert.deepEqual(first, second);
  assert.equal(farm.hpaTargetMetrics().queueDepthPerPod, 5);
});

test("autonomous content loop filters weak signals", () => {
  const jobs = autonomousContentFactoryLoop([
    { signalId: "s1", score: 0.95, topic: "web3" },
    { signalId: "s2", score: 0.4, topic: "noise" },
  ]);

  assert.equal(jobs.length, 1);
  assert.match(jobs[0].prompt, /web3/);
});
