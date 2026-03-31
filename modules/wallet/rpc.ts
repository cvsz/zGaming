export interface RpcResolution {
  endpoint: string;
  attempt: number;
}

/**
 * Stateless RPC endpoint chooser with deterministic fallback order.
 * The pool never stores credentials and only receives already-sanitized URLs.
 */
export class RpcEndpointPool {
  constructor(private readonly endpoints: readonly string[]) {
    if (!endpoints.length) {
      throw new Error("rpcEndpoints is empty");
    }
  }

  resolve(preferredAttempt = 0): RpcResolution {
    const attempt = Math.max(0, preferredAttempt);
    const index = attempt % this.endpoints.length;

    return {
      endpoint: this.endpoints[index],
      attempt,
    };
  }

  withFallbacks(): RpcResolution[] {
    return this.endpoints.map((endpoint, index) => ({ endpoint, attempt: index }));
  }
}
