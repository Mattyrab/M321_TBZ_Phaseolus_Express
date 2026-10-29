# 00 — Current state

What exists in the codebase **today**, before any change. The goal: a reader unfamiliar with this corner of the repo can follow links from this doc to the relevant code and understand what's there.

## Models / data shape

Keycloak realm/client/role shape (the closest thing to a "data model" for identity in this project):

- **Realm:** `phaseolus` (single realm, no multi-tenancy). Created via the Admin REST API in `setup.sh:202-205`.
- **Clients:** exactly **one** — `beanapp-client`. Created in `setup.sh:207-220`:
  - `publicClient: false` (confidential, has a secret)
  - `serviceAccountsEnabled: true` (so it can do client-credentials grants)
  - `standardFlowEnabled: true` (Authorization Code flow, for the admin browser login)
  - `directAccessGrantsEnabled: false` (no resource-owner-password grant)
  - `redirectUris: ["*"]`, `webOrigins: ["*"]`
  - `attributes: { "post.logout.redirect.uris": "+" }` (RP-initiated logout reuses the redirect URIs)
  - The secret is pinned to a fixed value and copy-committed into `M321_TBZ_Phaseolus_WebApp/deploy/deployment.yaml` (`Keycloak__ClientSecret`), not generated per-environment.
  - **This one client is used for two unrelated purposes today**: the admin's interactive login (Authorization Code + PKCE) *and* BeanApp's service-to-service calls to OrderBeans (client-credentials). No other Keycloak client exists anywhere in any of the five repos — confirmed by grepping all of them for `clientId`/`client_id`.
- **Realm role:** `admin` — created in `setup.sh:227-230` via `POST /admin/realms/phaseolus/roles`.
- **User:** `admin` / `phaseolus`, created in `setup.sh:233-239`, with the `admin` realm role assigned via `setup.sh:247-248`. This is the only Keycloak user that exists; there's no self-service registration or any other seeded account.
- **Protocol mapper:** the realm's built-in "roles" client scope has its "realm roles" mapper's `id.token.claim` flipped to `true` (done live via the admin API during the admin-login work; **not yet captured in `setup.sh`** — see "What's missing" below) so `realm_access.roles` actually lands in the ID token, not just the access token.

## Code paths involved

**BeanApp** (`M321_TBZ_Phaseolus_WebApp/`) — the only service with real Keycloak integration:
- `WebApp/Program.cs:40-105` — registers cookie auth as the default scheme and OIDC (Authorization Code + PKCE) as the challenge scheme. Pins `TokenValidationParameters.ValidIssuer` to `Keycloak:PublicAuthority` (browser-facing hostname) since the backend's own discovery call uses the in-cluster DNS `Authority`, and Keycloak stamps tokens with whichever hostname the browser actually used. Maps `realm_access.roles` onto `ClaimTypes.Role` in `OnTokenValidated` (`Program.cs:76-101`) since ASP.NET Core doesn't do this automatically.
- `WebApp/Pages/Admin.cshtml.cs` — `[Authorize(Roles = "admin")]` gates the page. `OnGetAsync` calls `BeanNotifs`' `GET /notifications` via a plain `HttpClient` with **no bearer token attached at all** — BeanNotifs doesn't check for one.
- `WebApp/Pages/Logout.cshtml.cs` — signs out of both the cookie and Keycloak (RP-initiated logout).
- `WebApp/Keycloak/KeycloakOptions.cs` — `Authority`, `ClientId`, `ClientSecret`, optional `PublicAuthority`.
- `WebApp/Keycloak/KeycloakTokenClient.cs` — caches a client-credentials token (`grant_type=client_credentials` against `{Authority}/protocol/openid-connect/token`), used **only** for the Cart/Checkout → OrderBeans call. Not used for the BeanNotifs call.
- `deploy/deployment.yaml` — `Keycloak__Authority` (in-cluster DNS), `Keycloak__PublicAuthority` (`http://localhost:8180/realms/phaseolus`, tied to the dev port-forward), `Keycloak__ClientId`/`Keycloak__ClientSecret`.
- `deploy/ingressroute.yaml` — a Traefik `IngressRoute` exists for BeanApp (`PathPrefix(\`/\`)` on the `web` entrypoint, routing to `svc/beanapp:8080`). **BeanApp is the only one of the five services with an IngressRoute.**

**OrderBeans** (`M321_TBZ_Phaseolus_Order/Program.cs:13-20`) — the only other service with any Keycloak awareness:
```csharp
builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = builder.Configuration["Keycloak:Authority"];
        options.RequireHttpsMetadata = false;
        options.TokenValidationParameters.ValidateAudience = false;
    });
```
- `Keycloak:Authority` is `http://keycloak.infra.svc.cluster.local/realms/phaseolus` — the in-cluster DNS name, identical value to BeanApp's own `Authority` (not `PublicAuthority`), because OrderBeans only ever receives calls from inside the cluster.
- `.MapPost("/orders", ...)` (`Program.cs:38`) is OrderBeans' only HTTP endpoint and the only one with `.RequireAuthorization()` anywhere in the whole project.
- **No audience validation** (`ValidateAudience = false`): any token issued by the `phaseolus` realm is accepted, regardless of which client it was issued to or what scopes it has. There's effectively no authorization beyond "is this a valid token from our realm."

**PayBeancoins, CookerBeaners, BeanNotifs** — grepping each `Program.cs` for `Authentication|Authorization|Jwt|Keycloak` returns **zero matches** in all three. These services have no Keycloak wiring of any kind:
- PayBeancoins and CookerBeaners expose only health-check and `/metrics` endpoints (no business HTTP API — they're pure RabbitMQ consumers), so there's nothing user-facing to protect today.
- BeanNotifs exposes `GET /notifications` (`Program.cs:43`, `app.MapGet("/notifications", (NotificationStore store) => store.GetAll());`) with no `.RequireAuthorization()` — this is the one meaningful gap, since it's the endpoint the Admin page actually reads admin-only data from.

## Behavior today

- An anonymous visitor hitting `/Admin` gets redirected into Keycloak's hosted login page, authenticates as `admin`/`phaseolus`, and lands back on `/Admin` with a cookie session. This part is a real, working SSO-style login against Keycloak.
- From there, BeanApp fetches `/notifications` from BeanNotifs over the network with **no credential at all** — if BeanNotifs' port were reachable directly (e.g. via its own port-forward, which the project's manual-testing setup already opens), anyone could read the same admin-only data with a bare `curl`, bypassing the login entirely.
- The Cart → OrderBeans checkout path uses a real bearer token (client-credentials), but it authenticates *BeanApp the service*, not the logged-in admin or the anonymous shopper — OrderBeans has no concept of "who placed this order" beyond "some request carrying a valid phaseolus-realm token."
- Every other inter-service hop (OrderBeans → RabbitMQ → PayBeancoins → CookerBeaners → BeanNotifs) is unauthenticated at the transport/application layer; RabbitMQ itself has its own separate username/password (unrelated to Keycloak) gating the broker connection.
- Access to any service today, in practice, is via `kubectl port-forward` (`setup.sh`'s final block: `beanapp` 5050→8080, `keycloak` 8180→80, `grafana` 3000→80, `rabbitmq` 15672→15672, `prometheus` 9090→9090, `argocd` 8443→443) or BeanApp's single Traefik `IngressRoute`. There is no ingress hostname for Keycloak, OrderBeans, PayBeancoins, CookerBeaners, or BeanNotifs — only BeanApp and (via `minikube service traefik -n infra --url`) the Traefik entrypoint itself are reachable as a "real" URL.

## What's missing or awkward

- **BeanNotifs has no auth at all** on an endpoint that only makes sense for admins — it's the most obvious gap given the user's "proper SSO" framing.
- **One client, two jobs**: `beanapp-client` is both an interactive OIDC client and a service-credential — fine at this scale, but conflates "who's allowed to log in as an admin" with "who's allowed to call OrderBeans," which would need separating if more clients/services join the picture.
- **No audience/client validation anywhere**: OrderBeans accepts any token from the realm; there's no concept of scopes or per-client authorization. A compromised or misconfigured future client would be trusted just as much as `beanapp-client`.
- **No real ingress for four of five services**: "SSO across services" usually implies a user can navigate between service UIs and stay logged in, but only BeanApp has a browsable UI/IngressRoute at all. OrderBeans/PayBeancoins/CookerBeaners/BeanNotifs have no UI — only JSON APIs, health checks, and metrics.
- **`setup.sh` is incomplete for the current state**: it creates `beanapp-client`, the `admin` role, and the `admin` user, but does **not** flip the "realm roles → ID token" protocol mapper or set `redirectUris`/`post.logout.redirect.uris` to match what's actually required for login to work (that was done live via the Admin API during the admin-login work and never ported back into the script). Anyone re-running `setup.sh` from scratch today would hit the same "stuck in a login loop" bug that was debugged and fixed interactively.
- **Dev-only hostname split**: `Keycloak:PublicAuthority` is hardcoded to the `kubectl port-forward` address (`http://localhost:8180/...`). There's no ingress-based browser-facing Keycloak hostname, so this entire mechanism is tied to a developer's local port-forward rather than something that would work for a real deployed user.

---

**Exit criterion:** A reader can navigate the relevant code from this doc alone. Mark ✅ in `README.md` when complete.
