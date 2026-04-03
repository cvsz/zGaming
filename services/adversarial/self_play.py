"""Toy self-play setup for fraud generation vs detection."""

from __future__ import annotations

import numpy as np


class FraudGenerator:
    def generate(self) -> dict:
        return {
            "amount": float(np.random.uniform(1, 10000)),
            "velocity": float(np.random.uniform(0, 10)),
            "pattern": str(np.random.choice(["normal", "burst", "smurf"])),
        }


class FraudDetector:
    def score(self, event: dict) -> float:
        score = 0.0
        if float(event.get("amount", 0.0)) > 5000:
            score += 0.5
        if float(event.get("velocity", 0.0)) > 5:
            score += 0.5
        return score


def self_play(rounds: int = 1000) -> None:
    gen = FraudGenerator()
    det = FraudDetector()

    for _ in range(rounds):
        event = gen.generate()
        score = det.score(event)
        if score < 0.5:
            event["amount"] = float(event["amount"]) * 1.1
