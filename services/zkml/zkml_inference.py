"""Simplified zkML-style inference commitment."""

import hashlib
import json

import numpy as np


class ZKML:
    def __init__(self, model_weights: np.ndarray):
        self.weights = np.asarray(model_weights)

    def infer(self, x: np.ndarray) -> tuple[np.ndarray, str]:
        x = np.asarray(x)
        y = np.dot(x, self.weights)
        proof = self._prove(x, y)
        return y, proof

    def _prove(self, x: np.ndarray, y: np.ndarray) -> str:
        payload = json.dumps(
            {
                "x": np.asarray(x).tolist(),
                "weights": self.weights.tolist(),
                "y": np.asarray(y).tolist(),
            },
            sort_keys=True,
        )
        return hashlib.sha256(payload.encode()).hexdigest()

    def verify(self, x: np.ndarray, y: np.ndarray, proof: str) -> bool:
        return self._prove(x, y) == proof
