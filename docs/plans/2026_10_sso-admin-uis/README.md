# SSO for Admin UIs

⏳ **Status:** all open questions resolved. Direction: native per-tool integration, dedicated gate only for Prometheus. Bring Grafana, RabbitMQ, Prometheus, and Argo CD's web UIs under the same Keycloak-backed SSO as the application services.

## Why this exists

The `../2026_10_sso-keycloak/` plan brought BeanApp, OrderBeans, and BeanNotifs under proper Keycloak authentication. The four infrastructure UIs this project also stands up — Grafana, Prometheus, RabbitMQ's management console, and Argo CD — are untouched by that work: each is reachable only via `kubectl port-forward` and guarded by its own separate, tool-specific local admin login (different username/password per tool, none of them tied to Keycloak or the `admin` realm role already established). The user wants that extended so logging into these operator-facing tools goes through the same identity, not a grab-bag of per-tool credentials.

## Index

- 📎 [`inputs.md`](./inputs.md) — user's source framing (verbatim)
- ✅ [`00_current_state.md`](./00_current_state.md) — what exists in the codebase today
- ✅ [`10_target_shape.md`](./10_target_shape.md) — what the change must produce
- ✅ [`20_options.md`](./20_options.md) — design options with pros/cons
- ✅ [`30_open_questions.md`](./30_open_questions.md) — decisions that block implementation (4 questions, all resolved)
- ⏳ [`40_implementation.md`](./40_implementation.md) — step plan
- ⏳ [`50_followups.md`](./50_followups.md) — out-of-scope items parked for later

## Status legend

- ✅ resolved / done
- ⏳ open / in flight
- ❌ rejected / dropped
- ⚠️ blocked / risk

Update an entry's emoji as the corresponding phase changes state.
