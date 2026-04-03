import asyncio
import json

from aiokafka import AIOKafkaConsumer


async def main() -> None:
    consumer = AIOKafkaConsumer(
        "risk-alerts",
        bootstrap_servers="kafka:9092",
        group_id="autonomous-agent",
    )
    await consumer.start()

    try:
        async for msg in consumer:
            alert = json.loads(msg.value)
            if float(alert.get("risk_score", 0.0)) > 0.9:
                print(f"[AUTO ACTION] Freeze user {alert.get('user_id')}")
    finally:
        await consumer.stop()


if __name__ == "__main__":
    asyncio.run(main())
