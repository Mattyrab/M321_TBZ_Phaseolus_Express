# 00 — Current state

What exists in the codebase **today**, before any change. The goal: a reader unfamiliar with this corner of the repo can follow links from this doc to the relevant code and understand what's there.

## Models / data shape

The message envelope is **byte-for-byte identical across four repos, duplicated rather than shared as a package** — same record shape, different namespace per repo:

```csharp
record EventEnvelope(Guid EventId, string EventType, DateTimeOffset OccurredAt, Guid OrderId, JsonElement Payload)
```

- `M321_TBZ_Phaseolus_Order/Messaging/EventEnvelope.cs`
- `M321_TBZ_Phaseolus_Pay/Messaging/EventEnvelope.cs`
- `M321_TBZ_Phaseolus_Cooker/Messaging/EventEnvelope.cs`
- `M321_TBZ_Phaseolus_Notifs/Messaging/EventEnvelope.cs`

No trace/span/correlation field exists on it today. `EventId` is a per-message GUID used for consumer-side idempotency (see "Code paths involved" below), not a trace identifier — it changes at every hop, so it can't double as a cross-service trace ID without redefinition.

## Code paths involved

**Publish side** — `Messaging/EventPublisher.cs` in Order/Pay/Cooker (near-identical; Cooker wraps calls in a `lock` because per-order delay tasks call it concurrently):
- RabbitMQ.Client **6.8.1** — the old synchronous-style API (`IModel`, `CreateBasicProperties()`, `BasicPublish`), not the newer async `IChannel` API.
- Publishes to a durable topic exchange (`ExchangeType.Topic`).
- `BasicProperties` today only sets `Persistent = true` and `ContentType = "application/json"` — no custom headers on the happy-path publish.
- Notifs has no publisher; it's the end of the chain.

**Consume side** — `Messaging/EventConsumerHostedService.cs` in Pay/Cooker/Notifs:
- `AsyncEventingBasicConsumer`, manual ack.
- In-memory `ConcurrentDictionary<Guid, byte>` idempotency guard keyed on `EventId` (flagged in `../2026_10_message-contracts-hardening/50_followups.md` as not shared across replicas — relevant if tracing work ever touches this file, since it's the same file a trace-context read would live in).
- A retry mechanism **already sets a custom AMQP header** on republish — `x-retry-count`, via `props.Headers = new Dictionary<string, object> {...}` (`EventConsumerHostedService.cs:126`). This is useful precedent: propagating metadata through AMQP message headers on this exact RabbitMQ.Client version is already an established pattern in this codebase, not something a tracing change would introduce for the first time.

**BeanApp** (`M321_TBZ_Phaseolus_WebApp/WebApp/WebApp/Program.cs:18-37`) — note the nested `WebApp/WebApp/WebApp/` path (a known quirk from `../2026_10_docs-and-ci/40_implementation.md`'s Step 2 fix):
- Has **no RabbitMQ plumbing at all** (by design — see `../2026_10_service-api-template/` Q1).
- Three named `HttpClient`s: `"Keycloak"`, `"OrderBeans"` (order placement, lines 26-28), `"BeanNotifs"` (Admin page reads, lines 33-36 — this is the one with `.AddStandardResilienceHandler()` from `../2026_10_observability-and-resilience/`).

**Existing correlation** — `OrderId` is passed today as a plain structured-logging parameter, not a log scope and not an AMQP header: e.g. `_logger.LogInformation("...{OrderId}...", envelope.OrderId)` in `M321_TBZ_Phaseolus_Pay/Program.cs:59,73` and `M321_TBZ_Phaseolus_Order/Program.cs:55`. It only ties log *lines* together for a human reading them side by side — it carries no timing, no parent/child relationship, and isn't on the wire as a header.

**Metrics infra (for contrast)** — every service has a `deploy/servicemonitor.yaml`, a plain Prometheus `ServiceMonitor` CRD scraping `/metrics` on port `http` every 15s. `k8s/infra/` has `prometheus-gate.yaml`, three `grafana-dashboard-*.yaml`, and `rabbitmq-metrics.yaml` — all metrics, no tracing. A repo-wide search found **no Tempo/Jaeger/Zipkin/OTel-collector manifest anywhere** in `k8s/`.

**Dependencies** — Order/Pay/Cooker/Notifs: `net8.0`, `RabbitMQ.Client 6.8.1`, `prometheus-net.AspNetCore 8.2.1` (Order and Notifs additionally reference `Microsoft.AspNetCore.Authentication.JwtBearer 8.0.11`). BeanApp (`WebApp/WebApp/WebApp.csproj`): `net8.0`, `Microsoft.AspNetCore.Authentication.OpenIdConnect 8.0.11`, `Microsoft.Extensions.Http.Resilience 10.11.0`, `prometheus-net.AspNetCore 8.2.1`. **Zero `OpenTelemetry.*` packages and zero Serilog anywhere** — logging is plain `Microsoft.Extensions.Logging` throughout, console-only (no log aggregation backend like Loki exists per the infra inventory above).

**CI** — each service's `.github/workflows/ci.yml` (confirmed via Order's) runs `dotnet restore` → `dotnet build --no-restore` → `dotnet format --verify-no-changes`. No test step exists yet (`../2026_10_docs-and-ci/50_followups.md`). Any new dependency this plan adds must build clean and pass `dotnet format` under this minimal gate.

## Behavior today

A single order's journey through the system looks like this: a browser hits BeanApp over HTTP, BeanApp calls OrderBeans synchronously over HTTP to place the order, OrderBeans publishes an `EventEnvelope` onto the RabbitMQ topic exchange, and PayBeancoins/CookerBeaners/BeanNotifs consume (and in Pay/Cooker's case, republish) further events down the chain — each hop wrapped in its own freshly-serialized envelope with a new `EventId`.

Nothing on the wire — neither the one HTTP hop nor any of the AMQP hops — carries a trace identifier today. The only thread connecting a given order across all five services' logs is the `OrderId` value embedded in the envelope's payload and echoed into each service's structured log lines. To understand what happened to one order, a developer today has to `kubectl logs` each of the five deployments individually and grep for that `OrderId` by hand — there is no single timeline, no per-hop latency breakdown, and no way to see where a slow or failed order actually spent its time without manually stitching timestamps together across five separate log streams.

## What's missing or awkward

- **No distributed tracing exists at all** — no spans, no trace-context propagation, not even ASP.NET Core's built-in `Activity`/`DiagnosticSource` auto-instrumentation is wired up anywhere.
- **Correlating one order's journey is entirely manual** — grep five services' `kubectl logs` output for a shared `OrderId`, by hand, with no visual waterfall or latency breakdown. This is exactly the gap `../2026_10_observability-and-resilience/README.md` names but deliberately left open ("structured logging... not... distributed tracing").
- **The message envelope has no field for trace context**, and it's duplicated across four repos with no shared package — adding a field means four coordinated edits, unless propagation goes through AMQP headers instead (which the existing `x-retry-count` precedent in `EventConsumerHostedService.cs` suggests is the more idiomatic fit for this codebase).
- **RabbitMQ.Client 6.8.1 is an old, synchronous-API version.** Whether a standard OpenTelemetry RabbitMQ instrumentation package actually supports this version (vs. requiring the newer async `IChannel` API) is unverified — this is a real open question for `20_options.md`/`30_open_questions.md`, not something this doc can resolve by reading code alone.
- **This is a fully greenfield addition** — zero `OpenTelemetry.*` packages exist anywhere today, so every choice (SDK setup, exporter, backend) is being made from scratch across five repos simultaneously, each gated by its own minimal lint+build CI.
- **No tracing backend exists in the cluster.** Something (Jaeger, Grafana Tempo, Zipkin, or similar) needs to be stood up net-new in `k8s/infra/`, alongside the existing Prometheus/Grafana stack that's already running there — whether it integrates into that same Grafana instance or runs as a separate UI is a design decision, not a fact about today's state.
- **BeanApp is the only entry point with an inbound synchronous request** (from the browser) and the only place with outbound `HttpClient` calls (to OrderBeans and BeanNotifs) — it's the natural place a trace would begin before handing off into the AMQP mesh, but today it participates in no messaging at all, so "message tracing" necessarily means tracing both the one HTTP hop and the four AMQP hops as a single connected flow, not just the queue portion.

---

**Exit criterion:** A reader can navigate the relevant code from this doc alone. Mark ✅ in `README.md` when complete.
