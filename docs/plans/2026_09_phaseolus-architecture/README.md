# Phaseolus Architecture

✅ **Status:** implementation plan drafted — all phases done. First rough draft of the Phaseolus Express microservice architecture — services, message broker, IAM, metrics, and deployment/orchestration for the M321 school project. Ready for team review before starting Step 1.

## Why this exists

The user needs a school microservice architecture project (module M321, TBZ) covering a message broker, IAM, metrics/monitoring, and deployment, where the priority is functionality and operation *between* systems rather than end-user features. The domain (bean-food ordering, "Phaseolus Express") and a first-pass service/infra list are already sketched in `README.md` and `docs/CLAUDE.md`, but haven't been worked through as a design: current state, concrete requirements, alternative shapes for service boundaries and infra choices, and a step-by-step build plan.

## Index

- 📎 [`inputs.md`](./inputs.md) — user's source framing (verbatim)
- ✅ [`00_current_state.md`](./00_current_state.md) — what exists in the codebase today
- ✅ [`10_target_shape.md`](./10_target_shape.md) — what the change must produce
- ✅ [`20_options.md`](./20_options.md) — design options with pros/cons
- ✅ [`30_open_questions.md`](./30_open_questions.md) — decisions that block implementation (all 8 resolved)
- ✅ [`40_implementation.md`](./40_implementation.md) — step plan (14 steps, Step 1 → cluster/infra, Steps 4–10 → services, Step 13 → Argo CD GitOps cutover)
- ⏳ [`50_followups.md`](./50_followups.md) — out-of-scope items parked for later

## Status legend

- ✅ resolved / done
- ⏳ open / in flight
- ❌ rejected / dropped
- ⚠️ blocked / risk

Update an entry's emoji as the corresponding phase changes state.
