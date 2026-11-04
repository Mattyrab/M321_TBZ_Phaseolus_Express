# 50 — Followups

The parking lot. Anything that came up while working on this plan but is **out of scope** for the current PR.

This file exists so the conversation doesn't bloat the current plan. When something interesting surfaces — a related refactor, an adjacent bug, a future feature, a test gap — drop it here in one bullet and move on.

## Out of scope, parked for later

- ⏳ **No scripted/documented way to temporarily test against a live Argo CD-managed Deployment without fighting self-heal.** Found during Step 2: the App-of-Apps structure (`phaseolus-root` → `orderbeans`/`paybeancoins` Applications → their Deployments) has `selfHeal: true` at every level, so a direct `kubectl apply`/`kubectl patch` on a managed resource — or even on a child Application's own `syncPolicy`, trying to disable its self-heal — gets silently reverted by the level above. Worked around it this time with standalone unmanaged pods (see `40_implementation.md` Step 2's Result), but there's no written-down, repeatable recipe for this (e.g. a documented `argocd app set <name> --sync-policy none` + restore sequence) — worth one if this comes up again. **Confirmed still an issue in Step 5**: a `kubectl scale --replicas=0` on PayBeancoins (for a deliberate-failure trace test) got reverted by self-heal within ~15 seconds, too fast to race against reliably — worked around by using an application-level failure path (PayBeancoins' "Rotten Beans" simulation) instead of an infrastructure-level one, which happened to produce a clearer result anyway, but the underlying self-heal friction is still unaddressed.

---

## Promoted to their own plan

<When a parked item gets serious enough to need its own folder, link the new plan here and tick the original entry ✅. Don't delete the entry — the trail matters.>

- e.g. ✅ "Allocation layer" → see `docs/plans/2026_06_allocation/`

---

**Exit criterion:** N/A — this file lives forever as a record of what was deferred. No status emoji needed in `README.md`'s index for this one beyond ⏳ (always open).
