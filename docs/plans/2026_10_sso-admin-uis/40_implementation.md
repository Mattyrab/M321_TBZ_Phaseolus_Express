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

✅ **Done.** Started as planned (ForwardAuth `Middleware`), pivoted mid-step to a simpler, more standard shape after a real bug surfaced — and reused `admin-ui-client` (Q1) rather than a dedicated client.

**What was tried first, and why it was dropped:** the originally-planned shape — Traefik `ForwardAuth` `Middleware` calling oauth2-proxy's lightweight `/oauth2/auth` check endpoint — works for the *check* itself, but that endpoint returns a bare `401` with no redirect by design (it's built for pure API-style auth checks, not browser flows). Getting a browser redirect out of that requires chaining Traefik's `errors` `Middleware` to substitute in oauth2-proxy's `/oauth2/start` page on a `401`/`403` — tried live, and found that Traefik's `errors` middleware preserves the *original* status code (`401`) while only substituting the response body, so a real browser never auto-follows the embedded `Location` header. The fix: drop both `Middleware` resources entirely and run oauth2-proxy in its **native reverse-proxy mode** (`--upstream` pointed at Prometheus) instead of as a bare forward-auth helper — it handles the unauthenticated-browser case correctly out of the box, issuing a real `302` to Keycloak. `--skip-provider-button=true` was added so it redirects straight there instead of showing its own "choose a provider" splash first (there's only one provider configured anyway). Net effect: **simpler** than the original plan, zero `Middleware` resources needed, one `IngressRoute` routing everything (including oauth2-proxy's own `/oauth2/*` paths, which it handles internally) straight to the oauth2-proxy Service.

**Config split, matching Grafana's pattern (not Argo CD's):** oauth2-proxy's `--login-url` (browser-facing, `http://localhost:8180/...`) is independent of `--redeem-url`/`--oidc-jwks-url` (in-cluster DNS, actually reached by oauth2-proxy's own backend) via `--skip-oidc-discovery=true` — the same "explicit endpoints, no single discovery fetch" escape hatch that worked for RabbitMQ (Step 4), unlike Argo CD's single-fetch limitation (Step 3). `--oidc-issuer-url` is the browser-facing address too, since it's only ever string-compared against the token's `iss` claim.

**New Traefik entrypoint, not a shared path prefix:** rather than sharing the existing `web`/`websecure` entrypoints (which would need path-prefix or Host-based disambiguation against BeanApp's and Keycloak's existing catch-all routes — and Prometheus's own UI assumes being served at `/`, so a path prefix like `/prometheus` would need extra `--web.route-prefix` config to avoid breaking its asset loading), Traefik gets a new dedicated `promgate` entrypoint (`setup.sh`'s Traefik Helm install, port 9091) used by nothing else.

**`setup.sh`'s existing direct Prometheus port-forward was replaced**, not left alongside the gate — leaving it would let anyone bypass Keycloak entirely by port-forwarding the Service directly. (Note, for honesty: this is a convenience-level gate, not a network-level one — the underlying `prometheus-kube-prometheus-prometheus` Service has no `NetworkPolicy` restricting direct access, consistent with this being a dev/demo project with no other `NetworkPolicy`-enforced boundaries either. `setup.sh` just no longer *offers* the unprotected path.)

**Verified live:** an anonymous request through the new `promgate` entrypoint gets a real `302` straight to Keycloak's login page (confirmed via a full simulated browser flow: redirect → Keycloak login form → callback → `_oauth2_proxy` session cookie issued) and the authenticated session reaches Prometheus's real API with real data (`/api/v1/query?query=up` returning live `up` metrics for every service, including the five Phaseolus services). Confirmed the Step 4 Keycloak TLS route still works unaffected after this step's Traefik Helm upgrade (no regression from adding the new entrypoint).

---

### Step 6 — End-to-end live verification (fresh cluster)

✅ **Done.** Clean on the first try — no bugs found, unlike `../2026_10_sso-keycloak/`'s Step 5 (which found two). `minikube delete` + a full `setup.sh` re-run completed with no manual follow-up: all 5 service pods `Running`, all 7 Argo CD Applications `Synced`/`Healthy`, all infra pods (Keycloak, RabbitMQ, Traefik, Prometheus stack, oauth2-proxy) `Running` within minutes.

**Verified, all on the fresh cluster:**
- **Grafana:** full simulated browser login via `/login/generic_oauth` → real session issued → `/api/user` shows `admin@phaseolus.local`, `authLabels: ["Generic OAuth"]`.
- **RabbitMQ:** full simulated browser login via the Step 4 TLS route (`https://localhost:9443`) → token exchange → `/api/whoami` via the management API shows `tags: ["administrator"]`, `is_internal_user: false`.
- **Prometheus:** full simulated browser login via the Step 5 `promgate` entrypoint (`http://localhost:9091`) → real `302` to Keycloak → session cookie issued → `/api/v1/query?query=up` returns live data for every service, including all five Phaseolus services at `up: 1`.
- **Argo CD:** `argocd-cm`/`argocd-rbac-cm` confirmed empty of any Keycloak config (Step 3's revert held through a from-scratch run, not just the live-tested cluster) — local `admin` login only, as intended.
- **Real order placed** through BeanApp's actual UI (Beans → Cart → Checkout) on the fresh cluster — `alert-success`, and RabbitMQ's message stats (`publish: 3, deliver_get: 4`) confirm the full order → pay → cook → notify chain ran over AMQP using the unchanged `phaseolus`/`phaseolus` internal backend.
- **Grafana dashboards:** all three Phaseolus dashboards (business metrics, order flow, technical) present and reachable for the SSO-authenticated session.
- **Prometheus gate:** confirmed the direct Service-level port-forward (`kubectl port-forward svc/prometheus-kube-prometheus-prometheus`) still reaches Prometheus without Keycloak — the honest, documented limitation from Step 5 (no `NetworkPolicy` enforces the gate; `setup.sh` just no longer *offers* that path) holds exactly as described, not a new bug.

## Rollback / blast radius

Grafana (Step 2) and Argo CD (Step 3) changes are configuration on already-stateless Deployments — reverting is deleting the added `grafana.ini`/`argocd-cm`/`argocd-rbac-cm` keys and letting `helm upgrade`/`kubectl apply` put them back. Prometheus (Step 5) is purely additive new resources (a new Deployment, Service, IngressRoute) — reverting is deleting them, with zero effect on Prometheus itself.

RabbitMQ (Step 4) is the one step touching a **stateful** release (RabbitMQ has a PVC, per the architecture plan's Step 13 incident) — enabling a plugin via Helm values will restart the `rabbitmq-0` pod, but should not touch its data volume. Still, per `10_target_shape.md`'s constraint and the Step 13 incident's lesson, verify this specific claim (plugin-enable causing a pod restart without PVC impact) against a disposable test before trusting it on the one RabbitMQ instance this project has, and keep the AMQP-still-works check in Step 4 as a hard gate before considering that step done.

## Quality gates before merging

- `bash -n setup.sh` after every `setup.sh` edit.
- `kubectl apply --dry-run=server` (or `helm template`) for any new/changed manifest before applying it live, where practical.
- Live verification per step against the dev `minikube` cluster, same as every prior plan in this repo — there is no automated test suite for infrastructure config.
- Step 6's fresh-cluster run is the final gate, not a formality — it's what caught two real bugs in `../2026_10_sso-keycloak/` that no amount of live-cluster testing alone found.

---

**Exit criterion:** Every step ✅, gates green, PR merged. Mark ✅ in `README.md` when complete and archive the folder per the project's plan-archive convention in `CLAUDE.md`.
