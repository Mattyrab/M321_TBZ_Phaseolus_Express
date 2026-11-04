# OpenTelemetry Message Tracing

✅ **Status:** complete. All five steps done and live-verified against the fully-merged system: a single order placed through BeanApp's real UI produces one connected trace spanning all five services (BeanApp → OrderBeans → PayBeancoins → CookerBeaners/BeanNotifs), with correlated logs one click away in Grafana (a real gap in that correlation was found and fixed during Step 5) and payment failures visibly distinguishable from the happy path. Closes the grading rubric's "Distributed Tracing" half of the observability criterion that `../2026_10_observability-and-resilience/` deliberately left open. See `40_implementation.md` for the full step-by-step record, including two things the plan got wrong and corrected live: the fire-and-forget `CookAsync` "gotcha" that turned out not to be real (Step 3), and the originally-planned pod-outage failure test that Argo CD's self-heal made impractical, replaced with a cleaner deterministic alternative (Step 5).

## Why this exists

A full audit against the project's grading rubric (`docs/LB3_Projektarbeit_WIR.md`) found criterion 5, "Observability & Distributed Tracing," only half-closed: `../2026_10_observability-and-resilience/` added structured logging with an `OrderId` correlation ID across all four backend services, but no actual distributed tracing (spans, trace context propagation) exists yet. Since the services communicate asynchronously over RabbitMQ rather than synchronous HTTP, a trace needs to survive crossing a message-queue boundary, not just an in-process call stack — that's the core design problem this plan needs to frame before any code changes across the five service repos.

## Index

- 📎 [`inputs.md`](./inputs.md) — user's source framing (verbatim)
- ✅ [`00_current_state.md`](./00_current_state.md) — what exists in the codebase today
- ✅ [`10_target_shape.md`](./10_target_shape.md) — what the change must produce
- ✅ [`20_options.md`](./20_options.md) — design options with pros/cons
- ✅ [`30_open_questions.md`](./30_open_questions.md) — decisions that block implementation
- ✅ [`40_implementation.md`](./40_implementation.md) — step plan
- ⏳ [`50_followups.md`](./50_followups.md) — out-of-scope items parked for later

## Status legend

- ✅ resolved / done
- ⏳ open / in flight
- ❌ rejected / dropped
- ⚠️ blocked / risk

Update an entry's emoji as the corresponding phase changes state.
