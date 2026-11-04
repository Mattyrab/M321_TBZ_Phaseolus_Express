# 30 — Open questions

Specific decisions that block implementation. Each question has a clear path to resolution. **No vibes-questions** ("is this a good idea?") — split those into the underlying yes/no decisions.

Resolve every question to ✅ or ❌ before starting `40_implementation.md`. If a question can't be answered now, either move it to `50_followups.md` (out of scope) or mark it ⚠️ blocked with a named blocker.

## Questions

### Q1 — Verify RabbitMQ trace propagation with a spike before rolling out to all five services?

✅ **Question.** Should we first prove that manually injecting/extracting a W3C `traceparent` into `BasicProperties.Headers` actually produces a correctly linked parent/child span in Tempo — as an isolated spike touching only OrderBeans → Pay — before instrumenting all five services, or proceed straight to the full rollout on the assumption `20_options.md`'s design works as described?

**Why it matters.** `00_current_state.md` flagged this as a genuinely unverified assumption against `RabbitMQ.Client 6.8.1`'s old synchronous API. If the linkage doesn't work as designed, discovering that after instrumenting one service pair is far cheaper to correct than after touching all five repos. This is a real time-tradeoff call given the project's stated time pressure, not something to decide unilaterally.

**Resolution.** ✅ 2026-11-04 — spike first. `40_implementation.md`'s first step(s) will be a throwaway/isolated OrderBeans→Pay propagation check, confirmed working in Tempo, before instrumenting Cooker/Notifs/BeanApp.

---

### Q2 — Raise `MINIKUBE_MEMORY`'s default to fit Tempo, or keep the current 8192MB budget?

✅ **Question.** Tempo (even in monolithic mode) adds another pod to the cluster. Should `setup.sh`'s `MINIKUBE_MEMORY` default (currently `8192`, per `00_current_state.md`) be raised, or should Tempo instead be configured with tight resource requests/limits to fit inside the existing budget?

**Why it matters.** Only the user knows how much RAM headroom their dev machine (or the Linux VM from earlier this session) actually has. Raising the default risks a `minikube start` failure on a constrained machine; keeping the budget fixed risks Tempo (or something else) getting OOM-killed under memory pressure. This directly affects a `setup.sh` config line and whether a fresh bring-up still succeeds unattended.

**Resolution.** ✅ 2026-11-04 — raise the default. `40_implementation.md` bumps `MINIKUBE_MEMORY`'s default (exact value TBD during implementation, enough headroom for Tempo + the Loki stack from Q3).

---

### Q3 — Is manual `OrderId` cross-reference between trace and logs sufficient, or is Grafana's click-through trace-to-logs correlation worth adding Loki for?

✅ **Question.** `20_options.md`'s Option B pros listed Grafana's "trace-to-logs correlation available for free" as a benefit of reusing the existing Grafana instance. That claim doesn't actually hold as stated: `00_current_state.md` confirmed **no log-aggregation backend exists today** (logs are plain console output, read via `kubectl logs`) — Grafana's click-through trace-to-logs feature requires a log datasource like Loki, which isn't in scope per `10_target_shape.md`'s non-goals as currently written. So the real choice is: (a) accept `10_target_shape.md`'s success criteria as literally written — a developer manually cross-references a trace's `OrderId` tag against `kubectl logs` output by eye, no UI click-through — or (b) expand scope to add Loki (a new Helm chart, a logging driver/sidecar change in every service, more `setup.sh` plumbing) to get the one-click correlation.

**Why it matters.** This is a real scope and time decision, not a detail — (b) is meaningfully more work across infra and all five services, under the same time constraint that drove the ingress revert.

**Resolution.** ✅ 2026-11-04 — add Loki (option b), despite the time-pressure default pointing the other way. `10_target_shape.md`'s non-goals and success criteria will need a follow-up edit to reflect the expanded scope (Loki now in scope; "manual cross-reference" is upgraded to "one-click trace-to-logs"). Implementation note: Loki typically needs **no per-service code changes** to ingest logs — a Promtail/Grafana Agent DaemonSet scrapes container stdout directly — so this is primarily new infra (`k8s/infra/` + `setup.sh`), not a fourth code change on top of the OTel SDK work. Pairs directly with Q4 (✅ below): trace-to-logs correlation works far better when the trace ID is actually present in the log line Loki ingests.

---

### Q4 — Inject the trace ID into existing structured log lines via OTel's logging integration?

✅ **Question.** Should each service's existing `Microsoft.Extensions.Logging` setup also emit the current trace/span ID (via `OpenTelemetry.Extensions.Hosting`'s standard `.Logging.AddOpenTelemetry()` / `IncludeFormattedMessage` wiring) alongside the existing `OrderId` structured-logging parameter, so a developer can `kubectl logs | grep <traceId>` directly — independent of whether Q3 resolves toward adding Loki or not?

**Why it matters.** This is comparatively low-cost (a few lines in each service's logging setup, no new infra) and directly improves the "sufficient without Loki" path from Q3 option (a) — but it's still a real change to every service's `Program.cs` logging configuration, so it should be an explicit yes/no rather than something quietly bundled into the OTel SDK setup.

**Resolution.** ✅ 2026-11-04 — yes, add it. Now load-bearing for Q3's resolution too: Grafana's trace-to-logs correlation against Loki works far better with the trace ID actually present in the ingested log line, not just the `OrderId`. `40_implementation.md` includes this as an explicit step in each of the five services' `Program.cs`.

---

**Exit criterion:** Every question is ✅ resolved, ❌ dropped, or ⚠️ blocked-with-blocker. Mark ✅ in `README.md` when complete.
