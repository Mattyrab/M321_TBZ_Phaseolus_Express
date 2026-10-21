# 40 — Implementation

Step plan for the chosen option from `20_options.md`. Each step has a verification.

## Plan summary

Build the plumbing once, inside OrderBeans, since it has to be fully built first anyway (architecture plan's causal order). Every subsequent service copies the relevant plumbing files verbatim and adds only its own bindings/handlers/payload records. BeanApp gets the thin, RabbitMQ-free slice (Q1). This plan's steps correspond to (and supersede the one-liner in) the architecture plan's Step 5, and feed directly into its Steps 6–10.

## Common building blocks (reference shape — every file below lives per-repo, copy-pasted, not shared)

**`Messaging/EventEnvelope.cs`** — the wire shape, identical in every repo that touches RabbitMQ:
```csharp
public record EventEnvelope(
    Guid EventId,
    string EventType,
    DateTimeOffset OccurredAt,
    Guid OrderId,
    JsonElement Payload);
```

**`Messaging/RabbitMqOptions.cs`** — bound from env vars (`RABBITMQ__HOST`, `RABBITMQ__PORT`, `RABBITMQ__USER`, `RABBITMQ__PASS`), not appsettings — these come from a k8s Secret/ConfigMap per pod.

**`Messaging/EventPublisher.cs`** — used by OrderBeans, PayBeancoins, CookerBeaners (not BeanNotifs, not BeanApp — Q1). Opens one long-lived connection/channel, declares `phaseolus.events` (topic, durable) idempotently, exposes `Publish(string routingKey, EventEnvelope envelope)` → serializes, publishes as a persistent message.

**`Messaging/EventConsumerHostedService.cs`** — used by PayBeancoins, CookerBeaners, BeanNotifs (not OrderBeans, not BeanApp). A `BackgroundService` registered with a list of `(string queueName, string routingKey, Func<EventEnvelope, Task> handler)` bindings:
- Declares the exchange idempotently, declares+binds each configured queue.
- Consumes with manual ack: on handler success, ack; on handler exception, check the message's `x-death` redelivery count — if ≥ 5, log-and-drop (ack anyway, per Q5 of `30_open_questions.md`); otherwise nack-and-requeue.
- One instance per service, configured with that service's specific bindings — this is the "light modification" surface.

**Health/metrics — identical one-liners in every service:**
```csharp
builder.Services.AddHealthChecks()
    .AddCheck("self", () => HealthCheckResult.Healthy(), tags: ["live"]);
    // + .AddRabbitMQ(...) or .AddNpgSql(...) tagged "ready", only where that dependency actually exists (Q1, Q3)
...
app.MapHealthChecks("/healthz/live", new() { Predicate = c => c.Tags.Contains("live") });
app.MapHealthChecks("/healthz/ready", new() { Predicate = c => c.Tags.Contains("ready") });
app.UseHttpMetrics();
app.MapMetrics(); // prometheus-net, serves /metrics
```

**`Dockerfile`** — identical multi-stage template across all five repos; only the `.csproj`/DLL filename differs.

**`/deploy/deployment.yaml` + `/deploy/service.yaml`** — near-identical; probes point at `/healthz/live` and `/healthz/ready`, env vars supply `RABBITMQ__*` (where applicable) from a shared `infra`-namespace Secret via `envFrom`.

## Per-service deltas

| Service | Publisher | Consumer | Bindings | Auth | Extra HTTP endpoint |
|---|---|---|---|---|---|
| OrderBeans | ✅ | — | publishes `order.created` | JwtBearer on `POST /orders` (Q7) | `POST /orders` |
| PayBeancoins | ✅ | ✅ | binds `pay.incoming-orders` ← `order.created`; publishes `payment.succeeded`/`payment.failed` | — | — |
| CookerBeaners | ✅ | ✅ | binds `cooker.paid-orders` ← `payment.succeeded`; publishes `order.cooked` | — | — |
| BeanNotifs | — | ✅ | binds `notifs.payment-failed` + `notifs.order-cooked` | — | `GET /notifications` |
| BeanApp | — | — | *(none — Q1)* | fetches a client-credentials token to call OrderBeans | existing Razor Pages + Cart checkout → calls OrderBeans |

## Steps

### Step 1 — Build the reference implementation in OrderBeans

✅ **Do.** Scaffold OrderBeans as a Minimal API project: the common building blocks above, `EventPublisher` only, `JwtBearer` validating against the `phaseolus` realm's OIDC discovery doc (issuer/signature/expiry only, per Q7), `POST /orders` that validates the token then publishes `order.created` (Q5's payload shape). Add `Dockerfile` and `/deploy/{deployment,service}.yaml`.

**Verify.** `dotnet build` and `docker build` succeed. `curl -X POST /orders` with no `Authorization` header → `401`; with a client-credentials token (fetched directly from Keycloak for this test) → `2xx`, and the message appears in RabbitMQ's management UI on `pay.incoming-orders`. `curl /healthz/live`, `/healthz/ready`, `/metrics` all return `200`.

✅ **Done 2026-10-21 (live, against the deployed cluster) —** verified as part of `../2026_09_phaseolus-architecture/40_implementation.md` Step 6. `dotnet build`/`docker build` ✅; unauthenticated → `401`; authenticated (in-cluster-fetched token) → `202` with a real `orderId`; message confirmed to have reached `pay.incoming-orders` by observing it flow all the way through to BeanNotifs (Steps 2–4 below).

---

### Step 2 — Copy into PayBeancoins

✅ **Do.** Copy `EventEnvelope`, `RabbitMqOptions`, `EventPublisher`, `EventConsumerHostedService`, the health/metrics wiring, `Dockerfile`, and `/deploy/*` from OrderBeans. Drop the `JwtBearer`/`POST /orders` pieces (not needed here). Add: bindings for `pay.incoming-orders` ← `order.created`; a handler implementing the Rotten-Beans rule (Q8); publishes `payment.succeeded`/`payment.failed`.

**Verify.** Publishing a test `order.created` message (via RabbitMQ's management UI) with normal items → a `payment.succeeded` message appears on `cooker.paid-orders`. Same with an item named `"Rotten Beans"` → `payment.failed` with the Q8 reason appears on `notifs.payment-failed`, nothing on `cooker.paid-orders`. Health/metrics endpoints respond.

✅ **Done 2026-10-21 (live).** Verified via the real flow rather than a hand-crafted test message: a normal order through OrderBeans produced `payment.succeeded` → `order-cooked` downstream; a `"Rotten Beans"` order produced `payment.failed` (with the exact Q8 reason text) and zero `cooker.paid-orders` activity for that order (no corresponding `order-cooked` ever appeared).

---

### Step 3 — Copy into CookerBeaners

✅ **Do.** Same copy as Step 2, minus the Rotten-Beans rule. Bindings: `cooker.paid-orders` ← `payment.succeeded`; publishes `order.cooked`.

**Verify.** A `payment.succeeded` test message produces an `order.cooked` message on `notifs.order-cooked`. Health/metrics respond.

✅ **Done 2026-10-21 (live).** Confirmed via the same end-to-end orders as Step 2 — every successful payment produced exactly one `order-cooked` entry in BeanNotifs.

---

### Step 4 — Copy into BeanNotifs

✅ **Do.** Copy `EventEnvelope`, `RabbitMqOptions`, `EventConsumerHostedService` (no `EventPublisher` — this service never publishes), health/metrics, `Dockerfile`, `/deploy/*`. Bindings: both `notifs.payment-failed` and `notifs.order-cooked`. Add `GET /notifications` backed by an in-memory list populated by both handlers (per the architecture plan's Step 9 — a real delivery channel is out of scope).

**Verify.** `GET /notifications` shows one entry per consumed message, each traceable to its `orderId`; one test message per queue produces one entry each.

✅ **Done 2026-10-21 (live).** `GET /notifications` showed correct, distinct entries per `orderId` for both event types across three real orders placed during this session's verification pass.

---

### Step 5 — Add the thin slice to BeanApp

✅ **Do.** No RabbitMQ plumbing (Q1). Add: health/metrics wiring (same one-liners, `/healthz/ready` checks Postgres only). Add a `KeycloakTokenClient` (fetches + caches a client-credentials token from the `phaseolus` realm) and wire the `Cart` page's (currently stub) checkout action to call OrderBeans' `POST /orders` with that token attached.

**Verify.** Submitting a test order from BeanApp's Cart page results in a `2xx` from OrderBeans and the corresponding message on `pay.incoming-orders`. `/healthz/live`, `/healthz/ready`, `/metrics` all respond on BeanApp too.

✅ **Done 2026-10-21, with one correction.** The `KeycloakTokenClient`/Cart-checkout wiring itself was already implemented and worked correctly once deployed (verified live via a real form POST to `/Cart`, including a valid antiforgery token — "Order placed! OrderBeans accepted it.", propagating through to a new `order-cooked` notification). However, `/healthz/ready` was still wired to **Postgres** as this step originally specified — that assumption is now wrong: BeanApp's ASP.NET Identity + PostgreSQL were **removed entirely** (unused default-template scaffolding, out of scope per the architecture plan's Q7). `/healthz/ready` now reports `self-ready` (trivially healthy, no external dependency), same pattern as the one-off health check convention used elsewhere. Containerization (Dockerfile + `/deploy/*`) was also done this session — it didn't exist yet going into it.

---

### Step 6 — Write up the convention for the team

⏳ **Do.** A short note (in OrderBeans' own `README.md`, once it exists, per Q4 — no separate meta-repo template folder) listing exactly which files are copy-pasted verbatim vs. per-service, pointing at this plan for the reasoning, so a teammate implementing Steps 3–4/the PayBeancoins or CookerBeaners repo doesn't have to re-derive the design from scratch.

**Verify.** A teammate unfamiliar with this plan can follow that note plus `00_current_state.md`'s table to correctly scaffold a new service without asking what files to copy.

⚠️ **Still not done.** OrderBeans' `README.md` is still the original one-liner ("Service handling ordering food.") — no convention write-up exists yet, even though Steps 1–5 are all complete and would make writing it trivial now. This is the one remaining gap in this sub-plan.

## Rollback / blast radius

Fully reversible — this is new code in repos that currently have no code (BeanApp aside, where only additive changes are made: new endpoints/health checks alongside the existing untouched Razor Pages). No manifest or image is deployed to the running minikube cluster by this plan alone; that happens under the architecture plan's own Steps 6–10, which this plan feeds into.

## Quality gates before merging (per service repo)

- `dotnet build` — compiles.
- `dotnet test` — at minimum, the redelivery-guard threshold (Q5) and, where applicable, the Rotten-Beans rule (Q8) and the 401-vs-200 auth behavior (OrderBeans) deserve a unit test each — cheap, catches regressions across a 5-repo project (mirrors the architecture plan's own quality-gate proposal, `../2026_09_phaseolus-architecture/40_implementation.md`).
- `docker build` succeeds.
- `kubectl apply --dry-run=client -f deploy/` validates.

---

**Exit criterion:** Every step ✅, gates green. Mark ✅ in `README.md` when complete.
