"""Profit agent."""


def evaluate_profit(features: dict) -> list[float]:
    return [
        float(features.get("amount", 0.0)) * 0.02,
        float(features.get("lifetime_value", 0.0)) * 0.1,
        -float(features.get("chargeback_rate", 0.0)),
    ]
