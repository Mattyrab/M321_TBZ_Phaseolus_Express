# SSO via Keycloak

⏳ **Status:** implementation plan drafted (5 steps), not yet executed. Direction: forward the admin's own token to BeanNotifs. Bring all five Phaseolus services under proper Keycloak-backed single sign-on, building on the admin login already working in BeanApp.

## Why this exists

The user wants "proper SSO for all services using Keycloak with the established admin in the webapp" (see `inputs.md`). Today, only BeanApp has real Keycloak integration: an Authorization Code login flow for the `/Admin` page, and a client-credentials token used to call OrderBeans. OrderBeans validates that bearer token; PayBeancoins, CookerBeaners, and BeanNotifs have no Keycloak awareness at all, and BeanNotifs' `/notifications` endpoint (which the Admin page reads) is open with no auth. What "all services" should mean here — and how far "proper SSO" extends beyond what already exists — is exactly what this plan needs to pin down.

## Index

- 📎 [`inputs.md`](./inputs.md) — user's source framing (verbatim)
- ✅ [`00_current_state.md`](./00_current_state.md) — what exists in the codebase today
- ✅ [`10_target_shape.md`](./10_target_shape.md) — what the change must produce
- ✅ [`20_options.md`](./20_options.md) — design options with pros/cons
- ✅ [`30_open_questions.md`](./30_open_questions.md) — decisions that block implementation (3 questions, all resolved)
- ⏳ [`40_implementation.md`](./40_implementation.md) — 5-step plan: Keycloak audience/lifespan + `setup.sh` fix, OrderBeans tightening, BeanNotifs auth, BeanApp token-forwarding, end-to-end verification
- ⏳ [`50_followups.md`](./50_followups.md) — out-of-scope items parked for later

## Status legend

- ✅ resolved / done
- ⏳ open / in flight
- ❌ rejected / dropped
- ⚠️ blocked / risk

Update an entry's emoji as the corresponding phase changes state.
