# Docs & CI

✅ **Status:** complete. Both steps done and live-verified: two Mermaid diagrams plus error-handling prose in the root README, both rendered independently with `@mermaid-js/mermaid-cli` before committing; a lint+build GitHub Actions workflow in all 5 service repos plus a minimal `bash -n setup.sh` check in the meta repo, every one confirmed passing via a real post-merge CI run. Step 2 found and fixed a real bug along the way (WebApp's nested `.csproj` path) and ran into a genuine GitHub Actions quirk that briefly looked like a hard blocker — see `40_implementation.md` for both. Closes the grading rubric's documentation (5 pts) and repo/CI (5 pts) criteria. This was the last of the three plans scaffolded from the original grading-rubric audit.

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
