"""Autonomous economic agent."""


class EconomicAgent:
    def __init__(self, agent_id: str, intent_engine, policy) -> None:
        self.agent_id = agent_id
        self.intent_engine = intent_engine
        self.policy = policy

    def act(self, state: dict) -> list[dict]:
        intent = self.policy.select_intent(state)
        plan = self.intent_engine.plan(intent, state)

        return [self.execute(step, state) for step in plan]

    def execute(self, step: str, state: dict) -> dict:
        return {"agent": self.agent_id, "action": step, "state": state}
