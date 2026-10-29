# Inputs

The user's framing for this work, captured **verbatim**. Do not paraphrase, summarize, or "clean up" — interpretation belongs in `10_target_shape.md`, and we need the unfiltered source to check that interpretation later.

## Source

### 2026-10-29, chat

> Excellent. Next up, I would like to setup a proper SSO for all services using keycloak with the established admin in thewebapp. Draft up a plan to implement this.

## Notes (optional)

"the established admin in thewebapp" refers to the admin-login feature already implemented in BeanApp this session (Keycloak Authorization Code flow, `admin`/`phaseolus` user with the `admin` realm role, gating the `/Admin` page via `[Authorize(Roles = "admin")]`) — see `../2026_09_phaseolus-architecture/` for that history. The user hasn't yet specified which services/endpoints need to be brought under SSO, or what "proper" means precisely (e.g. whether this covers service-to-service calls, which already use Keycloak client-credentials tokens for OrderBeans today). That's for `10_target_shape.md` and `30_open_questions.md` to pin down.
