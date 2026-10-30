# Observability & Resilience

✅ **Status:** complete. All three steps done and live-verified: success-path logging with `OrderId` correlation confirmed end-to-end across all four backend services; `OrderBeans` scaled to 2 replicas with genuine Service-level load distribution confirmed (after a `kubectl port-forward` false negative was caught and corrected); `Microsoft.Extensions.Http.Resilience`'s standard handler on BeanApp's one synchronous call, with real retry events observed against a genuine outage. Closes the grading rubric's observability (5 pts) and resilience/scaling (10 pts) criteria. See `40_implementation.md` for the full record and `50_followups.md` for what's parked (circuit-breaker not independently verified; only `OrderBeans` scales so far).

## Why this exists

A full audit against the project's grading rubric (`docs/LB3_Projektarbeit_WIR.md`) found criteria 5 (Observability & Distributed Tracing) and 6 (Skalierbarkeit & Resilienz) both sitting low — observability because structured logging exists only on failure paths despite a correlation ID already being available, and resilience because every service is pinned at `replicas: 1` with no documented scaling concept, even though at least two services are already stateless enough to scale today. Grouped together because both are small, mechanical, operational-maturity fixes with no real alternative designs to weigh (unlike `../2026_10_message-contracts-hardening/`, which got the full staged process).

**Skipping the middle phases deliberately** — this plan goes straight from `inputs.md` to `40_implementation.md`. `00_current_state`/`10_target_shape`/`20_options`/`30_open_questions` are omitted on purpose, not forgotten.

## Index

- 📎 [`inputs.md`](./inputs.md) — user's source framing (verbatim)
- ✅ [`40_implementation.md`](./40_implementation.md) — step plan
- ⏳ [`50_followups.md`](./50_followups.md) — out-of-scope items parked for later

## Status legend

- ✅ resolved / done
- ⏳ open / in flight
- ❌ rejected / dropped
- ⚠️ blocked / risk

Update an entry's emoji as the corresponding phase changes state.
