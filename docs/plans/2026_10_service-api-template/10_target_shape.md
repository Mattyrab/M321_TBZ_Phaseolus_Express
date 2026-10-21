# 10 — Target shape

What the change must produce. **Requirements, not solutions.** This is the interpretation of `inputs.md` against `00_current_state.md`. If you find yourself naming a class, file, or library call, you're in `20_options.md`/`40_implementation.md` territory — back up.

## Goals

- **A new service is scaffolded by copying an existing one and making small, obvious edits** — not by re-deriving RabbitMQ connection handling, exchange declaration, ack/nack semantics, metrics wiring, or health-check wiring from scratch each time. "Light modification" (per `inputs.md`) means: which queue(s)/routing key(s) to bind, which payload record(s) to deserialize, and the handler method bodies — nothing about the plumbing around them.
- **Every service exposes the same operational surface for Kubernetes**, regardless of what it does internally: a liveness endpoint, a readiness endpoint (reflecting its real dependencies — RabbitMQ, DB — not just "process is up"), and a Prometheus `/metrics` endpoint. A pod spec written against one service's health/metrics paths works unmodified against any other.
- **The messaging shape is uniform and matches the already-decided envelope/topology** (`00_current_state.md` Q5) — every service that touches RabbitMQ declares the same exchange the same way, and parses the same envelope. The *parsing* of `payload` (per `inputs.md`'s "parsed for whatever details are needed per service") is the one deliberately per-service piece: each service defines only the payload record(s) for the event(s) it actually consumes, ignoring the rest of the envelope shape.
- **Not every service needs the same slice of the template.** Some publish only, some consume only, some do both, one does neither (talks plain HTTP instead), and exactly one validates a JWT. The template must make each of these an explicit opt-in rather than force all five services to carry unused RabbitMQ/auth code.
- **Configuration is entirely environment-driven**, since every service runs as a Kubernetes pod (`inputs.md`, point 3): RabbitMQ host/credentials, DB connection strings, and the Keycloak issuer (where relevant) come from env vars / mounted config, never hardcoded, so the same built image runs correctly in any namespace without a rebuild.
- **The design is written down once and reproducible by someone who didn't design it** — a teammate implementing Steps 6–10 of the architecture plan should be able to follow this plan's `40_implementation.md` and produce a consistent result without re-deriving choices already made here.

## Non-goals

- **A shared NuGet package or library.** Already ruled out by Q2 (`00_current_state.md`) for message contracts specifically, and this plan extends the same reasoning to the plumbing code (RabbitMQ helpers, health checks, metrics wiring) — see `20_options.md`. The mechanism is copy-paste, not a dependency.
- **A generic/dynamic plugin system for arbitrary future event types.** Only the four events already fixed in Q5 exist; the template is built to make *those* easy to wire, not to anticipate event types nobody has designed yet.
- **Changing any already-resolved architecture-plan decision** — language/framework, exchange/queue names, manifest format, image tagging, namespace layout, auth scope, or the payment mock rule are fixed inputs here (`00_current_state.md`), not open for re-debate.
- **A dead-letter exchange or full poison-message handling.** The architecture plan explicitly parked this (`../2026_09_phaseolus-architecture/50_followups.md`). This plan may bake in a cheap redelivery-count guard (see `40_implementation.md`) but does not attempt a real DLX.
- **Rewriting BeanApp's existing Razor Pages/Identity UI.** That stays as-is; this plan only adds the operational surface (health/metrics) and the OrderBeans-calling piece to it.

## Constraints

- Must compose with the already-running infra from the architecture plan's Steps 1–4 (RabbitMQ in `infra`, Keycloak `phaseolus` realm, namespaces) without re-touching it.
- Must keep each of the five services independently buildable/deployable per-repo (architecture plan's Q3/Q4) — this plan's template is a *starting point* copied into each repo, not a dependency any of them import at build time.
- **Six repos, one team** (`../2026_09_phaseolus-architecture/30_open_questions.md` Q1): whatever reference implementation and copy-paste convention this plan settles on needs to be followable by a teammate working on a different repo, without this plan's author doing all five by hand.
- `docs/CLAUDE.md`'s guidelines apply: minimum code that solves the problem, no speculative abstraction, surgical changes.

## Success criteria

- A written description (this plan's `40_implementation.md`) exists such that: for each of OrderBeans/PayBeancoins/CookerBeaners/BeanNotifs, it's unambiguous which files are copied verbatim, which are copied-then-edited, and which are written fresh — and the same for BeanApp's smaller slice.
- The messaging plumbing's failure-mode behavior (ack/nack, redelivery guard) is specified precisely enough that two people implementing two different services independently would produce compatible, equally-correct consumers.
- Every service's health/metrics/config convention is specified precisely enough to write one Kubernetes probe/scrape template and reuse it, only substituting the service name/port.
- The plan explicitly states which services get which slice of the template (publisher / consumer / both / neither, auth yes/no) so nobody copy-pastes RabbitMQ or JWT code into a service that doesn't need it (e.g. BeanApp).

---

**Exit criterion:** Requirements are testable, not vague. Mark ✅ in `README.md` when complete.
