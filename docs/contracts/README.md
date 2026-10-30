# Message contracts

AsyncAPI 2.6.0 specs for every event type published on the `phaseolus.events`
RabbitMQ topic exchange. One file per event, each describing the shared
envelope (`EventId`, `EventType`, `OccurredAt`, `OrderId`) plus that event's
payload shape.

These are documentation, not a build dependency — no service imports or
validates against them. The envelope and payload records are still
copy-pasted independently into each service's own `Models`/`Messaging`
folders (see `docs/plans/2026_09_phaseolus-architecture/30_open_questions.md`
Q2 and `docs/plans/2026_10_service-api-template/20_options.md`), so these
specs are the single place to check "what does this event actually look
like" without reading a publisher's source.

| Event | Published by | Consumed by |
|---|---|---|
| [`order.created`](./order.created.yaml) | OrderBeans | PayBeancoins |
| [`payment.succeeded`](./payment.succeeded.yaml) | PayBeancoins | CookerBeaners, BeanNotifs |
| [`payment.failed`](./payment.failed.yaml) | PayBeancoins | BeanNotifs |
| [`order.cooking-started`](./order.cooking-started.yaml) | CookerBeaners | BeanNotifs |
| [`order.cooked`](./order.cooked.yaml) | CookerBeaners | BeanNotifs |

Written as part of `docs/plans/2026_10_message-contracts-hardening/` Step 3 —
see that plan for the full rationale (including why `order.created` carries
both a bug fix and a deliberate additive-field demo).
