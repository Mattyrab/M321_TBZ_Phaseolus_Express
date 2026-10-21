# 20 — Options

Design alternatives that satisfy `10_target_shape.md`. **At least three.** Each rejected option needs a stated reason.

The decision this phase resolves: **what form does the reusable "copy-paste with light modification" template take, and how generic is the RabbitMQ plumbing inside it?** The stack itself (C#/.NET 8, Minimal APIs, `RabbitMQ.Client`, `prometheus-net`, no shared package) is fixed by Q2 — each option below is a different *shape of code*, not a different toolset.

## Option A — No abstraction: inline RabbitMQ calls duplicated per service

**Shape.** Each service's `Program.cs` calls `RabbitMQ.Client` directly and in full: open a connection, declare the exchange, declare/bind its queue(s), call `BasicConsume`/`BasicPublish`, handle ack/nack inline, right there in `Program.cs` or a thin same-file handler. "Light modification" means editing these calls directly in each copy.

**Pros.**
- Zero abstraction to learn or document — anyone who knows `RabbitMQ.Client`'s raw API can read any service top-to-bottom.
- Fewest moving files per service.

**Cons.**
- The risky bits (manual ack discipline, exchange idempotent-declare, connection/channel lifetime, the redelivery-guard this plan wants to add) are hand-duplicated in up to four repos. A mistake in one (e.g. forgetting to ack, or acking before processing) has to be independently caught and independently fixed in each copy — there's no single place that "is" the correct pattern.
- Harder for a teammate to verify a new service "did it right" — the correctness of the risky plumbing is re-reviewed from scratch per repo instead of being true by construction.

**Verdict.** ❌ rejected — minimizes files but maximizes the chance the one part of this system that's genuinely easy to get subtly wrong (ack semantics) gets copy-paste-drifted across repos.

---

## Option B — Small per-repo plumbing layer, copy-pasted as a unit (not a package)

**Shape.** A handful of small classes — `EventEnvelope`, `EventPublisher`, `EventConsumerHostedService`, plus `AddPhaseolusHealthChecks()`/`AddPhaseolusMetrics()` extension methods — written once (in the first service built, OrderBeans) and copy-pasted as-is into each subsequent repo. Each service's own `Program.cs` only: registers the pieces it needs, lists its queue/routing-key bindings and handler delegates, and implements the handler bodies. The plumbing classes themselves are not meant to be edited per service — only the config/handlers around them are.

**Pros.**
- The risky logic (connect/declare/ack/nack/redelivery-guard) is written once, reviewed once, and every copy starts from a known-correct state — "light modification" becomes literal: a short config list plus handler bodies, nothing in the plumbing files needs to change.
- Still no shared package, no versioning, no build-time cross-repo dependency — matches Q2's explicit rejection of a shared contracts package, extended here to plumbing code for the same reason (team/timeline cost of hosting and versioning a private feed isn't worth it for 4-5 consumers).
- A bug found later in one copy is a known, bounded fix to hand-apply to the others (acceptable given this is a small, fixed set of files, not an open-ended surface).

**Cons.**
- Still duplicated across repos — a fix doesn't propagate automatically (same limitation as Option A, just with less surface area since the plumbing files themselves are meant to stay untouched).
- Requires writing and documenting the plumbing once before any service can be built against it — a small upfront cost Option A doesn't have.

**Verdict.** ✅ selected — see Decision below.

---

## Option C — Shared internal NuGet package for the plumbing (contracts stay separate)

**Shape.** Package only the plumbing (connection/publisher/consumer base class, health/metrics extensions) as a versioned NuGet package hosted on a local/private feed (e.g. a GitHub Packages feed under the team's org), referenced by all five repos. Message contracts (the payload records) stay per-repo, unpackaged, per Q2.

**Pros.**
- True single source of truth — a plumbing fix or improvement (e.g. a real DLX later) ships to every service by bumping a version number.
- Removes all hand-propagation risk from Option A/B.

**Cons.**
- Directly contradicts the literal ask in `inputs.md` ("copied und pasted with light modification") — the user is asking for a copy-paste template, not a package.
- Reintroduces exactly the cross-repo coordination and feed-hosting overhead that Q2 avoided by rejecting a shared contracts package — for a two-person school project on a tight timeline, standing up and authenticating against a private package feed is disproportionate to the benefit over Option B's "small, fixed set of files."
- A package version mismatch between repos becomes a new failure mode this project doesn't otherwise have.

**Verdict.** ❌ rejected — solves a problem (plumbing drift) that Option B already solves cheaply enough, at a coordination cost the project's own stated constraints (team size, no shared package, timeline) argue against.

---

## Decision

✅ **Selected:** Option B — a small, fixed set of plumbing classes (envelope, publisher, generic consumer, health/metrics extensions), written once against OrderBeans as the reference implementation, copy-pasted verbatim into each subsequent service repo; only the per-service config (bindings, handlers, payload records) is "light modification."

**Why this over the others.** It's the only option that satisfies the literal ask ("copy-paste with light modification") while still making the one genuinely risky piece of this system — RabbitMQ ack/nack/redelivery correctness — true by construction instead of re-derived per repo (Option A's failure mode) or requiring infrastructure the project's own constraints argue against (Option C's failure mode, and consistent with why Q2 already rejected a shared contracts package).

**What we're explicitly accepting.** The plumbing files are duplicated, not shared — if a bug is found in, say, the consumer's redelivery-guard logic after three services already copied it, fixing it means hand-applying the same patch to each repo. Judged acceptable because the plumbing surface is small and fixed (a handful of files, not an open-ended library), and because this matches the project's existing posture (Q2 already accepted the same tradeoff for message contracts).

---

**Exit criterion:** ≥3 options listed, one ✅ selected, others ❌ with reasons. Mark ✅ in `README.md` when complete.
