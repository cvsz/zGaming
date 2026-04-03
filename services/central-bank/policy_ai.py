"""AI-driven monetary policy toy model."""

import numpy as np


class MonetaryPolicyAI:
    def __init__(self) -> None:
        self.rate = 0.05

    def update(self, signals: dict[str, float]) -> float:
        delta = (
            0.5 * signals["inflation"]
            - 0.3 * signals["growth"]
            + 0.2 * signals["risk"]
            - 0.4 * signals["liquidity"]
        )
        self.rate = float(np.clip(self.rate + delta, 0.0, 1.0))
        return self.rate

    @staticmethod
    def supply_adjustment(demand: float) -> float:
        return float(np.tanh(demand))
