# Inputs

The user's framing for this work, captured **verbatim**. Do not paraphrase, summarize, or "clean up" — interpretation belongs in `10_target_shape.md`, and we need the unfiltered source to check that interpretation later.

## Source

### Turn 1 — scoping question (this session, earlier)

> How functional is the API currently?

Answered inline (not part of this plan): zero — `M321_TBZ_Phaseolus_WebApp` ("BeanApp") has no controllers, no `[Route]`/`[HttpGet/Post]` attributes, no minimal-API endpoints; every Razor Page handler (`Index`, `Beans`, `Cart`, `Error`) is an empty `OnGet()`. The only non-trivial backend code is ASP.NET Core Identity's scaffolded Register/Login/Logout.

### Turn 2 — this plan's request

> Before planning, first context. I would like to use a similar API design for all services in this project, such that it can be copied und pasted with light modification for each service. Second, these services send messages which are queued using RabbitMQ and sent to the correct location. Third, services will be spun up as pods in Kuberenetes cluster. With this information, I would like to plan the API. The payloads will be json, which will be parsed for whatever details are needed per service. Use the occ-new-plan skill to draft the plan.

## Notes (optional)

- `occ-new-plan` is not an available skill in this environment (checked — not in the skill listing, invoking it returns "Unknown skill"). This plan instead manually follows the pre-existing plan-folder convention already established in this repo at `docs/plans/2026_09_phaseolus-architecture/` (same file set: `inputs.md`, `00_current_state.md`, `10_target_shape.md`, `20_options.md`, `30_open_questions.md`, `40_implementation.md`, `50_followups.md`, `README.md`).
- This plan is **scoped to the common API/project template shape** shared across the five services (BeanApp, OrderBeans, PayBeancoins, CookerBeaners, BeanNotifs) — it is the detailed design behind Step 5 of `../2026_09_phaseolus-architecture/40_implementation.md` ("Agree the service-repo convention, scaffold all five"), which that plan left as a one-paragraph placeholder.
- It does **not** re-litigate anything already resolved in `../2026_09_phaseolus-architecture/30_open_questions.md` (language/framework, RabbitMQ topology, manifest format, auth scope, payment mock rule) — those are treated as fixed inputs here, same as that plan treated the infra product choices as fixed.
- Today's date at plan creation: 2026-10-13.
