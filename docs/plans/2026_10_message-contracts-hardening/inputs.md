# Inputs

The user's framing for this work, captured **verbatim**. Do not paraphrase, summarize, or "clean up" — interpretation belongs in `10_target_shape.md`, and we need the unfiltered source to check that interpretation later.

## Source

### The grading rubric (`docs/LB3_Projektarbeit_WIR.md`), the three criteria this plan targets, quoted verbatim

> | 2 | Schnittstellendesign & Kontrakte | 15 Pkt | Keine funktionierende synchrone Kommunikation zwischen den Services. | Keine Gemeinsame Schnittstellen Basis. Kommunikation funktioniert, aber Schnittstellenänderungen können nicht technisch propagiert werden. | Kontrakte über Shared Code aber ohne formalen Kontrakt gelöst. | Formale Kontrakte (OpenAPI/AsyncAPI/Protobuf) versioniert im Shared-Repo; klare DTO-Trennung. |
> | 3 | Asynchrone Entkopplung & Idempotenz | 15 Pkt | Keine asynchronität implementiert. Nur synchrone Kommunikation. | Asynchrone Prozesse implementiert, aber Services sind nicht voneinander entkoppelt. | Asynchrone Kommunikation via Message Broker für entkoppelte Prozesse. | Saubere Idempotenz-Strategie. Konsumenten ignorieren oder handhaben doppelte Nachrichten. Ausfall/Verzögerung des Consumers blockiert Publisher in keiner Weise. |
> | 7 | Evolution & Breaking Change Handling | 15 Pkt | Änderung kann nicht implementiert werden. Verständnis für System nicht genügend vorhanden. | Änderung am Schema bricht abhängige Services (erfordert zeitgleiches Deployment beider Services). | Breaking Change (v1 $\to$ v2) wird isoliert deployed; Rückwärtskompatibilität bleibt für bestehende Konsumenten gewahrt (z. B. Parallelbetrieb oder Tolerant Reader). | Konsequente Umsetzung des Expand and Contract-Patterns; Live-Migration eines Consumers ohne Unterbrechung oder Datenverlust. |

### The user's instruction to act on the audit

> Yes please, turn these into plans to be tackled.

(Said in response to being shown a full audit of the project against all 9 rubric criteria. The user had separately confirmed: 3 themed plans — this one covering criteria 2/3/7 together, since they share the `EventEnvelope`/payload/versioning surface — and the full occ-plan staged process specifically for this plan, since it's the one with genuine design trade-offs to weigh.)

## Notes

This plan's starting point is a live-codebase audit performed earlier in this session (three parallel investigations, one per criterion, each independently grepping/reading the actual service repos — not derived from docs or assumption). Key findings that `00_current_state.md` should verify fresh and build on, not take on faith:

- **Contracts (criterion 2):** the `EventEnvelope` wrapper (`EventId`, `EventType`, `OccurredAt`, `OrderId`, `Payload`) is identically copy-pasted into `Messaging/EventEnvelope.cs` in all four of OrderBeans/PayBeancoins/CookerBeaners/BeanNotifs. The *payload* inside it is not shared — each service redefines its own record independently, and a real drift already exists: `M321_TBZ_Phaseolus_Order/Models/OrderModels.cs`'s `OrderCreatedPayload` has an `Email` field that `M321_TBZ_Phaseolus_Pay/Models/PaymentModels.cs`'s copy of the same type lacks. Zero formal contract artifacts (OpenAPI/AsyncAPI/Protobuf) exist anywhere in the 6 repos. A prior plan, `../2026_10_service-api-template/`, deliberately chose copy-paste-over-shared-package for these DTOs — that decision should be read, not re-litigated, before proposing an approach here.
- **Idempotency (criterion 3):** communication is genuine fire-and-forget pub/sub (no RPC-style blocking), with manual ack and a solid bounded-retry mechanism (`x-retry-count` header, survives pod restarts, caps at 5 attempts, no dead-letter exchange after that). But the `EventId` already present on every message is never read by any consumer — a redelivery (e.g. after a consumer crash between handling and ack) would silently double-process a message (double-charge a payment, double-send a notification).
- **Breaking-change readiness (criterion 7):** no deliberate versioning exists anywhere (routing keys like `"order.created"` are unversioned strings, no schema version field). However, every consumer deserializes with default `System.Text.Json` settings, which silently ignores unknown JSON properties — an accidental, undocumented Tolerant Reader property that already covers additive field changes today, by luck rather than design.
