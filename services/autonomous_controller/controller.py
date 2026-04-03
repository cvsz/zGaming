"""Autonomous multi-agent decision controller."""

from agents.agent_compliance import evaluate_compliance
from agents.agent_profit import evaluate_profit
from agents.agent_risk import evaluate_risk
from multi_agent.orchestrator import MultiAgentSystem

system = MultiAgentSystem()


def decide_action(features: dict) -> int:
    actions = {
        "risk": evaluate_risk(features),
        "profit": evaluate_profit(features),
        "compliance": evaluate_compliance(features),
    }
    return system.decide(features, actions)
