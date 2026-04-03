"""Federated learning server (simplified secure aggregation)."""

import numpy as np


class FederatedServer:
    def __init__(self, dim: int = 5):
        self.global_weights = np.zeros(dim)

    def aggregate(self, client_updates: list[np.ndarray]) -> np.ndarray:
        if not client_updates:
            return self.global_weights
        agg = np.sum(client_updates, axis=0)
        self.global_weights += agg / len(client_updates)
        return self.global_weights
