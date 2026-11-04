# 10 — Target shape

What the change must produce. **Requirements, not solutions.** This is the interpretation of `inputs.md` against `00_current_state.md`. If you find yourself naming a model, table, or implementation detail, you're in `20_options.md` territory — back up.

## Goals

- A single order's full journey — BeanApp's HTTP handling, its outbound calls to OrderBeans and BeanNotifs, and all four RabbitMQ hops (OrderBeans → Pay → Cooker → Notifs) — appears as **one connected trace** with parent/child span relationships, not five isolated per-service traces that happen to share a timestamp.
- Trace context propagates across the one HTTP hop (BeanApp → OrderBeans) automatically, via standard ASP.NET Core / `HttpClient` instrumentation, with no hand-written header plumbing.
- Trace context propagates across all four RabbitMQ hops, surviving the publish → queue → consume boundary, even though `RabbitMQ.Client 6.8.1`'s synchronous API means this cannot be assumed to work via off-the-shelf auto-instrumentation (per `00_current_state.md`'s flagged unknown) — this may require explicit header propagation, matching the existing `x-retry-count` precedent in `EventConsumerHostedService.cs`.
- The trace is viewable end-to-end in a browser UI, with span names, per-hop duration, and service attribution — a developer can go from "order X was slow or failed" to a visual timeline without grep-ing `kubectl logs` across five deployments.
- Each span carries the order's `OrderId` as an attribute, so a trace can be cross-referenced against the existing structured logs (`../2026_10_observability-and-resilience/`) — the two correlation mechanisms stay linkable, not duplicated and disconnected. **Amended per `30_open_questions.md` Q3/Q4:** this is a one-click Grafana trace-to-logs jump backed by a new Loki log-aggregation backend, not manual grepping — see below.
- The tracing backend is stood up as part of `setup.sh`'s single-command bring-up (including surviving `--clean`), consistent with every other piece of infra in this project (`../2026_09_phaseolus-architecture/`) — not a manually-run extra step a grader has to know about.
- New dependencies build clean under each service's existing CI (`dotnet restore` → `dotnet build --no-restore` → `dotnet format --verify-no-changes`), with no test step added or required.

## Non-goals

- **Not replacing the existing `OrderId`-based structured logging.** Tracing supplements it; `../2026_10_observability-and-resilience/`'s logging work stays as-is.
- **Not collapsing the four duplicated `EventEnvelope.cs` copies into a shared package.** Per `CLAUDE.md`'s Surgical Changes guidance, this plan matches the existing per-repo duplication pattern unless `20_options.md` explicitly argues a shared package is required to carry trace context (in which case that tradeoff is named there, not assumed here).
- **Not upgrading `RabbitMQ.Client` off 6.8.1** to a newer async-API version. That's a separate, riskier migration across three repos and is out of scope for this plan regardless of what it would make easier.
- **Not changing the AMQP idempotency/dedup mechanism** (`EventId`-keyed `ConcurrentDictionary`, flagged as not shared-across-replicas in `../2026_10_message-contracts-hardening/50_followups.md`). Tracing is additive; that dedup gap is a separate, already-tracked followup.
- **Not building a production-grade tracing backend** — no long-term retention policy, no multi-tenant access control, no HA. A single self-hosted instance adequate for a live school-project demo is sufficient.
- **Not configuring trace sampling.** This is a low-traffic demo system; 100% sampling (the default for most OTel exporters at this scale) is fine and isn't a requirement either way.
- **Not instrumenting RabbitMQ, Keycloak, Traefik, or Postgres internals** themselves — only the five service repos' own code. The message broker and other infra stay black boxes from a tracing perspective.

## Constraints

- **Time.** The user explicitly reverted the admin-ui-ingress feature (PR #34) for being more effort than it was worth given the project's time limit. `20_options.md` must weigh implementation effort heavily and default toward the lowest-effort option that still satisfies the rubric criterion, not the most complete or "correct" tracing setup.
- **`RabbitMQ.Client 6.8.1`, synchronous API.** Whatever propagation mechanism is chosen must work against this exact client version without requiring an API-style upgrade (see Non-goals).
- **Minimal CI gate.** Each service repo's CI only runs lint+build (`dotnet format --verify-no-changes`, no test step) — any new package reference must be compatible with that, and this plan does not add a test step to compensate for lacking one.
- **Existing infra-management convention.** Per `../2026_09_phaseolus-architecture/`'s Step 13 incident writeup, the infra Helm charts (RabbitMQ, Keycloak, Traefik, Prometheus/Grafana) are deliberately *not* Argo CD-managed and installed directly via `helm` in `setup.sh`. A new tracing backend, if it's a Helm chart, should follow this same convention for consistency unless `20_options.md` names a specific reason to deviate.
- **`setup.sh` is the single source of truth for a fresh bring-up.** Any new infra component needs an install step there (and survive `--clean`, from `../..` PR #33), so the project's one-command bring-up claim (`../2026_10_docs-and-ci/`) stays true.
- **Branch discipline (`CLAUDE.md`).** Implementation will likely span multiple repos (up to all five services plus this meta repo for infra/`setup.sh` changes) — each repo's change needs its own explicit branch confirmation before any commit, per the project's established one-PR-per-repo pattern used throughout this session.

## Success criteria

- A real order placed through BeanApp's UI produces a single trace ID visible in the tracing backend's UI, with distinct, correctly-ordered spans for: BeanApp's HTTP request handling, BeanApp → OrderBeans HTTP call, OrderBeans' RabbitMQ publish, Pay's consume + publish, Cooker's consume + publish, and Notifs' consume — with parent/child relationships intact end-to-end, not five disconnected per-service traces.
- The trace is viewable in a browser, consistent with how the other admin UIs (Grafana, RabbitMQ management, Argo CD) are reached today — `localhost:<port>` via a `setup.sh`-started port-forward, per the ingress revert's decision to keep things simple (PR #34).
- At least one span attribute on every hop carries the request's `OrderId`, and each service's log lines carry the active trace ID (`30_open_questions.md` Q4) — letting a developer click from a trace straight to its matching log lines in Grafana, via the Loki backend added per Q3, rather than cross-referencing `kubectl logs` output by eye.
- `dotnet format --verify-no-changes` and `dotnet build` pass clean in all five repos after the new OTel packages are added — confirmed via each repo's CI run post-merge, same verification pattern used for every prior PR this session.
- A fresh `./setup.sh` run (and a `./setup.sh --clean` run) brings up the tracing backend with no manual steps, and the final summary echo block documents how to reach it — matching how every other admin UI is documented there today.
- A deliberately broken hop (e.g. briefly scaling a consumer to 0, the same technique already used to test `setup.sh`'s endpoint checks in PR #31) is visibly distinguishable in the trace UI — an error span, a gap, or a stalled span — demonstrating the tracing is actually diagnostic, not just decorative for the rubric.

---

**Exit criterion:** Requirements are testable, not vague. Mark ✅ in `README.md` when complete.
