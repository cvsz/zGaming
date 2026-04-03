"""Additive-share style secure aggregation toy module."""

import numpy as np


class MPCNode:
    def __init__(self, node_id: str):
        self.node_id = node_id

    def split_secret(self, x: float, n: int = 3) -> np.ndarray:
        shares = np.random.rand(n)
        shares[-1] = x - shares[:-1].sum()
        return shares

    def reconstruct(self, shares: np.ndarray) -> float:
        return float(np.sum(shares))
