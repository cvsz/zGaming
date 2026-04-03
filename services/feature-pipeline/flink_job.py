from __future__ import annotations

from pyflink.common import Types
from pyflink.datastream import StreamExecutionEnvironment
from pyflink.datastream.connectors.kafka import KafkaSource
from pyflink.datastream.formats.json import JsonRowDeserializationSchema


def compute_features(event: dict) -> dict:
    delta_t = max(float(event.get("delta_t", 1.0)), 1.0)
    ts = int(event.get("timestamp", 0))
    return {
        "user_id": event.get("user_id"),
        "velocity": float(event.get("amount", 0.0)) / delta_t,
        "hour": (ts % 86400) // 3600,
    }


def build_job() -> StreamExecutionEnvironment:
    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_parallelism(1)

    source = KafkaSource.builder() \
        .set_bootstrap_servers("kafka:9092") \
        .set_topics("ledger") \
        .set_group_id("feature-pipeline") \
        .set_value_only_deserializer(
            JsonRowDeserializationSchema.builder().type_info(
                Types.ROW_NAMED(
                    ["user_id", "amount", "delta_t", "timestamp"],
                    [Types.LONG(), Types.FLOAT(), Types.FLOAT(), Types.LONG()],
                )
            ).build()
        ) \
        .build()

    stream = env.from_source(source, watermark_strategy=None, source_name="ledger-source")
    stream.map(lambda row: compute_features(dict(row)), output_type=Types.MAP(Types.STRING(), Types.STRING()))
    return env


if __name__ == "__main__":
    build_job().execute("real-time-feature-pipeline")
