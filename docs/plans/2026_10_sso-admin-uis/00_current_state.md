# 00 — Current state

What exists in the codebase **today**, before any change. The goal: a reader unfamiliar with this corner of the repo can follow links from this doc alone and understand what's there.

## Models / data shape

Keycloak realm/client shape, extending `../2026_10_sso-keycloak/00_current_state.md`'s snapshot (that plan's work is complete and merged):

- **Realm:** `phaseolus`, same single realm as before.
- **Clients:** still just `beanapp-client` — no client exists yet for Grafana, RabbitMQ, Prometheus, or Argo CD. Each of these tools would need either its own registered OIDC client, or (for Grafana/Argo CD specifically) could in principle reuse `beanapp-client`, since both support specifying an arbitrary client ID/secret pair.
- **Roles:** the `admin` realm role exists (from the prior plan) and is the only role defined. No distinction exists yet between "admin of the shop" and "admin of the infrastructure" — today's `admin` user is the only identity in the system at all.
- **Audience:** `phaseolus-internal-api` exists (prior plan, Step 1) but is scoped to `beanapp-client`'s tokens for the application services (OrderBeans, BeanNotifs) — unrelated to what these four infra tools would need.

## Code paths involved

**`setup.sh`** installs all four tools, none with any Keycloak awareness:
- Lines 111/140-141: `helm upgrade --install prometheus prometheus-community/kube-prometheus-stack --version 91.8.2 --set grafana.adminPassword="$GRAFANA_PASSWORD"` — Grafana's only auth customization is its own local admin password (`GRAFANA_PASSWORD`, defaults to `phaseolus`). No `grafana.grafana.ini` override exists for an `[auth.generic_oauth]` section.
- Lines 114-120: `helm upgrade --install rabbitmq bitnami/rabbitmq --version 16.0.14 --set auth.password="$RABBITMQ_PASSWORD" ...` — RabbitMQ's only auth customization is its own local user/password (`phaseolus` / `$RABBITMQ_PASSWORD`, defaults to `phaseolus`). No OAuth2 configuration.
- Lines 152-165: Argo CD is installed from the project's own stable `install.yaml` manifest (`kubectl apply --server-side`) with no customization beyond registering the meta repo as a Git source. No `argocd-cm`/`argocd-rbac-cm` overrides exist anywhere in `k8s/argocd/`.
- Lines 350-357 (`start_port_forward`): all four tools are reached exclusively via `kubectl port-forward` — `grafana` (3000→80), `rabbitmq` (15672→15672), `prometheus` (9090→9090), `argocd` (8443→443). None has a Traefik `IngressRoute`.
- Lines 370-374: the script's own summary echoes four *different* credential pairs — Grafana (`admin`/`$GRAFANA_PASSWORD`), RabbitMQ (`phaseolus`/`$RABBITMQ_PASSWORD`), Argo CD (`admin`/the auto-generated `argocd-initial-admin-secret`), and Prometheus (no credential at all — its UI has none).

**Live cluster, verified directly** (not just inferred from `setup.sh`):
- `kubectl get configmap prometheus-grafana -n infra -o jsonpath='{.data.grafana\.ini}'` — no `[auth.generic_oauth]` or any `[auth.*]` section exists; Grafana runs with its chart's bare defaults plus the admin password.
- `kubectl get configmap argocd-cm -n argocd` — no `url`, `oidc.config`, or `dex.config` key exists. `argocd-rbac-cm` is entirely empty (no custom RBAC policy at all). Argo CD runs in pure default mode: one built-in `admin` user, full access.
- `argocd-dex-server` **is already running** as part of the stock `install.yaml` — Dex (Argo CD's bundled OIDC connector/proxy) is deployed but completely unconfigured and currently does nothing, since `argocd-cm` has no `dex.config`/`oidc.config` pointing it at an identity provider.
- `kubectl exec rabbitmq-0 -- rabbitmq-plugins list` — `rabbitmq_auth_backend_oauth2` (v4.1.3) **is present in the image but disabled** (`[  ]`, not `[E]`/`[e]`); `rabbitmq_management`, `rabbitmq_prometheus`, and (oddly, likely a Bitnami chart default never used by this project) `rabbitmq_auth_backend_ldap` are the only auth-adjacent plugins currently enabled.
- Prometheus's own web UI (port 9090, the `prometheus-kube-prometheus-prometheus` Service) has **no authentication mechanism of any kind, built-in or pluggable** — this is a structural property of Prometheus itself (by design, it expects to sit behind a reverse proxy for anything beyond trusted-network access), not a configuration gap like the other three.
- `kubectl get ingressroute,middleware -A` — exactly one `IngressRoute` exists in the whole cluster (`beanapp`, routing `/` to BeanApp on the `web` entrypoint). **Zero** Traefik `Middleware` resources exist. None of the four tools in scope here has any Traefik routing at all today.

## Behavior today

- An operator who wants to see dashboards, inspect queues, view metrics, or check sync status opens a separate `kubectl port-forward` for each tool (already running persistently once `setup.sh` finishes, per its final summary block) and logs into each with a different, tool-local credential pair that has nothing to do with Keycloak or the `admin` realm role established for the application.
- There is no single sign-on moment for operators at all — four tools, four independent login screens, four independent credential stores (Grafana's own user DB, RabbitMQ's own user DB, Argo CD's own built-in `admin` secret, and Prometheus's *lack* of any login screen whatsoever since anyone who can reach port 9090 has full access).
- Keycloak itself has no awareness that these tools exist — no clients, no scopes, no role mappings reference them.

## What's missing or awkward

- **Four different auth stories, one per tool**: Grafana and Argo CD both have first-class, well-documented OIDC support built directly into the application (`grafana.ini`'s `[auth.generic_oauth]`, `argocd-cm`'s `oidc.config` fed to the already-running Dex server) — these are comparatively small configuration changes. RabbitMQ has a real OAuth2 plugin already present in the image, just unconfigured — a bigger lift than Grafana/Argo CD (broker-level config, a token-to-permission-tag mapping, a dedicated Keycloak client) but still a supported, native path. **Prometheus has no path at all** — any "SSO" for it necessarily means putting something else (a reverse proxy) in front of it, which is qualitatively different work from configuring the other three.
- **No ingress exists for any of the four tools.** Whatever mechanism is chosen, especially for Prometheus (which needs a proxy *in front of* it to do anything), has to contend with the fact that these tools aren't exposed via Traefik today — only ad hoc port-forwards.
- **No distinction between "shop admin" and "infra admin."** The one existing `admin` role was built for gating BeanApp's `/Admin` page. Whether the same role should also grant access to Grafana/RabbitMQ/Prometheus/Argo CD, or whether a separate role/group is warranted, is an open design question this plan needs to settle.
- **`setup.sh`'s reproducibility bar**, established by the prior plan's Step 5, applies here too: whatever gets configured needs to be scripted, not just clicked into place on the live dev cluster, or a fresh `minikube delete` + re-run will regress.

---

**Exit criterion:** A reader can navigate the relevant code from this doc alone. Mark ✅ in `README.md` when complete.
