"""Meta-learner for agent weights."""

from __future__ import annotations

import numpy as np


class MetaLearner:
    def __init__(self) -> None:
        self.weights = np.array([1.0, 1.0, 1.0], dtype=float)

    def update(self, rewards: float, actions: list[float]) -> None:
        grad = np.array(actions, dtype=float) * float(rewards)
        self.weights += 0.01 * grad
        self.normalize()

    def normalize(self) -> None:
        self.weights = np.clip(self.weights, 1e-6, None)
        self.weights = self.weights / np.sum(self.weights)
