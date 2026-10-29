# 30 — Open questions

Specific decisions that block implementation. Each question has a clear path to resolution. **No vibes-questions** ("is this a good idea?") — split those into the underlying yes/no decisions.

Resolve every question to ✅ or ❌ before starting `40_implementation.md`. If a question can't be answered now, either move it to `50_followups.md` (out of scope) or mark it ⚠️ blocked with a named blocker.

## Questions

### Q1 — One shared Keycloak client for Grafana/Argo CD, or one per tool?

✅ **Question.** Grafana and Argo CD both do a standard browser OIDC redirect flow (RabbitMQ's OAuth2 plugin is a different enough mechanism that it needs its own client regardless — see Q3's context). Should Grafana and Argo CD share **one** new Keycloak client (e.g. `admin-ui-client`), or should each get its **own** dedicated client?

**Why it matters.** Determines how many new client registrations `40_implementation.md` creates in `setup.sh`, and what redirect URIs each needs (a shared client needs *both* tools' callback URLs in its `redirectUris` list; separate clients each need just their own). A shared client is less to register but couples the two tools' configs together; separate clients are more setup but fully independent (e.g. rotating one tool's secret doesn't touch the other).

**Resolution.** ✅ 2026-10-29 — one shared client, e.g. `admin-ui-client`, used by both Grafana and Argo CD. Its `redirectUris` list carries both tools' callback URLs.

---

### Q2 — How does Argo CD's RBAC policy recognize the admin?

✅ **Question.** Argo CD's OIDC users get **zero** access by default — `argocd-rbac-cm` needs an explicit policy mapping something in the token to `role:admin` (`10_target_shape.md`'s "no fine-grained RBAC" non-goal means this should map straight to Argo CD's own built-in admin role, not a custom policy). Should that policy match on the admin's **email/username claim directly** (e.g. `g, admin, role:admin`), or should Keycloak's existing `admin` **realm role** be exposed as a `groups` claim (via an added protocol mapper) and the policy match on that group instead?

**Why it matters.** Matching on username/email is zero extra Keycloak configuration but hardcodes a specific person's identifier into `argocd-rbac-cm` — add a second admin later and you edit this file again. Matching on a `groups` claim needs one more protocol mapper (mirroring how `../2026_10_sso-keycloak/` already maps `realm_access.roles`) but means "anyone with the `admin` realm role" is automatically an Argo CD admin, no `argocd-rbac-cm` edit needed if a second admin is ever added.

**Resolution.** ✅ 2026-10-29 — match directly on the admin's email claim (e.g. `g, admin@phaseolus.local, role:admin`). Simpler now; revisit with a `groups`-claim mapper if a second admin is ever added.

---

### Q3 — What sits in front of Prometheus?

✅ **Question.** `20_options.md` settled that Prometheus needs a dedicated access gate (no native auth exists), but not *which* one. Candidates: (a) `oauth2-proxy` as its own Deployment, fronted by a new Traefik `IngressRoute` + `ForwardAuth` `Middleware`; (b) a simpler auth-checking sidecar/container in the same pod; (c) reusing Grafana's own OIDC session somehow (e.g. only ever viewing Prometheus data *through* Grafana's already-configured Explore view, and not exposing Prometheus's own UI/port at all).

**Why it matters.** This is genuinely new infrastructure — nothing like it exists in the cluster today (`00_current_state.md`: zero Traefik `Middleware` resources anywhere). Option (c) is notably cheaper (no new proxy, no new IngressRoute) but changes what "access Prometheus" even means for an operator (no more direct PromQL UI, Grafana's Explore view only) — a real behavior change `10_target_shape.md`'s success criteria need to account for either way.

**Resolution.** ✅ 2026-10-29 — a real reverse proxy (`oauth2-proxy` + a new Traefik `IngressRoute`/`ForwardAuth` `Middleware`), keeping Prometheus's own UI directly reachable rather than folding it into Grafana's Explore view.

---

### Q4 — Does Grafana enforce the `admin` realm role, or accept any authenticated Keycloak login?

✅ **Question.** Grafana's `generic_oauth` config supports restricting login to users carrying a specific role/claim (`role_attribute_path`), or it can simply accept anyone who successfully authenticates against Keycloak. Since `admin` is currently the *only* Keycloak user in the whole realm (`00_current_state.md`), these are equivalent today — but only one of them stays correct if a second, non-admin Keycloak user is ever added. Should Grafana explicitly require the `admin` realm role to complete login, or just require successful Keycloak authentication?

**Why it matters.** `10_target_shape.md` says access is gated by "the `admin` role," not merely "a Keycloak account" — explicitly enforcing the role check is the more literal reading and costs one extra config line; skipping it is simpler today but silently drifts from that requirement the moment a second user exists.

**Resolution.** ✅ 2026-10-29 — accept any successful Keycloak login, no explicit role check in Grafana's `generic_oauth` config. Equivalent to requiring the `admin` role today since `admin` is the only account that exists; revisit if a second, non-admin Keycloak user is ever added.

---

**Exit criterion:** Every question is ✅ resolved, ❌ dropped, or ⚠️ blocked-with-blocker. Mark ✅ in `README.md` when complete.
