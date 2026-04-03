"""Risk agent."""


def evaluate_risk(features: dict) -> list[float]:
    return [
        float(features.get("amount", 0.0)) * 0.01,
        float(features.get("velocity", 0.0)) * 0.1,
        float(features.get("fx_volatility", 0.0)) * 0.5,
    ]
