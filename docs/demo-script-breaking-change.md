# Live demo script — Breaking Change & Evolution (rubric criterion 7)

Demonstrates the `DeliveryNote` field added to `order.created` as a live Tolerant Reader example. Rehearsed and verified end-to-end against the real cluster before being written down here — see the walkthrough at the bottom for what was actually run. No rollback or simulation needed: the schema mismatch this demo shows is the system's real, permanent state on `main` today, not a historical curiosity reproduced for the occasion.

Fits in ~2–3 minutes. Part of the Fachgespräch's "Breaking Change & Evolution" checklist item.

## Setup (before the exam, not during)

Port-forwards:

```bash
kubectl -n phaseolus port-forward svc/beanapp 5050:8080 &
kubectl -n infra port-forward svc/rabbitmq 15672:15672 &
```

Browser tabs:

- `http://localhost:5050` — BeanApp's checkout page
- `http://localhost:15672` — RabbitMQ management UI (login: `phaseolus` / `phaseolus`)

Code editor open to both payload records, side by side:

- `M321_TBZ_Phaseolus_Order/Models/OrderModels.cs` — the producer
- `M321_TBZ_Phaseolus_Pay/Models/PaymentModels.cs` — the consumer

## The script

### 1. Frame the breaking change (~15s)

Show both records side by side:

```csharp
// M321_TBZ_Phaseolus_Order/Models/OrderModels.cs — the producer
public record OrderCreatedPayload(List<OrderItem> Items, decimal TotalAmount, string Email, string? DeliveryNote = null);

// M321_TBZ_Phaseolus_Pay/Models/PaymentModels.cs — the consumer
public record OrderCreatedPayload(List<OrderItem> Items, decimal TotalAmount, string Email);
```

> "OrderBeans added a `DeliveryNote` field to the `order.created` event after PayBeancoins was already built. PayBeancoins only needs the fields it actually uses to charge a payment, so it was never touched, and never redeployed. This is the schema mismatch as it stands on `main` right now — not a rollback I'm simulating."

### 2. Create a "spy" queue in the RabbitMQ UI (~20s)

In the RabbitMQ UI: **Queues** → **Add a new queue** → name it `spy-order-created`, leave defaults, **Add queue**. Click into it → **Bindings** → bind from exchange `phaseolus.events`, routing key `order.created`, **Bind**.

> "I'm binding a throwaway queue to the same exchange and routing key PayBeancoins listens on, just so we can see the raw message on the wire."

### 3. Place a real order with a delivery note (~30s)

In BeanApp: add an item to the cart, go to checkout, fill in email + **delivery note** (e.g. "Leave at the front desk, ring the bell twice"), submit. Point out "Payment accepted!"

### 4. Show the raw message (~20s)

Back in the RabbitMQ UI, on `spy-order-created`: **Get messages** → **Get Message(s)**. Point at the payload JSON — `DeliveryNote` is right there in `Payload`.

### 5. Prove PayBeancoins tolerated it (~20s)

```bash
kubectl -n phaseolus logs -l app=paybeancoins --tail=5
```

Point at `Payment succeeded for order <id>` — no exception, no crash, despite the extra field its own record doesn't declare.

### 6. Land the principle (~15s)

> "This is Tolerant Reader: System.Text.Json ignores properties it doesn't recognize by default, so a consumer only needs to declare the fields it actually cares about. OrderBeans could keep adding optional fields indefinitely without ever requiring PayBeancoins to redeploy — and this was also proven the other direction: OrderBeans was deployed alone with this field while PayBeancoins stayed on its old image, and separately, PayBeancoins shipped its own fix alone, each verified live with zero downtime to the other."

That last line is a true, citable fact, not invented for the demo — see `docs/plans/2026_10_message-contracts-hardening/40_implementation.md` Step 2 for the original isolated-deploy proof and its PR links, if a grader wants to dig in.

## Cleanup after the demo

In the RabbitMQ UI: **Queues** → `spy-order-created` → **Delete Queue**.

## Rehearsal record

Run live end-to-end on 2026-11-05 against the dev cluster before writing this script down, using RabbitMQ's HTTP API in place of the UI clicks (faster to script, identical effect):

```bash
# Create + bind the spy queue
curl -u phaseolus:phaseolus -X PUT "http://localhost:15672/api/queues/%2f/spy-order-created" \
  -H "Content-Type: application/json" -d '{"durable":false,"auto_delete":true}'
curl -u phaseolus:phaseolus -X POST "http://localhost:15672/api/bindings/%2f/e/phaseolus.events/q/spy-order-created" \
  -H "Content-Type: application/json" -d '{"routing_key":"order.created"}'

# (place an order through BeanApp's actual checkout UI here)

# Fetch the raw message
curl -u phaseolus:phaseolus -X POST "http://localhost:15672/api/queues/%2f/spy-order-created/get" \
  -H "Content-Type: application/json" -d '{"count":1,"ackmode":"ack_requeue_true","encoding":"auto"}'
```

Confirmed the fetched payload genuinely carried `DeliveryNote`:

```json
{
  "EventId": "15e6728d-7cd2-4bd7-949d-8700f98ffa22",
  "EventType": "order.created",
  "OccurredAt": "2026-11-05T15:40:59.4659403+00:00",
  "OrderId": "b65a0683-a069-4899-97ce-310d9344b9bf",
  "Payload": {
    "Items": [{ "Name": "Classic Beans", "Quantity": 1 }],
    "TotalAmount": 5.0,
    "Email": "demo-rehearsal-2@phaseolus.local",
    "DeliveryNote": "Leave at the front desk, ring the bell twice"
  }
}
```

And confirmed PayBeancoins processed that exact order cleanly:

```
kubectl -n phaseolus logs -l app=paybeancoins --tail=5
# Payment succeeded for order b65a0683-a069-4899-97ce-310d9344b9bf
```
