"""Compliance agent."""


def evaluate_compliance(features: dict) -> list[float]:
    penalties = 0.0
    if float(features.get("amount", 0.0)) > 100000:
        penalties += 10.0
    if float(features.get("country_risk", 0.0)) > 0.8:
        penalties += 5.0
    return [penalties, penalties, penalties]
