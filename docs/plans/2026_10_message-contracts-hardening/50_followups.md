# 50 — Followups

The parking lot. Anything that came up while working on this plan but is **out of scope** for the current PR.

This file exists so the conversation doesn't bloat the current plan. When something interesting surfaces — a related refactor, an adjacent bug, a future feature, a test gap — drop it here in one bullet and move on.

## Out of scope, parked for later

- ⏳ **No dead-letter exchange.** `00_current_state.md`/`10_target_shape.md` both named this gap: after `MaxDeliveryAttempts` (5) a failing message is logged and permanently dropped, with no parking lot to inspect or replay it from. Deliberately out of scope here (this plan's job was idempotency, not broker-level durability) — revisit if a future need arises to recover from a systematically-failing handler rather than just a transient one.
- ⏳ **The AsyncAPI specs are hand-maintained, not enforced.** `20_options.md`'s accepted tradeoff: nothing stops the specs in `docs/contracts/` from drifting from the actual C# records again, the same way the `Email` field already did once. A JSON-Schema-validation-at-runtime approach (Option C, rejected as over-engineering for this plan) would close that gap if it's ever worth the cost.
- ⏳ **The idempotency dedup set grows forever.** `ConcurrentDictionary<Guid, byte>` in each consumer never evicts (`10_target_shape.md` non-goals: acceptable at this project's demo scale). A long-running production deployment would need a TTL or persisted store instead.

---

## Promoted to their own plan

<When a parked item gets serious enough to need its own folder, link the new plan here and tick the original entry ✅. Don't delete the entry — the trail matters.>

- e.g. ✅ "Allocation layer" → see `docs/plans/2026_06_allocation/`

---

**Exit criterion:** N/A — this file lives forever as a record of what was deferred. No status emoji needed in `README.md`'s index for this one beyond ⏳ (always open).
