# 00 — Current state

What exists in the codebase **today**, before any change. The goal: a reader unfamiliar with this corner of the repo can follow links from this doc to the relevant code and understand what's there.

## Models / data shape

N/A — no code, schema, or data model exists anywhere in the system yet. Every repo (this one and the five service repos) is at scaffold stage: a `README.md` and a `.gitignore`, nothing else. There is nothing to reverse-engineer a data shape from; any model will be a `10_target_shape.md` / `20_options.md` decision, not an observation.

## Code paths involved

This meta repo (`M321_TBZ_Phaseolus_Express`, "Phaseolus Central"):
- `README.md` — one-paragraph pitch plus the current service/infra list and links to the five sub-repos.
- `docs/CLAUDE.md` — expanded restatement of the same list, plus the *why* (school module M321/TBZ, grading criterion is inter-service functionality over end-user features) and unrelated Claude-Code behavioral/branch-discipline guidance.
- `docs/plans/2026_09_phaseolus-architecture/` — this plan folder, created this session; no prior plans exist.
- No Kubernetes manifests, Helm charts, Argo CD Application definitions, CI config, or any infra-as-code exist in this repo yet.

Sub-repos (each under `github.com/Timposter8107/`, checked directly since they're outside this checkout):
- `M321_TBZ_Phaseolus_WebApp` ("BeanApp") — 2 commits, README says "Front end web application". No source files.
- `M321_TBZ_Phaseolus_Order` ("OrderBeans") — 3 commits, README says "Service handling ordering food." No source files.
- `M321_TBZ_Phaseolus_Pay` ("PayBeancoins") — 2 commits, README says "Service handling payments." No source files.
- `M321_TBZ_Phaseolus_Cooker` ("CookerBeaners") — 2 commits, README says "Service handling processing food." No source files.
- `M321_TBZ_Phaseolus_Notifs` ("BeanNotifs") — 2 commits, README says "Service handling notifications." No source files.

All five are one-line-README stubs: no application code, no Dockerfile, no dependency manifest (package.json/pom.xml/etc.), no tests. The repos exist and are named/scoped, nothing more.

## Behavior today

Nothing runs. There is no deployable artifact, no container image, no running service, and no local dev environment documented (no `docker-compose.yml`, no minikube setup script, no Helm values). The only "behavior" today is documentation: the root `README.md`/`CLAUDE.md` describe an *intended* architecture (RabbitMQ broker, Traefik gateway, Keycloak IAM, Prometheus/Grafana metrics, Argo CD deployment, Kubernetes/minikube orchestration) that has not been built or wired up anywhere.

## What's missing or awkward

- **No architecture decisions below the infra-product-name level.** We know *which products* will be used (RabbitMQ, Keycloak, Traefik, Prometheus/Grafana, Argo CD, minikube) but not how they compose: exchange/queue topology, which services need IAM-protected endpoints vs. internal-only, what gets scraped/dashboarded, how Argo CD watches which repos.
- **No defined service contracts.** OrderBeans → PayBeancoins → CookerBeaners → BeanNotifs is implied by the service names and by the "order → pay → cook → notify" line in `docs/CLAUDE.md`, but no message schemas, event names, or REST/queue boundaries are written down anywhere.
- **No repo-orchestration mechanism yet.** "Meta repo using Kubernetes to spin up pods with images from the various services" is the stated intent, but there is no manifest, Kustomize overlay, Helm umbrella chart, or Argo CD App-of-Apps that actually references the five sub-repos' images.
- **BeanApp (webapp) is on the service list in the README but was added inconsistently** — `docs/CLAUDE.md`'s service bullet list (as of this plan's `inputs.md` capture) didn't originally include it, then the root `README.md` was updated separately to add `BeanApp` and real GitHub links. The two docs should be treated as the current source of truth (root `README.md` has the live links); `docs/CLAUDE.md`'s wording may need a follow-up sync — flagged in `50_followups.md`, not fixed here since `00` is descriptive only.
- **Language/framework/hosting choices are entirely open** — nothing pins a language, web framework, container base image, or registry for any of the five services yet.

---

**Exit criterion:** A reader can navigate the relevant code from this doc alone. Mark ✅ in `README.md` when complete.

---

**Exit criterion:** A reader can navigate the relevant code from this doc alone. Mark ✅ in `README.md` when complete.
