import test from "node:test";
import assert from "node:assert/strict";
import { simulateTransfer } from "../modules/wallet/simulation";
import { validateChainId } from "../modules/wallet/chain-validation";

const ethConfig = {
  supportedChainIds: [1, 137],
  rpcEndpoints: ["https://rpc.example"],
  requiredChainId: 1,
  maxAllowedFeeAtomic: 100_000n,
} as const;

test("strict chainId validation rejects unsupported chain", () => {
  assert.throws(() => validateChainId("eth", 137, ethConfig), /Strict chainId validation failed/);
});

test("simulation fails when fee policy is exceeded", () => {
  const result = simulateTransfer(
    {
      chain: "eth",
      chainId: 1,
      from: "0xabc",
      to: "0xdef",
      amountAtomic: 10n,
      asset: "USDC",
      nonce: "nonce-001",
      maxFeePerGas: 2n,
      gasLimit: 60_000n,
    },
    ethConfig,
  );

  assert.equal(result.ok, false);
  assert.equal(result.reason, "fee policy exceeded");
});
