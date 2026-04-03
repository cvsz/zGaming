def decide(event: dict, rl_action: str, uplift_score: float) -> str:
    if float(event.get("amount", 0.0)) > 100000:
        return "BLOCK"

    if uplift_score < -0.1:
        return "ALLOW"

    return rl_action
