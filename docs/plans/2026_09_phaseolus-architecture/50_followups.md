# 50 — Followups

The parking lot. Anything that came up while working on this plan but is **out of scope** for the current PR.

This file exists so the conversation doesn't bloat the current plan. When something interesting surfaces — a related refactor, an adjacent bug, a future feature, a test gap — drop it here in one bullet and move on.

## Out of scope, parked for later

- ⏳ Sync `docs/CLAUDE.md`'s service list with the root `README.md`. The root `README.md` now lists `BeanApp`/`M321_TBZ_Phaseolus_WebApp` with live GitHub links; `docs/CLAUDE.md`'s equivalent list should be checked against it for drift, but that's a doc-consistency fix, not part of this architecture plan.
- ⏳ Dead-letter exchange / retry-limit handling for RabbitMQ consumers. Q5 (`30_open_questions.md`) settled on plain nack-and-requeue with no DLX for the first pass — fine for a demo, but a poison message would loop forever as-is. Revisit if that becomes a problem.

---

## Promoted to their own plan

<When a parked item gets serious enough to need its own folder, link the new plan here and tick the original entry ✅. Don't delete the entry — the trail matters.>

- e.g. ✅ "Allocation layer" → see `docs/plans/2026_06_allocation/`

---

**Exit criterion:** N/A — this file lives forever as a record of what was deferred. No status emoji needed in `README.md`'s index for this one beyond ⏳ (always open).
