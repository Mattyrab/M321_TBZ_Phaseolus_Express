# SSO for Admin UIs

⏳ **Status:** executing `40_implementation.md`. Steps 1–2 done (Keycloak clients, Grafana). Step 3 (Argo CD) found a real architecture limit live — Argo CD can't split the browser-facing/in-cluster Keycloak addresses the way Grafana can — and the user chose to accept that limitation rather than make the Windows hosts-file edit the only fix needs; Argo CD keeps its local admin login (see `40_implementation.md` Step 3, `50_followups.md`). Step 4 (RabbitMQ) hit a harder wall — RabbitMQ's oauth2 plugin hard-requires HTTPS for Keycloak — but this one *was* fixable: a small self-signed TLS route via the already-running Traefik, plus one small (user-approved) Keycloak proxy-header setting, now live-verified end-to-end including a real placed order. Steps 5–6 (Prometheus, fresh-cluster verification) remain. Working Keycloak SSO: Grafana, RabbitMQ. Argo CD: investigated, documented, parked.

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
