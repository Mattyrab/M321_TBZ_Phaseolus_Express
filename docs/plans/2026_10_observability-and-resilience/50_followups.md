# 50 — Followups

The parking lot. Anything that came up while working on this plan but is **out of scope** for the current PR.

This file exists so the conversation doesn't bloat the current plan. When something interesting surfaces — a related refactor, an adjacent bug, a future feature, a test gap — drop it here in one bullet and move on.

## Out of scope, parked for later

- ⏳ **The circuit breaker wasn't independently verified, only retries.** `40_implementation.md` Step 3: `AddStandardResilienceHandler()`'s circuit breaker needs a minimum sampling window/failure rate before it opens, which one short outage-and-recovery test doesn't necessarily exercise. If the live demo wants to show the breaker specifically (not just retries), rehearse a longer/higher-volume outage against `BeanNotifs` beforehand to confirm it actually trips.
- ⏳ **Only `OrderBeans` scales today.** `PayBeancoins`/`CookerBeaners`/`BeanNotifs` can't be cleanly scaled until their `EventId` idempotency guard (from `../2026_10_message-contracts-hardening/`) moves from per-pod in-memory state to something shared across replicas (e.g. a Redis set, or a persisted table) — already flagged as a followup in that plan's own `50_followups.md`. Cross-referenced here since it directly blocks scaling any of the three consumer services.
- ⏳ **`BeanApp` itself isn't scaled.** Not required by the rubric (only "at least one" service), and untested for statelessness here — `AddSession`/`AddDistributedMemoryCache` are in its `Program.cs`, which would need checking before assuming it scales as cleanly as `OrderBeans` does.

---

## Promoted to their own plan

<When a parked item gets serious enough to need its own folder, link the new plan here and tick the original entry ✅. Don't delete the entry — the trail matters.>

- e.g. ✅ "Allocation layer" → see `docs/plans/2026_06_allocation/`

---

**Exit criterion:** N/A — this file lives forever as a record of what was deferred. No status emoji needed in `README.md`'s index for this one beyond ⏳ (always open).
