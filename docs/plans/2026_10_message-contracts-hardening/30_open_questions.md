# 30 — Open questions

Specific decisions that block implementation. Each question has a clear path to resolution. **No vibes-questions** ("is this a good idea?") — split those into the underlying yes/no decisions.

Resolve every question to ✅ or ❌ before starting `40_implementation.md`. If a question can't be answered now, either move it to `50_followups.md` (out of scope) or mark it ⚠️ blocked with a named blocker.

## Questions

### Q1 — Does the breaking-change demo use Tolerant Reader or Parallel Operation?

✅ **Question.** The rubric's Ideal tier for criterion 7 names two acceptable mechanisms: *"Parallelbetrieb oder Tolerant Reader."* Should the demo rely on the already-present Tolerant Reader property (`00_current_state.md`: `System.Text.Json` silently ignores unknown fields, so an additive field change just works today without touching the routing key), or build real Parallel Operation (a new, versioned routing key published alongside the old one for a transition window, consumers migrating to it one at a time)?

**Why it matters.** This is almost entirely an effort/ambition trade-off. Tolerant Reader is nearly free — add a field, deploy the publisher, show nothing broke. Parallel Operation is real new work (dual-publish logic, a second set of queue bindings, a migration sequencing story) but much more directly demonstrates the rubric's named pattern and pushes toward Maximal's *"Konsequente Umsetzung des Expand and Contract-Patterns."* Determines how big `40_implementation.md`'s breaking-change step is.

**Resolution.** ✅ 2026-10-29 — Tolerant Reader. The demo relies on the already-present lenient-deserialization behavior; no new routing key, no dual-publish. Targets Ideal tier for criterion 7 deliberately rather than reaching for Maximal's full Expand-and-Contract/live-migration bar.

---

### Q2 — Which event and field carries the breaking change?

✅ **Question.** Two real candidates: (a) use the **already-existing `Email` drift** on `order.created` (`OrderBeans.OrderCreatedPayload` has it, `PayBeancoins`' copy doesn't) as the demo — turn a real, already-present gap into the demonstrated fix; or (b) pick a **fresh additive field** on a different event not already drifted — the audit's suggestion was `PaymentSucceededPayload` gaining an optional `OrderNote`, published by PayBeancoins and consumed by both CookerBeaners and BeanNotifs, good for showing multiple unaffected consumers at once.

**Why it matters.** Option (a) is thematically honest (closes a gap this very audit found) but risks reading as "explaining away a pre-existing bug" rather than a deliberately engineered demo. Option (b) is a clean, deliberate demonstration untangled from existing drift, and has two consumers to show staying unaffected instead of one. Blocks naming the specific AsyncAPI spec and the specific `40_implementation.md` step.

**Resolution.** ✅ 2026-10-29, revised after a concern raised mid-drafting — fixing the `Email` drift alone isn't a real schema evolution: `OrderBeans` already sends `Email` today, so correcting `PayBeancoins`' copy to declare it is a consumer catching up to an already-stable shape, not a producer evolving its API. No genuine "v1 → v2" to narrate. **Combined approach:** the `Email` fix still happens (it's free, risk-free, and resolves Q4 regardless), but the actual breaking-change demo is a **new** producer-side change layered on top — `OrderBeans` adds a new optional field, `DeliveryNote` (string?), to `OrderCreatedPayload` and starts sending it. That's deployed to `OrderBeans` alone; `PayBeancoins` (now already fixed to declare `Email`, but still not declaring `DeliveryNote`) keeps working unmodified, thanks to the same Tolerant Reader property from Q1 — this is the genuine v1→v2 story.

---

### Q3 — Does the idempotency guard go in one consumer or all three?

✅ **Question.** `10_target_shape.md`'s success criteria only require "a chosen consumer" to demonstrate safe redelivery handling. Should the `EventId`-dedup guard be added to just the one consumer used for the live demo, or to all three (PayBeancoins, CookerBeaners, BeanNotifs), since it's the same small, copy-pasted snippet each time (consistent with the project's established plumbing-copy-paste convention)?

**Why it matters.** Rubric wording for Maximal is "Konsumenten" (plural) — "consumers ignore or handle duplicate messages." Guarding all three is a stronger, more honest claim to that tier and costs little extra (same snippet, three repos instead of one) but does mean touching three repos' PRs instead of one.

**Resolution.** ✅ 2026-10-29 — all three (PayBeancoins, CookerBeaners, BeanNotifs) get the `EventId`-dedup guard, not just the one used in the live demo.

---

### Q4 — Does the existing `Email` drift get fixed regardless of Q2's answer?

✅ **Question.** Independent of whether `order.created`/`Email` is chosen as the breaking-change demo (Q2), should `PayBeancoins`' `OrderCreatedPayload` be corrected to include `Email` as part of writing its AsyncAPI spec (since the spec needs to describe one true shape, and the publisher's shape — with `Email` — is the one PayBeancoins is actually sent today)? The field is currently unread by PayBeancoins either way, so adding it is risk-free.

**Why it matters.** If Q2 picks a *different* event for the demo, this drift would otherwise sit there, now formally documented as a known inconsistency rather than fixed — worth a deliberate answer either way rather than leaving it unaddressed by default.

**Resolution.** ✅ 2026-10-29 — yes, fixed regardless. `PayBeancoins`' `OrderCreatedPayload` gains `Email`, matching what `OrderBeans` already sends. Folded into the same `40_implementation.md` step as Q2's `DeliveryNote` addition, since both touch the same spec/payload.

---

**Exit criterion:** Every question is ✅ resolved, ❌ dropped, or ⚠️ blocked-with-blocker. Mark ✅ in `README.md` when complete.
