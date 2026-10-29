# 40 — Implementation

Step plan for the chosen option from `20_options.md`. **Do not start this phase while `30_open_questions.md` has any ⏳ items** — that's the discipline this folder structure exists to enforce.

Each step has a verification: how do we know the step is done? Strong verification turns the plan into a checklist you can run independently.

## Plan summary

Keycloak comes first (Step 1) since every other step needs its clients to exist before anything can be configured against them. Steps 2–5 (Grafana, Argo CD, RabbitMQ, Prometheus) each touch a different tool and are otherwise independent — sequenced here by risk, cheapest/safest first: Grafana and Argo CD are both pure config changes to stateless Deployments; RabbitMQ is config to a **stateful** release (a PVC-backed `StatefulSet`, per the architecture plan's Step 13 incident, so treated with the same caution); Prometheus is the only step building genuinely new infrastructure (a reverse proxy that doesn't exist anywhere in the cluster today). Step 6 is the same kind of full fresh-cluster verification `../2026_10_sso-keycloak/`'s Step 5 ran, now an established bar for this project.

Unlike `../2026_10_sso-keycloak/`, **no C# code changes are involved anywhere in this plan** — every step is Keycloak admin-API config, Helm values, or Kubernetes manifests.

**Cross-cutting technical note, called out once rather than per step:** Grafana's, Argo CD's, and RabbitMQ's OIDC/OAuth2 integrations all have a backend half (token exchange, JWKS fetch, OIDC discovery) that must reach Keycloak via the in-cluster DNS name, and a browser half (the actual login redirect) that must reach Keycloak via the dev-machine-reachable port-forward address (`http://localhost:8180/...`) — the exact same split `../2026_10_sso-keycloak/` hit (and fixed) twice for BeanApp and BeanNotifs. Grafana's `generic_oauth` config has explicit, separate `auth_url`/`token_url`/`api_url` keys built for exactly this. Argo CD's and RabbitMQ's exact support for the same split was **not yet confirmed when written** — Step 3 found live that Argo CD has no such split (neither its native `oidc.config` nor its Dex connector), and could not be made to work without an out-of-cluster DNS change the user chose not to make; see Step 3 for the full finding. RabbitMQ's support is still to be confirmed in Step 4.

**Update after Step 3:** Argo CD Keycloak SSO is **not implemented** — see Step 3's notes. Three of the four tools named in `inputs.md` (Grafana, RabbitMQ, Prometheus) remain in scope; Argo CD keeps its local admin login. This is a real, accepted narrowing of scope, not a silent drop — recorded here, in Step 3, and in `50_followups.md`.

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

⚠️ **Not implemented — blocked on a real architecture limit, found and accepted live.** Argo CD has no way to split the browser-facing Keycloak address from the in-cluster one its own backend needs, unlike Grafana's explicit `auth_url`/`token_url` keys.

**What was tried.**
- **Native `oidc.config`** with `issuer` set to the in-cluster DNS address (`http://keycloak.infra.svc.cluster.local/realms/phaseolus`): backend discovery succeeds, but Argo CD reuses that *same* discovered `authorization_endpoint` for the browser redirect — an anonymous login attempt redirects the browser straight to the in-cluster address, which it cannot resolve.
- **Native `oidc.config`** with `issuer` set to the browser-facing address (`http://localhost:8180/realms/phaseolus`) instead: the browser redirect would be correct, but Argo CD's own backend discovery fails outright — confirmed live: `failed to query provider ...: dial tcp [::1]:8180: connect: connection refused` (`localhost` inside the `argocd-server` pod means the pod itself, not the dev machine).
- **`dex.config`** with an `oidc`-type Keycloak connector, expecting Dex to broker the login so the browser only ever talks to Argo CD's own `/api/dex/...` endpoints: confirmed live that Dex's `oidc` connector type is a thin redirect wrapper, not a login-form proxy — it performs its own discovery against whichever `issuer` it's given and sends the browser's *second* hop straight there. Pointed at the in-cluster address, the browser again lands on `http://keycloak.infra.svc.cluster.local/...` and fails identically to the native path.

**Why no further workaround was pursued.** The only real fix is making one hostname resolve differently from inside the cluster (to Keycloak's ClusterIP) than from the dev machine (to the `kubectl port-forward` on `127.0.0.1`) — a hosts-file entry on the Windows host paired with a matching in-cluster DNS override (`hostAliases` on `argocd-server`/`argocd-dex-server`, or a CoreDNS rewrite). Presented to the user as a real choice (since it needs an admin-elevated edit outside this session's reach); the user chose to accept the limitation rather than make that edit.

**Resolution.** Argo CD keeps its local `admin` account (`argocd-initial-admin-secret`) as its only login method. All live-tested config (`argocd-cm`'s `url`/`oidc.config`/`dex.config`, `argocd-rbac-cm`'s policy, `argocd-secret`'s `oidc.keycloak.clientSecret`, and `admin-ui-client`'s now-unused Argo CD redirect URIs) was reverted from the live cluster. `admin-ui-client` (Step 1) is now Grafana-only in practice; its `redirectUris` in `setup.sh` was trimmed back to just Grafana's callback. Filed in `50_followups.md` for anyone willing to make the hosts-file edit later.

**Original plan (kept for reference, not executed):** patch `argocd-cm` with `url` + `oidc.config` (`issuer`, `clientID: admin-ui-client`, `clientSecret`, `requestedScopes: [openid, profile, email]`), and `argocd-rbac-cm` with `g, admin@phaseolus.local, role:admin` (Q2).

---

### Step 4 — RabbitMQ: OAuth2 plugin for the management UI

✅ **Done.** Harder than planned, but fully working and live-verified.

**Found live, not anticipated in the original plan:** `rabbitmq_auth_backend_oauth2`'s config schema has a **hardcoded, unconditional validator** requiring `https://` for `auth_oauth2.issuer`/`jwks_uri`/`jwks_url`/`token_endpoint`/`authorization_endpoint` — not a config flag, no override exists. Confirmed live: setting these to plain `http://` crash-loops RabbitMQ outright (`According to the JWT Specification, Key Server URL must be https.`) — immediately reverted since a crash-looping broker breaks the entire AMQP bus. Presented to the user as a choice (small isolated TLS proxy vs. accept the limitation, matching Step 3's precedent); the user chose to build the proxy.

**The fix, in three pieces:**
1. **`k8s/infra/keycloak-tls-route.yaml`** — a Traefik `IngressRoute` putting the already-running Traefik's `websecure` entrypoint (TLS-enabled, self-signed, zero new pods) in front of the existing Keycloak Service. This is the project's first `Middleware`-adjacent Traefik resource beyond the one existing `IngressRoute`.
2. **Keycloak's `proxyHeaders=xforwarded`** (`setup.sh`) — without this, Keycloak reported `http://` in its issuer even when reached via the new TLS route (confirmed live), because it doesn't trust `X-Forwarded-Proto` by default. This is the one deviation from the originally-pitched "zero Keycloak changes" — re-confirmed with the user before applying. Verified inert for everything else: the existing plain-HTTP `:8180` port-forward still reports `http://` in its issuer, unchanged, after this was applied.
3. **RabbitMQ's `auth_oauth2` config, split like Grafana's `auth_url`/`token_url`** — unlike Argo CD, RabbitMQ's plugin *does* support this split: `issuer` is only ever string-compared against the token's `iss` claim (never fetched), while `jwks_uri` is independently configurable and actually dereferenced. So `issuer = https://localhost:9443/realms/phaseolus` (the new TLS route, browser-facing — matches what the browser's login actually produces) and `jwks_uri = https://traefik.infra.svc.cluster.local/realms/phaseolus/protocol/openid-connect/certs` (same route, in-cluster-reachable address, self-signed cert trust skipped via `auth_oauth2.https.peer_verification = verify_none`).

**Other findings along the way:**
- A **hardcoded-claim protocol mapper on the `scope` claim is silently ignored** by Keycloak — `scope` is a protected, scope-negotiation-derived claim. The real fix: create actual Keycloak **client scopes** named `rabbitmq.tag:administrator`, `rabbitmq.read:*/*`, `rabbitmq.write:*/*`, `rabbitmq.configure:*/*`, assigned as **default** client scopes on `rabbitmq-client` — Keycloak populates `scope` from granted scope *names*, which this exploits directly.
- RabbitMQ's management-UI OAuth2 flow is browser-only PKCE with no backend secret, so `rabbitmq-client` is **public** (`publicClient: true`), unlike every other client in this project (which are all confidential with a pinned secret). Confirmed live that the authorization-code exchange works fine without a `client_secret`.
- An audience mapper (`included.custom.audience: "rabbitmq"`) matches `auth_oauth2.resource_server_id = rabbitmq`.

**Verified live, in full:**
- `GET /api/overview`, `/api/vhosts`, `/api/queues` with the OAuth2 token all return `200`, with real data (`/api/whoami` → `tags: ["administrator"]`, `is_internal_user: false`).
- The existing plain-HTTP Keycloak path's issuer is unaffected by `proxyHeaders`.
- **Regression check (the one that matters most):** the existing `phaseolus`/`phaseolus` AMQP connections (one per running service) all survived the RabbitMQ pod restart and reconnected automatically — `/api/connections` shows all six `state: running`, `user: phaseolus`, unchanged. A **real order was placed** through BeanApp's actual UI (Beans → Cart → Checkout, simulated via curl against the real forms/antiforgery tokens) and completed successfully (`alert-success`); RabbitMQ's message-stats showed `publish: 4, deliver_get: 5`, consistent with the full order → pay → cook → notify chain. A few transient `health check rabbitmq: connection closed` log lines appeared in OrderBeans/CookerBeaners/BeanNotifs/PayBeancoins during the ~10s RabbitMQ pod restart window itself, then stopped — expected, not a regression.

**Original plan (for reference — superseded by the above):** enable the plugin via Helm values pointed directly at Keycloak's in-cluster DNS address, no TLS proxy. Turned out to be impossible given the plugin's HTTPS requirement.

---

### Step 5 — Prometheus: a reverse-proxy gate

⏳ **Do.** Deploy `oauth2-proxy` (new Deployment + Service in the `infra` namespace, new manifests under `k8s/infra/`) configured against Keycloak — reusing `admin-ui-client` if its redirect-URI model accommodates a third callback cleanly, otherwise registering a dedicated client (decide during this step, not pre-decided here, since Q1 only covered Grafana/Argo CD explicitly). Add a new Traefik `IngressRoute` for the Prometheus Service plus a `ForwardAuth` `Middleware` pointed at `oauth2-proxy`'s verify endpoint — the first `Middleware` resource this project will have (`00_current_state.md`: zero exist today). Reconcile with `setup.sh`'s existing direct `kubectl port-forward svc/prometheus-kube-prometheus-prometheus` — if that's left in place, it bypasses the new gate entirely (anyone who starts that port-forward skips Keycloak altogether), so this step must explicitly decide and document whether that direct port-forward is removed, replaced with one to Traefik's entrypoint instead, or deliberately left as a known-unprotected local-only escape hatch.

**Verify.** An anonymous visit to Prometheus via the new Traefik route redirects to Keycloak; completing login as `admin` lands in Prometheus's own query UI, authenticated. Explicitly test and document whether the old direct-to-Service path still bypasses the gate.

---

### Step 6 — End-to-end live verification (fresh cluster)

⏳ **Do.** No code change — the same kind of full regression + new-behavior pass `../2026_10_sso-keycloak/`'s Step 5 ran, culminating in `minikube delete` + a full `setup.sh` re-run from the merged state of every step above.

**Verify.**
- Grafana and RabbitMQ (and Prometheus, via its gate): anonymous → Keycloak redirect → login as `admin` → authenticated in that tool, on a freshly built cluster with no manual follow-up.
- Argo CD: confirm it still only offers local `admin` login (no stray "Log in via Keycloak" option left over from Step 3's live testing) — the explicit regression check for Step 3's revert actually having stuck through a fresh `setup.sh` run.
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
