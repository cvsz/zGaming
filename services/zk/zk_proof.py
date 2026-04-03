"""Hash-based verifiable decision trace."""

import hashlib
import json


def generate_proof(decision: str, features: dict) -> str:
    payload = json.dumps({"decision": decision, "features": features}, sort_keys=True)
    return hashlib.sha256(payload.encode()).hexdigest()


def verify_proof(decision: str, features: dict, proof: str) -> bool:
    return generate_proof(decision, features) == proof
