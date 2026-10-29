# 30 — Open questions

Specific decisions that block implementation. Each question has a clear path to resolution. **No vibes-questions** ("is this a good idea?") — split those into the underlying yes/no decisions.

Resolve every question to ✅ or ❌ before starting `40_implementation.md`. If a question can't be answered now, either move it to `50_followups.md` (out of scope) or mark it ⚠️ blocked with a named blocker.

## Questions

### Q1 — One shared audience, or a distinct audience per protected service?

✅ **Question.** When `beanapp-client`'s tokens get a real audience claim (closing the "any realm token is accepted" gap from `00_current_state.md`), should there be **one** shared audience value (e.g. `phaseolus-internal-api`) that both OrderBeans and BeanNotifs validate against, or a **distinct** audience per service (e.g. `orderbeans-api`, `notifs-api`) that each only accepts its own?

**Why it matters.** This determines how many Keycloak protocol mappers/client scopes `40_implementation.md` needs to create, and what `ValidAudience` string gets hardcoded into each service's `AddJwtBearer` config. Since there's only one client (`beanapp-client`) issuing every token in the system today, a distinct-per-service audience adds configuration without adding real security *right now* (it would only matter once a second client exists) — but it's the more future-proof shape if more services or clients join later.

**Resolution.** ✅ 2026-10-29 — one shared audience value, `phaseolus-internal-api`. A single client-level audience mapper on `beanapp-client`, validated identically by OrderBeans and BeanNotifs.

---

### Q2 — What happens on the Admin page when the admin's token has expired?

✅ **Question.** `20_options.md`'s selected design means a logged-in admin's BeanNotifs call can start failing with 401 once their 5-minute access token expires, while their BeanApp cookie session is still otherwise valid (`20_options.md`'s accepted tradeoff). Should `Admin.cshtml.cs` detect this specific case and do something about it (e.g. show "Your session has expired — please log in again" with a link that re-triggers the Keycloak challenge), or should it fall through to the existing generic `catch` that currently shows "Could not reach BeanNotifs" for any failure?

**Why it matters.** `10_target_shape.md` requires the Admin page to keep working end-to-end — if a confusing generic error is what an admin sees every ~5 minutes, that's a real usability regression even though the underlying security behavior (reject expired tokens) is correct. This is a small, bounded piece of `40_implementation.md`'s BeanApp work either way; it just needs to be decided before writing that step.

**Resolution.** ✅ 2026-10-29 — detect the 401 specifically and show "Your session has expired — please log in again," distinct from the generic "Could not reach BeanNotifs" message used for other failures (e.g. the service being down).

---

### Q3 — Leave Keycloak's default access-token lifespan, or extend it for this project?

✅ **Question.** Keycloak's default access token lifespan (observed as 5 minutes against this realm) drives how often Q2's expiry case is actually hit. Should this plan extend `phaseolus` realm's (or just `beanapp-client`'s) access token lifespan to something longer — e.g. 15–30 minutes — to make the demo/grading experience smoother, or leave Keycloak's default as-is and accept 5-minute re-logins as part of "what we're explicitly accepting" per `20_options.md`?

**Why it matters.** This is a one-line Keycloak realm/client setting (`40_implementation.md` either includes it or doesn't), but it directly trades off against the security principle of short-lived tokens — worth a deliberate choice rather than defaulting silently either way. It also affects how annoying Q2's fallback behavior will be in practice: a good Q2 answer matters less if tokens rarely expire mid-session, and matters more if they don't.

**Resolution.** ✅ 2026-10-29 — extend to 15 minutes (realm-level `accessTokenLifespan`), balancing a smoother demo experience against keeping tokens reasonably short-lived.

---

**Exit criterion:** Every question is ✅ resolved, ❌ dropped, or ⚠️ blocked-with-blocker. Mark ✅ in `README.md` when complete.
