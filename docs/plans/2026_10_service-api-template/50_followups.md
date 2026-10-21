# 50 — Followups

The parking lot. Anything that came up while working on this plan but is **out of scope** for the current PR.

## Out of scope, parked for later

- ⏳ **Real dead-letter exchange.** This plan's redelivery-count guard (Q5, `30_open_questions.md`) stops an infinite requeue loop by logging-and-dropping after 5 attempts, but a dropped poison message is still silently lost rather than inspectable. A real DLX (separate exchange/queue to hold dropped messages for later inspection) remains the actual fix — same item already parked in `../2026_09_phaseolus-architecture/50_followups.md`, now with a concrete stop-gap in place instead of nothing.
- ⏳ **Shared plumbing package (Option C, `20_options.md`).** Rejected for now on coordination-cost grounds specific to this project's size/timeline. Worth revisiting only if the four-repo copy-paste genuinely becomes painful to keep in sync in practice — not a given, since the plumbing surface is small and fixed.
- ⏳ **BeanApp reacting to async events itself** (e.g. a live "your order is cooking" status on the Cart/order page, driven by a RabbitMQ consumer in BeanApp). Explicitly out of scope per Q1 — BeanApp's only interaction with the rest of the system is the synchronous `POST /orders` call. Would require revisiting Q1 if ever wanted.
- ⏳ **Readiness-check flakiness under RabbitMQ restarts.** Not investigated here: if RabbitMQ itself restarts (e.g. during a demo), how quickly `/healthz/ready` recovers once the connection is re-established depends on `EventPublisher`/`EventConsumerHostedService`'s reconnect behavior, which this plan specifies only at the level of "a long-lived connection" — the exact reconnect/backoff strategy is left to whoever implements Step 1, not pinned down here.

---

## Promoted to their own plan

<When a parked item gets serious enough to need its own folder, link the new plan here and tick the original entry ✅. Don't delete the entry — the trail matters.>

---

**Exit criterion:** N/A — this file lives forever as a record of what was deferred.
