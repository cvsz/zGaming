"""Incentive-aligned mechanism scoring."""


class Mechanism:
    def __init__(self) -> None:
        self.penalty = 1.0
        self.reward = 1.0

    def payoff(self, action: str, outcome: str) -> float:
        if action == "ALLOW" and outcome == "fraud":
            return -10 * self.penalty
        if action == "BLOCK" and outcome == "legit":
            return -2 * self.penalty
        if action == "ALLOW" and outcome == "legit":
            return +5 * self.reward
        if action == "BLOCK" and outcome == "fraud":
            return +8 * self.reward
        return 0.0
