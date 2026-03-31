import type { ChainRuntimeConfig, SimulationReport, TransferRequest } from "./types";

const DEFAULT_GAS_LIMIT_ETH = 21_000n;
const DEFAULT_GAS_LIMIT_SOL = 5_000n;
const DEFAULT_FEE_PER_GAS = 1n;

export function simulateTransfer(request: TransferRequest, config: ChainRuntimeConfig): SimulationReport {
  const warnings: string[] = [];

  if (request.amountAtomic <= 0n) {
    return failed(request, "amount must be positive", warnings);
  }

  if (request.from === request.to) {
    return failed(request, "sender and receiver must differ", warnings);
  }

  const gasLimit = request.gasLimit ?? (request.chain === "eth" ? DEFAULT_GAS_LIMIT_ETH : DEFAULT_GAS_LIMIT_SOL);
  const feePerGas = request.maxFeePerGas ?? DEFAULT_FEE_PER_GAS;

  if (gasLimit <= 0n || feePerGas <= 0n) {
    return failed(request, "invalid gas configuration", warnings);
  }

  const predictedFee = gasLimit * feePerGas;
  if (config.maxAllowedFeeAtomic !== undefined && predictedFee > config.maxAllowedFeeAtomic) {
    warnings.push(`predicted fee ${predictedFee.toString()} exceeds policy ${config.maxAllowedFeeAtomic.toString()}`);
    return failed(request, "fee policy exceeded", warnings, gasLimit, predictedFee);
  }

  if (request.nonce.length < 8) {
    warnings.push("short nonce may reduce replay safety");
  }

  return {
    ok: true,
    chain: request.chain,
    chainId: request.chainId,
    estimatedGas: gasLimit,
    predictedFee,
    warnings,
  };
}

function failed(
  request: TransferRequest,
  reason: string,
  warnings: string[],
  estimatedGas = 0n,
  predictedFee = 0n,
): SimulationReport {
  return {
    ok: false,
    chain: request.chain,
    chainId: request.chainId,
    estimatedGas,
    predictedFee,
    warnings,
    reason,
  };
}
