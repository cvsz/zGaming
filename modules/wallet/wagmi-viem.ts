import { createConfig, http } from "@wagmi/core";
import { mainnet, polygon, arbitrum } from "viem/chains";
import type { ChainRuntimeConfig } from "./types";

const CHAIN_MAP = {
  1: mainnet,
  137: polygon,
  42161: arbitrum,
} as const;

export function createDeterministicWagmiConfig(config: ChainRuntimeConfig) {
  const chains = config.supportedChainIds.map((id) => {
    const chain = CHAIN_MAP[id as keyof typeof CHAIN_MAP];
    if (!chain) {
      throw new Error(`Unsupported Wagmi/Viem chain mapping for chainId ${id}`);
    }
    return chain;
  });

  if (chains.length === 0) {
    throw new Error("No configured chains for Wagmi/Viem config");
  }

  return createConfig({
    chains,
    transports: chains.reduce<Record<number, ReturnType<typeof http>>>((acc, chain, index) => {
      acc[chain.id] = http(config.rpcEndpoints[index % config.rpcEndpoints.length]);
      return acc;
    }, {}),
    multiInjectedProviderDiscovery: false,
  });
}
