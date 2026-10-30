# 50 — Followups

The parking lot. Anything that came up while working on this plan but is **out of scope** for the current PR.

This file exists so the conversation doesn't bloat the current plan. When something interesting surfaces — a related refactor, an adjacent bug, a future feature, a test gap — drop it here in one bullet and move on.

## Out of scope, parked for later

- ⏳ **No test projects exist anywhere.** CI runs lint+build, not tests, because there's simply nothing to test yet (checked: zero `Microsoft.NET.Test.Sdk`/xunit/nunit/MSTest references in any of the 5 service repos). If real tests are ever added, the existing `ci.yml` in each repo would just need a `dotnet test` step appended.
- ⏳ **No branch-protection rule requires CI to pass before merging.** The workflows run and report status, but nothing currently stops a merge if they fail — the rubric's "Isolierte CI-Pipelines" is satisfied by the pipelines existing and running, but enforcing them (Settings → Branches → require status checks) would be a stronger version of this if ever wanted.
- ⏳ **The meta repo's CI is minimal (`bash -n` only).** No linting of the Kubernetes YAML manifests or Helm values in `k8s/`, and no validation that `setup.sh`'s Keycloak/RabbitMQ API calls are still well-formed. Deliberately kept cheap for this plan's scope; could grow into a real `kubectl apply --dry-run=client` / `yamllint` pass later.

---

## Promoted to their own plan

<When a parked item gets serious enough to need its own folder, link the new plan here and tick the original entry ✅. Don't delete the entry — the trail matters.>

- e.g. ✅ "Allocation layer" → see `docs/plans/2026_06_allocation/`

---

**Exit criterion:** N/A — this file lives forever as a record of what was deferred. No status emoji needed in `README.md`'s index for this one beyond ⏳ (always open).
