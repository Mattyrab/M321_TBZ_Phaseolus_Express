# 30 — Open questions

Specific decisions that block implementation. Each question has a clear path to resolution. **No vibes-questions** ("is this a good idea?") — split those into the underlying yes/no decisions.

Resolve every question to ✅ or ❌ before starting `40_implementation.md`. If a question can't be answered now, either move it to `50_followups.md` (out of scope) or mark it ⚠️ blocked with a named blocker.

## Questions

### Q1 — Who implements the five service repos?

✅ **Question.** Is `Timposter8107` (owner of `M321_TBZ_Phaseolus_WebApp`/`Order`/`Pay`/`Cooker`/`Notifs`) a teammate splitting this project with you, or your own second account? Pick one: (a) solo — you have full write access to all six repos, or (b) team — coordination with another person is needed for any change to the five service repos.

**Why it matters.** Option C (`20_options.md`) requires each service repo to gain its own deploy manifest. If (b), that work needs to be assigned/agreed with the other person before `40_implementation.md` can schedule it; if (a), it's just sequencing on one person's plate.

**Resolution.** ✅ 2026-09-25 — (b) team: `Timposter8107` is a teammate, not your own account. Changes to the five service repos (deploy manifests, Dockerfiles, RabbitMQ/Keycloak/Prometheus integration per Q2–Q8) need to be coordinated with them rather than done unilaterally — `40_implementation.md` should sequence/assign steps accordingly rather than assume one person does everything.

---

### Q2 — Language/framework per service

✅ **Question.** What language + web framework will each of the five services use — one uniform choice across all five (e.g. all Node/Express, all Python/FastAPI), or a per-service choice? Name the pick(s).

**Why it matters.** Blocks writing Dockerfiles, blocks how Prometheus metrics get exposed (client library differs per language), and blocks the deploy-manifest work in Q3 (a manifest needs a concrete image/port/health-check to reference). Currently fully open per `00_current_state.md`.

**Resolution.** ✅ 2026-09-25 — C# / .NET 8, uniform across all five services. Adjacent details fixed as part of this resolution:
- **Framework:** ASP.NET Core, Minimal APIs (not MVC controllers).
- **Hosting shape:** all five are ASP.NET Core Web Apps, even the primarily-message-consuming ones (PayBeancoins, CookerBeaners, BeanNotifs) — each needs a small HTTP surface anyway for the Prometheus `/metrics` endpoint, so one project template covers all five uniformly.
- **RabbitMQ client:** official `RabbitMQ.Client` package used directly (not MassTransit/Rebus), to keep exchange/queue/routing-key mechanics explicit in code rather than abstracted away.
- **Metrics:** `prometheus-net` / `prometheus-net.AspNetCore`.
- **Auth:** `Microsoft.AspNetCore.Authentication.JwtBearer`, validating Keycloak-issued JWTs via Keycloak's OIDC discovery endpoint.
- **Docker:** multi-stage build, `mcr.microsoft.com/dotnet/sdk:8.0` (build) → `mcr.microsoft.com/dotnet/aspnet:8.0` (runtime).
- **Message contracts:** no shared NuGet package across the four repos — each service defines its own local C# record matching the JSON event shape agreed in Q5.

---

### Q3 — Deploy-manifest format and location per service repo

✅ **Question.** Given Option C (each service repo owns its manifest), pick one format: (a) plain Kubernetes YAML under a `/deploy` folder in each service repo, (b) a small per-service Helm chart, or (c) Kustomize base+overlay per service repo. Argo CD's App-of-Apps needs one consistent answer across all five so the root Application's child-Application template is uniform.

**Why it matters.** Directly blocks setting up the Argo CD App-of-Apps root Application in this meta repo — it needs to know what kind of source each child Application points at.

**Resolution.** ✅ 2026-09-25 — (a) plain Kubernetes YAML under a `/deploy` folder in each service repo (`Deployment`, `Service`, and, where the service is directly Traefik-exposed, an `IngressRoute`/`Ingress`). No Helm or Kustomize — five near-identical ASP.NET Core services (per Q2) don't need templating machinery yet; each repo's Argo CD child Application in the App-of-Apps root simply points at `<repo>/deploy`.

---

### Q4 — Container registry and image tagging scheme

✅ **Question.** Where are the five services' images pushed (Docker Hub, GitHub Container Registry, a local minikube-only registry), and how are tags decided (git SHA, semver, or `latest`)?

**Why it matters.** Argo CD needs a concrete image reference to sync to, and this determines whether "push a new image" alone triggers a deploy or whether a manifest edit (tag bump) is also required — which is exactly what the `10_target_shape.md` deployment success criterion tests.

**Resolution.** ✅ 2026-09-25 — no external registry: images are built locally per service (one image per service repo, confirmed) and loaded directly into minikube's runtime via `minikube image load <service>:<sha>` (or building inside `eval $(minikube docker-env)`); tagged with the **git commit SHA** of the service repo.

Consequence this locks in for `40_implementation.md`: since there's no registry to pull from, every `Deployment` manifest (from Q3's `/deploy` folder) must set `imagePullPolicy: Never`, and the image with that exact SHA tag must already be loaded into minikube *before* the manifest bump reaches it — Kubernetes won't fetch it over the network. The pipeline shape is therefore: build image → `minikube image load` (local, manual step, since minikube isn't reachable from external CI) → bump the SHA tag in the service repo's `/deploy` manifest → commit/push → Argo CD syncs the tag change into the running Deployment. This still satisfies the "no manual `kubectl apply`" success criterion (Argo CD does the actual deploy step from the git-tracked manifest), with the accepted tradeoff that image publishing itself is a local, single-machine step rather than a real CI→registry pipeline — consistent with the single-node-minikube constraint from `10_target_shape.md`.

---

### Q5 — RabbitMQ exchange/queue topology

✅ **Question.** For the choreographed flow selected in `20_options.md`, name the concrete exchange type (topic exchange recommended, given routing-key-based fan-out) and the routing keys/queue names for each step: order created, payment succeeded, payment failed, order cooked, notification sent. Does BeanNotifs subscribe to multiple event types (payment failure *and* cook completion), or only the happy path?

**Why it matters.** This is the literal shape of "the message broker" — OrderBeans/PayBeancoins/CookerBeaners/BeanNotifs can't be implemented against an undefined contract, and this is the piece every one of the four service repos needs to agree on identically.

**Resolution.** ✅ 2026-09-25 —

**Exchange.** One topic exchange, `phaseolus.events`, durable. Each service declares it idempotently (same name/type/durable=true) on startup before binding its own queue — no separate infra-bootstrap step needed.

**Routing keys (events).**
| Routing key | Published by | Consumed by |
|---|---|---|
| `order.created` | OrderBeans | PayBeancoins |
| `payment.succeeded` | PayBeancoins | CookerBeaners |
| `payment.failed` | PayBeancoins | BeanNotifs |
| `order.cooked` | CookerBeaners | BeanNotifs |

**BeanNotifs subscribes to both** `payment.failed` and `order.cooked` — confirmed multi-event consumer, since both are user-relevant outcomes (payment failed → tell the user; order cooked → tell the user it's ready). This also gives Q8's failure path a visible, demoable consequence.

**Queue naming/ownership.** Each *consumer* declares and owns its own durable queue, named `<consumer>.<purpose>`, bound to `phaseolus.events` with the one routing key it needs:
- `pay.incoming-orders` ← `order.created`
- `cooker.paid-orders` ← `payment.succeeded`
- `notifs.payment-failed` ← `payment.failed`
- `notifs.order-cooked` ← `order.cooked`

Publishers only ever publish to the exchange and never declare or know about a consumer's queue — standard pub/sub decoupling.

**Message envelope (JSON, shared shape across repos since there's no shared contracts package per Q2).**
```json
{
  "eventId": "guid",
  "eventType": "order.created",
  "occurredAt": "2026-09-25T12:00:00Z",
  "orderId": "guid",
  "payload": { }
}
```
`payload` per event type:
- `order.created`: `{ "items": [{ "name": "string", "quantity": 1 }], "totalAmount": 0.0 }`
- `payment.succeeded`: `{ "amountCharged": 0.0 }`
- `payment.failed`: `{ "reason": "string" }`
- `order.cooked`: `{ }` (orderId alone is sufficient)

**Delivery/ack semantics.** Manual ack after successful processing; nack-and-requeue (no dead-letter exchange) on failure. A DLX/retry-limit is deliberately not in scope for this first pass — parked in `50_followups.md` if it turns out to be needed.

---

### Q6 — Namespace layout in minikube

✅ **Question.** One flat namespace for everything, or split (e.g. `phaseolus` for the five services, `infra` for RabbitMQ/Keycloak/Traefik/Prometheus/Grafana/Argo CD)? Pick one.

**Why it matters.** Affects every manifest's `metadata.namespace`, Traefik's routing rules, and how Prometheus is configured to discover scrape targets (single-namespace vs cross-namespace service discovery).

**Resolution.** ✅ 2026-09-25 — three-way split, not two:
- **`phaseolus`** — the five services (BeanApp, OrderBeans, PayBeancoins, CookerBeaners, BeanNotifs).
- **`infra`** — RabbitMQ, Keycloak, Traefik, Prometheus, Grafana.
- **`argocd`** — Argo CD itself, left on its own standard install namespace rather than folded into `infra`, since Argo CD's own install manifests default to `argocd` and fighting that default buys nothing.

Mechanically this is cheap: each Argo CD child Application (from the App-of-Apps root, `20_options.md`) just sets its own `spec.destination.namespace`; Prometheus discovers scrape targets cluster-wide via pod/service role discovery with no namespace restriction, so split namespaces cost nothing there; cross-namespace traffic (services in `phaseolus` calling Keycloak/RabbitMQ in `infra`, Traefik `IngressRoute`s in `infra` routing to Services in `phaseolus`) works by default over cluster DNS (`<service>.<namespace>.svc.cluster.local`) since no `NetworkPolicy` is in scope (matches the "no production-grade hardening" non-goal). `kubectl get pods -A` (per `10_target_shape.md`'s success criterion) still shows everything in one view regardless of the split.

---

### Q7 — Scope of Keycloak enforcement

✅ **Question.** Which specific request path gets IAM-protected to satisfy the `10_target_shape.md` success criterion ("a request with no valid token is rejected, one with a valid token succeeds")? Candidates: (a) BeanApp requires end-user login before placing an order, (b) OrderBeans' order-creation endpoint requires a valid token regardless of caller, (c) both. Pick one scope for the first pass.

**Why it matters.** `10_target_shape.md` only requires *one* real boundary to exist and be observably checked — over-scoping this (protecting every service) adds work the grading criteria doesn't require and the non-goals explicitly discourage (production-grade hardening is out of scope).

**Resolution.** ✅ 2026-09-25 — **(b): OrderBeans' order-creation endpoint requires a valid Keycloak-issued bearer token**, regardless of caller. Chosen over (a)/(c) because it's the genuinely *inter-service* boundary — matches `inputs.md`'s priority ("operation between systems matters more than end-user features") — whereas (a) is end-user login UX, which the non-goals already deprioritize, and (c) adds scope the success criterion doesn't require.

Mechanics this implies for `40_implementation.md`:
- **Realm:** `phaseolus`, in the `infra`-namespace Keycloak (per Q6).
- **Client:** BeanApp is registered as a confidential client (`beanapp-client`) with the **client-credentials grant** and service account enabled — no end-user login flow. On startup/per-request, BeanApp fetches a token via client-credentials and attaches it as `Authorization: Bearer <token>` when calling OrderBeans.
- **Validation on OrderBeans:** standard `JwtBearer` validation against Keycloak's OIDC discovery document for the `phaseolus` realm — issuer, signature, and expiry only. **No role/scope-based authorization** — any validly-issued token is sufficient. Fine-grained RBAC is explicitly not attempted here, consistent with the "no production-grade hardening" non-goal.
- **Testable directly:** `curl` OrderBeans' order-creation endpoint with no `Authorization` header → 401; with a token obtained via client-credentials from the `phaseolus` realm → 2xx. This is the literal success criterion from `10_target_shape.md`.

---

### Q8 — Payment mock behavior

✅ **Question.** Does PayBeancoins (a) always succeed, (b) fail on a fixed probability/random basis, or (c) fail based on a specific test input (e.g. an order amount or item name that deterministically triggers failure)?

**Why it matters.** The success criteria in `10_target_shape.md` imply the flow should be demonstrably traceable end-to-end; showing *both* the payment-succeeded and payment-failed branches reacting correctly (CookerBeaners never starts on failure, BeanNotifs still fires a failure notice) is a stronger demo than only ever exercising the happy path. (c) makes the failure path repeatable on demand for a live demo.

**Resolution.** ✅ 2026-09-25 — **(c): deterministic trigger**, not random. PayBeancoins inspects the `order.created` event's `items` (per Q5's payload shape) and fails the payment if any line item's name case-insensitively equals the reserved sentinel **`"Rotten Beans"`**; any other order succeeds. Rejected (a) outright (never exercises the failure branch — weaker demo) and (b) specifically because randomness is a liability in a live grading demo: a probabilistic failure might simply not fire when it's being shown, and isn't reproducible for debugging.

This is a testing convention, not a UI requirement — whoever builds BeanApp's (intentionally minimal, per non-goals) ordering UI can either expose "Rotten Beans" as a literal selectable item, or the failure path can be triggered directly via an API call to OrderBeans with that item name. On trigger: PayBeancoins publishes `payment.failed` with `reason: "Simulated failure: Rotten Beans"`; CookerBeaners never receives a `payment.succeeded` event and so never starts; BeanNotifs reacts to `payment.failed` as designed in Q5.

---

<Add more `### Qn` blocks as questions arise. Don't delete answered ones — the resolution log is part of the record.>

---

**Exit criterion:** Every question is ✅ resolved, ❌ dropped, or ⚠️ blocked-with-blocker. Mark ✅ in `README.md` when complete.
