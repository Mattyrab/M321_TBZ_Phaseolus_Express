# 10 — Target shape

What the change must produce. **Requirements, not solutions.** This is the interpretation of `inputs.md` against `00_current_state.md`. If you find yourself naming a class, file, or library call, you're in `20_options.md`/`40_implementation.md` territory — back up.

## Goals

- **The admin identity established by logging into BeanApp is honored everywhere it currently isn't.** Concretely: BeanNotifs' `GET /notifications` must require a valid, Keycloak-issued credential tied to the `admin` role before returning data — today it returns data to anyone who can reach its port, logged in or not. This is the single clearest gap `00_current_state.md` identified and the most direct reading of "proper SSO ... with the established admin."
- **Service-to-service calls are properly scoped, not just "signed by our realm."** OrderBeans currently accepts any token issued by the `phaseolus` realm with `ValidateAudience = false` — i.e. it can't actually tell *which* client or *which* role a token belongs to. Whatever token BeanApp presents (to OrderBeans, to BeanNotifs, to any future protected endpoint) must be checked for the right audience/role, not merely "valid and from our realm."
- **The pattern is repeatable, not a one-off fix wedged into BeanNotifs.** Any of the five services that exposes an HTTP endpoint carrying sensitive/admin data must be protectable using the same Keycloak-validation shape, so adding auth to a sixth service later is "copy the pattern," not "redesign it."
- **`setup.sh` reproduces a fully working login from a clean cluster.** `00_current_state.md` found that the realm-roles-in-ID-token protocol mapper fix (and the exact `redirectUris`/`post.logout.redirect.uris` config) only exists live in the running cluster, not in the script — anyone re-running `setup.sh` today regresses into the login-loop bug that was already debugged once. This plan must close that gap as part of "proper" SSO, since a setup that only works until the next `minikube delete` isn't proper.
- **The existing admin login flow keeps working exactly as it does today** (Authorization Code + PKCE, cookie session, `[Authorize(Roles = "admin")]` gating `/Admin`) — this plan extends what the credential is honored *by*, not how the admin obtains it.

## Non-goals

- **Logging in as a shopper.** Browsing Beans, adding to Cart, and Checkout stay anonymous/public. "SSO ... with the established admin" is about the one admin identity that already exists, not about adding customer accounts — that would be a materially different, unrequested feature.
- **RabbitMQ-level authentication/authorization changes.** RabbitMQ already has its own username/password gating the broker connection, entirely separate from Keycloak. Retrofitting JWT-based auth onto the async message bus itself is a much larger, separate undertaking than "SSO for services" implies, and nothing in `inputs.md` asks for it.
- **Auth-gating health-check or `/metrics` endpoints.** These are scraped by Kubernetes probes and Prometheus, not accessed by any human or admin credential — adding auth there would break the existing monitoring setup (`../2026_09_phaseolus-architecture/`) for no security benefit.
- **Adding auth to PayBeancoins or CookerBeaners.** Per `00_current_state.md`, neither exposes any HTTP endpoint beyond health/metrics — there is nothing for Keycloak to protect in either service today. If a future change gives either of them a real API, it can follow the same pattern this plan establishes; building it preemptively would be speculative.
- **Standing up real Traefik ingress for every service.** `00_current_state.md` confirms only BeanApp has an `IngressRoute`; everything else is reached via `kubectl port-forward` or in-cluster DNS. Building production-grade ingress for all five services is a separate, much larger infrastructure project the user hasn't asked for — this plan works within the existing access pattern (documenting it clearly, per the `setup.sh` goal above) rather than replacing it.
- **Splitting `beanapp-client` into multiple Keycloak clients, or any other specific Keycloak topology.** Whether to introduce new clients, use client scopes, or keep one client is a design choice for `20_options.md`, not a requirement fixed here.
- **Re-litigating the admin user/role itself.** The `admin`/`phaseolus` user and `admin` realm role are the "established admin" the user referred to — this plan uses them as-is, it doesn't redesign Keycloak's user/role model.

## Constraints

- Must not break the Cart → Checkout → OrderBeans flow, which already depends on BeanApp's client-credentials token being accepted by OrderBeans today.
- Must not break the already-working `/Admin` login flow (Authorization Code + PKCE, cookie session, role-claim mapping) — this is the thing being extended, not replaced.
- No shared NuGet package across services for the Keycloak-validation code (architecture plan Q2, reaffirmed by the service-api-template plan) — any reusable validation pattern is a copy-paste convention per service, like the existing JWT Bearer setup in OrderBeans.
- Each service stays independently buildable/deployable per its own repo (service-api-template plan constraint) — this plan's changes to one service's auth must not require simultaneous changes to unrelated services to keep building.
- `docs/CLAUDE.md`'s guidelines apply directly here: minimum code that solves the problem, no speculative abstraction (e.g. no generic multi-tenant auth framework), surgical changes to each service.
- Whatever `setup.sh` changes are needed must keep the script idempotent/rerunnable the way it is today (it's the documented "set this project up on a new machine" path).

## Success criteria

- An anonymous `curl` to BeanNotifs' `/notifications` (no `Authorization` header) is rejected; a request carrying a valid admin-scoped credential succeeds and returns the same data the Admin page shows today.
- BeanApp's `/Admin` page continues to load and display notifications end-to-end after the change, using a real credential on the BeanNotifs call instead of none.
- A token that OrderBeans or BeanNotifs would previously have accepted purely because it came from the `phaseolus` realm, but that lacks the correct audience/role, is now rejected — demonstrated with a live test (e.g. a token from a different/unintended client, or one missing the `admin` role, where that's the relevant check).
- Running `setup.sh` against a brand-new `minikube` cluster produces a working `/Admin` login on the first try, with no manual Keycloak Admin API fix-up required afterward — the exact scenario that failed before this plan.
- The existing Cart → Checkout → OrderBeans path and the existing `/Admin` login path both still work, verified live, after all changes in this plan land.

---

**Exit criterion:** Requirements are testable, not vague. Mark ✅ in `README.md` when complete.
