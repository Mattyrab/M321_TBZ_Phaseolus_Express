# 10 — Target shape

What the change must produce. **Requirements, not solutions.** This is the interpretation of `inputs.md` against `00_current_state.md`. If you find yourself naming a model, table, or implementation detail, you're in `20_options.md` territory — back up.

## Goals

- **Every event type has a single, formally-specified, discoverable payload shape** — a reader (or a new consumer being written) can find out what a message looks like without reading the publisher's source code, and a change to that shape is visible as a change to the specification, not just a silent edit to one service's local record.
- **Drift between a publisher's payload and a consumer's own copy of it is something the project can point to and explain**, not an undetected accident — the existing `Email`-field drift (`00_current_state.md`) should become either fixed or a deliberately-documented example, not quietly left as-is.
- **At least one consumer can receive the same message twice (by `EventId`) and only act on it once** — a redelivery (crash-then-reconnect, or the existing retry mechanism) must not double-charge, double-cook, or double-notify.
- **A real payload change can be deployed to its publisher alone**, with every existing, not-yet-updated consumer continuing to run correctly against the new message shape — no coordinated/simultaneous deploy required.
- **The above is demonstrable live**, end-to-end, against the real running system — not just true in code review. This plan exists partly to produce the rubric's explicit live-demo checklist item ("Demonstration einer API-Änderung in einem Service, während abhängige Services ohne Ausfall weiterfunktionieren").

## Non-goals

- **No shared NuGet/build-time package between the service repos.** Already deliberately rejected twice — `docs/plans/2026_09_phaseolus-architecture/30_open_questions.md` Q2 and `docs/plans/2026_10_service-api-template/20_options.md` Option C — for team-size/timeline reasons that still apply. Any contract artifact this plan adds is documentation, not a compiled dependency.
- **No schema registry, contract-testing CI, or automated drift detection.** Worth wanting, but that's infrastructure work belonging to `../2026_10_docs-and-ci/`'s territory if it ever gets picked up — this plan's job is to close the rubric gap, not build a platform.
- **No dead-letter exchange, no persisted/external idempotency store (Redis, a database table).** `00_current_state.md`'s retry mechanism already survives pod restarts via the message header; an in-memory dedup guard is sufficient for this project's demo scale (`docs/CLAUDE.md`: "minimum code that solves the problem"). A DLX is a real gap but a separate one from idempotency — not in scope here unless it turns out to be the cheapest way to satisfy a goal above.
- **Not retrofitting every event type with a version suffix in one pass.** One real, deliberately-chosen breaking change carries the versioning scheme; the other four event types stay as they are unless the chosen option naturally requires touching them.
- **Not changing the fire-and-forget pub/sub architecture itself.** `00_current_state.md` confirms publishers already never block on a consumer — that part of criterion 3 is already satisfied and out of scope here.
- **Not building a second, parallel v1-and-v2-running-forever system.** The breaking-change demo needs to show an *isolated, safe* deploy — it doesn't need to prove the project can run two permanent versions of every service forever.

## Constraints

- **A breaking change must never require simultaneous deployment of two services.** This is the literal "Ungenügend" bar for criterion 7 (`inputs.md`) — failing this isn't a partial loss, it's the floor.
- **Must preserve the established "copy-paste, no shared package" convention** (see Non-goals) — whatever makes contracts "formal" must not quietly reintroduce a shared library through the back door.
- **Must not regress the existing, already-verified RabbitMQ/Keycloak/observability setup** from the `2026_10_sso-keycloak` and `2026_10_sso-admin-uis` plans — any change to `EventConsumerHostedService.cs`/`EventPublisher.cs` must keep the existing retry/ack/auth behavior intact unless the change is specifically about that behavior.
- **The idempotency fix must be cheap and local**, consistent with `docs/CLAUDE.md`'s "no abstractions for single-use code" — a single dedup check per consumer, not a generic framework.
- **The breaking-change demo must use a real message already in the system**, not a synthetic/toy example invented just for the demo — it needs to read as a credible, narrated part of the actual Phaseolus Express flow, not a side quest.
- **Whatever event is chosen for the breaking-change demo needs a consumer that's safe to leave unmodified** — i.e., don't pick a change where the "old" consumer would behave incorrectly (not just suboptimally) once the publisher changes. This is what makes "isolated deploy" credible rather than merely lucky.

## Success criteria

- A formal, versioned contract document exists for every event type currently in the system (`order.created`, `payment.succeeded`, `payment.failed`, `order.cooking-started`, `order.cooked`), each one's payload shape matching what's actually on the wire today (closing the drift gap, or documenting it as a deliberate example — whichever `20_options.md` picks).
- A chosen consumer, when manually handed a redelivery of a message it has already fully processed (same `EventId`), produces no duplicate observable side effect — concretely: no second Prometheus counter increment, no second notification-log entry, no second downstream publish for the same `EventId`. Demonstrated live by re-publishing a captured message and showing the counter/log does not move.
- A chosen payload change (additive) is deployed to its publisher service alone; its existing, unmodified consumer(s) keep running without error, without restart, and without any manual intervention through that deploy — demonstrated live by watching the consumer's logs/metrics/behavior stay healthy across the publisher's rollout.
- Running `setup.sh` against a freshly deleted `minikube` cluster still reproduces a fully working system afterward — same reproducibility bar every prior plan in this repo has held to.

---

**Exit criterion:** Requirements are testable, not vague. Mark ✅ in `README.md` when complete.
