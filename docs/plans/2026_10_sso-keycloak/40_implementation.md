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

**Amendment (found during Step 5):** that deferred fresh-cluster run uncovered a real `setup.sh` bug unrelated to the three changes above — the Keycloak Helm install's default `livenessProbe` (120s initial delay) is shorter than Keycloak's actual cold-start time on this machine, so a genuinely fresh pod got killed and restarted mid-startup, which then corrupted the Postgres schema (a partially-applied Liquibase migration) and caused a real crash loop. Fixed by enabling the chart's `startupProbe` (which suppresses liveness/readiness until the app is actually up) with a generous tolerance. See Step 5's notes for the full story and recovery.

---

### Step 2 — OrderBeans: require the shared audience

✅ **Do.** In `Program.cs`'s `AddJwtBearer` setup, change `options.TokenValidationParameters.ValidateAudience = false` to `true` and set `options.TokenValidationParameters.ValidAudience = "phaseolus-internal-api"`.

**Verify.** The existing Cart → Checkout flow still works end-to-end (BeanApp's client-credentials token now carries the new audience from Step 1, so this should be a no-op in practice) — place a real order through BeanApp and confirm OrderBeans accepts it (`202`) same as before. Separately, confirm a token that does *not* carry the audience (e.g. one fetched directly from a different, ad-hoc test client, or simply the pre-Step-1 token shape if still cached) is rejected with `401`.

✅ **Done 2026-10-29 (live, against the dev cluster).** Isolated the audience check from issuer/signature validation by temporarily deleting and restoring Step 1's audience mapper around two in-cluster-fetched tokens (via a throwaway `curlimages/curl` pod hitting Keycloak's in-cluster DNS directly, so the issuer matches what OrderBeans expects):
- Correct issuer, **no** `phaseolus-internal-api` audience → `401`.
- Correct issuer, **with** the audience → `202`.
- No `Authorization` header at all → `401`.
- A first attempt using tokens fetched through the Keycloak *admin* port-forward (`localhost:18081`) produced a false failure on the "good" token too — that token's issuer was `http://localhost:18081/realms/...`, not the in-cluster DNS name OrderBeans validates against, so it was never really testing the audience check. Caught by checking OrderBeans' behavior against both a known-good and known-bad case rather than assuming the first 401 meant success.
- Confirmed the real path still works: placed an actual order through BeanApp's Cart → Checkout flow end-to-end, accepted normally.

---

### Step 3 — BeanNotifs: require a valid, admin-scoped token

✅ **Do.**
- Add `Keycloak:Authority` to `appsettings.json` and `deploy/deployment.yaml` (`Keycloak__Authority`), same in-cluster DNS value OrderBeans already uses — BeanNotifs has no `Keycloak` config section today.
- Add the same `AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(...)` block OrderBeans has, plus: `ValidateAudience = true` / `ValidAudience = "phaseolus-internal-api"` (Step 1), `MapInboundClaims = false`, and an `OnTokenValidated` event that maps `realm_access.roles` onto `ClaimTypes.Role` — the same mapping logic already in BeanApp's OIDC setup (`WebApp/Program.cs`), adapted to `JwtBearerEvents`.
- Change `app.MapGet("/notifications", ...)` to `.RequireAuthorization(policy => policy.RequireRole("admin"))` (needs `builder.Services.AddAuthorization()` too, which doesn't exist in this service yet).

**Verify.** `curl` with no `Authorization` header → `401`. `curl` with BeanApp's client-credentials token (valid audience, but no `admin` role — service accounts don't carry realm roles) → `403`. `curl` with a freshly-fetched admin user token (`admin`/`phaseolus`, Resource Owner Password grant for this one manual test, or copied from an active browser session) → `200` with the same notification data the Admin page shows today. Confirm `/healthz/live`, `/healthz/ready`, and `/metrics` remain unauthenticated (non-goal from `10_target_shape.md` — must not regress).

✅ **Done 2026-10-29 (locally, against port-forwarded RabbitMQ + Keycloak).** Tested via `dotnet run` rather than redeploying to the cluster -- `deploy/deployment.yaml` changed (new `Keycloak__Authority` env var), and applying that manually ahead of the PR merge would've raced against Argo CD's `selfHeal` reverting it (same class of issue hit testing BeanApp earlier). Running locally against the real port-forwarded RabbitMQ and Keycloak sidesteps that entirely.
- No `Authorization` header → `401`.
- BeanApp's client-credentials token (valid `phaseolus-internal-api` audience, no `admin` role) → `403`.
- A real admin token (temporarily enabled direct-access-grants on `beanapp-client` for this one fetch, reverted immediately after) → `200` (empty array, since this was a fresh local instance with no accumulated notifications -- not a bug).
- `/healthz/live` and `/metrics` confirmed still unauthenticated (`200`, no token).
- No errors in the local run's logs (RabbitMQ consumer connected fine against the port-forward).

---

### Step 4 — BeanApp: forward the admin's token, handle expiry

✅ **Do.** In `Admin.cshtml.cs`'s `OnGetAsync`:
- Retrieve the current request's access token via `HttpContext.GetTokenAsync("access_token")`.
- Replace the plain `GetFromJsonAsync` call with an explicit `HttpRequestMessage` carrying `Authorization: Bearer {token}` (same pattern `Checkout.cshtml.cs` already uses for the OrderBeans call), targeting BeanNotifs.
- On a `401` response specifically, set a distinct message — "Your session has expired — please log in again" — instead of falling into the existing generic `catch` (`10_target_shape.md`/Q2). Other failures (BeanNotifs unreachable, 5xx, etc.) keep the existing generic "Could not reach BeanNotifs" message.

**Verify.** Log in as `admin`, load `/Admin` — notifications render exactly as before (now carrying a real bearer token BeanNotifs actually checks). Manually expire the session (wait out the lifespan, or use Step 5's temporary short-lifespan trick) and reload `/Admin` — confirm the new "please log in again" message appears instead of the generic error, and that logging in again restores normal behavior.

✅ **Done 2026-10-29 (locally, BeanApp + BeanNotifs both via `dotnet run`, against port-forwarded Keycloak/RabbitMQ).** Ran both services together locally (same reasoning as Step 3 -- avoids racing Argo CD on `deploy/deployment.yaml` changes ahead of merge) so the real round trip could be observed:
- Logged in as `admin`, loaded `/Admin` -- BeanNotifs' own request metrics confirmed exactly one `200` response to `/notifications`, i.e. the forwarded token was genuinely accepted, not a silently-swallowed failure.
- Expiry case: Keycloak's default 5-minute `ClockSkew` tolerance meant a short-lived test token wasn't actually treated as expired within a reasonable wait, so this was verified precisely instead of waiting out a real 15-minute window -- temporarily set `accessTokenLifespan` to 5s and, in the **local test instance only**, `ClockSkew = TimeSpan.Zero` on BeanNotifs (never committed; discarded via `git checkout --` immediately after, confirmed clean against the Step 3 commit). With that, the stale token correctly produced a `401`, and `/Admin` showed "Your session has expired — please log in again" exactly as designed. Both the Keycloak lifespan and the BeanNotifs code were restored to their Step 1/3 state afterward.

---

### Step 5 — End-to-end live verification

✅ **Do.** Planned as "no code change, just a verification pass" — in practice this step found and fixed two real bugs that only a genuinely fresh cluster could expose. `minikube delete` + a full `setup.sh` re-run (with explicit user confirmation first, given the destructive teardown), building from each service's merged `main`.

**Verify / what actually happened, in order:**

1. **`setup.sh` itself wasn't runnable from this dev machine as-is** — it assumes a Linux VM (`apt-get`/`sudo` for `jq`); this Windows/Git-Bash environment has neither. Installed a standalone `jq.exe` into a user-writable PATH directory (no `setup.sh` change needed — this is a dev-machine gap, not a script bug, since the script's own doc comment says "a new Linux system").
2. **Keycloak crash-looped on the genuinely fresh pod** — see the amendment on Step 1 above. The chart's default `livenessProbe` (120s) was shorter than real cold-start time; kubelet killed it mid-Liquibase-migration, which left Postgres with a partially-applied schema change. The *next* start then failed for real (`column "description" ... already exists` — Liquibase trying to reapply a changeset its own tracking table didn't know had partially landed). Fixed by enabling the chart's `startupProbe` in `setup.sh` (suppresses liveness/readiness until the app is actually up, generous 310s tolerance) and wiping the corrupted Postgres PVC (safe — this was a from-scratch test cluster, not live data) so Keycloak could re-migrate cleanly. Re-ran `setup.sh` end to end afterward; the Keycloak section (realm/client/audience-mapper/role/token-lifespan, all the Step 1 pieces) now succeeds on the first try with no restarts.
3. **With the fresh cluster fully up, the five scenarios below were run in order:**
   - Cart → Checkout → OrderBeans: placed a real order, accepted (`202`).
   - Anonymous `curl` to `/notifications`: `401`.
   - BeanApp's client-credentials token (valid audience, no `admin` role): `403` — but only once fetched via the correct route (see bug below).
   - Logged-in admin's `/Admin` page: **failed the first time** — showed "session expired" immediately after a brand-new login. Root cause and fix below.
   - Expired-token UX: set `accessTokenLifespan` to 5s, logged in fresh, waited out Keycloak's real 5-minute clock-skew window (~6 minutes, not simulated), reloaded `/Admin` — "Your session has expired — please log in again" rendered correctly. Restored the realm to 900s afterward.
4. **Real bug found: BeanNotifs validated the wrong issuer.** `/notifications` only ever receives the admin's own browser-login token (forwarded as-is by Step 4), and Keycloak stamps that token with whichever host the *browser* used (`PublicAuthority`) — not the in-cluster DNS name (`Authority`) BeanNotifs uses to reach Keycloak for discovery. Same class of bug as BeanApp's own original login-loop issue; same fix (pin `ValidIssuer` to `PublicAuthority`, keep `Authority` for discovery/connectivity). This didn't surface in Steps 3/4's local testing because both services shared one Keycloak address there, masking the exact mismatch the real deployed topology has. Fixed in a new PR ([Timposter8107/M321_TBZ_Phaseolus_Notifs#6](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Notifs/pull/6)); OrderBeans needed no equivalent fix since it only ever receives *backend*-minted tokens (same host for both discovery and token issuance).
5. **Testing the fix required pausing Argo CD properly.** Patching just the `beannotifs` Application's `syncPolicy` wasn't enough — the root App-of-Apps reconciler restored it within about a minute (same behavior noted in the architecture plan's Step 13 incident). Paused `automated` sync on both `phaseolus-root` and `beannotifs` together, verified it held, applied the fix, confirmed it, then restored both to `{prune: true, selfHeal: true}` immediately after. No StatefulSets/PVCs were touched this time (unlike the Step 13 incident) — purely a stateless Deployment, low blast radius throughout.
6. **After the fix, all five scenarios passed cleanly**, including a second, independent token-expiry wait (the ~6-minute one in point 3 above, run against the fixed deployment).

**What this step validated about the methodology itself:** every prior step's local/isolated testing was honest about what it covered, and this step is exactly why `10_target_shape.md` asked for it — the gap between "works in a simplified local topology" and "works in the real deployed one" was real, not hypothetical.

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
