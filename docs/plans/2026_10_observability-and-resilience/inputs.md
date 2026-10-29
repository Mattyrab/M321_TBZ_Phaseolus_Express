# Inputs

The user's framing for this work, captured **verbatim**. Do not paraphrase, summarize, or "clean up" — interpretation belongs in `10_target_shape.md`, and we need the unfiltered source to check that interpretation later.

## Source

### The grading rubric (`docs/LB3_Projektarbeit_WIR.md`), the two criteria this plan targets, quoted verbatim

> | 5 | Observability & Distributed Tracing | 5 Pkt | Unstrukturierte Konsolen-Logs ohne Kontext; Nachverfolgung über Services hinweg unmöglich. | Korrelation der Logs der Services manuell möglich. | Einheitliches Logging-Format. Korrelations-ID wird über alle Aufrufe und Message-Payloads durchgereicht. | Vollständiges Distributed Tracing (z.B. OpenTelemetry/Jaeger) oder zentralisiertes Log-Aggregation-Setup mit Trace-Verknüpfung. |
> | 6 | Skalierbarkeit & Resilienz | 10 Pkt | Kein Konzept für Skaliereung vorhanden | Konzept zur Skalierung von mindestens einem Worker/Service vorhanden aber nicht implementiert. | Services sind stateless; mindestens ein Worker/Service lässt sich horizontal hochskalieren. | Lastverteilung funktioniert dynamisch; Timeouts, Retries und Circuit-Breaker oder Graceful Degradation implementiert. |

### The user's instruction to act on the audit

> Yes please, turn these into plans to be tackled.

(Said in response to being shown a full audit of the project against all 9 rubric criteria. The user confirmed: 3 themed plans — this one covering criteria 5/6 together, both "operational maturity" fixes that are small and independent of each other — skipping straight to an implementation doc rather than the full staged process, since neither has a real design decision to weigh.)

## Notes

This plan's starting point is a live-codebase audit performed earlier in this session. Findings `40_implementation.md` should verify fresh, not take on faith:

- **Observability (criterion 5):** structured `ILogger` is used in OrderBeans/PayBeancoins/CookerBeaners/BeanNotifs' consumer code, but only on *failure* paths — zero `LogInformation` calls exist anywhere in the project. A stable correlation ID (`OrderId`) already rides in every `EventEnvelope`, and is already interpolated correctly into the failure-path log templates (e.g. `PayBeancoins/Messaging/EventConsumerHostedService.cs`) — it's just never logged on success.
- **Resilience/scaling (criterion 6):** every service's `deploy/deployment.yaml` is pinned at `replicas: 1`, no HPA anywhere, no Polly (or other resilience library) for HTTP timeouts/retries/circuit-breakers. The architecture plan (`docs/plans/2026_09_phaseolus-architecture/10_target_shape.md`) explicitly disclaimed scaling as out of scope at the time. OrderBeans and CookerBeaners hold no shared mutable state and would scale cleanly today. **BeanNotifs is the exception** — its admin-visible notification log lives in an in-memory `ConcurrentQueue<Notification>` singleton (`M321_TBZ_Phaseolus_Notifs/Models/NotificationModels.cs`), so scaling it would silently split that log across replicas. Any scale-out demo should pick OrderBeans or CookerBeaners, not BeanNotifs.
