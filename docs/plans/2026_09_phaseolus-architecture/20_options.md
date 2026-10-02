# 20 — Options

Design alternatives that satisfy `10_target_shape.md`. **At least three.** If you can only think of one, the problem isn't framed yet — go back to `10`. Each rejected option needs a stated reason; "didn't pick it" is not a reason.

The decision this phase resolves: **how do the five services integrate to run the order → pay → cook → notify flow, and how does this meta repo/Argo CD deploy them together?** Product choices (RabbitMQ, Keycloak, Traefik, Prometheus/Grafana, Argo CD, Kubernetes/minikube) are fixed per `10_target_shape.md`'s non-goals — each option below is a different *shape*, not a different toolset. IAM and metrics wiring specifics (which routes are protected, which dashboards exist) are deliberately left to `30_open_questions.md`/`40_implementation.md` rather than turned into more options here, to keep this phase to the one structural fork that most shapes everything downstream.

## Option A — Choreographed events, App-of-Apps with centralized manifests

**Shape.** Every service publishes domain events to RabbitMQ topic exchanges (`order.created`, `payment.succeeded`, `payment.failed`, `order.cooked`) and each downstream service independently subscribes to what it needs — no central coordinator decides "what happens next." BeanApp talks synchronously only to OrderBeans (create order, via Traefik) for the immediate "order accepted" response; everything downstream is async. This meta repo holds a `k8s/` directory with plain manifests for *all* five services plus infra, and Argo CD's root Application uses the "app of apps" pattern to declare one child Application per service/component, all sourced from this one repo.

**Pros.**
- Strong, genuine RabbitMQ pub/sub story — directly demonstrates the message-broker requirement as real inter-service choreography, not a thin RPC wrapper.
- Services stay decoupled: adding a consumer (e.g. a future analytics service) doesn't require touching existing publishers.
- Failure in one downstream consumer (e.g. BeanNotifs down) doesn't block the others.

**Cons.**
- Centralizing every service's manifest in this meta repo means a service-internal change (new env var, resource limit) still requires a meta-repo edit — contradicts the "meta repo is thin orchestration" framing in the root `README.md`/`inputs.md`, and adds coordination overhead with whoever maintains the five service repos.
- No single place to see "what's the status of order #123" — debugging the flow means correlating logs/messages across five services and RabbitMQ.

**Verdict.** ❌ rejected — satisfies the messaging goal well, but the centralized-manifest choice works against the "meta repo = orchestration only" framing and adds an ownership/coordination problem that Option C avoids at low cost.

---

## Option B — Central orchestrator + single meta-repo manifest set

**Shape.** OrderBeans (or a new orchestrator role) drives the flow explicitly: on order creation it calls PayBeancoins, then CookerBeaners, then BeanNotifs in sequence via RPC-over-RabbitMQ (request/reply queues) or direct REST, tracking each order's state itself (a simple saga). This meta repo's `k8s/` directory holds one manifest set for everything, synced by a single Argo CD Application; image tags are bumped by hand or a small script.

**Pros.**
- Order status is centrally visible — one service to query for "where is this order."
- Simplest possible Argo CD setup: one Application, one sync target, easiest to get working first on minikube.
- Simplest failure/retry logic: one place owns compensation if a downstream step fails.

**Cons.**
- Makes OrderBeans a bottleneck/coordinator that every other service depends on synchronously (even if the calls ride over RabbitMQ as RPC) — directly contradicts the `10_target_shape.md` goal of independent services reacting to messages, and the grading criterion of demonstrating genuine inter-service *operation*.
- RabbitMQ degrades to a transport for point-to-point RPC rather than pub/sub — a much weaker demonstration of "message broker" than what the assignment is testing for.
- Centralized manifests carry the same coordination downside as Option A, without Option A's messaging upside.

**Verdict.** ❌ rejected — easiest to build first, but undermines the two things this project is actually graded on: real inter-service messaging and independently operating services.

---

## Option C — Choreographed events, service-owned manifests, App-of-Apps

**Shape.** Same event choreography as Option A for the core flow (RabbitMQ pub/sub, BeanApp → OrderBeans stays a synchronous "order accepted" REST call), but each of the five service repos owns its own deploy manifest (e.g. a `/deploy` folder or small Helm chart in that repo). This meta repo stays thin: it holds only the root Argo CD "app of apps" Application (pointing one child Application per service straight at that service's own repo/path) plus the infra manifests (RabbitMQ, Keycloak, Traefik, Prometheus, Grafana) that don't belong to any single service.

**Pros.**
- Matches the actual framing of this repo — "meta repo for orchestration," not "meta repo that also contains every service's Kubernetes YAML."
- A service-internal change (resource limits, new env var, probe tuning) stays inside that service's own repo and its own Argo CD child Application — no meta-repo edit or cross-repo coordination needed for routine changes.
- Keeps the strong RabbitMQ choreography story from Option A.

**Cons.**
- Requires the five service repos to each gain a deploy manifest — under the "six repos, one team" constraint from `10_target_shape.md`, this needs coordination with whoever owns those repos before implementation can start there.
- Five separate Argo CD child Applications (plus infra) is more moving parts to configure correctly than Option B's single Application — more surface area for a first-time Argo CD setup to get wrong.
- Debugging the end-to-end flow has the same cross-service tracing cost as Option A (no central status view).

**Verdict.** ✅ selected — see Decision below.

---

## Decision

✅ **Selected:** Option C — choreographed events over RabbitMQ for the core flow, service-owned deploy manifests, Argo CD App-of-Apps from this meta repo.

**Why this over the others.** It's the only option that satisfies both of the two most consequential goals in `10_target_shape.md` at once: genuine RabbitMQ choreography (the message-broker requirement, done as real pub/sub rather than Option B's RPC-over-broker) *and* a meta repo that stays true to its own stated role as an orchestration layer rather than a dumping ground for every service's manifests (which Option A's centralized-manifest choice would turn it into). Option B was rejected first since it weakens the two things the assignment specifically grades.

**What we're explicitly accepting.** Coordination cost: before implementation, the five service repos need a deploy-manifest convention agreed (path, format) with whoever maintains them — this isn't fully this repo's call to make alone (see `10_target_shape.md`'s "six repos, one team" constraint). We're also accepting more Argo CD configuration surface (five child Applications instead of one) and no centralized order-status view — debugging the flow means reading logs/messages across services, which is judged an acceptable tradeoff for a project whose whole point is demonstrating inter-service operation.

---

**Exit criterion:** ≥3 options listed, one ✅ selected, others ❌ with reasons. Mark ✅ in `README.md` when complete.
