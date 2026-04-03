import asyncio
import json
import os
from typing import Any

import aiohttp
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

KAFKA = os.getenv("KAFKA_BROKER", "kafka:9092")
TRITON = os.getenv("TRITON_URL", "http://triton:8000/v2/models/risk_model/infer")
IN_TOPIC = os.getenv("KAFKA_IN_TOPIC", "ledger")
OUT_TOPIC = os.getenv("KAFKA_OUT_TOPIC", "risk-alerts")


async def infer(features: list[float], session: aiohttp.ClientSession) -> float:
    payload = {
        "inputs": [
            {
                "name": "input",
                "shape": [1, 5],
                "datatype": "FP32",
                "data": [features],
            }
        ]
    }
    async with session.post(TRITON, json=payload, timeout=2) as resp:
        resp.raise_for_status()
        result = await resp.json()
        return float(result["outputs"][0]["data"][0])


def _features(event: dict[str, Any]) -> list[float]:
    return [
        float(event.get("amount", 0.0)),
        float(event.get("velocity", 0.0)),
        float(event.get("balance", 0.0)),
        float(event.get("fx_rate", 1.0)),
        float(event.get("hour", 0)),
    ]


async def main() -> None:
    consumer = AIOKafkaConsumer(IN_TOPIC, bootstrap_servers=KAFKA, group_id="risk-engine")
    producer = AIOKafkaProducer(bootstrap_servers=KAFKA)

    await consumer.start()
    await producer.start()

    async with aiohttp.ClientSession() as session:
        try:
            async for msg in consumer:
                event = json.loads(msg.value)
                score = await infer(_features(event), session)

                if score > 0.8:
                    alert = {
                        "user_id": event.get("user_id"),
                        "event_id": event.get("event_id"),
                        "risk_score": score,
                        "action": "BLOCK",
                    }
                    await producer.send_and_wait(OUT_TOPIC, json.dumps(alert).encode())
        finally:
            await consumer.stop()
            await producer.stop()


if __name__ == "__main__":
    asyncio.run(main())
