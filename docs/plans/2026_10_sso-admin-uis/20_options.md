# 20 — Options

Design alternatives that satisfy `10_target_shape.md`. **At least three.** If you can only think of one, the problem isn't framed yet — go back to `10`. Each rejected option needs a stated reason; "didn't pick it" is not a reason.

The core fork: given that Grafana, Argo CD, and RabbitMQ each already have their own first-class (or at least plugin-supported) way to talk OIDC/OAuth2 to an identity provider, while Prometheus structurally has none — should this plan use each tool's own native mechanism where one exists, or impose one uniform mechanism (a reverse proxy) across all four regardless of what each tool already supports? A third axis — doing fewer than all four tools — is also considered, since it's a real way to reduce risk even though it under-delivers on `inputs.md`'s literal ask.

## Option A — Native integration per tool, proxy only where Prometheus forces it

**Shape.** Configure each tool's own first-class mechanism: Grafana's `[auth.generic_oauth]` section (built into `grafana.ini`), Argo CD's `oidc.config`/`dex.config` fed to the Dex server that's already running unconfigured, and RabbitMQ's `rabbitmq_auth_backend_oauth2` plugin (already present in the image, currently disabled). Only Prometheus — which has no native auth of any kind — gets something new: a lightweight auth-gate (reverse proxy or Traefik `ForwardAuth` middleware) sitting in front of just its Service.

**Pros.**
- Leverages purpose-built, maintained integrations that already exist for 3 of the 4 tools — the RabbitMQ OAuth2 plugin and Argo CD's Dex server are already sitting there, built but unused, per `00_current_state.md`.
- Smallest blast radius per tool: a misconfiguration in Grafana's OIDC settings doesn't touch Argo CD, RabbitMQ, or Prometheus's gate, and vice versa.
- Each tool keeps its own native session/logout/user-display behavior (e.g. Argo CD showing the logged-in user's name) rather than an opaque passthrough.
- Directly matches `10_target_shape.md`'s framing: "Prometheus gets an equivalent access gate... not that Prometheus itself becomes OIDC-aware" — this option treats that as the exception, not the rule.

**Cons.**
- Four different configuration surfaces to learn and maintain (`grafana.ini` syntax, `argocd-cm` YAML + Dex connector config, `rabbitmq.conf`/`advanced.config` + a scope-to-tag mapping, plus whatever the Prometheus gate needs) — more distinct pieces in aggregate, even though each individual piece is simpler than building a proxy for everything.

**Verdict.** ✅ selected — see Decision.

---

## Option B — One uniform reverse-proxy/auth-gate in front of all four tools

**Shape.** Deploy a single auth-proxy (e.g. `oauth2-proxy`) plus Traefik `ForwardAuth` middleware in front of all four tools' Services — Grafana, RabbitMQ management, Prometheus, *and* Argo CD. None of the tools' own native OIDC/OAuth2 support gets configured; they stay on local-admin-only config, simply unreachable except through the proxy.

**Pros.**
- One mechanism, one Keycloak client, one codebase/config surface to understand and debug — conceptually simpler to reason about than four different integrations, even though more infrastructure has to be built up front.
- Handles Prometheus the same way as the other three — no special case at the architecture level (though the IngressRoute/Middleware plumbing is still new work for all four either way, since none exists today).

**Cons.**
- Throws away native integrations that are objectively simpler than building and operating a reverse proxy for 3 of the 4 tools — reinventing what Grafana and Argo CD already do well, and ignoring a RabbitMQ plugin that's already in the image.
- The proxy becomes a single point of failure for *all four* tools at once, where Option A's per-tool failures stay isolated.
- Loses each tool's native session/user-display/logout behavior — Argo CD and Grafana's own OIDC integrations show who's logged in and support real logout; a transparent forward-auth proxy typically doesn't surface that to the tool itself.
- Needs exactly the same new Traefik `IngressRoute`-per-tool plumbing Option A's Prometheus piece needs anyway (`00_current_state.md`: zero IngressRoutes exist for any of the four today) — so the "simpler infra" framing doesn't hold once all four tools need routing either way.

**Verdict.** ❌ rejected — pays the full cost of building new reverse-proxy infrastructure for *every* tool while discarding native support that already exists (and is already partially built, per `00_current_state.md`) for three of them, for a "one mechanism" benefit that matters more at a scale (many services, many teams) this project doesn't have.

---

## Option C — Grafana and Argo CD only; park RabbitMQ and Prometheus

**Shape.** Implement only the two tools with the lowest-friction native OIDC support — Grafana's `generic_oauth` and Argo CD's `oidc.config`/Dex — since both are well-trodden, low-risk configuration changes. File RabbitMQ (touches the broker's auth stack, which every service's AMQP connection depends on) and Prometheus (needs brand-new reverse-proxy infrastructure that doesn't exist yet) in `50_followups.md` instead.

**Pros.**
- Much smaller, lower-risk change — avoids touching RabbitMQ's auth configuration at all (relevant given the architecture plan's Step 13 incident and its explicit caution about infra Helm changes to stateful releases) and avoids building new infrastructure (a reverse proxy) that doesn't exist anywhere in this project today.
- Delivers real value with near-zero regression risk to the two tools where "SSO" is closest to a config flag.

**Cons.**
- Directly under-delivers against `inputs.md`'s literal request, which names all four tools individually ("Grafana, RabbitMQ, Prometheus, and Argo CD") — this isn't a simplification of *how* to satisfy the ask, it's declining to satisfy two-fourths of it.

**Verdict.** ❌ rejected — the risk-reduction is real, but the user asked for all four by name; deferring two of them isn't this plan's call to make unilaterally. (If the user wants to phase it this way after seeing `30_open_questions.md`, that's a legitimate scope-narrowing decision to make explicitly there — not something to decide silently in `20_options.md`.)

---

## Decision

✅ **Selected:** Option A — native integration per tool (Grafana OIDC, Argo CD Dex/OIDC, RabbitMQ OAuth2 plugin), with a dedicated access gate built only for Prometheus, where no native option exists.

**Why this over the others.** It's the only option that satisfies `10_target_shape.md`'s explicit constraint ("minimum config that solves the problem") while still covering all four tools named in `inputs.md`. Option B pays to build the same new infrastructure Option A needs for Prometheus anyway, but pays it four times over and throws away working native support in the process. Option C is lower-risk but silently drops two of the four tools the user explicitly asked for.

**What we're explicitly accepting.** Four distinct configuration surfaces instead of one uniform mechanism — more moving parts to document and keep working (especially across a `setup.sh` fresh-cluster rebuild, per `10_target_shape.md`'s reproducibility requirement) than a single proxy would be. This is a real cost, named and accepted because each individual piece is still simpler than the alternative, and it's directly reversible per-tool if one integration turns out to be more trouble than it's worth.

---

**Exit criterion:** ≥3 options listed, one ✅ selected, others ❌ with reasons. Mark ✅ in `README.md` when complete.
