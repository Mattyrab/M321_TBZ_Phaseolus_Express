# 50 — Followups

The parking lot. Anything that came up while working on this plan but is **out of scope** for the current PR.

This file exists so the conversation doesn't bloat the current plan. When something interesting surfaces — a related refactor, an adjacent bug, a future feature, a test gap — drop it here in one bullet and move on.

## Out of scope, parked for later

- ⏳ **Argo CD Keycloak SSO.** Blocked on a real split-horizon DNS problem: Argo CD (neither its native `oidc.config` nor its Dex `oidc` connector) has no way to use the in-cluster Keycloak address for its own backend while using the browser-facing `localhost:8180` address for the login redirect — both live-tested and confirmed broken in `40_implementation.md` Step 3. The only real fix found is a Windows hosts-file entry (e.g. `127.0.0.1 keycloak.phaseolus.local`, needing admin elevation) paired with a matching in-cluster DNS override (`hostAliases` on `argocd-server`/`argocd-dex-server`, or a CoreDNS rewrite) so one hostname resolves two different ways. Revisit if/when a real ingress hostname exists for Keycloak (also flagged in `../2026_10_sso-keycloak/50_followups.md`), since a real DNS name removes the whole problem. Until then, Argo CD's local `admin` account is its only login.

---

## Promoted to their own plan

<When a parked item gets serious enough to need its own folder, link the new plan here and tick the original entry ✅. Don't delete the entry — the trail matters.>

- e.g. ✅ "Allocation layer" → see `docs/plans/2026_06_allocation/`

---

**Exit criterion:** N/A — this file lives forever as a record of what was deferred. No status emoji needed in `README.md`'s index for this one beyond ⏳ (always open).
