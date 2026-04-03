import asyncio
import json

import numpy as np
import redis
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

REDIS = redis.Redis(host="redis", port=6379, decode_responses=True)
ACTIONS = ["ALLOW", "CHALLENGE", "BLOCK"]


class Policy:
    def __init__(self) -> None:
        self.weights = np.random.rand(5, len(ACTIONS))

    def predict(self, x: np.ndarray) -> np.ndarray:
        scores = x @ self.weights
        return self._softmax(scores)

    def update(self, x: np.ndarray, action_idx: int, reward: float, lr: float = 0.01) -> None:
        self.weights[:, action_idx] += lr * x * reward

    @staticmethod
    def _softmax(x: np.ndarray) -> np.ndarray:
        e = np.exp(x - np.max(x))
        return e / e.sum()


policy = Policy()


async def main() -> None:
    consumer = AIOKafkaConsumer("risk-events", bootstrap_servers="kafka:9092", group_id="rl-agent")
    producer = AIOKafkaProducer(bootstrap_servers="kafka:9092")

    await consumer.start()
    await producer.start()

    try:
        async for msg in consumer:
            event = json.loads(msg.value)
            x = np.array(
                [
                    float(event.get("amount", 0.0)),
                    float(event.get("velocity", 0.0)),
                    float(event.get("balance", 0.0)),
                    float(event.get("fx_rate", 1.0)),
                    float(event.get("hour", 0.0)),
                ]
            )

            probs = policy.predict(x)
            action_idx = int(np.random.choice(len(ACTIONS), p=probs))
            action = ACTIONS[action_idx]

            decision = {"user_id": event.get("user_id"), "action": action, "event_id": event.get("event_id")}
            await producer.send_and_wait("decisions", json.dumps(decision).encode())

            REDIS.set(
                str(event.get("event_id")),
                json.dumps({"x": x.tolist(), "action": action_idx}),
                ex=300,
            )
    finally:
        await consumer.stop()
        await producer.stop()


if __name__ == "__main__":
    asyncio.run(main())
