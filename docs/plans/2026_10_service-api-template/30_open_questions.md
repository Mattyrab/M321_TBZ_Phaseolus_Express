# 30 — Open questions

Specific decisions that block implementation. Resolved inline here (same session, per this project's established pattern) — flag disagreement and I'll revise.

## Questions

### Q1 — What slice of the template does BeanApp get?

✅ **Question.** BeanApp is the one service that doesn't fit the "publish and/or consume RabbitMQ events" shape the other four do — per the architecture plan's Step 10, it only needs to fetch a Keycloak client-credentials token and call OrderBeans' `POST /orders` over plain HTTP. Does BeanApp adopt the full template (publisher + consumer, even unused), a partial slice, or none of the RabbitMQ plumbing at all?

**Why it matters.** Copy-pasting the full template into BeanApp "for uniformity" would add a RabbitMQ connection, an exchange declaration, and a consumer hosted service that never binds any queue — dead code with a live connection to a broker BeanApp doesn't need, and more importantly a connection-failure mode (RabbitMQ unreachable) that would make BeanApp's readiness probe flap for a dependency it has no actual use for.

**Resolution.** ✅ 2026-10-13 — **none of the RabbitMQ plumbing.** BeanApp gets only the universal slice (health checks, `/metrics`, env-driven config) plus a new piece unique to it: a small `KeycloakTokenClient` (fetches/caches a client-credentials token) and an `HttpClient`-based call to OrderBeans' `POST /orders`, wired into the existing (currently stub) `Cart` page's checkout action. It does **not** get `EventPublisher` or `EventConsumerHostedService` — it never publishes or consumes a RabbitMQ message in this design. Its existing Razor Pages + Identity UI is untouched.

---

### Q2 — How are a service's queue/routing-key bindings configured?

✅ **Question.** Hard-coded in `Program.cs` (a literal list of `(queueName, routingKey, handler)` tuples) vs. driven by `appsettings.json`/env-var-based configuration that could change per deployment without a rebuild.

**Why it matters.** Determines whether the "light modification" per service touches code or config, and whether the topology (already fixed by Q5) is ever meant to vary at deploy time.

**Resolution.** ✅ 2026-10-13 — **hard-coded in `Program.cs`.** The exchange/queue/routing-key topology is a design-time decision already fixed in Q5 — it is not meant to be reconfigurable per deployment, and adding a config schema for something that never varies at runtime would be speculative flexibility `docs/CLAUDE.md` explicitly discourages. A service's bindings are a literal array passed to `AddPhaseolusConsumer(...)` at startup; changing what a service listens to is a code change (and should be, since it changes which handler method needs to exist).

---

### Q3 — Health check shape and k8s probe mapping

✅ **Question.** A trivial custom `/health` endpoint that always returns 200, vs. ASP.NET Core's built-in `Microsoft.Extensions.Diagnostics.HealthChecks` with real dependency checks (RabbitMQ connection open? DB reachable?) split across liveness/readiness.

**Why it matters.** A liveness probe that checks RabbitMQ connectivity would cause Kubernetes to kill-and-restart a pod whose *process* is fine but whose broker is briefly unreachable — the wrong failure response (restarting doesn't fix a broker outage, and causes a restart storm). Readiness, not liveness, is what should reflect "can't currently do useful work."

**Resolution.** ✅ 2026-10-13 — use `Microsoft.Extensions.Diagnostics.HealthChecks`, split in two:
- **`/healthz/live`** — trivial, always-healthy-if-the-process-is-responding check. Maps to the k8s `livenessProbe`.
- **`/healthz/ready`** — checks the service's actual dependencies: RabbitMQ connection open (for any service with `EventPublisher`/`EventConsumerHostedService`), and/or DB reachable (BeanApp → Postgres). Maps to the k8s `readinessProbe`. A service with no RabbitMQ dependency (BeanApp) only checks what it actually depends on (DB) — not RabbitMQ it never touches (consistent with Q1).

---

### Q4 — Where does the reference implementation live?

✅ **Question.** A dedicated `/templates` (or `/scaffold`) folder in this meta repo that the other four repos copy *from*, vs. no separate template — OrderBeans itself (the first service built, per the architecture plan's causal build order) *is* the reference, and PayBeancoins/CookerBeaners/BeanNotifs copy the relevant files directly from it.

**Why it matters.** A meta-repo template folder is an extra artifact to keep in sync with whatever OrderBeans actually ends up looking like after Step 6 is really implemented (two places claiming to be "the" reference invites drift between them). Affects whether this plan's Step 6 implementation task (below) produces a meta-repo folder or just OrderBeans itself.

**Resolution.** ✅ 2026-10-13 — **no separate template folder.** OrderBeans is the reference implementation (it has to be fully built anyway, as the first service in the causal chain per the architecture plan's Step 6), and the other three copy the plumbing files directly from OrderBeans' repo once it exists. This avoids a second artifact that could drift from the real thing, and keeps the meta repo thin (consistent with the architecture plan's own framing of this repo as orchestration-only, `../2026_09_phaseolus-architecture/10_target_shape.md`). The exact file list to copy is enumerated in `40_implementation.md`.

---

### Q5 — Does the template address the parked poison-message risk?

✅ **Question.** The architecture plan flagged (`../2026_09_phaseolus-architecture/50_followups.md`) that plain nack-and-requeue with no dead-letter exchange means a poison message loops forever. Does this plan's generic consumer leave that entirely unaddressed (matches the architecture plan's as-decided scope exactly), or add a cheap guard without building a full DLX?

**Why it matters.** A full DLX is explicitly out of scope (non-goal, `10_target_shape.md`), but an unbounded requeue loop is a real failure mode a grading demo could hit by accident (e.g. a bug in a handler), and the fix is a few lines inside plumbing code this plan is writing anyway.

**Resolution.** ✅ 2026-10-13 — add a **cheap redelivery-count guard**, not a DLX. `EventConsumerHostedService` reads the message's `x-death` header count (populated by RabbitMQ on requeue); after a small fixed threshold (5 redeliveries), it logs the message as dropped and acks it instead of nacking — stopping the loop without standing up an exchange/queue for dead-lettering. This directly addresses the parked risk at near-zero cost since the consumer plumbing is being written from scratch regardless; a real DLX remains out of scope and stays parked in `50_followups.md`.

---

**Exit criterion:** Every question is ✅ resolved, ❌ dropped, or ⚠️ blocked-with-blocker. Mark ✅ in `README.md` when complete.
