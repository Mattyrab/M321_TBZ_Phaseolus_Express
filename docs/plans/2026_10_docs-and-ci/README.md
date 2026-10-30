# Docs & CI

⏳ **Status:** implementation plan drafted. Direction: two Mermaid diagrams (service/data-flow, deployment topology) plus error-handling prose in the root README, aiming past "Ideal" toward "Maximal" (Step 1); a lint+build GitHub Actions workflow for each of the 5 service repos plus a minimal `bash -n setup.sh` check for the meta repo, since no test projects exist anywhere to run as "Tests" (Step 2).

## Why this exists

A full audit against the project's grading rubric (`docs/LB3_Projektarbeit_WIR.md`) found criterion 1 (Systemdokumentation & Architekturüberblick) sitting at Minimal — no diagram anywhere despite thorough prose documentation — and criterion 8 (Autonomie, Repo-Struktur & Deployment) one step short of Maximal — clean repo isolation and a genuine one-command bring-up, but zero CI pipelines across all 6 repos. Grouped together as "project hygiene": both are cheap, mechanical additions with no real alternative designs to weigh (unlike `../2026_10_message-contracts-hardening/`, which got the full staged process).

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
