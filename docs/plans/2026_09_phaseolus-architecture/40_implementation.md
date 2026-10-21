# 40 — Implementation

Step plan for the chosen option from `20_options.md`. **Do not start this phase while `30_open_questions.md` has any ⏳ items** — that's the discipline this folder structure exists to enforce.

Each step has a verification: how do we know the step is done? Strong verification turns the plan into a checklist you can run independently.

## Plan summary

Build bottom-up: cluster and shared infra first (nothing custom depends on anything custom yet), then Keycloak's realm/client (needed before any service can be written against it), then the four message-driven services in their causal order (OrderBeans → PayBeancoins → CookerBeaners → BeanNotifs, matching the event chain from Q5 so each step can be verified against the one built immediately before it), then BeanApp (the one piece that depends on everything else existing), then the two cross-cutting concerns that only make sense once services exist (Traefik ingress, Prometheus/Grafana), and finally Argo CD's App-of-Apps so the whole thing becomes git-driven rather than hand-applied. This order means every step has something concrete to verify against, and the riskiest/most novel piece for this team (Argo CD GitOps) is proven last, after the simpler kubectl-applied version already works — so a GitOps wiring mistake doesn't block seeing the application work at all.

**One implementation-time decision not covered by Q1–Q8:** the open questions scoped manifest format (Q3) and registry/tagging (Q4) to the *five custom services* only. For the **infra components** (RabbitMQ, Keycloak, Traefik, Prometheus, Grafana), Step 2 uses their official/community Helm charts rather than hand-written manifests — hand-rolling a RabbitMQ or Keycloak deployment from scratch is effort this plan doesn't need to spend, and it doesn't contradict Q3 (which was explicitly about the custom services' manifests). Flagging this here since it's a real decision, just not one of the original 8 questions.

**Team sequencing note (Q1):** since `Timposter8107` is a teammate, Steps 5–10 (the five service repos) are naturally splittable by repo across two people — Step 5's manifest/Dockerfile convention needs to be agreed between you before either of you starts Steps 6–10 in parallel.

## Steps

### Step 1 — Stand up minikube and namespaces

✅ **Do.** `minikube start` with enough resources for 5 services + RabbitMQ + Keycloak + Traefik + Prometheus + Grafana + Argo CD (e.g. `--cpus=4 --memory=8192`, adjust to the dev machine). Create the `phaseolus` and `infra` namespaces (Q6); `argocd`'s namespace is created by its own install in Step 3.

**Verify.** `kubectl get ns` lists `phaseolus` and `infra`; `kubectl cluster-info` succeeds.

---

### Step 2 — Install infra components

✅ **Do.** Into the `infra` namespace, install RabbitMQ, Keycloak, Traefik, and a Prometheus+Grafana stack (e.g. the `kube-prometheus-stack` Helm chart, which bundles both) via their official/community Helm charts — see the implementation-time decision above.

**Verify.** `kubectl get pods -n infra` shows all five infra pods `Running`; RabbitMQ's management UI, Keycloak's admin console, and Grafana are each reachable via `kubectl port-forward` for setup purposes.

✅ **Done 2026-10-02.** Repos added: `bitnami` (RabbitMQ, Keycloak), `traefik`, `prometheus-community` (`kube-prometheus-stack`, which installs Prometheus + Grafana + Alertmanager + kube-state-metrics + node-exporter together). Two gotchas hit and worth recording so this is reproducible:
- **Bitnami's August 2025 catalog change broke default images.** `bitnami/rabbitmq` and `bitnami/keycloak` (and their `bitnami/os-shell`, `bitnami/postgresql` dependents) 404 on Docker Hub as of free-tier access — only the `bitnamilegacy/*` org still hosts the last free versions. Both installs needed `--set global.security.allowInsecureImages=true` plus explicit `image.repository=bitnamilegacy/<name>` overrides (and `postgresql.image.repository`/`postgresql.volumePermissions.image.repository` for Keycloak's bundled Postgres subchart).
- **Keycloak's default `resourcesPreset: small` (768Mi limit) OOM-kills the JVM on boot.** Fixed with `--set resourcesPreset=large`. Plenty of room on this cluster (8GB allocated) to afford it.

Credentials set: RabbitMQ `phaseolus`/`phaseolus`; Keycloak admin `admin`/`phaseolus`; Grafana admin `admin`/`phaseolus` — all dev-only, fine for a local minikube demo, not meant to survive past this plan.

---

### Step 3 — Install Argo CD

✅ **Do.** Apply Argo CD's official install manifest into its own `argocd` namespace (Q6). Access the UI via port-forward for initial setup only (it becomes git-driven once Step 13 lands).

**Verify.** `kubectl get pods -n argocd` shows Argo CD components `Running`; `argocd login` (or the UI) succeeds.

✅ **Done 2026-10-05.** One gotcha: plain `kubectl apply -f install.yaml` failed — the `applicationsets.argoproj.io` CRD exceeds the 262144-byte limit on the client-side `last-applied-configuration` annotation. Fixed with `kubectl apply --server-side --force-conflicts`, which applies without that annotation. All 7 Argo CD pods (`argocd-server`, `argocd-repo-server`, `argocd-application-controller`, `argocd-applicationset-controller`, `argocd-dex-server`, `argocd-redis`, `argocd-notifications-controller`) came up `Running`. Login verified directly against `/api/v1/session` with the `admin` user and the auto-generated initial password from the `argocd-initial-admin-secret` secret → `HTTP 200`.

---

### Step 4 — Configure the Keycloak realm and client

✅ **Do.** Create the `phaseolus` realm (Q7). Register `beanapp-client` as a confidential client with the client-credentials grant and service account enabled — no end-user login flow.

**Verify.** A direct `curl` to the realm's token endpoint with `beanapp-client`'s credentials returns a valid access token (decode it to confirm issuer = the `phaseolus` realm).

✅ **Done 2026-10-05.** Configured via Keycloak's Admin REST API (port-forwarded `svc/keycloak`, authenticated as the `admin` user from Step 2 against the `master` realm). `phaseolus` realm created (`201`); `beanapp-client` created (`201`) with `publicClient: false`, `serviceAccountsEnabled: true`, `standardFlowEnabled: false`, `directAccessGrantsEnabled: false` — i.e. client-credentials/service-account only, matching Q7 exactly. Verification: requested a token via `grant_type=client_credentials` against `/realms/phaseolus/protocol/openid-connect/token` → `HTTP 200`; decoded the JWT payload and confirmed `"iss":"http://localhost:8081/realms/phaseolus"` and `"azp":"beanapp-client"`. No credentials or tokens were printed to the terminal — the client secret and admin token were held in short-lived temp files and deleted after use.

---

### Step 5 — Agree the service-repo convention, scaffold all five

**Detailed design:** see [`../2026_10_service-api-template/`](../2026_10_service-api-template/) — the code-level shape of the template, which repo is the reference implementation, and the exact per-service deltas.

✅ **Do.** With your teammate (Q1), agree and apply to all five service repos: the Dockerfile shape (multi-stage, `sdk:8.0` → `aspnet:8.0`, per Q2), the ASP.NET Core Minimal API project skeleton (each exposing at least a `/metrics` endpoint via `prometheus-net`), and the `/deploy/deployment.yaml` + `/deploy/service.yaml` pair (plain YAML, `imagePullPolicy: Never`, per Q3/Q4) with a placeholder image tag.

**Verify.** Each of the five repos: `dotnet build` succeeds, `docker build` succeeds, and `kubectl apply --dry-run=client -f deploy/` validates without error.

✅ **Done 2026-10-20/21.** OrderBeans/PayBeancoins/CookerBeaners/BeanNotifs were scaffolded and implemented by Matthew on 2026-10-20 per the `service-api-template` sub-plan, merged via PR with Tim Kunz. BeanApp (this session, 2026-10-21) had app logic already (Keycloak token client, OrderBeans HTTP client, Cart checkout) but was missing its Dockerfile/deploy manifest and had leftover ASP.NET Identity + a standalone PostgreSQL dependency (default template scaffolding, unused by any page) — **removed entirely** per explicit decision, since IAM was scoped to OrderBeans only (Q7), not end-user login. Added BeanApp's Dockerfile (repo-root context, since its `.sln`/`.csproj` are nested under `WebApp/WebApp/`) and `/deploy/*`. All five: `dotnet build` ✅, `docker build` ✅, `kubectl apply --dry-run=client` ✅.
Two real bugs found and fixed along the way:
- **Keycloak port bug:** OrderBeans' and BeanApp's config pointed `Keycloak:Authority` at `keycloak.infra.svc.cluster.local:8080`, but the Keycloak Service only exposes port 80 (confirmed via `kubectl get svc keycloak -n infra`). Fixed in both `appsettings.json` files and in OrderBeans' `deploy/deployment.yaml` env var (the one that actually matters at runtime).
- **Windows/.NET Docker build bug:** BeanApp's Docker build failed with a NuGet `ResolvePackageAssets` error referencing `C:\Program Files (x86)\Microsoft Visual Studio\Shared\NuGetPackages` — a Windows-only fallback folder baked into the host's locally-built `obj/project.assets.json` (nested under `WebApp/WebApp/obj/`), which leaked into the Docker build context. Fixed by deleting the stale `bin/`/`obj/` folders and hardening `.dockerignore` to `**/bin/`/`**/obj/` (bare `bin/`/`obj/` wasn't reliably excluding the nested path) — relevant for your teammate's machine too.

---

### Step 6 — Implement OrderBeans

✅ **Do.** `POST /orders` endpoint: validates the caller's Keycloak bearer token (Q7, `JwtBearer` against the `phaseolus` realm's OIDC discovery doc — issuer/signature/expiry only); on success, publishes `order.created` to `phaseolus.events` with the Q5 payload shape.

**Verify.** `curl -X POST` with no `Authorization` header → `401`. The same request with a client-credentials token from Step 4 → `2xx`, and the message appears in the `pay.incoming-orders` queue (checked via RabbitMQ's management UI/API).

✅ **Done 2026-10-21 (live, against the deployed cluster).** `curl -X POST /orders` with no `Authorization` header → `401`. With a client-credentials token fetched **from inside the cluster** (a throwaway `curlimages/curl` pod — a token fetched via host port-forward has a different `iss` claim and is correctly rejected, which is *not* a bug, just means the test has to originate in-cluster) → `202` with a real `orderId`. One real debugging detour: an initial in-cluster-token test still got `401` with `SecurityTokenInvalidSignatureException`; independent signature verification (Node crypto, cross-checked against both the JWK `n`/`e` and the `x5c` cert) also failed — traced to `kubectl run`'s own `pod "..." deleted` status message getting concatenated onto the captured token's signature segment by a sloppy `tail -1` capture, not a real Keycloak/OrderBeans bug. Fixed the capture method (`kubectl logs` after `kubectl wait --for=jsonpath='{.status.phase}'=Succeeded`), re-verified the signature as valid, and the request succeeded.

---

### Step 7 — Implement PayBeancoins

✅ **Do.** Consumes `pay.incoming-orders`; applies the deterministic "Rotten Beans" rule (Q8); publishes `payment.succeeded` or `payment.failed` accordingly.

**Verify.** An order with normal items → a `payment.succeeded` message appears in `cooker.paid-orders`. An order containing an item named `"Rotten Beans"` (any case) → a `payment.failed` message (with the `reason` from Q8) appears in `notifs.payment-failed`, and nothing appears in `cooker.paid-orders` for that order.

✅ **Done 2026-10-21 (live).** Verified indirectly but conclusively via BeanNotifs' `/notifications` (Step 9) rather than inspecting RabbitMQ queues directly: a normal order resulted in an `order-cooked` entry (proving `payment.succeeded` → CookerBeaners fired), and a `"Rotten Beans"` order resulted in a `payment-failed` entry reading `"Payment failed: Simulated failure: Rotten Beans"` with **no** corresponding `order-cooked` entry for that `orderId` — confirming CookerBeaners never received anything for the failed payment.

---

### Step 8 — Implement CookerBeaners

✅ **Do.** Consumes `cooker.paid-orders`; publishes `order.cooked`.

**Verify.** Following a successful-payment message from Step 7, a message appears in `notifs.order-cooked`.

✅ **Done 2026-10-21 (live).** Same evidence as Step 7: the normal order's `order-cooked` notification is proof CookerBeaners consumed `payment.succeeded` and published correctly; the Rotten-Beans order producing zero `order-cooked` entries is proof it correctly never fires on a failed payment.

---

### Step 9 — Implement BeanNotifs

✅ **Do.** Consumes both `notifs.payment-failed` and `notifs.order-cooked` (Q5's dual-event consumer). Records each as a structured log line plus an in-memory list exposed via `GET /notifications` — a real delivery channel (email/SMS/push) is out of scope per `10_target_shape.md`'s non-goals; this just needs to be *observable* for the demo.

**Verify.** `GET /notifications` shows one entry for a normal order (order-cooked) and one entry for a Rotten-Beans order (payment-failed), each traceable to its `orderId`.

✅ **Done 2026-10-21 (live).** `GET /notifications` on the deployed pod returned exactly this: one `order-cooked` entry and one `payment-failed` entry, each with the correct `orderId` matching the order that produced it, plus a third entry once Step 10 was tested (see below). Dual-event consumption confirmed working.

---

### Step 10 — Implement BeanApp

✅ **Do.** Minimal ordering UI/API (per `10_target_shape.md`'s non-goal on UX polish). On request, fetches a client-credentials token from Keycloak (Step 4) and calls OrderBeans' `POST /orders` with it attached. Supports submitting an order containing `"Rotten Beans"`, either as a selectable item or free text, to trigger the failure path on demand.

**Verify.** Full end-to-end: placing a normal order results in a `GET /notifications` (BeanNotifs) entry for "order cooked"; placing a Rotten-Beans order results in a "payment failed" entry, and CookerBeaners never logs/publishes anything for that order.

✅ **Done 2026-10-21 (live, via the real Cart page, not a direct API call).** Fetched BeanApp's `/Cart` page to get a valid antiforgery token + session cookie, then POSTed a checkout form submission exactly as a browser would. Response: `"Order placed! OrderBeans accepted it."` — and the resulting order appeared as a new `order-cooked` entry in BeanNotifs, confirming the full chain (BeanApp → Keycloak token fetch → OrderBeans → RabbitMQ → PayBeancoins → CookerBeaners → BeanNotifs) works through the actual UI, not just direct service-to-service calls.

---

### Step 11 — Expose BeanApp via Traefik

✅ **Do.** Add an `IngressRoute`/`Ingress` (wherever each service's own manifest lives, per Q3) so Traefik is the only externally-reachable path to BeanApp.

**Verify.** The Traefik-exposed host/path reaches BeanApp; none of the other four services are reachable from outside the cluster (no stray `NodePort`/`LoadBalancer` Services).

✅ **Done 2026-10-21 (live).** Added `deploy/ingressroute.yaml` to BeanApp's own repo (per-service manifest ownership, consistent with Q3) — a Traefik `IngressRoute` on the `web` entryPoint matching `PathPrefix(\`/\`)`, routing to the `beanapp` Service. Verified via `minikube service traefik -n infra --url` (a real external tunnel, not `kubectl port-forward`): `GET /Cart` → `200`, and `GET /` returned BeanApp's actual homepage title, confirming genuine external routing through Traefik rather than a coincidental match. Confirmed all five `phaseolus` Services are plain `ClusterIP` (`kubectl get svc -n phaseolus`) and `beanapp` is the only `IngressRoute` in the namespace — no other service has any external path.

---

### Step 12 — Wire Prometheus scraping and a Grafana dashboard

✅ **Do.** Configure Prometheus (via the `kube-prometheus-stack`'s `ServiceMonitor` CRDs, or static scrape configs) to scrape all five services' `/metrics` across the `phaseolus` namespace, plus RabbitMQ's metrics. Build one Grafana dashboard: request count/latency per service, and queue depth for the four queues from Q5.

**Verify.** After running a few orders through the flow (including one Rotten-Beans order), the Grafana dashboard shows non-zero, moving data for each panel.

✅ **Done 2026-10-21 (live).** Added a `ServiceMonitor` to each of the five services' own `/deploy` (per-service manifest ownership, Q3) — required adding `name: http` + a matching `labels.app` to each `service.yaml` first, since ServiceMonitor selects Services by label and endpoints by named port. RabbitMQ was handled separately in this meta repo (`k8s/infra/rabbitmq-metrics.yaml`), since it's an infra-level concern per Option C: a `rabbitmq-metrics` Service exposing port 9419 (the `rabbitmq_prometheus` plugin's port — confirmed enabled but **not exposed by the Helm-managed Service**), its `ServiceMonitor`, and a supplementary `NetworkPolicy` opening ingress on 9419 (the Helm-managed RabbitMQ `NetworkPolicy` only allows the AMQP/management ports — NetworkPolicies on the same pods are additive/union, so this doesn't touch the Helm-owned one and survives `helm upgrade`). Also upgraded the RabbitMQ release with `extraConfiguration: "prometheus.return_per_object_metrics = true"` — off by default, which meant `rabbitmq_queue_messages_ready` etc. only reported one aggregate series with no `queue` label; this is required for genuine per-queue panels.

All 6 scrape targets (`orderbeans`, `paybeancoins`, `cookerbeaners`, `beannotifs`, `beanapp`, `rabbitmq-metrics`) confirmed `up` in Prometheus. Built `k8s/infra/grafana-dashboard-order-flow.yaml` (a ConfigMap labeled `grafana_dashboard: "1"`, auto-discovered by the chart's Grafana sidecar, which watches all namespaces) with four panels: request rate per service, p95 latency per service, RabbitMQ queue depth, and per-queue publish rate. After placing a normal order and a Rotten-Beans order, queried all four panels' exact PromQL through Grafana's own datasource proxy (not just Prometheus directly) and confirmed non-zero, correctly-labeled data on every one.

---

### Step 13 — Wire the Argo CD App-of-Apps

⚠️ **Do.** In this meta repo, add the root Argo CD `Application` (app-of-apps pattern, `20_options.md`): one child `Application` per service repo (source: `<repo>/deploy`, per Q3) plus Applications for the Step 2 infra charts. Apply the root Application once manually — this is the one allowed `kubectl apply`, bootstrapping Argo CD to manage everything from here on.

**Verify.** Argo CD's UI shows every child Application `Synced`/`Healthy`. Bump an image's git-SHA tag (per Q4's flow: `minikube image load` the new image, then edit the tag in the service repo's `/deploy/deployment.yaml` and push) and confirm Argo CD reconciles the running Deployment **without** a manual `kubectl apply`/`kubectl set image`.

⚠️ **Done 2026-10-21, with reduced scope after a real incident.** The App-of-Apps pattern is live and working for the five services plus this meta repo's own `k8s/infra/` plain manifests (6 child Applications, all `Synced`/`Healthy`) — **but the four infra Helm charts (RabbitMQ, Keycloak, Traefik, Prometheus stack) were deliberately reverted to manual Helm management**, not GitOps-adopted, after attempting it caused real damage:

**What went wrong.** Argo CD's Helm source templating uses the *Application's own name* as the Helm release name by default. Setting `source.helm.releaseName` to match the original manual release names (`rabbitmq`, `keycloak`, `traefik`, `prometheus`) was supposed to make the first sync a no-op diff against the already-running state. Instead, the first sync (before the fix) created differently-named duplicate resources, and a later reconcile — after the `releaseName` fix — **deleted the original RabbitMQ/Keycloak/Traefik StatefulSets, Services, and (for Keycloak) the Postgres credentials Secret outright**, rather than adopting them in place. Disabling `syncPolicy.automated` did not reliably stop an already-queued sync operation from completing, so the Applications had to be deleted outright (`--cascade=orphan`) to actually stop the churn — twice, since one got recreated again by the root Application's own reconcile before the git revert was merged.

**What was lost vs. recovered.**
- **RabbitMQ**: fully recovered. `helm upgrade` with the original values reattached to the surviving `data-rabbitmq-0` PVC — no data loss.
- **Traefik**: nothing to lose (stateless); trivially recreated.
- **Keycloak**: **not recoverable**. The Postgres credentials Secret was deleted along with the StatefulSet, so the existing data PVC couldn't be reattached (wrong/unknown password). Had to delete the orphaned PVC and do a clean `helm uninstall` + `helm install`, then **redo Step 4 from scratch** (recreate the `phaseolus` realm and `beanapp-client`, fetch the new client secret, update BeanApp's deploy manifest and redeploy). This is a real, explicit decision point the user approved mid-incident (see `AskUserQuestion` log in the session) rather than something fixed silently.
- **Prometheus stack**: survived untouched — caught and stopped before its (slower, larger) reconcile reached the prune step.

**Final state (re-verified live, 2026-10-21):** full order flow through BeanApp's real Cart page — normal order → `order-cooked`; `"Rotten Beans"` order → `payment-failed`, no `order-cooked` — works end-to-end exactly as before the incident. Argo CD auto-synced the corrected Keycloak client secret into BeanApp's Deployment the moment the fix PR merged, with **zero manual `kubectl` action** — this is itself a direct, if unplanned, demonstration of the sync criterion this step asks for (just via an env var change rather than an image-tag bump). `helm list -n infra` shows all four infra releases `deployed` cleanly, no duplicate resources anywhere, 6 Argo Applications all `Synced`/`Healthy`.

**Standing decision:** the four infra Helm charts remain manually Helm-managed going forward (not GitOps-owned), per `20_options.md`'s spirit of keeping this meta repo's automated surface area matched to what's actually been proven safe — full infra-into-Argo-CD adoption is parked as a followup (`50_followups.md`) rather than reattempted blindly.

---

### Step 14 — End-to-end verification against `10_target_shape.md`

✅ **Do.** Walk the `10_target_shape.md` success-criteria list explicitly as a checklist rather than assuming prior steps covered it:
- Full order flow traceable through RabbitMQ (Steps 6–10).
- Unauthenticated vs. authenticated request to OrderBeans (Step 6).
- Grafana shows live per-service and RabbitMQ data (Step 12).
- A manifest/tag change reaches the cluster via Argo CD alone (Step 13).
- `kubectl get pods -A` shows all five services + all infra running, Traefik as the only ingress (Steps 1–13 combined).

**Verify.** Each bullet confirmed against the running cluster, not just against individual step verifications in isolation — this step exists because passing each step locally doesn't guarantee the *combined* system satisfies every criterion simultaneously.

✅ **Done 2026-10-21 — all 5 `10_target_shape.md` success criteria confirmed live, fresh, against the post-incident cluster state (not reused from earlier step verifications, except where noted):**

1. **Full order flow traceable through RabbitMQ.** Placed a fresh order directly against OrderBeans (`orderId 7b2202b6-...`) and confirmed it reached `order-cooked` in BeanNotifs — i.e. OrderBeans → `order.created` → PayBeancoins → `payment.succeeded` → CookerBeaners → `order.cooked` → BeanNotifs, the full chain, traced via the `/notifications` endpoint (which is itself backed entirely by consumed RabbitMQ messages).
2. **Unauthenticated vs. authenticated request to OrderBeans.** Re-tested against the *rebuilt* Keycloak realm (post-incident): no `Authorization` header → `401`; a token fetched fresh from inside the cluster → `202` with a real `orderId`.
3. **Grafana shows live per-service and RabbitMQ data.** All 6 Prometheus scrape targets (`orderbeans`, `paybeancoins`, `cookerbeaners`, `beannotifs`, `beanapp`, `rabbitmq-metrics`) confirmed `up`. Queried the dashboard's actual panel PromQL through Grafana's own datasource proxy: non-zero per-service request rate, and non-zero per-queue publish rate for all four queues — including `notifs.payment-failed`, confirming the per-object RabbitMQ metrics config survived the Step 13 reinstall.
4. **A manifest/tag change reaches the cluster via Argo CD alone.** Already demonstrated unprompted during Step 13's incident recovery: merging the Keycloak-client-secret fix PR caused Argo CD to redeploy BeanApp's Deployment with the new value automatically — zero manual `kubectl` involvement, observed in real time. Reused here rather than re-run, since it's the identical mechanism this criterion asks for.
5. **`kubectl get pods -A` shows everything running, Traefik as the only ingress.** All five `phaseolus` services, all `infra` components, and `argocd` itself confirmed `Running`. Checked every namespace for `LoadBalancer`/`NodePort` Services: **Traefik is the only one** in the entire cluster. Exactly one `IngressRoute` exists (`beanapp`).

**Overall result: the architecture plan's target shape is met.** The system doesn't just pass each step in isolation — the combined, currently-running cluster satisfies all five success criteria simultaneously, re-verified after (and despite) the Step 13 incident.

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
