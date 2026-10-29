# 10 — Target shape

What the change must produce. **Requirements, not solutions.** This is the interpretation of `inputs.md` against `00_current_state.md`. If you find yourself naming a Helm value, a ConfigMap key, or a specific plugin, you're in `20_options.md`/`40_implementation.md` territory — back up.

## Goals

- **Logging into Grafana, RabbitMQ's management UI, and Argo CD authenticates against Keycloak**, using each tool's own native login flow (OIDC for Grafana and Argo CD, the OAuth2 plugin for RabbitMQ) — not that tool's separate local username/password. This is the direct, achievable core of "expand the SSO" for the three tools that actually support it.
- **Prometheus gets an equivalent access gate**, even though it has no native auth to configure — some fronting mechanism must sit between an anonymous request and the Prometheus UI, redirect to Keycloak, and only admit a request carrying a valid admin session. "SSO for Prometheus" means this gate exists and uses the same identity as the other three, not that Prometheus itself becomes OIDC-aware (it structurally can't).
- **One identity, one role, four tools.** The existing `admin` realm role (established by `../2026_10_sso-keycloak/`) is what grants access everywhere in this plan — an operator who can log into BeanApp's `/Admin` page as `admin` can also reach all four of these tools with the same credential, without a second role/group needing to be invented first.
- **The whole thing is reproducible by `setup.sh` from a clean cluster**, same bar `../2026_10_sso-keycloak/`'s Step 5 established — whatever Keycloak clients, realm config, Helm values, or Kubernetes manifests this plan adds must be scripted, not just clicked into place on the live dev cluster.
- **None of the four tools' existing non-UI functionality regresses**: RabbitMQ's AMQP-level auth (the `phaseolus` broker user every service already authenticates with to publish/consume) keeps working exactly as today; Argo CD keeps syncing Applications; Grafana keeps rendering its existing ConfigMap-provisioned dashboards (business metrics, technical, order flow) without needing a login to have been fetched correctly in the first place.

## Non-goals

- **Standing up production-grade public ingress or TLS for any of these tools.** `00_current_state.md` confirms the whole project's access model is `kubectl port-forward`-based, with no public hostname for anything except BeanApp's single `IngressRoute`. This plan does not change that — "SSO" here means the login screen reached after port-forwarding uses Keycloak, not that these tools become internet-reachable. If a reverse-proxy is needed (for Prometheus), it only needs to work over the same port-forward-based access pattern already established.
- **Fine-grained, per-tool RBAC mapping from Keycloak groups/roles to tool-specific permission levels.** Argo CD, for instance, supports mapping OIDC group claims to project-scoped RBAC policies — real functionality, but this project has exactly one admin user and one role (per `00_current_state.md`); building a permission matrix for a population of one is the same class of over-engineering `../2026_10_sso-keycloak/20_options.md` already rejected (token exchange) for the same reason. Every tool in this plan gets a simple "the `admin` role can log in" gate, not tiered access.
- **A second Keycloak realm, or any multi-tenancy.** Everything stays in the `phaseolus` realm.
- **Changing RabbitMQ's AMQP-level service authentication.** The `phaseolus`/`phaseolus` broker credentials OrderBeans/PayBeancoins/CookerBeaners/BeanNotifs already use over AMQP are untouched — only the management UI's *human* HTTP login is in scope for RabbitMQ's OAuth2 plugin.
- **Disabling Argo CD's or RabbitMQ's local admin fallback.** Both tools support SSO *alongside* a local admin account by default; removing the local fallback entirely would risk total lockout from a misconfiguration, which is a real, named risk this plan should not introduce casually (see Constraints).
- **Reusing the `phaseolus-internal-api` audience from the prior plan.** That audience exists for *backend services validating a bearer token forwarded between them* — the mechanism here is fundamentally different: each of these four tools runs its own browser-based OIDC login flow directly against Keycloak, with no token being forwarded by a third service. A new, separate client (or clients) is expected; which exact shape is `20_options.md`'s job.

## Constraints

- Must not break the live, already-working AMQP service-to-service auth in RabbitMQ (verified end-to-end by every prior plan in this repo via real order placement) — any RabbitMQ change here is scoped to the management plugin/UI only.
- Must not break Argo CD's ability to sync Applications or the `argocd-application-controller`'s own cluster access, which has nothing to do with human UI login.
- Must not break the Grafana dashboard sidecar's ConfigMap-based provisioning (`grafana_dashboard: "1"` labeled ConfigMaps) — these are fetched by a sidecar container independent of how a human logs into the Grafana UI.
- No shared NuGet-style code reuse concern applies here (this plan touches infra config, not the five C#/.NET services) — but the project's general "minimum config that solves the problem" principle (`docs/CLAUDE.md`) still applies: e.g. don't build a general-purpose auth-proxy framework when a single, scoped middleware/sidecar for Prometheus will do.
- Whatever Keycloak client(s) this plan adds must follow the same "pin a fixed secret, commit it, document it" convention `../2026_10_sso-keycloak/00_current_state.md` already established for `beanapp-client` — no per-environment secret generation this project doesn't have infrastructure to manage.
- `setup.sh` must stay idempotent/rerunnable, as it already is.
- Given the architecture plan's Step 13 incident (infra Helm adoption into Argo CD deleted StatefulSet data) and this plan's own Step-5-equivalent testing will likely touch live Helm releases for RabbitMQ/Grafana/Prometheus again, any experimentation must follow the same discipline already written down in `../2026_09_phaseolus-architecture/50_followups.md`: test against disposable/throwaway state first, never assume a config change to a stateful release is risk-free.

## Success criteria

> **Amended after `40_implementation.md` Step 3:** Argo CD turned out to have no way to meet the first bullet below — it has no mechanism to split the browser-facing Keycloak address from the in-cluster one its own backend needs (unlike Grafana's `generic_oauth`), and the real fix (a Windows hosts-file entry + matching in-cluster DNS override) was declined. Argo CD keeps its local admin login; see Step 3 and `50_followups.md`. Left as originally written below for the record.

- An anonymous request to each of Grafana, RabbitMQ's management UI, and Argo CD's UI is redirected into a real Keycloak login page (not shown that tool's own local login form); authenticating as `admin`/`phaseolus` lands back in that tool, logged in.
- An anonymous request to Prometheus's UI is similarly gated — redirected to Keycloak login, only reachable after authenticating as `admin`.
- A user who is *not* the `admin` (or lacks the `admin` role) is not able to complete login to any of the four tools — demonstrated live, the same way the prior plan demonstrated a non-admin token being rejected by BeanNotifs.
- Running `setup.sh` against a freshly deleted `minikube` cluster reproduces all of the above on the first try, with no manual follow-up — the exact bar `../2026_10_sso-keycloak/`'s Step 5 set and then met.
- After this plan lands: a real order still flows end-to-end through RabbitMQ (OrderBeans → PayBeancoins → CookerBeaners → BeanNotifs), Argo CD still shows all Applications `Synced`/`Healthy`, and Grafana's three existing dashboards still render their data — proving none of the three regression-risk areas named in Goals/Constraints actually broke.

---

**Exit criterion:** Requirements are testable, not vague. Mark ✅ in `README.md` when complete.
