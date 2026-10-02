# Inputs

The user's framing for this work, captured **verbatim**. Do not paraphrase, summarize, or "clean up" — interpretation belongs in `10_target_shape.md`, and we need the unfiltered source to check that interpretation later.

## Source

### Turn 1 — original project framing (earlier session)

> I am currently tasked with developing a simple microservice architecture project for school, which includes a message broker, IAM, metrics and monitoring, and deployment. My current ideas involve using a meta github repo for the orchestration via Kubernetes, with sub repos representing various services.
>
> The functionality and operation between systems is more important than what features are provided by the services for the end user.
>
> What I need is an Idea on what exactly I should make that meets these requirements. I'm thinking of either a messaging system or online ordering system (such as for a shop or restaurant)

### Turn 2 — this session, kicking off planning

> Alrighty, start planning a rough first draft of the project, no code yet.

## Notes (optional)

- School module: M321, TBZ. This repo (`M321_TBZ_Phaseolus_Express`) is the meta/orchestration repo, "Phaseolus Central".
- Following Turn 1, the decision landed on the online-ordering/shop domain, themed as "Phaseolus Express" (bean-food ordering, bean puns throughout). This decision and the resulting service/infra list are already recorded in `README.md` and `docs/CLAUDE.md` at the repo root — treat those as the current decided state, not as options still open in `20_options.md`.
- Today's date at plan creation: 2026-09-25.
