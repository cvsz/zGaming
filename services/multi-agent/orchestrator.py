"""Multi-agent game-theoretic orchestrator."""

from __future__ import annotations

import numpy as np

AGENTS = ["risk", "profit", "compliance"]


class MultiAgentSystem:
    def __init__(self) -> None:
        self.weights = {"risk": 1.0, "profit": 1.0, "compliance": 1.0}

    def decide(self, state: dict, actions: dict[str, list[float]]) -> int:
        utilities: dict[str, np.ndarray] = {}
        for agent in AGENTS:
            utilities[agent] = self.evaluate(agent, state, actions[agent])

        final_scores = np.zeros(len(actions["risk"]), dtype=float)
        for agent in AGENTS:
            final_scores += self.weights[agent] * utilities[agent]

        return int(np.argmax(final_scores))

    def evaluate(self, agent: str, state: dict, action_scores: list[float]) -> np.ndarray:
        scores = np.array(action_scores, dtype=float)
        if agent == "risk":
            return -scores
        if agent == "profit":
            return scores
        if agent == "compliance":
            return -np.abs(scores)
        return scores
