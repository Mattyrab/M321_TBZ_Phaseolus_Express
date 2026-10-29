# 40 — Implementation

Step plan for the chosen option from `20_options.md`. **Do not start this phase while `30_open_questions.md` has any ⏳ items** — that's the discipline this folder structure exists to enforce.

Each step has a verification: how do we know the step is done? Strong verification turns the plan into a checklist you can run independently.

## Plan summary

Keycloak comes first (Step 1) since every other step depends on the `phaseolus-internal-api` audience existing on issued tokens before any service can validate against it. OrderBeans (Step 2) comes next because it's a pure tightening of an already-working check — low risk, and a good smoke test that the new audience mapper doesn't break the existing Cart → Checkout flow before anything new is built on top of it. BeanNotifs (Step 3) and BeanApp (Step 4) are the real feature work and are tightly coupled: BeanNotifs starts rejecting the unauthenticated calls BeanApp makes today, so between merging Step 3 and Step 4 the Admin page's BeanNotifs call will degrade to its existing generic error message (not break the whole page — `Admin.cshtml.cs` already wraps the call in a try/catch) until Step 4 lands. Step 5 is end-to-end live verification tying all four together, including the one scenario that needs a deliberate, temporary Keycloak setting change to observe (an expired token).

Each step maps to one repo/PR, following the project's established branch-per-concern convention: Step 1 is the meta repo (`setup.sh` + a live Keycloak Admin API change), Steps 2–4 are OrderBeans / BeanNotifs / BeanApp respectively.

## Per-service deltas

| Service | Change | Auth before | Auth after |
|---|---|---|---|
| Keycloak (meta repo) | New audience mapper (`phaseolus-internal-api`) on `beanapp-client`; realm access-token lifespan → 15 min; port the already-live "realm roles → ID token" mapper fix into `setup.sh` | — | — |
| OrderBeans | `ValidateAudience = true`, `ValidAudience = "phaseolus-internal-api"` | any token from the `phaseolus` realm | any token from the realm **with the right audience** |
| BeanNotifs | New `AddJwtBearer` (Authority + audience check), realm-role claim mapping, `RequireRole("admin")` on `GET /notifications` | none — fully open | valid token, `phaseolus-internal-api` audience, `admin` role |
| BeanApp | `Admin.cshtml.cs` forwards the admin's own access token to BeanNotifs; detects a 401 and shows a distinct "please log in again" message | no credential sent to BeanNotifs | admin's own Keycloak access token, as a `Bearer` header |

## Steps

### Step 1 — Keycloak: shared audience, longer token lifespan, and the missing `setup.sh` fix

✅ **Do.**
- Via the Admin API (live, against the dev cluster) and ported into `setup.sh`'s Keycloak section:
  - Add a protocol mapper of type "Audience" to `beanapp-client` (or a default client scope it uses) that adds `phaseolus-internal-api` to the `aud` claim of every token the client issues — both the interactive login (Authorization Code) and client-credentials grants, since it's a client-level mapper rather than scope-specific to one flow.
  - Set the `phaseolus` realm's `accessTokenLifespan` to `900` (15 minutes), per Q3's resolution.
- Separately, port the fix already live on the dev cluster but missing from the script (`00_current_state.md`): flip the realm's "roles" client scope's "realm roles" protocol mapper `id.token.claim` to `true`, so a fresh `setup.sh` run doesn't regress into the login-loop bug that was debugged interactively earlier.

**Verify.** Fetch a client-credentials token for `beanapp-client` directly from Keycloak and decode it — confirm `aud` includes `phaseolus-internal-api`. Log in as `admin`/`phaseolus` through BeanApp, decode the resulting ID token, confirm both the `admin` realm role and the new audience are present, and confirm the token's `exp` is ~15 minutes out from `iat`. Tear down and re-run `setup.sh` against a fresh `minikube` cluster; confirm `/Admin` login succeeds on the first try with no manual follow-up.

✅ **Done 2026-10-29 (live, against the dev cluster).** Applied all three Keycloak changes via the Admin API and ported them into `setup.sh` (plus one more undocumented gap found while editing: the admin user's `create` call was missing `email`/`firstName`/`lastName`, which is what actually caused the `VERIFY_PROFILE` login-block bug debugged earlier this session — fixed alongside, since it blocks this step's own "login succeeds on the first try" criterion). Verified:
- Client-credentials token decoded: `aud: phaseolus-internal-api, account`; `exp - iat = 900` seconds.
- Full Authorization Code login as `admin`/`phaseolus` through BeanApp still succeeds end-to-end (`/Admin` renders) with the new audience mapper and 15-minute lifespan in place — no regression.
- Cart → Checkout → OrderBeans still works unchanged (order accepted) — confirms the new audience claim doesn't disturb OrderBeans, which doesn't check it yet (that's Step 2).
- Deferred to Step 5 rather than repeated here: the actual "tear down and re-run `setup.sh` against a fresh cluster" test. Doing a full teardown/rebuild now would only exercise the Keycloak piece in isolation, since Steps 2–4's code isn't written yet — running it once at Step 5, against the complete system, gets the same proof without rebuilding the cluster twice.

---

### Step 2 — OrderBeans: require the shared audience

⏳ **Do.** In `Program.cs`'s `AddJwtBearer` setup, change `options.TokenValidationParameters.ValidateAudience = false` to `true` and set `options.TokenValidationParameters.ValidAudience = "phaseolus-internal-api"`.

**Verify.** The existing Cart → Checkout flow still works end-to-end (BeanApp's client-credentials token now carries the new audience from Step 1, so this should be a no-op in practice) — place a real order through BeanApp and confirm OrderBeans accepts it (`202`) same as before. Separately, confirm a token that does *not* carry the audience (e.g. one fetched directly from a different, ad-hoc test client, or simply the pre-Step-1 token shape if still cached) is rejected with `401`.

---

### Step 3 — BeanNotifs: require a valid, admin-scoped token

⏳ **Do.**
- Add `Keycloak:Authority` to `appsettings.json` and `deploy/deployment.yaml` (`Keycloak__Authority`), same in-cluster DNS value OrderBeans already uses — BeanNotifs has no `Keycloak` config section today.
- Add the same `AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(...)` block OrderBeans has, plus: `ValidateAudience = true` / `ValidAudience = "phaseolus-internal-api"` (Step 1), `MapInboundClaims = false`, and an `OnTokenValidated` event that maps `realm_access.roles` onto `ClaimTypes.Role` — the same mapping logic already in BeanApp's OIDC setup (`WebApp/Program.cs`), adapted to `JwtBearerEvents`.
- Change `app.MapGet("/notifications", ...)` to `.RequireAuthorization(policy => policy.RequireRole("admin"))` (needs `builder.Services.AddAuthorization()` too, which doesn't exist in this service yet).

**Verify.** `curl` with no `Authorization` header → `401`. `curl` with BeanApp's client-credentials token (valid audience, but no `admin` role — service accounts don't carry realm roles) → `403`. `curl` with a freshly-fetched admin user token (`admin`/`phaseolus`, Resource Owner Password grant for this one manual test, or copied from an active browser session) → `200` with the same notification data the Admin page shows today. Confirm `/healthz/live`, `/healthz/ready`, and `/metrics` remain unauthenticated (non-goal from `10_target_shape.md` — must not regress).

---

### Step 4 — BeanApp: forward the admin's token, handle expiry

⏳ **Do.** In `Admin.cshtml.cs`'s `OnGetAsync`:
- Retrieve the current request's access token via `HttpContext.GetTokenAsync("access_token")`.
- Replace the plain `GetFromJsonAsync` call with an explicit `HttpRequestMessage` carrying `Authorization: Bearer {token}` (same pattern `Checkout.cshtml.cs` already uses for the OrderBeans call), targeting BeanNotifs.
- On a `401` response specifically, set a distinct message — "Your session has expired — please log in again" — instead of falling into the existing generic `catch` (`10_target_shape.md`/Q2). Other failures (BeanNotifs unreachable, 5xx, etc.) keep the existing generic "Could not reach BeanNotifs" message.

**Verify.** Log in as `admin`, load `/Admin` — notifications render exactly as before (now carrying a real bearer token BeanNotifs actually checks). Manually expire the session (wait out the lifespan, or use Step 5's temporary short-lifespan trick) and reload `/Admin` — confirm the new "please log in again" message appears instead of the generic error, and that logging in again restores normal behavior.

---

### Step 5 — End-to-end live verification

⏳ **Do.** No code change — this step is the full regression + new-behavior pass across the live cluster, after Steps 1–4 are all deployed together (per the plan summary's sequencing note).

**Verify.**
- Cart → Checkout → OrderBeans: unchanged, place a real order, confirm success.
- Anonymous `curl` to BeanNotifs' `/notifications`: `401`.
- BeanApp's client-credentials token (valid audience, no `admin` role) against BeanNotifs: `403`.
- Logged-in admin's `/Admin` page: notifications load correctly, using the forwarded token.
- Expired-token UX: temporarily set `accessTokenLifespan` to something very short (e.g. 10s) via the Admin API, log in fresh, wait it out, reload `/Admin`, confirm the "please log in again" message from Step 4 — then restore the realm to the 15-minute setting from Step 1.
- A fresh `setup.sh` run (Step 1's verification) still reproduces all of the above from a clean cluster.

## Rollback / blast radius

Every change here is additive configuration or a tightened check on top of already-working auth — no data migrations, no destructive Keycloak operations. If a step causes a live problem:
- Step 1 (audience mapper, token lifespan): both are reversible single Admin API calls (remove the mapper, reset the lifespan) or a `setup.sh` edit; neither touches existing users, roles, or the realm/client identity itself — nothing like the Step-13 infra-Helm incident from the architecture plan, which involved StatefulSets and real data.
- Steps 2–3 (`ValidateAudience`/`RequireRole` additions): reverting is a one-line code change back to the prior `Program.cs` state and a redeploy; no state is written anywhere by these checks.
- Step 4 (BeanApp): reverting is restoring the prior `GetFromJsonAsync` call; worst case during rollout is the Admin page showing the generic "Could not reach BeanNotifs" error until Step 4 is deployed (already called out in the plan summary), not a hard failure of the rest of the app.

## Quality gates before merging

- `dotnet build` passes for each touched service (OrderBeans, BeanNotifs, BeanApp) before opening its PR, per this project's established per-repo workflow.
- Live verification per step (above) against the dev `minikube` cluster before merging that step's PR — this project has no automated test suite; live manual verification is the existing quality gate (see every prior plan's `40_implementation.md` in this repo).
- `setup.sh`'s changes are verified end-to-end against a genuinely fresh cluster (Step 1 and Step 5), not just the already-running dev cluster, since the whole point of that fix is reproducibility from scratch.

---

**Exit criterion:** Every step ✅, gates green, PR merged. Mark ✅ in `README.md` when complete and archive the folder per the project's plan-archive convention in `CLAUDE.md`.
