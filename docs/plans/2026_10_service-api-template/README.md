# Service API Template

⚠️ **Status:** Steps 1–5 implemented and live-verified on minikube (2026-10-21) — OrderBeans, PayBeancoins, CookerBeaners, BeanNotifs, and BeanApp all working end-to-end, including the Rotten-Beans failure path and a correction to Step 5 (BeanApp's Identity/Postgres scaffolding was removed, not kept — `/healthz/ready` no longer checks Postgres). Only Step 6 (write up the convention in OrderBeans' README) remains. This is the detailed design behind Step 5 of [`../2026_09_phaseolus-architecture/40_implementation.md`](../2026_09_phaseolus-architecture/40_implementation.md).

## Why this exists

The user wants a single, consistent API/project design for all five Phaseolus services (BeanApp, OrderBeans, PayBeancoins, CookerBeaners, BeanNotifs) that can be copy-pasted with light modification per service, given that services communicate over RabbitMQ with JSON payloads and run as Kubernetes pods. The broader architecture (stack, RabbitMQ topology, auth scope, manifest format) is already decided in `../2026_09_phaseolus-architecture/`; this plan works out the actual code-level shape of the template those decisions imply, which that plan's Step 5 never detailed.

## Index

- 📎 [`inputs.md`](./inputs.md) — user's source framing (verbatim)
- ✅ [`00_current_state.md`](./00_current_state.md) — what's already decided, what exists in BeanApp today, what's unknown about the other four repos
- ✅ [`10_target_shape.md`](./10_target_shape.md) — what the template must achieve
- ✅ [`20_options.md`](./20_options.md) — three shapes for the reusable template, one selected
- ✅ [`30_open_questions.md`](./30_open_questions.md) — 5 questions, all resolved
- ✅ [`40_implementation.md`](./40_implementation.md) — 6-step plan: build the reference in OrderBeans, copy into the other three, add the thin slice to BeanApp, document the convention
- ⏳ [`50_followups.md`](./50_followups.md) — out-of-scope items parked for later

## Status legend

- ✅ resolved / done
- ⏳ open / in flight
- ❌ rejected / dropped
- ⚠️ blocked / risk

Update an entry's emoji as the corresponding phase changes state.
