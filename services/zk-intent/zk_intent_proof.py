"""Hash proof for intent-plan-outcome integrity."""

import hashlib
import json


def prove_intent(intent: str, plan: list[str], outcome: dict) -> str:
    payload = json.dumps({"intent": intent, "plan": plan, "outcome": outcome}, sort_keys=True)
    return hashlib.sha256(payload.encode()).hexdigest()


def verify_intent(intent: str, plan: list[str], outcome: dict, proof: str) -> bool:
    return prove_intent(intent, plan, outcome) == proof
