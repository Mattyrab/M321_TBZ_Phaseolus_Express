# 40 — Implementation

Step plan for the chosen option from `20_options.md`. **Do not start this phase while `30_open_questions.md` has any ⏳ items** — that's the discipline this folder structure exists to enforce.

Each step has a verification: how do we know the step is done? Strong verification turns the plan into a checklist you can run independently.

## Plan summary

Four steps. **Step 1 (idempotency) is independent of everything else** and goes first — lowest risk, touches only the already-shared consumer plumbing, no payload/spec dependencies. **Step 2 (payload evolution) must come before Step 3 (AsyncAPI specs)** — the specs need to describe the *final* shape, not the pre-fix one. **Step 4 (live verification) is last**, after everything else is merged, and is itself the rehearsal for the rubric's live-demo checklist item.

Step 2 is this plan's centerpiece: it both fixes the real `Email` drift `00_current_state.md` found (free, risk-free — `PayBeancoins` was always receiving `Email`, just not declaring it) *and* carries the genuine breaking-change demo (`OrderBeans` adds a new `DeliveryNote` field, deployed alone, proving to the rubric's Tolerant-Reader-sanctioned standard that existing, unmodified consumers keep working). These two changes are bundled in one step because they touch the same payload type, but they demonstrate two *different* halves of "isolated deployment" — a producer changing alone, and (separately, in Step 4's rehearsal) a consumer catching up alone — worth narrating as two distinct moments in the actual demo, not one.

## Steps

### Step 1 — `EventId` idempotency guard in all three consumers

⏳ **Do.** In each of `PayBeancoins`, `CookerBeaners`, `BeanNotifs`'s `Messaging/EventConsumerHostedService.cs` (identical copy-pasted plumbing in all three, per `00_current_state.md`), add an in-memory `HashSet<Guid>` (or `ConcurrentDictionary<Guid, byte>` if the consumer dispatch ever runs concurrently) of already-processed `EventId`s. In `HandleDeliveryAsync`, right after a message deserializes successfully and *before* calling `binding.Handler`: if `envelope.EventId` is already in the set, log it, `BasicAck` immediately, and return without invoking the handler — this is the "ignore duplicate messages" behavior the rubric names. On the handler's first successful completion, add the `EventId` to the set. No persistence, no eviction policy, no dead-letter exchange — per `10_target_shape.md`'s non-goals, an in-memory guard is sufficient at this project's demo scale.

**Verify.** Unit-level: none needed (the change is small enough to verify live). Live: see Step 4's redelivery test.

---

### Step 2 — Payload evolution: fix the `Email` drift, add `DeliveryNote`

⏳ **Do.**
- **The `Email` fix (closes the real drift):** `PayBeancoins/Models/PaymentModels.cs:6` — change `OrderCreatedPayload` from `(List<OrderItem> Items, decimal TotalAmount)` to `(List<OrderItem> Items, decimal TotalAmount, string Email)`, matching what `OrderBeans` already sends. No handler logic changes — `PayBeancoins` still doesn't *use* `Email`, it now just correctly declares what it receives.
- **The `DeliveryNote` addition (the actual breaking-change demo):**
  - `OrderBeans/Models/OrderModels.cs` — add `string? DeliveryNote` to both `CreateOrderRequest` and `OrderCreatedPayload`.
  - `OrderBeans/Program.cs:41-57` (`POST /orders`) — pass `request.DeliveryNote` through into the constructed `OrderCreatedPayload`.
  - `BeanApp/WebApp/WebApp/Models/OrderModels.cs:6` — add `string? DeliveryNote` to its own `CreateOrderRequest` copy.
  - `BeanApp/WebApp/WebApp/Pages/Checkout.cshtml.cs` — add a `[BindProperty] public string? DeliveryNote { get; set; }`, pass it into the `CreateOrderRequest` constructed in `OnPostPayAsync` (`:60-63`).
  - `BeanApp/WebApp/WebApp/Pages/Checkout.cshtml` — one optional textarea input bound to `DeliveryNote`, next to the existing email field.
- **Deliberately not touched:** `PayBeancoins`, `CookerBeaners`, `BeanNotifs` do not need to know about `DeliveryNote` at all — that's the point. `CookerBeaners`/`BeanNotifs` don't even deserialize `order.created`'s payload (per `00_current_state.md`'s routing table), so they're doubly unaffected.

**Verify.** `dotnet build` clean in `OrderBeans`, `PayBeancoins`, and `WebApp`. Live verification (the actual isolated-deploy proof) is Step 4 — this step is just the code change.

---

### Step 3 — AsyncAPI specs for all five event types

⏳ **Do.** Add `docs/contracts/` to this meta repo (the project's existing shared/meta repo, satisfying the rubric's "versioniert im Shared-Repo" wording) with one AsyncAPI document per event type: `order.created.yaml`, `payment.succeeded.yaml`, `payment.failed.yaml`, `order.cooking-started.yaml`, `order.cooked.yaml`. Each describes the shared envelope (`EventId`, `EventType`, `OccurredAt`, `OrderId`) plus that event's payload schema, matching the *final* shapes after Step 2 — `order.created`'s spec documents `Email` (now correctly consumed) and `DeliveryNote` (optional, added in Step 2) together, with a short note on `DeliveryNote` explaining it's an additive, Tolerant-Reader-safe field that existing consumers may ignore.

**Verify.** Each YAML file is valid AsyncAPI (a linter if one's easy to reach for, otherwise a careful manual read against the spec format) and matches the actual C# record shapes byte-for-byte — cross-check each spec's fields against the corresponding `Models/*.cs` file named in `00_current_state.md`.

---

### Step 4 — Live verification (the demo rehearsal)

⏳ **Do.** No code change — this step *is* the verification, run against the real cluster, and doubles as the rehearsal for the rubric's live-demo checklist item ("Demonstration einer API-Änderung... während abhängige Services ohne Ausfall weiterfunktionieren").

**Verify.**
- **Idempotency:** capture one real message (e.g. a `payment.succeeded` delivery) from the running system, then manually re-publish the identical message (same `EventId`) via a throwaway script/pod. Confirm the receiving consumer's Prometheus counter does not increment a second time and no duplicate downstream effect occurs (no second notification logged, no second `order.cooking-started` published) — the dedup guard from Step 1 must visibly skip it.
- **Isolated producer deploy (the core demo):** with `PayBeancoins`/`CookerBeaners`/`BeanNotifs` still on their pre-Step-2 images, deploy only the new `OrderBeans` (+ `BeanApp`, so the UI field exists) image. Place a real order through BeanApp's checkout with a delivery note filled in. Confirm it completes end-to-end — payment, cooking, notification — with zero errors in any of the three untouched services' logs, proving they tolerate the new field without having been redeployed.
- **Isolated consumer deploy (the other half):** separately, deploy the fixed `PayBeancoins` (with the `Email` field now declared) on its own. Confirm it starts cleanly and continues processing orders normally — demonstrating a consumer can also be updated independently, in either order relative to the producer.
- **Regression — the baseline flow still works:** place one more real order with the delivery-note field left blank (confirms `DeliveryNote`'s optionality didn't break the existing path) and confirm the full order → pay → cook → notify chain completes exactly as it did before this plan, matching the regression bar every prior plan in this repo has held to.
- **Fresh-cluster reproducibility:** run `setup.sh` against a freshly deleted `minikube` cluster and confirm the system comes up with all of the above already true — same bar `../2026_10_sso-keycloak/`'s Step 5 and `../2026_10_sso-admin-uis/`'s Step 6 established.

## Rollback / blast radius

Every change in this plan is additive and backward-compatible by construction — new optional fields, a new in-memory dedup set, new documentation files. Nothing persists data, nothing migrates a schema, nothing removes a field any consumer currently relies on. Reverting any step is a plain code/doc revert in the relevant repo(s); there is no data-loss or corruption risk to plan around, unlike the stateful-release incidents named in the architecture plan's Step 13 and this plan's own sibling SSO plans.

## Quality gates before merging

- `dotnet build` clean in `OrderBeans`, `PayBeancoins`, `CookerBeaners`, `BeanNotifs`, and `WebApp` for every repo touched by a given step.
- Each AsyncAPI YAML file cross-checked by hand against its corresponding C# record — no automated contract test exists (deliberately out of scope, per `10_target_shape.md`'s non-goals), so this check is manual and must actually happen, not be assumed.
- Live verification per Step 4 against the dev `minikube` cluster — this project has no automated test suite; live verification is the established quality gate (same as every prior plan in this repo).
- Step 4's fresh-cluster run is the final gate, not a formality — matching the bar that caught real bugs in both prior SSO plans.

---

**Exit criterion:** Every step ✅, gates green, PR merged. Mark ✅ in `README.md` when complete and archive the folder per the project's plan-archive convention in `CLAUDE.md`.
