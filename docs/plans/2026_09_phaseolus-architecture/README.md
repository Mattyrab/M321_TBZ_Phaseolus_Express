# Phaseolus Architecture

⚠️ **Status:** execution in progress — Steps 1–13 done, with Step 13 landing at reduced scope after a real incident (see `40_implementation.md`): Argo CD manages the five services + this repo's own infra manifests cleanly, but the four infra Helm charts were reverted to manual management after adoption deleted the original resources (Keycloak's realm had to be rebuilt). System re-verified fully working end-to-end afterward. Only Step 14 (final checklist) remains. First rough draft of the Phaseolus Express microservice architecture for the M321 school project.

## Why this exists

The user needs a school microservice architecture project (module M321, TBZ) covering a message broker, IAM, metrics/monitoring, and deployment, where the priority is functionality and operation *between* systems rather than end-user features. The domain (bean-food ordering, "Phaseolus Express") and a first-pass service/infra list are already sketched in `README.md` and `docs/CLAUDE.md`, but haven't been worked through as a design: current state, concrete requirements, alternative shapes for service boundaries and infra choices, and a step-by-step build plan.

## Index

- 📎 [`inputs.md`](./inputs.md) — user's source framing (verbatim)
- ✅ [`00_current_state.md`](./00_current_state.md) — what exists in the codebase today
- ✅ [`10_target_shape.md`](./10_target_shape.md) — what the change must produce
- ✅ [`20_options.md`](./20_options.md) — design options with pros/cons
- ✅ [`30_open_questions.md`](./30_open_questions.md) — decisions that block implementation (all 8 resolved)
- ⚠️ [`40_implementation.md`](./40_implementation.md) — step plan (14 steps; Step 13 done at reduced scope after an incident — see its own notes)
- ⏳ [`50_followups.md`](./50_followups.md) — out-of-scope items parked for later

## Status legend

- ✅ resolved / done
- ⏳ open / in flight
- ❌ rejected / dropped
- ⚠️ blocked / risk

Update an entry's emoji as the corresponding phase changes state.
