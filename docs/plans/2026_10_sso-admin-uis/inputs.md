# Inputs

The user's framing for this work, captured **verbatim**. Do not paraphrase, summarize, or "clean up" — interpretation belongs in `10_target_shape.md`, and we need the unfiltered source to check that interpretation later.

## Source

### 2026-10-29, chat

> Further expand the SSO to Grafana, RabbitMQ, Prometheus, and Argo CD UI

## Notes (optional)

Follows directly on from `../2026_10_sso-keycloak/`, which brought BeanApp/OrderBeans/BeanNotifs under proper Keycloak auth (completed and merged). This request extends the same idea to the four infrastructure UIs the project already stands up (Grafana and Prometheus from `kube-prometheus-stack`, RabbitMQ's management UI, Argo CD's own UI) — currently all reachable only via `kubectl port-forward` with their own separate local admin credentials (see `../2026_09_phaseolus-architecture/` and `setup.sh` for how each is installed/configured today). The user hasn't specified depth (e.g. whether Prometheus — which has no native auth support at all — should get a reverse-proxy, or be explicitly left out) or role/access requirements per tool; that's for `10_target_shape.md` and `30_open_questions.md` to pin down.
