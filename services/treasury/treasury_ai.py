"""Autonomous treasury allocator."""

import numpy as np

ASSETS = ["cash", "crypto", "fiat", "liquidity_pool"]


class TreasuryAI:
    def __init__(self) -> None:
        self.allocation = np.array([0.25, 0.25, 0.25, 0.25])

    def optimize(self, signals: dict[str, float]) -> dict[str, float]:
        score = np.array(
            [
                1 - signals["risk"],
                signals["yield"],
                1 - signals["volatility"],
                signals["liquidity"],
            ]
        )
        self.allocation = self.softmax(score)
        return dict(zip(ASSETS, self.allocation))

    @staticmethod
    def softmax(x: np.ndarray) -> np.ndarray:
        e = np.exp(x - np.max(x))
        return e / e.sum()
