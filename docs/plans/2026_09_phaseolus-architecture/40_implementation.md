# 40 — Implementation

Step plan for the chosen option from `20_options.md`. **Do not start this phase while `30_open_questions.md` has any ⏳ items** — that's the discipline this folder structure exists to enforce.

Each step has a verification: how do we know the step is done? Strong verification turns the plan into a checklist you can run independently.

## Plan summary

Build bottom-up: cluster and shared infra first (nothing custom depends on anything custom yet), then Keycloak's realm/client (needed before any service can be written against it), then the four message-driven services in their causal order (OrderBeans → PayBeancoins → CookerBeaners → BeanNotifs, matching the event chain from Q5 so each step can be verified against the one built immediately before it), then BeanApp (the one piece that depends on everything else existing), then the two cross-cutting concerns that only make sense once services exist (Traefik ingress, Prometheus/Grafana), and finally Argo CD's App-of-Apps so the whole thing becomes git-driven rather than hand-applied. This order means every step has something concrete to verify against, and the riskiest/most novel piece for this team (Argo CD GitOps) is proven last, after the simpler kubectl-applied version already works — so a GitOps wiring mistake doesn't block seeing the application work at all.

**One implementation-time decision not covered by Q1–Q8:** the open questions scoped manifest format (Q3) and registry/tagging (Q4) to the *five custom services* only. For the **infra components** (RabbitMQ, Keycloak, Traefik, Prometheus, Grafana), Step 2 uses their official/community Helm charts rather than hand-written manifests — hand-rolling a RabbitMQ or Keycloak deployment from scratch is effort this plan doesn't need to spend, and it doesn't contradict Q3 (which was explicitly about the custom services' manifests). Flagging this here since it's a real decision, just not one of the original 8 questions.

**Team sequencing note (Q1):** since `Timposter8107` is a teammate, Steps 5–10 (the five service repos) are naturally splittable by repo across two people — Step 5's manifest/Dockerfile convention needs to be agreed between you before either of you starts Steps 6–10 in parallel.

## Steps

### Step 1 — Stand up minikube and namespaces

⏳ **Do.** `minikube start` with enough resources for 5 services + RabbitMQ + Keycloak + Traefik + Prometheus + Grafana + Argo CD (e.g. `--cpus=4 --memory=8192`, adjust to the dev machine). Create the `phaseolus` and `infra` namespaces (Q6); `argocd`'s namespace is created by its own install in Step 3.

**Verify.** `kubectl get ns` lists `phaseolus` and `infra`; `kubectl cluster-info` succeeds.

---

### Step 2 — Install infra components

⏳ **Do.** Into the `infra` namespace, install RabbitMQ, Keycloak, Traefik, and a Prometheus+Grafana stack (e.g. the `kube-prometheus-stack` Helm chart, which bundles both) via their official/community Helm charts — see the implementation-time decision above.

**Verify.** `kubectl get pods -n infra` shows all five infra pods `Running`; RabbitMQ's management UI, Keycloak's admin console, and Grafana are each reachable via `kubectl port-forward` for setup purposes.

---

### Step 3 — Install Argo CD

⏳ **Do.** Apply Argo CD's official install manifest into its own `argocd` namespace (Q6). Access the UI via port-forward for initial setup only (it becomes git-driven once Step 13 lands).

**Verify.** `kubectl get pods -n argocd` shows Argo CD components `Running`; `argocd login` (or the UI) succeeds.

---

### Step 4 — Configure the Keycloak realm and client

⏳ **Do.** Create the `phaseolus` realm (Q7). Register `beanapp-client` as a confidential client with the client-credentials grant and service account enabled — no end-user login flow.

**Verify.** A direct `curl` to the realm's token endpoint with `beanapp-client`'s credentials returns a valid access token (decode it to confirm issuer = the `phaseolus` realm).

---

### Step 5 — Agree the service-repo convention, scaffold all five

⏳ **Do.** With your teammate (Q1), agree and apply to all five service repos: the Dockerfile shape (multi-stage, `sdk:8.0` → `aspnet:8.0`, per Q2), the ASP.NET Core Minimal API project skeleton (each exposing at least a `/metrics` endpoint via `prometheus-net`), and the `/deploy/deployment.yaml` + `/deploy/service.yaml` pair (plain YAML, `imagePullPolicy: Never`, per Q3/Q4) with a placeholder image tag.

**Verify.** Each of the five repos: `dotnet build` succeeds, `docker build` succeeds, and `kubectl apply --dry-run=client -f deploy/` validates without error.

---

### Step 6 — Implement OrderBeans

⏳ **Do.** `POST /orders` endpoint: validates the caller's Keycloak bearer token (Q7, `JwtBearer` against the `phaseolus` realm's OIDC discovery doc — issuer/signature/expiry only); on success, publishes `order.created` to `phaseolus.events` with the Q5 payload shape.

**Verify.** `curl -X POST` with no `Authorization` header → `401`. The same request with a client-credentials token from Step 4 → `2xx`, and the message appears in the `pay.incoming-orders` queue (checked via RabbitMQ's management UI/API).

---

### Step 7 — Implement PayBeancoins

⏳ **Do.** Consumes `pay.incoming-orders`; applies the deterministic "Rotten Beans" rule (Q8); publishes `payment.succeeded` or `payment.failed` accordingly.

**Verify.** An order with normal items → a `payment.succeeded` message appears in `cooker.paid-orders`. An order containing an item named `"Rotten Beans"` (any case) → a `payment.failed` message (with the `reason` from Q8) appears in `notifs.payment-failed`, and nothing appears in `cooker.paid-orders` for that order.

---

### Step 8 — Implement CookerBeaners

⏳ **Do.** Consumes `cooker.paid-orders`; publishes `order.cooked`.

**Verify.** Following a successful-payment message from Step 7, a message appears in `notifs.order-cooked`.

---

### Step 9 — Implement BeanNotifs

⏳ **Do.** Consumes both `notifs.payment-failed` and `notifs.order-cooked` (Q5's dual-event consumer). Records each as a structured log line plus an in-memory list exposed via `GET /notifications` — a real delivery channel (email/SMS/push) is out of scope per `10_target_shape.md`'s non-goals; this just needs to be *observable* for the demo.

**Verify.** `GET /notifications` shows one entry for a normal order (order-cooked) and one entry for a Rotten-Beans order (payment-failed), each traceable to its `orderId`.

---

### Step 10 — Implement BeanApp

⏳ **Do.** Minimal ordering UI/API (per `10_target_shape.md`'s non-goal on UX polish). On request, fetches a client-credentials token from Keycloak (Step 4) and calls OrderBeans' `POST /orders` with it attached. Supports submitting an order containing `"Rotten Beans"`, either as a selectable item or free text, to trigger the failure path on demand.

**Verify.** Full end-to-end: placing a normal order results in a `GET /notifications` (BeanNotifs) entry for "order cooked"; placing a Rotten-Beans order results in a "payment failed" entry, and CookerBeaners never logs/publishes anything for that order.

---

### Step 11 — Expose BeanApp via Traefik

⏳ **Do.** Add an `IngressRoute`/`Ingress` (wherever each service's own manifest lives, per Q3) so Traefik is the only externally-reachable path to BeanApp.

**Verify.** The Traefik-exposed host/path reaches BeanApp; none of the other four services are reachable from outside the cluster (no stray `NodePort`/`LoadBalancer` Services).

---

### Step 12 — Wire Prometheus scraping and a Grafana dashboard

⏳ **Do.** Configure Prometheus (via the `kube-prometheus-stack`'s `ServiceMonitor` CRDs, or static scrape configs) to scrape all five services' `/metrics` across the `phaseolus` namespace, plus RabbitMQ's metrics. Build one Grafana dashboard: request count/latency per service, and queue depth for the four queues from Q5.

**Verify.** After running a few orders through the flow (including one Rotten-Beans order), the Grafana dashboard shows non-zero, moving data for each panel.

---

### Step 13 — Wire the Argo CD App-of-Apps

⏳ **Do.** In this meta repo, add the root Argo CD `Application` (app-of-apps pattern, `20_options.md`): one child `Application` per service repo (source: `<repo>/deploy`, per Q3) plus Applications for the Step 2 infra charts. Apply the root Application once manually — this is the one allowed `kubectl apply`, bootstrapping Argo CD to manage everything from here on.

**Verify.** Argo CD's UI shows every child Application `Synced`/`Healthy`. Bump an image's git-SHA tag (per Q4's flow: `minikube image load` the new image, then edit the tag in the service repo's `/deploy/deployment.yaml` and push) and confirm Argo CD reconciles the running Deployment **without** a manual `kubectl apply`/`kubectl set image`.

---

### Step 14 — End-to-end verification against `10_target_shape.md`

⏳ **Do.** Walk the `10_target_shape.md` success-criteria list explicitly as a checklist rather than assuming prior steps covered it:
- Full order flow traceable through RabbitMQ (Steps 6–10).
- Unauthenticated vs. authenticated request to OrderBeans (Step 6).
- Grafana shows live per-service and RabbitMQ data (Step 12).
- A manifest/tag change reaches the cluster via Argo CD alone (Step 13).
- `kubectl get pods -A` shows all five services + all infra running, Traefik as the only ingress (Steps 1–13 combined).

**Verify.** Each bullet confirmed against the running cluster, not just against individual step verifications in isolation — this step exists because passing each step locally doesn't guarantee the *combined* system satisfies every criterion simultaneously.

## Rollback / blast radius

Fully reversible throughout: this is a greenfield build with no production data (`00_current_state.md`). `minikube delete` and re-running Steps 1–13 reproduces the entire cluster from the git-tracked manifests and Argo CD config — there is no manual cluster state that isn't recoverable from the repos. The only non-git state is Keycloak's realm/client configuration (Step 4) if configured by hand through its admin console rather than exported — consider exporting the realm as JSON into this meta repo once Step 4 is stable, so it survives a `minikube delete` without redoing the manual setup (not required for this first pass, but cheap insurance).

## Quality gates before merging

`docs/CLAUDE.md` does not yet define a project-specific quality-gate sequence (no language/build tooling existed there until Q2 of this plan). Proposed gates, to be run per service repo before merging that repo's changes:
- `dotnet build` — compiles.
- `dotnet test` — even a minimal smoke test per service (e.g. the Rotten-Beans rule in PayBeancoins, the 401-vs-200 behavior in OrderBeans) is cheap and catches regressions across a 6-repo project.
- `kubectl apply --dry-run=client -f deploy/` — manifest validity, per repo.
- For this meta repo specifically: `kubectl apply --dry-run=client` (or `argocd app diff`) against the App-of-Apps root and infra manifests before pushing.

This list isn't in `docs/CLAUDE.md` yet — worth adding there once Step 5 lands, so it's not only recorded in this plan folder.

---

**Exit criterion:** Every step ✅, gates green, PR merged. Mark ✅ in `README.md` when complete and archive the folder per the project's plan-archive convention in `CLAUDE.md`.
