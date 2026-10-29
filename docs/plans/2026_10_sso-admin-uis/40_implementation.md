# 40 — Implementation

Step plan for the chosen option from `20_options.md`. **Do not start this phase while `30_open_questions.md` has any ⏳ items** — that's the discipline this folder structure exists to enforce.

Each step has a verification: how do we know the step is done? Strong verification turns the plan into a checklist you can run independently.

## Plan summary

Keycloak comes first (Step 1) since every other step needs its clients to exist before anything can be configured against them. Steps 2–5 (Grafana, Argo CD, RabbitMQ, Prometheus) each touch a different tool and are otherwise independent — sequenced here by risk, cheapest/safest first: Grafana and Argo CD are both pure config changes to stateless Deployments; RabbitMQ is config to a **stateful** release (a PVC-backed `StatefulSet`, per the architecture plan's Step 13 incident, so treated with the same caution); Prometheus is the only step building genuinely new infrastructure (a reverse proxy that doesn't exist anywhere in the cluster today). Step 6 is the same kind of full fresh-cluster verification `../2026_10_sso-keycloak/`'s Step 5 ran, now an established bar for this project.

Unlike `../2026_10_sso-keycloak/`, **no C# code changes are involved anywhere in this plan** — every step is Keycloak admin-API config, Helm values, or Kubernetes manifests.

**Cross-cutting technical note, called out once rather than per step:** Grafana's, Argo CD's, and RabbitMQ's OIDC/OAuth2 integrations all have a backend half (token exchange, JWKS fetch, OIDC discovery) that must reach Keycloak via the in-cluster DNS name, and a browser half (the actual login redirect) that must reach Keycloak via the dev-machine-reachable port-forward address (`http://localhost:8180/...`) — the exact same split `../2026_10_sso-keycloak/` hit (and fixed) twice for BeanApp and BeanNotifs. Grafana's `generic_oauth` config has explicit, separate `auth_url`/`token_url`/`api_url` keys built for exactly this. Argo CD's and RabbitMQ's exact support for the same split is **not yet confirmed** and is called out as a verification risk in Steps 3 and 4 rather than assumed solved here.

## Steps

### Step 1 — Keycloak: `admin-ui-client` and `rabbitmq-client`

⏳ **Do.**
- Create `admin-ui-client` (confidential, `standardFlowEnabled: true`, `redirectUris: ["*"]`, `attributes: {"post.logout.redirect.uris": "+"}` — same shape as `beanapp-client`) for Grafana and Argo CD to share (Q1).
- Create `rabbitmq-client`, dedicated (RabbitMQ's OAuth2 plugin has its own scope/claim conventions unrelated to the other two). Pin both clients' secrets the same way `beanapp-client`'s is pinned (fixed value, committed, documented) rather than generated per-environment.
- Port both into `setup.sh`'s Keycloak section.

**Verify.** Fetch a token for `admin-ui-client` via the Authorization Code flow as `admin`/`phaseolus` (same curl-based login simulation used throughout `../2026_10_sso-keycloak/`) and confirm it issues correctly. Confirm both clients exist via `GET /admin/realms/phaseolus/clients`.

---

### Step 2 — Grafana: `generic_oauth`

⏳ **Do.** Add a `grafana.grafana.ini` `[auth.generic_oauth]` block to the `kube-prometheus-stack` Helm install in `setup.sh`: `enabled = true`, `client_id`/`client_secret` from `admin-ui-client`, `auth_url` pointed at the browser-facing Keycloak address, `token_url`/`api_url` pointed at the in-cluster DNS address (the explicit split this tool supports natively — see the plan summary's cross-cutting note). Per Q4, no `role_attribute_path` restriction — any successful Keycloak login is admitted. Leave Grafana's own local login form enabled as a fallback (same "don't remove the local admin escape hatch" spirit as `../2026_10_sso-keycloak/10_target_shape.md`'s Argo CD non-goal, applied here too).

**Verify.** An anonymous visit to Grafana offers (or auto-redirects to) a "Sign in with Keycloak" option; completing login as `admin`/`phaseolus` lands back in Grafana authenticated, with the existing three dashboards (business metrics, technical, order flow) still rendering real data.

---

### Step 3 — Argo CD: `oidc.config` + RBAC

⏳ **Do.** Patch `argocd-cm` with `url` (the browser-facing Argo CD address) and `oidc.config` (`issuer`, `clientID: admin-ui-client`, `clientSecret`, `requestedScopes: [openid, profile, email]`). Patch `argocd-rbac-cm` with a policy mapping the admin's email claim directly to `role:admin` (Q2) — e.g. `g, admin@phaseolus.local, role:admin`. Apply both via a new manifest under `k8s/argocd/` (or a `kubectl patch` in `setup.sh`, whichever proves more reliably idempotent on a re-run) rather than editing the live ConfigMaps only.

**Verify.** An anonymous visit to the Argo CD UI offers "Log in via Keycloak"; completing login as `admin` lands back in Argo CD with full access (Applications visible, sync-able). The local `admin` account (`argocd-initial-admin-secret`) still works as a fallback login — confirms the non-goal from `../2026_10_sso-keycloak/10_target_shape.md` (don't remove local admin fallbacks) holds here too.

**Known risk to resolve live, not assumed here:** whether Argo CD's native `oidc.config` supports the same backend/browser address split Grafana's config does, or whether `issuer` has to be one single value — if the latter, this step needs a concrete workaround (possibly accepting Argo CD's backend reaches Keycloak via the browser-facing address too, which only works if that address is *also* reachable from inside the `argocd-server` pod — not true today). Document whatever is actually found here.

---

### Step 4 — RabbitMQ: OAuth2 plugin for the management UI

⏳ **Do.** Enable `rabbitmq_auth_backend_oauth2` via Helm values on the `rabbitmq` release: `management.oauth_enabled`, `management.oauth_client_id: rabbitmq-client`, `oauth_provider_url` (browser-facing), `resource_server_id`, and a JWKS/signing-key source pointed at Keycloak's in-cluster DNS address. Add a protocol mapper on `rabbitmq-client` producing whatever scope format the plugin expects for management-UI access (likely `rabbitmq.tag:administrator`-shaped scopes) — the **exact string convention needs confirming against RabbitMQ's own oauth2-plugin docs during this step**, not assumed here. Critically: `auth_backends` must list the **existing internal backend alongside (not instead of) oauth2**, so the AMQP-level `phaseolus`/`phaseolus` broker login every service already uses is untouched (`10_target_shape.md` constraint).

**Verify.** An anonymous visit to RabbitMQ's management UI redirects to Keycloak; completing login as `admin` lands back in the management UI authenticated. Separately — and this is the regression check that matters most for this step — place a real order through the full chain (Cart → Checkout → OrderBeans → RabbitMQ → PayBeancoins → CookerBeaners → BeanNotifs) and confirm it completes exactly as before, proving AMQP service auth wasn't disturbed.

---

### Step 5 — Prometheus: a reverse-proxy gate

⏳ **Do.** Deploy `oauth2-proxy` (new Deployment + Service in the `infra` namespace, new manifests under `k8s/infra/`) configured against Keycloak — reusing `admin-ui-client` if its redirect-URI model accommodates a third callback cleanly, otherwise registering a dedicated client (decide during this step, not pre-decided here, since Q1 only covered Grafana/Argo CD explicitly). Add a new Traefik `IngressRoute` for the Prometheus Service plus a `ForwardAuth` `Middleware` pointed at `oauth2-proxy`'s verify endpoint — the first `Middleware` resource this project will have (`00_current_state.md`: zero exist today). Reconcile with `setup.sh`'s existing direct `kubectl port-forward svc/prometheus-kube-prometheus-prometheus` — if that's left in place, it bypasses the new gate entirely (anyone who starts that port-forward skips Keycloak altogether), so this step must explicitly decide and document whether that direct port-forward is removed, replaced with one to Traefik's entrypoint instead, or deliberately left as a known-unprotected local-only escape hatch.

**Verify.** An anonymous visit to Prometheus via the new Traefik route redirects to Keycloak; completing login as `admin` lands in Prometheus's own query UI, authenticated. Explicitly test and document whether the old direct-to-Service path still bypasses the gate.

---

### Step 6 — End-to-end live verification (fresh cluster)

⏳ **Do.** No code change — the same kind of full regression + new-behavior pass `../2026_10_sso-keycloak/`'s Step 5 ran, culminating in `minikube delete` + a full `setup.sh` re-run from the merged state of every step above.

**Verify.**
- All four tools: anonymous → Keycloak redirect → login as `admin` → authenticated in that tool, on a freshly built cluster with no manual follow-up.
- RabbitMQ AMQP flow: a real order still completes end-to-end.
- Argo CD: all five service Applications still show `Synced`/`Healthy`.
- Grafana: all three existing dashboards still render real data.
- Prometheus: the access-gate question from Step 5 (does the old direct port-forward still bypass it?) is re-confirmed on the fresh cluster, since `setup.sh`'s own port-forward section is exactly what would reintroduce that bypass if Step 5 didn't address it.

## Rollback / blast radius

Grafana (Step 2) and Argo CD (Step 3) changes are configuration on already-stateless Deployments — reverting is deleting the added `grafana.ini`/`argocd-cm`/`argocd-rbac-cm` keys and letting `helm upgrade`/`kubectl apply` put them back. Prometheus (Step 5) is purely additive new resources (a new Deployment, Service, IngressRoute, Middleware) — reverting is deleting them, with zero effect on Prometheus itself.

RabbitMQ (Step 4) is the one step touching a **stateful** release (RabbitMQ has a PVC, per the architecture plan's Step 13 incident) — enabling a plugin via Helm values will restart the `rabbitmq-0` pod, but should not touch its data volume. Still, per `10_target_shape.md`'s constraint and the Step 13 incident's lesson, verify this specific claim (plugin-enable causing a pod restart without PVC impact) against a disposable test before trusting it on the one RabbitMQ instance this project has, and keep the AMQP-still-works check in Step 4 as a hard gate before considering that step done.

## Quality gates before merging

- `bash -n setup.sh` after every `setup.sh` edit.
- `kubectl apply --dry-run=server` (or `helm template`) for any new/changed manifest before applying it live, where practical.
- Live verification per step against the dev `minikube` cluster, same as every prior plan in this repo — there is no automated test suite for infrastructure config.
- Step 6's fresh-cluster run is the final gate, not a formality — it's what caught two real bugs in `../2026_10_sso-keycloak/` that no amount of live-cluster testing alone found.

---

**Exit criterion:** Every step ✅, gates green, PR merged. Mark ✅ in `README.md` when complete and archive the folder per the project's plan-archive convention in `CLAUDE.md`.
