# Inputs

The user's framing for this work, captured **verbatim**. Do not paraphrase, summarize, or "clean up" — interpretation belongs in `10_target_shape.md`, and we need the unfiltered source to check that interpretation later.

## Source

> Next up, I would like to add message tracing with OpenTelemetry for the services

Follow-up, when asked whether to scaffold a staged design doc given the recent time pressure on the ingress feature vs. implement directly with reasonable defaults: user chose "Staged design doc first (recommended)".

## Notes (optional)

- Immediate context: this request came right after reverting the admin-ui-ingress feature (`docs/plans/` has no folder for that revert — it was a plain PR, see PR #34) specifically because of time constraints on the project. That time pressure is still live and should inform scope decisions in `10_target_shape.md` and `20_options.md` (favor the lowest-effort option that still satisfies the grading rubric, not the most complete tracing setup).
- Relevant existing rubric criterion (`docs/LB3_Projektarbeit_WIR.md`, per `docs/plans/2026_10_observability-and-resilience/README.md`): criterion 5 is "Observability & **Distributed Tracing**". The observability-and-resilience plan closed the logging/correlation-ID half of that criterion but explicitly did not add distributed tracing (OpenTelemetry spans) — this plan is the natural continuation of that gap.
- The five services (BeanApp/WebApp, OrderBeans, PayBeancoins, CookerBeaners, BeanNotifs) communicate over RabbitMQ (see `docs/plans/2026_10_message-contracts-hardening/`), so "message tracing" implies trace-context propagation across AMQP message boundaries, not just HTTP-style in-process spans.
