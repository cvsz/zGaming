"""Simple iterative best-response approximation."""

from __future__ import annotations

import numpy as np


def best_response(payoff_matrix: np.ndarray) -> np.ndarray:
    return np.argmax(payoff_matrix, axis=1)


def compute_equilibrium(payoffs: list[np.ndarray], iterations: int = 10) -> np.ndarray:
    num_actions = payoffs[0].shape[1]
    strategy = np.ones(num_actions) / num_actions

    for _ in range(iterations):
        responses = [best_response(p) for p in payoffs]
        hist = np.zeros(num_actions)
        for resp in responses:
            for action in np.atleast_1d(resp):
                hist[int(action)] += 1
        strategy = hist / np.sum(hist)

    return strategy
