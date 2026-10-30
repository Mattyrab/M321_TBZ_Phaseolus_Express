# Message Contracts Hardening

⏳ **Status:** all open questions resolved. Direction: AsyncAPI specs per event (docs only, no runtime enforcement); breaking-change demo via Tolerant Reader (`OrderBeans` adds a new optional `DeliveryNote` field, deployed alone); the pre-existing `Email` drift gets fixed as free cleanup alongside it; the `EventId`-dedup idempotency guard goes into all three consumers, not just one. Closes the three most heavily-weighted (15 pts each, 45 of 100 total) gaps the grading-rubric audit found.

## Why this exists

A full audit against the project's grading rubric (`docs/LB3_Projektarbeit_WIR.md`) found that criteria 2 (Schnittstellendesign & Kontrakte), 3 (Asynchrone Entkopplung & Idempotenz), and 7 (Evolution & Breaking Change Handling) are each sitting at "Minimal" or just above — and each is worth 15 of the rubric's 100 points, the three joint-heaviest line items. All three are deeply technically intertwined: contracts define the payload shape, idempotency needs a stable identifier already present in that shape, and a believable breaking-change demo needs both a versioning scheme (from contracts) and safe redelivery handling (from idempotency) to be credible. Doing them as one plan avoids redesigning the message envelope three separate times.

## Index

- 📎 [`inputs.md`](./inputs.md) — user's source framing (verbatim)
- ✅ [`00_current_state.md`](./00_current_state.md) — what exists in the codebase today
- ✅ [`10_target_shape.md`](./10_target_shape.md) — what the change must produce
- ✅ [`20_options.md`](./20_options.md) — design options with pros/cons
- ✅ [`30_open_questions.md`](./30_open_questions.md) — decisions that block implementation (4 questions, all resolved)
- ✅ [`40_implementation.md`](./40_implementation.md) — step plan
- ⏳ [`50_followups.md`](./50_followups.md) — out-of-scope items parked for later

## Status legend

- ✅ resolved / done
- ⏳ open / in flight
- ❌ rejected / dropped
- ⚠️ blocked / risk

Update an entry's emoji as the corresponding phase changes state.
