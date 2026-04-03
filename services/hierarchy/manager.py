"""Hierarchical manager agent."""

from agents.agent_compliance import evaluate_compliance
from agents.agent_profit import evaluate_profit
from agents.agent_risk import evaluate_risk


class ManagerAgent:
    def __init__(self) -> None:
        self.policies = {
            "low_risk": ["profit"],
            "medium_risk": ["risk", "profit"],
            "high_risk": ["risk", "compliance"],
        }

    def route(self, features: dict) -> list[str]:
        risk_score = sum(evaluate_risk(features))
        if risk_score < 1:
            return self.policies["low_risk"]
        if risk_score < 5:
            return self.policies["medium_risk"]
        return self.policies["high_risk"]

    def decide(self, features: dict) -> float:
        active_agents = self.route(features)
        outputs: list[float] = []
        for agent in active_agents:
            if agent == "risk":
                outputs.append(sum(evaluate_risk(features)))
            elif agent == "profit":
                outputs.append(sum(evaluate_profit(features)))
            elif agent == "compliance":
                outputs.append(sum(evaluate_compliance(features)))
        return max(outputs) if outputs else 0.0
