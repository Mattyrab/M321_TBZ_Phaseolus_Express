# 50 — Followups

The parking lot. Anything that came up while working on this plan but is **out of scope** for the current PR.

This file exists so the conversation doesn't bloat the current plan. When something interesting surfaces — a related refactor, an adjacent bug, a future feature, a test gap — drop it here in one bullet and move on.

## Out of scope, parked for later

- ⏳ Real Traefik ingress for OrderBeans, PayBeancoins, CookerBeaners, and BeanNotifs. Only BeanApp has one today (`10_target_shape.md` non-goal) — everything else is reached via `kubectl port-forward`, which is also why `Keycloak:PublicAuthority` is hardcoded to `http://localhost:8180/...` in both BeanApp and BeanNotifs. Building real ingress would let that value become an actual hostname instead of a dev-machine port-forward address.
- ⏳ Silent token refresh for the admin session. `20_options.md`'s selected design explicitly accepts that a 15-minute access token expiring mid-session forces a re-login (`30_open_questions.md` Q2/Q3) — fine at this project's scale, but a real improvement would use the refresh token already available (`SaveTokens = true`) to renew silently instead of surfacing "please log in again."
- ⏳ OAuth2 token exchange (`20_options.md` Option C, rejected). Explicitly rejected because there's only one admin user today and the added Keycloak configuration complexity isn't worth it for that — revisit only if a second admin (or any multi-user audit requirement) is ever added.
- ⏳ Splitting `beanapp-client` into separate interactive-login and service-credential clients (`20_options.md`'s Decision, named as a non-goal). Fine as one client at this scale; would matter if more services/clients join the picture.

---

## Promoted to their own plan

<When a parked item gets serious enough to need its own folder, link the new plan here and tick the original entry ✅. Don't delete the entry — the trail matters.>

- e.g. ✅ "Allocation layer" → see `docs/plans/2026_06_allocation/`

---

**Exit criterion:** N/A — this file lives forever as a record of what was deferred. No status emoji needed in `README.md`'s index for this one beyond ⏳ (always open).
