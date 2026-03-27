# Observability Tracing Bootstrap

This directory is reserved for distributed tracing bootstrap (e.g., OpenTelemetry + Jaeger).

Minimum rollout checklist:

1. Add request trace IDs at API Gateway boundary.
2. Propagate trace context across module boundaries.
3. Export traces to collector with retry + backoff.
4. Alert on elevated error-rate and p99 latency.
