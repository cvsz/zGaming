"""Federated learning client node."""

import numpy as np


class FederatedClient:
    def __init__(self, data: np.ndarray):
        self.data = data

    def train(self, global_weights: np.ndarray) -> np.ndarray:
        grad = np.mean(self.data, axis=0) - global_weights
        return grad
