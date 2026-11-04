# 20 — Options

Design alternatives that satisfy `10_target_shape.md`. **At least three.** If you can only think of one, the problem isn't framed yet — go back to `10`. Each rejected option needs a stated reason; "didn't pick it" is not a reason.

All three options below use the real OpenTelemetry SDK across all five services (`OpenTelemetry.Extensions.Hosting` + ASP.NET Core / `HttpClient` auto-instrumentation) — that much follows directly from the user's explicit ask in `inputs.md` ("add message tracing with OpenTelemetry") and isn't re-litigated here. What varies is (a) which tracing backend receives the spans, and (b) how trace context survives the RabbitMQ hop, since `00_current_state.md` flagged that as genuinely unverified against `RabbitMQ.Client 6.8.1`'s old synchronous API.

## Option A — Dedicated Jaeger backend, manual AMQP header propagation

**Shape.** Deploy Jaeger's "all-in-one" image (single container, in-memory storage — no separate storage backend needed at this scale) as a new Deployment/Service in `k8s/infra/`, installed via `setup.sh` alongside the existing Helm-managed infra. Each service exports spans via OTLP to Jaeger. For the RabbitMQ hops, manually inject the current `Activity`'s W3C `traceparent` into `BasicProperties.Headers` on publish (`EventPublisher.cs`) and manually extract it to start a linked child `Activity` on consume (`EventConsumerHostedService.cs`) — following the same header-based-metadata pattern already established by the existing `x-retry-count` header. Jaeger gets its own port-forward and summary entry, following the plain-localhost-port pattern from the ingress revert (PR #34).

**Pros.**
- Jaeger's all-in-one is genuinely minimal to stand up — one container, no external storage dependency, widely recognized as "the" distributed-tracing tool, easy for a grader to recognize at a glance.
- Fully decoupled from the existing Prometheus/Grafana stack — a mistake here can't destabilize already-working dashboards.

**Cons.**
- Adds a wholly new admin surface: a new port-forward, a new summary-block entry, new endpoint checks (PR #31's pattern) — exactly the kind of "one more thing to document and maintain" the admin-ui-ingress revert (PR #34) just explicitly decided against, under the same time pressure that applies here.
- In-memory storage means traces vanish on pod restart — fine for a live demo, but worth naming since it's a real limitation, not swept under the rug.

**Verdict.** ❌ rejected — satisfies the goals, but adds new standalone infra and documentation surface area the project just finished deliberately shedding (PR #34), for no capability gain over Option B.

---

## Option B — Grafana Tempo integrated into the existing Grafana instance, manual AMQP header propagation

**Shape.** Deploy Grafana Tempo in monolithic mode (single binary, local-disk storage — no object-store dependency needed at this scale) in `k8s/infra/`, installed via `setup.sh` the same way as the other Helm-managed infra (`../2026_09_phaseolus-architecture/` Step 13 convention). Register Tempo as a new datasource on the **already-running** `kube-prometheus-stack` Grafana via its `grafana.additionalDataSources` Helm value — the same values-file-templating pattern `setup.sh` already uses for Grafana's OAuth config. RabbitMQ propagation is identical to Option A: manual `traceparent` header injection/extraction in `EventPublisher.cs`/`EventConsumerHostedService.cs`. Traces are viewed inside the Grafana UI already reachable at `http://localhost:3000` — no new port-forward, no new hosts-file entry, no new line in the final summary beyond "Grafana now also shows traces."

**Pros.**
- Zero new admin UI or port to document, test, or add to `setup.sh`'s endpoint checks — reuses an access path that already exists and is already verified working.
- A single pane of glass: the same Grafana instance that already shows Prometheus dashboards now also shows traces, with Grafana's native "trace-to-logs" correlation available for free — a stronger "functionality and operation between systems" story for the grading rubric than a second, disconnected UI.
- Same vendor (Grafana Labs) and Helm-chart conventions already in use for `kube-prometheus-stack` — no new unfamiliar tooling.

**Cons.**
- Slightly more `setup.sh` plumbing than Option A: a Helm values fragment to register the datasource (comparable in size to the existing Grafana OAuth values block already there, so not a new category of work, just incremental).
- Tempo's monolithic mode still needs a storage backend configured (even if local-disk, not full object storage) — marginally more to get right in a minikube environment than Jaeger's literal single-process image.

**Verdict.** ✅ selected — see Decision below.

---

## Option C — Auto-instrumentation only, no RabbitMQ header propagation, correlate via shared `OrderId` tag

**Shape.** Add the OTel SDK and ASP.NET Core/`HttpClient` auto-instrumentation to all five services and a tracing backend (either A's or B's), but do **not** touch `EventPublisher.cs` or `EventConsumerHostedService.cs` at all. Each service's RabbitMQ consume starts its own disconnected root trace; the five services' traces are linked only after the fact by filtering/grouping on a shared `OrderId` span tag in the backend's UI, the same way `OrderId` already links log lines today.

**Pros.**
- Lowest possible implementation effort — touches only each service's startup/DI wiring, never the message-handling hot path, so zero risk from `RabbitMQ.Client 6.8.1`'s AMQP-header behavior.
- No RabbitMQ.Client-version-compatibility risk at all, since nothing new touches AMQP headers.

**Cons.**
- **Directly fails `10_target_shape.md`'s first goal** — "one connected trace... not five isolated per-service traces that happen to share a timestamp" was written specifically to rule this out. Tag-filtering across disconnected traces gives no real parent/child causality or waterfall timing across the AMQP hops.
- Doesn't actually deliver "message tracing" as asked — it's auto-instrumented HTTP tracing with log-like tag correlation bolted on, not tracing of the messages themselves.

**Verdict.** ❌ rejected — the effort savings come directly from skipping the one requirement (connected cross-service traces over RabbitMQ) that is the actual point of this plan.

---

## Decision

✅ **Selected:** Option B — Grafana Tempo integrated into the existing Grafana instance, manual AMQP header propagation.

**Why this over the others.** Under the explicit time-pressure constraint from `10_target_shape.md`, the deciding factor is total new surface area, not raw deployment complexity: Option A is arguably a simpler *container* to deploy, but it reintroduces exactly the pattern — a new standalone admin UI needing its own port-forward, hosts/summary documentation, and endpoint checks — that the admin-ui-ingress revert (PR #34) just decided wasn't worth the effort for an optional feature. Option B reuses an access path (`http://localhost:3000`) that's already built, documented, and endpoint-checked, so the net new `setup.sh`/documentation work is smaller even though the Helm chart itself is marginally fussier. Option C is rejected outright because it fails the plan's core requirement rather than trading it off.

**What we're explicitly accepting.** Tempo's monolithic mode requires a bit more Helm-values configuration than Jaeger's single-process all-in-one, and the team is trading away Jaeger's more immediately recognizable, purpose-built tracing UI for tighter integration with Grafana. The manual AMQP header propagation (`traceparent` injection/extraction in `EventPublisher.cs`/`EventConsumerHostedService.cs`) is identical effort and identical version-compatibility risk regardless of backend choice, so it isn't a factor in the A-vs-B decision — it still needs its own verification in `30_open_questions.md`/`40_implementation.md`.

---

**Exit criterion:** ≥3 options listed, one ✅ selected, others ❌ with reasons. Mark ✅ in `README.md` when complete.
