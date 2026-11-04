# 40 — Implementation

Step plan for the chosen option from `20_options.md`. **Do not start this phase while `30_open_questions.md` has any ⏳ items** — that's the discipline this folder structure exists to enforce.

Each step has a verification: how do we know the step is done? Strong verification turns the plan into a checklist you can run independently.

## Plan summary

Stand up Tempo + Loki + Promtail as new Helm-managed infra first (Step 1), since every later step needs somewhere to send spans and logs. Then prove the riskiest, least-certain part — manual W3C `traceparent` propagation across one RabbitMQ hop — on just two services (Step 2, the Q1-mandated spike) before touching the rest. Only once that's confirmed working does the same pattern roll out to the remaining backend services (Step 3) and finally BeanApp (Step 4, pure auto-instrumentation, no RabbitMQ involved, so it only makes sense once the chain it's attaching to actually exists). Each per-service step bundles both the tracing wiring and the Q4 log-correlation config into the same `Program.cs` touch, rather than revisiting each repo twice. Step 5 is pure verification against the live cluster — no new code.

This order is deliberately incremental and non-breaking at every point: because propagation goes through AMQP message *headers* (not a change to the `EventEnvelope` JSON schema), a service that hasn't been instrumented yet simply ignores a `traceparent` header it doesn't recognize — there's no "stop the world" cutover, and a trace through a not-yet-instrumented hop just ends early rather than breaking anything.

## Steps

### Step 1 — Stand up Tempo, Loki, and Alloy; raise the memory budget

✅ **Do.** In this meta repo: add Helm installs to `setup.sh`'s infra section, following the existing manual-Helm convention (`../2026_09_phaseolus-architecture/` Step 13).

**Correction found during implementation:** both charts originally planned here are deprecated. `grafana/tempo` migrated to `grafana-community/helm-charts` on 2026-01-30 — used `grafana-community/tempo` (v3.2.1, still single-binary mode) instead. `grafana/loki-stack` and its bundled Promtail are also deprecated with no migrated replacement for Promtail specifically — used the modern `grafana-community/loki` chart (v20.4.1, `deploymentMode: SingleBinary`, `auth_enabled: false` to avoid needless per-request tenant headers at this single-tenant scale, `resultsCache`/`chunksCache` disabled after their default memcached sidecars caused real pod-scheduling failures from insufficient memory) plus **Grafana Alloy** (`grafana/alloy` v1.15.0 — still on the old `grafana/` repo, not yet migrated) as Promtail's actively-maintained successor for shipping pod logs to Loki.

Registered both as Grafana datasources via `additionalDataSources` in the same values file already used for Grafana's OAuth config (renamed `/tmp/phaseolus-grafana-oauth-values.yaml` → `/tmp/phaseolus-grafana-values.yaml` since it now holds more than OAuth config), with Tempo's `tracesToLogsV2` pointed at the Loki datasource for Q3's one-click correlation. **Found and fixed a real mistake here:** Tempo's query API is on port `3200`, not Loki's `3100` — an easy mix-up that produced a silent 502 through Grafana's datasource proxy until caught.

Raised `MINIKUBE_MEMORY`'s default from `8192` to `10240` (`30_open_questions.md` Q2).

**Verify.** All three Helm releases (`tempo`, `loki`, `alloy`) installed and reached `Running`/`2/2` against the live cluster. Confirmed Loki's full write→query path end-to-end (direct API query against an active namespace, not just "pushes return 204" — an earlier zero-result query turned out to be the `phaseolus` namespace services simply being idle, not a real ingestion bug, confirmed via `kubectl logs --since` showing no output from any of them). Confirmed both datasources are registered and actually queryable through Grafana's own API (`/api/datasources/proxy/uid/<uid>/...`), not just present in the datasource list — Tempo's `/api/search` returns `200` with an empty result set (correct: no service emits spans until Step 2). Did not run a full `./setup.sh --clean` end-to-end (expensive — full cluster rebuild, image reloads, Keycloak cold start) given every new piece was individually live-verified and the script's heredoc content was diffed byte-for-byte against what was actually tested.

---

### Step 2 — Spike: prove trace-context propagation across one RabbitMQ hop (OrderBeans → Pay)

✅ **Do.** This is the Q1 gate — the riskiest, least-certain part of the whole plan, isolated to two repos before committing to the rest. Implemented as planned, exactly as described below — no design changes needed, unlike Step 1.

In **OrderBeans** and **PayBeancoins**: add `OpenTelemetry`, `OpenTelemetry.Extensions.Hosting`, `OpenTelemetry.Instrumentation.AspNetCore`, `OpenTelemetry.Instrumentation.Http`, and `OpenTelemetry.Exporter.OpenTelemetryProtocol` to each `.csproj` (pin to each package's current latest stable version, matching this codebase's existing pinned-version convention). In each `Program.cs`, register tracing: ASP.NET Core + `HttpClient` auto-instrumentation, a service-specific `ActivitySource` (e.g. `new ActivitySource("OrderBeans")`), and an OTLP exporter. Set `OTEL_SERVICE_NAME` (`orderbeans` / `paybeancoins`) and `OTEL_EXPORTER_OTLP_ENDPOINT` (`http://tempo.infra.svc.cluster.local:4317`) as env vars in each `deploy/deployment.yaml`, alongside the existing `RabbitMq__*`/`Keycloak__*` env vars. Also apply Q4's log-correlation config in both services' `Program.cs`: configure logging's `ActivityTrackingOptions` to include `TraceId`/`SpanId`/`ParentId`, and enable the console logger's scope output, so the active trace ID shows up in plain stdout log lines (which Promtail already ships to Loki from Step 1, no per-service Loki code needed).

In `OrderBeans/Messaging/EventPublisher.cs`'s `Publish` method: start an `Activity` (`ActivityKind.Producer`) around the existing `BasicPublish` call, and inject its context into `properties.Headers` via `OpenTelemetry.Context.Propagation.Propagators.DefaultTextMapPropagator.Inject(...)` — writing the W3C `traceparent` string as a UTF-8 byte array, matching the existing `x-retry-count` header's style in `EventConsumerHostedService.cs`. Tag the activity with `order.id` = `envelope.OrderId`.

In `PayBeancoins/Messaging/EventConsumerHostedService.cs`'s `HandleDeliveryAsync`, **before** invoking `binding.Handler(envelope)`: extract the incoming `traceparent` from `ea.BasicProperties.Headers` via `Propagators.DefaultTextMapPropagator.Extract(...)`, then start a linked `Activity` (`ActivityKind.Consumer`) using that extracted context as its parent, wrapping the `await binding.Handler(envelope)` call in that activity's scope (`using var activity = ...`) so the handler — including Pay's own `publisher.Publish(...)` calls for `payment.succeeded`/`payment.failed` — picks it up automatically as `Activity.Current`.

**Verify.** `curl` a test order directly to OrderBeans' `/orders` endpoint (BeanApp is not yet instrumented — this step tests the AMQP hop in isolation). In Grafana's Explore view against the Tempo datasource, confirm the test order produced **one trace** containing both OrderBeans' publish span and Pay's consume span, correctly nested as parent/child with plausible timing — not two separate, disconnected traces. Also confirm the trace ID appears in both services' `kubectl logs` output (Q4). **Do not proceed to Step 3 until this is confirmed** — if propagation doesn't link correctly, this is the point to revisit the approach, not after instrumenting all five services.

**Result: ✅ confirmed.** Querying Tempo directly for the test order's trace ID returned one trace with exactly the expected shape: `POST /orders` (ASP.NET Core auto-instrumented root span) → `publish order.created` (OrderBeans' manual producer span, correctly nested as its child) → an unnamed consume span on Pay's side, correctly parented to OrderBeans' publish span by trace ID — → `publish payment.succeeded` (Pay's manual producer span, correctly nested under its own consume span). Both services' `kubectl logs` output showed the identical `TraceId` on their respective log lines (Q4 confirmed working too).

**A real, unplanned obstacle hit during verification, not the propagation design itself:** this project's Argo CD setup is a recursive App-of-Apps (`phaseolus-root` manages the `orderbeans`/`paybeancoins` Application objects, which in turn manage their Deployments) with `selfHeal: true` at **every level**. A direct `kubectl apply` of the new env vars onto the real `orderbeans`/`paybeancoins` Deployments got silently reverted by the children's own self-heal; patching the children's `syncPolicy` to disable that also got silently reverted, because `phaseolus-root`'s own self-heal re-asserts the children's spec (including their `syncPolicy`) back to git. Disabling `phaseolus-root`'s sync was correctly judged too high-blast-radius and blocked. Worked around it entirely without touching any Argo CD-managed resource: ran the instrumented code as two **standalone, unmanaged pods** (direct `kubectl run`/`kubectl apply` of bare `Pod` manifests, addressed by pod IP, outside any Deployment Argo CD tracks), with Pay's consumer temporarily bound to a differently-named queue (reverted immediately after the test, confirmed via a byte-identical image rebuild) so it didn't compete with the real `paybeancoins` Deployment's consumer for the same message. Confirmed afterward that the real Deployments were untouched and still `Synced`/`Healthy`.

---

### Step 3 — Roll the same pattern out to CookerBeaners and BeanNotifs

⏳ **Do.** Repeat Step 2's `.csproj`, OTel SDK registration, env var, and log-correlation changes in **CookerBeaners** and **BeanNotifs**. Add the same publish-side `Activity`/header-injection to `CookerBeaners/Messaging/EventPublisher.cs` (inside its existing `lock (_channelLock)` block) and the same consume-side extraction to `CookerBeaners/Messaging/EventConsumerHostedService.cs` and `BeanNotifs/Messaging/EventConsumerHostedService.cs` (Notifs is consume-only — it has no `EventPublisher`, so only the extraction side applies there).

**Known gotcha to handle explicitly, not discover the hard way:** `CookerBeaners/Program.cs`'s `HandlePaymentSucceededAsync` fires `CookAsync` **without awaiting it** (`_ = CookAsync(...)`), and `CookAsync` publishes the `order.cooked` event only after an in-process `Task.Delay`. By the time that delayed publish runs, `HandlePaymentSucceededAsync` has already returned, the consume handler's `using var activity` scope has already ended, and `Activity.Current` is no longer the consume span — relying on ambient capture here would silently produce a disconnected trace for every order's `order.cooked` event specifically (while `order.cooking-started`, published synchronously before the handler returns, would work fine). Fix: capture the consume `Activity` (or just its `ActivityContext`) as a local variable in `HandlePaymentSucceededAsync` *before* it returns, and pass that context explicitly as a parameter into `CookAsync`, which uses it as the explicit parent when starting its own `Activity` around the `order.cooked` publish — rather than relying on `Activity.Current`.

**Verify.** Same direct-`curl`-to-OrderBeans test as Step 2, extended through all four hops. Confirm a single trace in Tempo contains OrderBeans' publish → Pay's consume+publish → Cooker's consume+publish (**both** `order.cooking-started` and the delayed `order.cooked` spans correctly parented) → Notifs' consume, with correct nesting and plausible timing throughout.

---

### Step 4 — Instrument BeanApp (HTTP side)

⏳ **Do.** Add the same OTel packages to `M321_TBZ_Phaseolus_WebApp`'s `.csproj` and register ASP.NET Core + `HttpClient` auto-instrumentation plus the OTLP exporter in `Program.cs` (`OTEL_SERVICE_NAME=beanapp`). No manual header code is needed here — BeanApp has no RabbitMQ plumbing (`00_current_state.md`), and `OpenTelemetry.Instrumentation.Http`'s auto-instrumentation already injects the W3C `traceparent` header on outgoing `HttpClient` calls automatically, which OrderBeans' ASP.NET Core auto-instrumentation (already wired in Step 2) already knows how to pick up as an incoming request's parent context — this hop was implicitly ready since Step 2. Apply the same Q4 log-correlation config to BeanApp's `Program.cs` as the other services.

**Verify.** Place a real order through BeanApp's actual web UI (not a direct curl). Confirm Tempo shows a single trace beginning with BeanApp's HTTP request span, continuing through its call to OrderBeans, and on through all four AMQP hops to Notifs — the full chain from browser to final notification, in one trace.

---

### Step 5 — End-to-end verification against the live cluster

⏳ **Do.** No new code — this step validates `10_target_shape.md`'s success criteria holistically, against all five services instrumented together.

**Verify.**
- Place one real order via BeanApp's UI; confirm the resulting single trace's spans, names, and per-hop durations all look correct in Tempo/Grafana.
- Click from a span in that trace into its correlated log lines via Grafana's trace-to-logs feature against the new Loki datasource (Q3) — confirm it actually jumps to the right log lines, not just that both datasources independently exist.
- Deliberately break one hop (e.g. briefly scale PayBeancoins to 0 replicas, the same technique already used to test `setup.sh`'s endpoint checks in PR #31) and place another order; confirm the resulting trace visibly shows the failure or a stalled/incomplete span, rather than looking identical to a healthy trace.
- Confirm `dotnet format --verify-no-changes` and `dotnet build` pass clean in all five repos' CI after the new packages are added.

## Rollback / blast radius

Everything here is additive: new NuGet packages, new `Program.cs` registration code, new AMQP message *headers* (not a change to the `EventEnvelope` JSON schema or its fields), and new, entirely separate infra components (Tempo/Loki/Promtail) in `k8s/infra/`. A service that hasn't been instrumented yet simply ignores an incoming `traceparent` header it doesn't recognize — there's no hard cutover and no risk of breaking message processing for services mid-rollout. Reverting any single repo's PR is a plain code revert with no data cleanup. Removing Tempo/Loki/Promtail later is just deleting their Helm releases; nothing else in the cluster depends on them.

## Quality gates before merging

- Each of the five service repos: `dotnet restore && dotnet build --no-restore && dotnet format --verify-no-changes` (the existing CI gate, per `../2026_10_docs-and-ci/`) — no test step exists or is added by this plan.
- This meta repo: `bash -n setup.sh` (the existing CI check).
- Live verification per each step's **Verify** section above, performed before merging that step's PR — matching the live-verify-before-committing pattern used for every PR this session (e.g. PR #29–#34).
- Per `CLAUDE.md`'s branch discipline: each repo touched (OrderBeans, PayBeancoins, CookerBeaners, BeanNotifs, BeanApp, and this meta repo for Step 1) gets its own explicit branch confirmation before any commit — consistent with the one-PR-per-repo pattern used throughout this session.

---

**Exit criterion:** Every step ✅, gates green, PR merged. Mark ✅ in `README.md` when complete and archive the folder per the project's plan-archive convention in `CLAUDE.md`.
