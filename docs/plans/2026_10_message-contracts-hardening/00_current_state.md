# 00 — Current state

What exists in the codebase **today**, before any change. The goal: a reader unfamiliar with this corner of the repo can follow links from this doc to the relevant code and understand what's there.

## Models / data shape

**The envelope — shared shape, copy-pasted verbatim, not drifted.** Every service's `Messaging/EventEnvelope.cs` (`M321_TBZ_Phaseolus_{Order,Pay,Cooker,Notifs}/Messaging/EventEnvelope.cs`) is byte-identical except for its namespace:
```csharp
public record EventEnvelope(
    Guid EventId,
    string EventType,
    DateTimeOffset OccurredAt,
    Guid OrderId,
    JsonElement Payload);
```
This is a deliberate decision, not an accident — `docs/plans/2026_09_phaseolus-architecture/30_open_questions.md` Q2's tech-stack bullet list: *"Message contracts: no shared NuGet package across the four repos — each service defines its own local C# record matching the JSON event shape"* — reaffirmed in `docs/plans/2026_10_service-api-template/20_options.md`'s Option B (copy-paste plumbing, not a package).

**The payload inside `Payload` — independently redefined per service, already drifted.** Each service that touches a given event type keeps its own copy of that event's payload record:

| Event type | Published by (payload definition) | Payload shape | Also redefined by (consumer's own copy) |
|---|---|---|---|
| `order.created` | `OrderBeans.Models.OrderCreatedPayload` (`M321_TBZ_Phaseolus_Order/Models/OrderModels.cs:7`) | `(List<OrderItem> Items, decimal TotalAmount, string Email)` | `PayBeancoins.Models.OrderCreatedPayload` (`M321_TBZ_Phaseolus_Pay/Models/PaymentModels.cs:6`) — **`(List<OrderItem> Items, decimal TotalAmount)` — missing `Email`** |
| `payment.succeeded` | `PayBeancoins.Models.PaymentSucceededPayload` (`M321_TBZ_Phaseolus_Pay/Models/PaymentModels.cs:8`) | `(decimal AmountCharged, List<OrderItem> Items)` | `CookerBeaners.Models.PaymentSucceededPayload` (`M321_TBZ_Phaseolus_Cooker/Models/CookerModels.cs:6`) — identical today, but independently typed, so nothing stops future drift |
| `payment.failed` | `PayBeancoins.Models.PaymentFailedPayload` (`M321_TBZ_Phaseolus_Pay/Models/PaymentModels.cs:10`) | `(string Reason)` | `BeanNotifs.Models.PaymentFailedPayload` (`M321_TBZ_Phaseolus_Notifs/Models/NotificationModels.cs:6`) — identical today |
| `order.cooking-started` | `CookerBeaners.Models.OrderCookingStartedPayload` (`M321_TBZ_Phaseolus_Cooker/Models/CookerModels.cs:9`) | `()` — empty, `OrderId` on the envelope is sufficient | not redefined — BeanNotifs' handler reads only `envelope.OrderId`/`OccurredAt`, never deserializes the payload |
| `order.cooked` | `CookerBeaners.Models.OrderCookedPayload` (`M321_TBZ_Phaseolus_Cooker/Models/CookerModels.cs:12`) | `()` — empty | not redefined, same reason |

`OrderItem` (`(string Name, int Quantity)`) is copy-pasted identically into `OrderBeans`, `PayBeancoins`, and `CookerBeaners`'s own `Models/*.cs`.

**No formal contract artifact exists anywhere.** No OpenAPI, AsyncAPI, JSON Schema, or `.proto` file in this meta repo, any of the 5 service repos, or a dedicated shared/contracts repo.

## Code paths involved

- **Publishing:** `EventPublisher.cs` in `OrderBeans`, `PayBeancoins`, `CookerBeaners` (`M321_TBZ_Phaseolus_{Order,Pay,Cooker}/Messaging/EventPublisher.cs`) — identical shape, each declares the shared topic exchange (`RabbitMqOptions.ExchangeName = "phaseolus.events"`, `M321_TBZ_Phaseolus_Order/Messaging/RabbitMqOptions.cs:12`) and does a plain, persistent `BasicPublish`. BeanNotifs never publishes (it's a terminal consumer).
- **Consuming:** `EventConsumerHostedService.cs` in `PayBeancoins`, `CookerBeaners`, `BeanNotifs` (`M321_TBZ_Phaseolus_{Pay,Cooker,Notifs}/Messaging/EventConsumerHostedService.cs`) — identical shape across all three. Manual ack (`autoAck: false`), `BasicQos(prefetchCount: 10)`. On handler failure: re-publishes the same message to the same routing key with an incrementing `x-retry-count` header (survives pod restarts, since the count lives in the message, not in memory), capped at `MaxDeliveryAttempts = 5`, then logs and drops — no dead-letter exchange.
- **Event routing table**, assembled from each service's `Program.cs`:
  - OrderBeans (`Program.cs:41-57`, `POST /orders`) publishes `order.created`.
  - PayBeancoins (`Program.cs:15-22`, queue `pay.incoming-orders`) consumes `order.created`; publishes `payment.succeeded` or `payment.failed` (`Program.cs:41-74`) — a hardcoded "Rotten Beans" item name deterministically simulates a failed payment.
  - CookerBeaners (`Program.cs:15-22`, queue `cooker.paid-orders`) consumes `payment.succeeded`; publishes `order.cooking-started` immediately, then `order.cooked` after a per-item cook delay (`Program.cs:39-76`).
  - BeanNotifs (`Program.cs:74-84`, four queues: `notifs.payment-succeeded`, `notifs.payment-failed`, `notifs.order-cooking-started`, `notifs.order-cooked`) consumes all four downstream event types and appends to an in-memory notification log; never publishes.
  - BeanApp → BeanNotifs is the **one synchronous call in the system**: `BeanApp/Pages/Admin.cshtml.cs:30` uses `IHttpClientFactory.CreateClient("BeanNotifs")` to fetch `GET /notifications` directly over REST for the admin page.
- **Deserialization call sites** (where a payload is actually read back out of `JsonElement Payload`): `PayBeancoins/Program.cs:43` (`OrderCreatedPayload`), `CookerBeaners/Program.cs:41` (`PaymentSucceededPayload`), `BeanNotifs/Program.cs:120` (`PaymentFailedPayload`, the *only* payload BeanNotifs ever deserializes — its other three handlers read only `envelope.OrderId`/`OccurredAt`). All use plain `envelope.Payload.Deserialize<T>()` with no `JsonSerializerOptions` override anywhere in any of the four services — `System.Text.Json`'s default behavior applies throughout.

## Behavior today

- Communication between the four backend services is pure fire-and-forget pub/sub: a publisher calls `BasicPublish` and returns immediately; nothing waits on a consumer's response (confirmed: zero `HttpClient`/RPC-style reply-to usage between these four services — only the one BeanApp→BeanNotifs REST call noted above).
- A down or slow consumer never blocks a publisher — messages simply accumulate in that consumer's RabbitMQ queue.
- `System.Text.Json`'s default deserialization is lenient: unknown JSON properties are silently dropped, not an error. This is why the already-present `Email`-field drift (OrderBeans has it, PayBeancoins' copy of the same payload doesn't) hasn't caused a visible failure — PayBeancoins' deserialize call simply never sees `Email`, by construction, not by any explicit tolerant-reader design.
- No message carries any version marker. Routing keys (`"order.created"`, `"payment.succeeded"`, etc.) and `EventType` string values are both unversioned literals.
- `EventId` is generated fresh on every publish (`Guid.NewGuid()` at the call site in each publisher) but is never read back by any consumer — nothing currently checks "have I already handled this `EventId`."

## What's missing or awkward

- **Contract drift has already happened** (the `Email` field) and nothing would have caught it — no formal schema, no shared type, no build-time or runtime check ties a publisher's payload shape to what its consumer(s) expect.
- **No idempotency guard.** The retry mechanism above will re-deliver the *same* message (same `EventId`) to a handler more than once in two scenarios: (a) the handler throws partway through after already taking an external side effect, then the retry re-runs it; (b) a pod crash between `await binding.Handler(envelope)` succeeding and `BasicAck` being called causes RabbitMQ to redeliver an already-fully-processed message on reconnect. Either would currently double-process — e.g. `PayBeancoins` double-publishing `payment.succeeded`/`payment.failed` for one order, or `BeanNotifs` double-logging a notification.
- **No versioning scheme at all**, so there's currently no vocabulary for "this is a v2 message" — any future payload change has only ever been exercised as an untracked, same-version edit.
- **No dead-letter exchange.** After `MaxDeliveryAttempts` (5), a failing message is logged and permanently dropped — there's no parking lot to inspect or manually replay it from.

---

**Exit criterion:** A reader can navigate the relevant code from this doc alone. Mark ✅ in `README.md` when complete.
