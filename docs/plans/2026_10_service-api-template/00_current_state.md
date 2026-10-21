# 00 — Current state

What exists in the codebase **today**, before any change. The goal: a reader unfamiliar with this corner of the repo can follow links from this doc to the relevant code and understand what's there.

## Decisions already locked (not re-opened by this plan)

From `../2026_09_phaseolus-architecture/30_open_questions.md`, all ✅ resolved 2026-09-25:

- **Q2 — stack:** C#/.NET 8, ASP.NET Core **Minimal APIs** (not MVC), uniform across all five services, even the message-consumer-only ones (each needs a `/metrics` endpoint regardless). `RabbitMQ.Client` used directly (no MassTransit/Rebus). `prometheus-net`/`prometheus-net.AspNetCore` for metrics. `Microsoft.AspNetCore.Authentication.JwtBearer` for the one auth boundary (Q7). Docker multi-stage, `sdk:8.0` → `aspnet:8.0`. **No shared NuGet package across repos** — each service defines its own local record types matching the agreed JSON shape.
- **Q3 — manifests:** plain Kubernetes YAML under a `/deploy` folder in each service's own repo (`Deployment` + `Service`, plus `IngressRoute` where Traefik-exposed). No Helm/Kustomize.
- **Q4 — images:** no registry; built locally, loaded into minikube via `minikube image load`, tagged by git SHA, `imagePullPolicy: Never`.
- **Q5 — messaging topology:** one durable topic exchange `phaseolus.events`, declared idempotently by every service that touches it. Routing keys/queues:

  | Routing key | Published by | Consumed by | Queue |
  |---|---|---|---|
  | `order.created` | OrderBeans | PayBeancoins | `pay.incoming-orders` |
  | `payment.succeeded` | PayBeancoins | CookerBeaners | `cooker.paid-orders` |
  | `payment.failed` | PayBeancoins | BeanNotifs | `notifs.payment-failed` |
  | `order.cooked` | CookerBeaners | BeanNotifs | `notifs.order-cooked` |

  Envelope: `{ "eventId": "guid", "eventType": "string", "occurredAt": "ISO-8601", "orderId": "guid", "payload": {} }`. Manual ack on success; nack-and-requeue on failure; no dead-letter exchange (flagged as a risk in that plan's `50_followups.md`).
- **Q6 — namespaces:** `phaseolus` (the five services), `infra` (RabbitMQ/Keycloak/Traefik/Prometheus/Grafana), `argocd` (Argo CD itself).
- **Q7 — auth scope:** only **OrderBeans' `POST /orders`** validates a Keycloak-issued JWT (client-credentials grant; BeanApp is the only token-fetching caller). No other service/route is protected.
- **Q8 — payment mock:** PayBeancoins fails deterministically on an item named `"Rotten Beans"` (case-insensitive); everything else succeeds.

Infra (RabbitMQ, Keycloak realm/client, Argo CD, minikube namespaces) is already stood up per that plan's Steps 1–4 (marked ✅ 2026-09-25 / 2026-10-02 / 2026-10-05). Steps 5–14 (the five services, Traefik exposure, metrics dashboard, Argo CD App-of-Apps, end-to-end verification) are still ⏳.

## Code paths involved

**This repo's service, BeanApp (`M321_TBZ_Phaseolus_WebApp/WebApp/WebApp`):**
- ASP.NET Core 8 **Razor Pages** app (not Minimal API) — `Program.cs`, `Pages/Index`, `Pages/Beans`, `Pages/Cart`, `Pages/Error`, all handlers are empty `OnGet()`s.
- ASP.NET Core Identity scaffolded (register/login/logout via the `Microsoft.AspNetCore.Identity.UI` Razor Class Library), backed by `ApplicationDbContext : IdentityDbContext` — no domain entities.
- EF Core + Npgsql wired to a local Postgres container (`Postgres/compose.yaml`) — fixed earlier this session; migration applies cleanly.
- `WebApp.csproj` references: `Microsoft.AspNetCore.Diagnostics.EntityFrameworkCore`, `Microsoft.AspNetCore.Identity.EntityFrameworkCore`, `Microsoft.AspNetCore.Identity.UI`, `Microsoft.EntityFrameworkCore.Tools`, `Npgsql.EntityFrameworkCore.PostgreSQL`. **No** `RabbitMQ.Client`, **no** `prometheus-net`, **no** `Microsoft.AspNetCore.Authentication.JwtBearer`.
- No `/metrics` or health endpoint. No Dockerfile. No `/deploy` manifests.

**The other four service repos (OrderBeans/PayBeancoins/CookerBeaners/BeanNotifs):** not present in this checkout (separate repos under `Timposter8107`). Per `../2026_09_phaseolus-architecture/00_current_state.md` (2026-09-25) each was a one-line-README stub with zero code. **This has not been re-verified as of today (2026-10-13)** — 18 days have passed since that snapshot, so treat "still stubs" as an assumption, not a confirmed fact.

## Behavior today

Nothing in this system publishes or consumes a RabbitMQ message yet, anywhere. BeanApp is the only service with any running code at all, and that code (Razor Pages + Identity + DB) has no bean/order/cart domain logic and no awareness of RabbitMQ, Keycloak, or Prometheus.

## What's missing or awkward

- **Step 5's "scaffold all five" has no code-level design yet** — only "ASP.NET Core Minimal API, `/metrics` endpoint" is fixed; everything about how RabbitMQ publishing/consuming is structured inside a service, how health checks map to k8s probes, and what's genuinely copy-paste-able vs. per-service is undecided. That's this plan's job.
- **BeanApp is architecturally the odd one out.** Q2 frames all five as uniform Minimal API projects, but BeanApp already exists as a Razor Pages app with Identity UI (built before Q2 was resolved, and left alone since — per `../2026_09_phaseolus-architecture/40_implementation.md` Step 10, BeanApp only needs to *call* OrderBeans over HTTP with a fetched token; it's never described as publishing or consuming RabbitMQ messages itself). Whether BeanApp adopts the full "service template" or only a slice of it is unresolved — see `30_open_questions.md` Q1.
- **No reference implementation exists to copy from.** "Copied und pasted with light modification" (this plan's input) presumes a first real copy exists somewhere; today there is none.

---

**Exit criterion:** A reader can navigate the relevant code from this doc alone. Mark ✅ in `README.md` when complete.
