"""Contextual segmented epsilon-greedy bandit."""

from collections import defaultdict

import numpy as np


class SegmentBandit:
    def __init__(self) -> None:
        self.q = defaultdict(lambda: np.zeros(3, dtype=float))
        self.n = defaultdict(lambda: np.zeros(3, dtype=float))

    def select(self, segment: str) -> int:
        if np.random.rand() < 0.1:
            return int(np.random.randint(3))
        return int(np.argmax(self.q[segment]))

    def update(self, segment: str, action: int, reward: float) -> None:
        self.n[segment][action] += 1
        alpha = 1 / self.n[segment][action]
        self.q[segment][action] += alpha * (reward - self.q[segment][action])
