# 10 — Target shape

What the change must produce. **Requirements, not solutions.** This is the interpretation of `inputs.md` against `00_current_state.md`. If you find yourself naming a model, table, or implementation detail, you're in `20_options.md` territory — back up.

## Goals

- **A full order flow runs end-to-end, driven by asynchronous messages, not just synchronous calls.** Placing an order in BeanApp results in OrderBeans → PayBeancoins → CookerBeaners → BeanNotifs each reacting to a message on RabbitMQ, in that causal order, without any service calling another's HTTP API directly for the core flow.
- **IAM actually gates something observable.** At least one real access-control boundary exists and is checked at request time: an unauthenticated caller is rejected, an authenticated one (via Keycloak) is accepted. Not "Keycloak is deployed" — "Keycloak's decision changes the outcome of a request."
- **Metrics/monitoring cover the inter-service flow, not just host/pod health.** Prometheus scrapes each of the five services plus RabbitMQ, and Grafana has at least one dashboard that shows the order flow moving through the system (e.g. requests per service, queue depth/consumer lag on the relevant RabbitMQ queues).
- **Deployment is a pipeline, not a manual step.** A change to a service (new image tag) or to a manifest in this meta repo reaches the running minikube cluster via Argo CD syncing, without a manual `kubectl apply`/`kubectl set image` in the loop.
- **Every service is independently built and deployed from its own repo's image**, and this meta repo is the single place that declares how those five images + the infra components (RabbitMQ, Keycloak, Traefik, Prometheus, Grafana, Argo CD) compose into one running system on minikube.
- **Traefik is the single entry point** for external traffic into the cluster (webapp, and any exposed API), rather than each service being reached ad hoc via NodePort/port-forward.

## Non-goals

- **Real payment processing.** PayBeancoins simulates/mocks a payment outcome (success/fail); no real payment gateway, card data, or money movement is in scope.
- **Production-grade security hardening.** IAM must demonstrably gate *something*; going further (rate limiting, WAF, secret rotation, mTLS between all services) is not required for this project.
- **Polished end-user UX.** BeanApp needs to be usable enough to trigger the flow (place an order); visual design, accessibility, and UX polish are explicitly out of scope, per the "operation between systems matters more than end-user features" framing in `inputs.md`.
- **Multi-tenant / multi-shop support.** One "Phaseolus Express" bean-food shop instance is enough; no support for multiple restaurants, catalogs, or currencies.
- **High availability / multi-node / multi-cluster deployment.** A single-node minikube cluster is the target; no HA, no cloud cluster, no autoscaling requirements.
- **Load/performance testing or scalability targets.** This is a functionality-and-wiring demo, not a benchmark.
- **Changing the already-decided infra product choices** (RabbitMQ, Kubernetes/minikube, Traefik, Keycloak, Prometheus/Grafana, Argo CD) or the five service names/roles. Those are treated as fixed inputs for this plan (see `inputs.md`, `00_current_state.md`); `20_options.md` is about *how they're wired together*, not *which products are used*.

## Constraints

- **Single-node minikube cluster.** Every component (5 services + RabbitMQ + Keycloak + Traefik + Prometheus + Grafana + Argo CD) must run within what one dev machine's minikube can host — lightweight images, no dependency on a managed cloud service.
- **Six repos, one team.** This meta repo plus five already-created, near-empty service repos (`M321_TBZ_Phaseolus_WebApp`/`Order`/`Pay`/`Cooker`/`Notifs`, currently under the `Timposter8107` GitHub account per `00_current_state.md`) — changes to those repos' code/CI/Docker setup are not solely this repo's decision to make unilaterally; the orchestration/manifest layer here needs to agree on a contract (image name/tag scheme, at minimum) that the service repos can each satisfy independently.
- **Grading rubric is the hard requirement, not a nice-to-have.** The assignment explicitly requires message broker, IAM, metrics/monitoring, and deployment/orchestration (`docs/CLAUDE.md` → Project Goals), and grades on inter-system functionality specifically — so each of those four must be *visibly wired into the order flow*, not merely present as an installed-but-unused component.
- **No existing code to preserve.** Because every repo is still a scaffold (`00_current_state.md`), there's no legacy behavior, schema, or API to stay compatible with — this plan is greenfield, which simplifies `20_options.md` but means nothing here is validated by existing usage.
- **Do not switch branches without explicit user confirmation** (per `docs/CLAUDE.md`'s Branch discipline section) when this plan moves into implementation.

## Success criteria

- Placing an order in BeanApp is followed, without further manual action, by: an order created in OrderBeans, a payment outcome recorded by PayBeancoins, a cook/fulfillment step logged by CookerBeaners, and a notification emitted by BeanNotifs — each step traceable to a RabbitMQ message, visible in logs or a dashboard.
- A request to a protected endpoint/route with no valid Keycloak-issued token is rejected (401/403); the same request with a valid token succeeds.
- Grafana shows live data for: at least one metric per custom service (e.g. request count or latency), and at least one RabbitMQ metric (e.g. queue depth, message rate) tied to the order flow's queues/exchanges.
- Editing a manifest (or bumping an image tag) in this meta repo, then pushing it, results in Argo CD reconciling the running minikube cluster to match — observable via `kubectl get pods` showing the updated state and/or the Argo CD UI showing a sync — without a manual `kubectl` mutation.
- `kubectl get pods -A` (or namespace-scoped equivalent) on the minikube cluster shows all five services and all infra components running simultaneously, with Traefik as the only externally-reachable ingress.

---

**Exit criterion:** Requirements are testable, not vague. Mark ✅ in `README.md` when complete.
