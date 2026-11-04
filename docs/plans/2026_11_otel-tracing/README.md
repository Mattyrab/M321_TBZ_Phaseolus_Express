# OpenTelemetry Message Tracing

⏳ **Status:** in progress (Steps 1-2 of 5 done and live-verified; see `40_implementation.md`). Direction: Grafana Tempo + Loki wired into the existing Grafana instance, with manual W3C `traceparent` propagation across RabbitMQ message headers. Add distributed tracing across the five services' RabbitMQ-based message flow with OpenTelemetry, closing the "Distributed Tracing" half of the grading rubric's observability criterion that `../2026_10_observability-and-resilience/` deliberately left open.

## Why this exists

A full audit against the project's grading rubric (`docs/LB3_Projektarbeit_WIR.md`) found criterion 5, "Observability & Distributed Tracing," only half-closed: `../2026_10_observability-and-resilience/` added structured logging with an `OrderId` correlation ID across all four backend services, but no actual distributed tracing (spans, trace context propagation) exists yet. Since the services communicate asynchronously over RabbitMQ rather than synchronous HTTP, a trace needs to survive crossing a message-queue boundary, not just an in-process call stack — that's the core design problem this plan needs to frame before any code changes across the five service repos.

## Index

- 📎 [`inputs.md`](./inputs.md) — user's source framing (verbatim)
- ✅ [`00_current_state.md`](./00_current_state.md) — what exists in the codebase today
- ✅ [`10_target_shape.md`](./10_target_shape.md) — what the change must produce
- ✅ [`20_options.md`](./20_options.md) — design options with pros/cons
- ✅ [`30_open_questions.md`](./30_open_questions.md) — decisions that block implementation
- ⏳ [`40_implementation.md`](./40_implementation.md) — step plan
- ⏳ [`50_followups.md`](./50_followups.md) — out-of-scope items parked for later

## Status legend

- ✅ resolved / done
- ⏳ open / in flight
- ❌ rejected / dropped
- ⚠️ blocked / risk

Update an entry's emoji as the corresponding phase changes state.
