import type { ChainRuntimeConfig, ChainValidationResult } from "./types";

export function validateChainId(chain: "eth" | "sol", chainId: number, config: ChainRuntimeConfig): ChainValidationResult {
  if (!Number.isInteger(chainId) || chainId <= 0) {
    throw new Error(`Invalid ${chain.toUpperCase()} chainId ${chainId}`);
  }

  if (config.requiredChainId !== undefined && chainId !== config.requiredChainId) {
    throw new Error(
      `Strict chainId validation failed for ${chain.toUpperCase()}: expected ${config.requiredChainId}, got ${chainId}`,
    );
  }

  if (!config.supportedChainIds.includes(chainId)) {
    throw new Error(`Unsupported ${chain.toUpperCase()} chainId ${chainId}`);
  }

  return {
    requestedChainId: chainId,
    normalizedChainId: chainId,
  };
}
