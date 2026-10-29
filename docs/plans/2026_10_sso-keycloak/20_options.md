# 20 — Options

Design alternatives that satisfy `10_target_shape.md`. **At least three.** If you can only think of one, the problem isn't framed yet — go back to `10`. Each rejected option needs a stated reason; "didn't pick it" is not a reason.

The core fork: when BeanApp calls another service *on behalf of the logged-in admin* (today: the Admin page's call to BeanNotifs), what credential does it present, and how does the downstream service decide "this request is allowed"? OrderBeans' own call (Cart → Checkout, always anonymous-shopper-triggered, never admin-triggered) keeps using client-credentials either way — none of these options touch that flow, they only tighten its audience validation per `10_target_shape.md`.

## Option A — Forward the admin's own Keycloak token

**Shape.** BeanApp's OIDC login already has `SaveTokens = true`, so the access token Keycloak issued the admin at login time is sitting in the auth cookie. When `Admin.cshtml.cs` calls BeanNotifs, it retrieves that token (`HttpContext.GetTokenAsync("access_token")`) and sends it as a `Bearer` header, unchanged. BeanNotifs adds the same `AddJwtBearer` setup OrderBeans already has, plus two checks OrderBeans is missing: a required-role check (`RequireRole("admin")` or a custom policy) and audience validation. The credential reaching BeanNotifs is literally the admin's own session token — the same one minted when they logged in.

**Pros.**
- Most literal match for "SSO ... with the established admin": one login produces one credential, and that same credential is what's checked downstream — not a second, service-level identity standing in for the admin.
- Reuses infrastructure that already exists (`SaveTokens = true` is already set; nothing new to configure on the token-issuing side).
- Downstream services can tell *a specific authenticated admin* made the request, not just "some request came from BeanApp" — the token's claims (`sub`, `preferred_username`, `realm_access.roles`) are the real user's.

**Cons.**
- Access tokens are short-lived (observed `expires_in: 300` — 5 minutes) and BeanApp isn't refreshing them. If an admin leaves `/Admin` open past that window, the next load's call to BeanNotifs fails with 401 until they log in again. Acceptable for a demo, but a real nuisance for sustained use.
- Forwarding a user's own access token between internal services is something OAuth2 practice generally steers away from (the "textbook" answer for this is token exchange — Option C below) — fine at this project's scale, but worth naming as a shortcut being taken deliberately.

**Verdict.** ✅ selected — see Decision.

---

## Option B — Keep it service-to-service (client-credentials everywhere)

**Shape.** BeanApp calls BeanNotifs the same way it already calls OrderBeans: a client-credentials token for `beanapp-client`, carrying no information about which human triggered the call. BeanNotifs validates it exactly like OrderBeans does today, with the audience-validation gap closed (so it at least confirms the token was issued to `beanapp-client` specifically, not just "any client in the realm"). The only thing gating access to `/notifications` is "did this request come from BeanApp" — `[Authorize(Roles = "admin")]` on the BeanApp page remains the *only* place the admin's identity is ever checked.

**Pros.**
- Simplest change — BeanNotifs' auth setup becomes a near-copy of OrderBeans' existing, already-working `AddJwtBearer` block.
- No token-expiry-during-a-long-admin-session problem: service tokens get refreshed by `KeycloakTokenClient`'s existing caching logic, same as the OrderBeans call does today, independent of the admin's own login session length.
- No question of forwarding a user's token between services.

**Cons.**
- Doesn't actually extend SSO to BeanNotifs in any meaningful sense — it closes the "anonymous access" security hole, but the admin's identity never leaves BeanApp. This under-delivers on "SSO ... with the established admin" specifically, versus just "add auth to BeanNotifs."
- If BeanApp itself had a bug that let a non-admin reach the `OnGetAsync` handler (e.g. a missing `[Authorize]` attribute added later by mistake), BeanNotifs would have no independent way to catch that — the only admin check in the entire path lives in one place.

**Verdict.** ❌ rejected — closes the security hole `00_current_state.md` flagged, but doesn't meet the specific "with the established admin" framing from `inputs.md`; it's service-to-service hardening wearing an SSO label.

---

## Option C — Token exchange (on-behalf-of)

**Shape.** Use Keycloak's token-exchange grant (`urn:ietf:params:oauth:grant-type:token-exchange`): BeanApp presents the admin's access token plus its own client credentials to Keycloak, which mints a new, short-lived "exchanged" token for BeanNotifs' audience, carrying the admin's identity but minted fresh rather than forwarded as-is. BeanNotifs validates that exchanged token.

**Pros.**
- The architecturally "correct" OAuth2 answer to "service A needs to call service B on behalf of a logged-in user" — avoids passing the user's own token around, and each downstream audience gets a token scoped specifically to it.
- Sidesteps Option A's expiry problem somewhat (BeanApp could exchange for a fresh token per call rather than reusing the login-time one), and sidesteps Option B's "admin identity never leaves BeanApp" problem.

**Cons.**
- Keycloak's token-exchange feature has historically required extra realm/client configuration (and, depending on version, enabling a preview feature or specific client permissions) beyond anything this project's Keycloak setup currently does — meaningfully more moving parts to configure, document in `setup.sh`, and keep working.
- Solves a problem this project doesn't actually have: there is exactly **one** admin user (`00_current_state.md`), so the benefit token exchange provides over Option A — a verifiable, freshly-minted per-call identity assertion suitable for fine-grained multi-user audit — has no practical payoff here. Per `docs/CLAUDE.md`'s "Simplicity First" ("would a senior engineer say this is overcomplicated?"), adding this machinery for a single-admin demo is the textbook case of unrequested complexity.

**Verdict.** ❌ rejected — architecturally the most "correct" of the three, but solves a scale/audit problem this project doesn't have, at a real setup-complexity cost `10_target_shape.md`'s constraints (simplicity, `setup.sh` reproducibility) argue against.

---

## Decision

✅ **Selected:** Option A — forward the admin's own Keycloak token to BeanNotifs, validated there with role + audience checks.

**Why this over the others.** It's the only option that actually makes BeanNotifs' authorization decision depend on the logged-in admin's own credential, which is the specific thing `inputs.md` asked for ("SSO ... with the established admin") — Option B keeps the admin's identity trapped inside BeanApp, and Option C buys correctness this single-admin project has no use for at a setup-complexity cost that conflicts with `10_target_shape.md`'s constraints.

**What we're explicitly accepting.** A logged-in admin whose 5-minute access token expires mid-session will see the Admin page's BeanNotifs call start failing until they log in again — no silent refresh is being built. This is a fine failure mode for this project's scale (one admin, a demo/grading context) and is cheaper to accept than to engineer around; if it becomes a real problem later, it's a self-contained follow-up (refresh-token handling in BeanApp), not a reason to revisit this decision now.

---

**Exit criterion:** ≥3 options listed, one ✅ selected, others ❌ with reasons. Mark ✅ in `README.md` when complete.
