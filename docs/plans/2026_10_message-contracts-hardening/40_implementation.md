# 40 — Implementation

Step plan for the chosen option from `20_options.md`. **Do not start this phase while `30_open_questions.md` has any ⏳ items** — that's the discipline this folder structure exists to enforce.

Each step has a verification: how do we know the step is done? Strong verification turns the plan into a checklist you can run independently.

## Plan summary

Four steps. **Step 1 (idempotency) is independent of everything else** and goes first — lowest risk, touches only the already-shared consumer plumbing, no payload/spec dependencies. **Step 2 (payload evolution) must come before Step 3 (AsyncAPI specs)** — the specs need to describe the *final* shape, not the pre-fix one. **Step 4 (live verification) is last**, after everything else is merged, and is itself the rehearsal for the rubric's live-demo checklist item.

Step 2 is this plan's centerpiece: it both fixes the real `Email` drift `00_current_state.md` found (free, risk-free — `PayBeancoins` was always receiving `Email`, just not declaring it) *and* carries the genuine breaking-change demo (`OrderBeans` adds a new `DeliveryNote` field, deployed alone, proving to the rubric's Tolerant-Reader-sanctioned standard that existing, unmodified consumers keep working). These two changes are bundled in one step because they touch the same payload type, but they demonstrate two *different* halves of "isolated deployment" — a producer changing alone, and a consumer catching up alone — narrated as two distinct moments in the actual demo, not one.

**Post-execution note:** the isolated-deploy proof originally planned for Step 4 ended up happening live during Step 2's own PR work instead, as each change was built — a stronger result than planned (proven as real as it gets, not just rehearsed afterward). Step 4 then re-verified idempotency and the full chain on the *final, fully-merged* state and added the fresh-cluster reproducibility run.

## Steps

### Step 1 — `EventId` idempotency guard in all three consumers

✅ **Done.** Added a `ConcurrentDictionary<Guid, byte>` of already-processed `EventId`s to `Messaging/EventConsumerHostedService.cs` in `PayBeancoins`, `CookerBeaners`, and `BeanNotifs` (identical copy-pasted plumbing, patched identically in each). Checked before invoking the handler; recorded only after it succeeds. PRs: [Pay #5](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Pay/pull/5), [Cooker #5](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Cooker/pull/5), [Notifs #7](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Notifs/pull/7).

**Verified live** (not deferred to Step 4 as originally planned — proven immediately on each PR): captured a real message via a temporary queue binding, manually re-published it (same `EventId`) to the exchange, confirmed the receiving service's Prometheus counter did not move a second time and logs showed the duplicate being skipped. Done independently on `PayBeancoins` (`payments_succeeded_total`) and `BeanNotifs` (`notifications_sent_total`); `CookerBeaners` verified by code identity + clean build, given the byte-identical guard logic.

---

### Step 2 — Payload evolution: fix the `Email` drift, add `DeliveryNote`

✅ **Done.** PRs: [Pay #6](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Pay/pull/6) (`Email` fix), [Order #6](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Order/pull/6) (`DeliveryNote`), [WebApp #10](https://github.com/Timposter8107/M321_TBZ_Phaseolus_WebApp/pull/10) (`DeliveryNote` UI). Exactly as planned — `Email` added to `PayBeancoins`' `OrderCreatedPayload`; `DeliveryNote` (optional) added to `OrderBeans`'/`BeanApp`'s records, wired through `Program.cs` and `Checkout.cshtml`/`.cs`. `CookerBeaners`/`BeanNotifs` untouched, as intended.

**Verified live, the isolated-deploy proof (moved up from Step 4, done here instead):**
- Deployed `OrderBeans`+`BeanApp` alone, `PayBeancoins` left on its pre-fix image. Placed a real order through BeanApp's actual checkout form with a delivery note. Captured the resulting message via a temporary queue binding — confirmed `DeliveryNote` present on the wire. Confirmed zero errors in `PayBeancoins`' logs and `payments_succeeded_total` incremented normally, proving the untouched consumer tolerates the new field.
- Separately deployed `PayBeancoins`'s `Email` fix alone. Confirmed it started clean and continued processing a fresh real order correctly — the other half of "isolated deployment," a consumer updating independently of the producer.

---

### Step 3 — AsyncAPI specs for all five event types

✅ **Done.** [PR #23](https://github.com/Mattyrab/M321_TBZ_Phaseolus_Express/pull/23). Added `docs/contracts/` with one AsyncAPI 2.6.0 spec per event type plus a short README, matching the final post-Step-2 shapes (`order.created` documents both `Email` and `DeliveryNote` together).

**Verified:** all five files pass `npx @asyncapi/cli validate` with 0 errors (only cosmetic governance warnings — missing optional `operationId`/`messageId`/`contact`/`license`/`tags`). Each schema cross-checked by hand against its corresponding C# record.

---

### Step 4 — Live verification (the demo rehearsal)

✅ **Done.**

**Isolated producer/consumer deploys were actually proven during Step 2's own PRs, live, as they were built** — not deferred to this step as originally planned: `OrderBeans`+`BeanApp` were deployed alone (with `PayBeancoins` left on its pre-Step-2 image) and a real order with a delivery note was placed and completed end-to-end with zero errors in the untouched service; then `PayBeancoins`'s `Email` fix was deployed on its own and confirmed to start clean and keep processing orders. See Step 2's "Done" notes and its PRs' test plans for that evidence. Step 4 re-confirmed both fields working *together* on the fully-merged state (see below) rather than re-staging the isolation a second time.

**What Step 4 itself verified, against the fully-merged system:**
- **Idempotency on the final state:** placed a real order (`OrderBeans` directly), captured the resulting `order.created` message (now carrying both `Email` and `DeliveryNote`) via a temporary queue binding, manually re-published the identical payload (same `EventId`) to the exchange. `payments_succeeded_total` did not move a second time; logs showed `"Duplicate delivery... already processed, skipping"`.
- **Regression — the baseline flow:** placed a plain order with no `DeliveryNote` field in the request body at all (confirms the optional parameter's default works for genuinely omitted data, not just an explicit null) and confirmed the full order → pay → cook → notify chain completed (`orders_cooking_started_total`, `orders_cooked_total`, `notifications_sent_total` all incremented correctly).
- **Fresh-cluster reproducibility:** ran `minikube delete` + `setup.sh` from scratch. Came up clean on the first try — no bugs found, unlike both prior SSO plans' fresh-cluster runs. All 5 services `Running`, all 7 Argo CD Applications `Synced`/`Healthy`. Re-ran the idempotency redelivery test and a full order (with `DeliveryNote`) against this freshly built cluster independently — both passed identically to the pre-rebuild cluster, confirming nothing in this plan depends on manual/non-scripted setup steps.

**Note:** `setup.sh` itself needed zero changes for this plan — every change was pure application code (4 service repos) plus documentation (AsyncAPI specs); there was no new infra/Helm/Keycloak config to script.

## Rollback / blast radius

Every change in this plan is additive and backward-compatible by construction — new optional fields, a new in-memory dedup set, new documentation files. Nothing persists data, nothing migrates a schema, nothing removes a field any consumer currently relies on. Reverting any step is a plain code/doc revert in the relevant repo(s); there is no data-loss or corruption risk to plan around, unlike the stateful-release incidents named in the architecture plan's Step 13 and this plan's own sibling SSO plans.

## Quality gates before merging

- `dotnet build` clean in `OrderBeans`, `PayBeancoins`, `CookerBeaners`, `BeanNotifs`, and `WebApp` for every repo touched by a given step.
- Each AsyncAPI YAML file cross-checked by hand against its corresponding C# record — no automated contract test exists (deliberately out of scope, per `10_target_shape.md`'s non-goals), so this check is manual and must actually happen, not be assumed.
- Live verification per Step 4 against the dev `minikube` cluster — this project has no automated test suite; live verification is the established quality gate (same as every prior plan in this repo).
- Step 4's fresh-cluster run is the final gate, not a formality — matching the bar that caught real bugs in both prior SSO plans.

---

**Exit criterion:** Every step ✅, gates green, PR merged. Mark ✅ in `README.md` when complete and archive the folder per the project's plan-archive convention in `CLAUDE.md`.
