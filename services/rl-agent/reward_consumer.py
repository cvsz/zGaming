import asyncio
import json

import numpy as np
import redis
from aiokafka import AIOKafkaConsumer

REDIS = redis.Redis(host="redis", port=6379, decode_responses=True)


class Policy:
    def __init__(self) -> None:
        self.weights = np.random.rand(5, 3)

    def update(self, x: np.ndarray, action: int, reward: float, lr: float = 0.01) -> None:
        self.weights[:, action] += lr * x * reward


policy = Policy()


def compute_reward(outcome: dict) -> float:
    if outcome.get("fraud"):
        return -1.0
    if outcome.get("blocked"):
        return -0.2
    return 1.0


async def main() -> None:
    consumer = AIOKafkaConsumer("outcomes", bootstrap_servers="kafka:9092", group_id="rl-reward")
    await consumer.start()

    try:
        async for msg in consumer:
            outcome = json.loads(msg.value)
            event_id = str(outcome.get("event_id"))
            ctx_raw = REDIS.get(event_id)
            if not ctx_raw:
                continue

            ctx = json.loads(ctx_raw)
            x = np.array(ctx["x"])
            action = int(ctx["action"])
            policy.update(x, action, compute_reward(outcome))
    finally:
        await consumer.stop()


if __name__ == "__main__":
    asyncio.run(main())
