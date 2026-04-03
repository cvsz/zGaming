"""Intent-centric planning engine."""


class IntentEngine:
    def __init__(self) -> None:
        self.strategies = {
            "maximize_yield": ["allocate_high_yield", "rebalance"],
            "minimize_risk": ["diversify", "reduce_exposure"],
            "liquidity_ready": ["increase_cash", "exit_positions"],
        }

    def plan(self, intent: str, context: dict) -> list[str]:
        steps = self.strategies.get(intent, [])
        return self.optimize(steps, context)

    def optimize(self, steps: list[str], context: dict) -> list[str]:
        return sorted(steps, key=lambda s: context.get(s, 0), reverse=True)
