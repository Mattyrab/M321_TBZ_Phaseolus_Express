# 20 — Options

Design alternatives that satisfy `10_target_shape.md`. **At least three.** If you can only think of one, the problem isn't framed yet — go back to `10`. Each rejected option needs a stated reason; "didn't pick it" is not a reason.

The core fork: how to make the message contracts "formal" without reintroducing a shared package (already rejected twice, per `10_target_shape.md`'s non-goals) or over-building beyond what the rubric actually asks for. The idempotency guard's exact shape and the specific event chosen for the breaking-change demo are smaller, more mechanical decisions that follow from whichever option here is picked — they're deferred to `30_open_questions.md`.

## Option A — AsyncAPI specs per event type, committed as docs (no runtime enforcement)

**Shape.** One AsyncAPI document per event type (e.g. `docs/contracts/order.created.yaml`, `payment.succeeded.yaml`, …), each describing the envelope + that event's payload schema, hand-maintained alongside the code. The `EventType` string gets a version suffix going forward for any event this plan changes (e.g. `"payment.succeeded.v2"` only if/when that payload changes — the other four stay as they are, per `10_target_shape.md`'s non-goals). Nothing validates a running service against these documents automatically; they're read, not executed.

**Pros.**
- Matches the rubric's Maximal bar for criterion 2 *literally*: "Formale Kontrakte (OpenAPI/AsyncAPI/Protobuf) versioniert im Shared-Repo." AsyncAPI specifically (not OpenAPI, which is REST-shaped) is the format built for describing pub/sub event schemas, so it fits this architecture's actual shape instead of being bent to fit.
- Pure documentation — no new package, build step, or runtime dependency in any of the four services. Fully compatible with the established copy-paste convention.
- Cheap: a handful of YAML files, no new library to learn, no wiring into `Program.cs`.

**Cons.**
- Nothing stops the spec and the code from drifting again later — the same way the current `Email` drift happened silently, a future edit to a payload record without a matching spec edit wouldn't be caught by anything. The spec becomes true by discipline, not by construction.

**Verdict.** ✅ selected — see Decision below.

---

## Option B — Lightweight markdown contract tables, no formal spec language

**Shape.** A single markdown file (or one per event) listing each event's fields as a table — name, type, required/optional, one-line description — hand-written in prose, no AsyncAPI/OpenAPI/Protobuf syntax at all.

**Pros.**
- Fastest to produce; zero new syntax for anyone on the team to learn; fully readable by anyone without any spec-format knowledge.

**Cons.**
- Doesn't satisfy the rubric's Maximal bar, which names specific formats (OpenAPI/AsyncAPI/Protobuf) — a markdown table reads as Ideal tier's "Kontrakte über Shared Code aber ohne formalen Kontrakt gelöst" at best, not "formale Kontrakte." This criterion is worth 15 of the rubric's 100 points; capping it at Ideal to save a small amount of YAML-writing effort over Option A is a poor trade.

**Verdict.** ❌ rejected — under-delivers against the explicit rubric wording for a marginal time saving over Option A.

---

## Option C — JSON Schema files plus runtime validation on publish/consume

**Shape.** A formal JSON Schema document per payload (not full AsyncAPI, just the schema), *and* each service loads its own schemas at startup and actually validates messages against them — rejecting or logging a loud error on a publish or receive that doesn't match, via a JSON-schema-validation library added to each service's `.csproj`.

**Pros.**
- The only option that would have actually *caught* the existing `Email` drift mechanically, at runtime, rather than requiring a human to notice it — closes the "spec can still silently drift from code" gap Option A accepts.

**Cons.**
- Meaningfully more work: a new library dependency in all four services, wiring validation into every publish and every consume call, deciding what happens on a validation failure (which itself risks becoming a second, parallel error-handling path next to the existing retry mechanism). This is contract-testing infrastructure, which `10_target_shape.md`'s non-goals explicitly parked for later (`../2026_10_docs-and-ci/`'s territory, if ever picked up) — the rubric's Maximal bar for criterion 2 doesn't require runtime enforcement, only that the contract be formal and versioned. Building it here would be solving a problem one tier above what's being graded.

**Verdict.** ❌ rejected — over-engineers relative to the actual rubric bar and this plan's own stated non-goals; the gap it closes (spec/code drift) is real but not what's being asked for.

---

## Decision

✅ **Selected:** Option A — AsyncAPI specs per event type, committed as documentation, no runtime enforcement.

**Why this over the others.** It's the only option that satisfies `10_target_shape.md`'s goal of a "formally-specified, discoverable payload shape" using *exactly* the vocabulary the rubric names for its top tier, at a cost proportionate to a plan that's also carrying the idempotency and breaking-change work. Option B would under-deliver on a 15-point criterion to save a small amount of effort; Option C would over-deliver on infrastructure this plan's own non-goals already ruled out.

**What we're explicitly accepting.** The spec is maintained by hand and can drift from the code again, the same way the payload records already did — this plan closes today's known gap but doesn't install a mechanism that prevents a new one from opening later. That's a real, named limitation, acceptable because automated contract enforcement was already placed out of scope in `10_target_shape.md`, not an oversight here.

---

**Exit criterion:** ≥3 options listed, one ✅ selected, others ❌ with reasons. Mark ✅ in `README.md` when complete.
