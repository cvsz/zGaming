"""World model for simple next-state simulation."""

from __future__ import annotations

import numpy as np
from sklearn.linear_model import LinearRegression


class WorldModel:
    def __init__(self) -> None:
        self.model = LinearRegression()

    def train(self, X: np.ndarray, y: np.ndarray) -> None:
        self.model.fit(X, y)

    def predict_next(self, state: np.ndarray) -> np.ndarray:
        return self.model.predict([state])[0]

    def simulate(self, state: np.ndarray, action: int, steps: int = 5) -> list[np.ndarray]:
        trajectory = []
        s = state
        for _ in range(steps):
            s = self.predict_next(s)
            trajectory.append(s)
        return trajectory
