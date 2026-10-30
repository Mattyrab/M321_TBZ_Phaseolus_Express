# 40 — Implementation

Step plan for closing the grading rubric's observability (criterion 5, 5 pts) and resilience/scaling (criterion 6, 10 pts) gaps. This plan skipped the full staged process (`inputs.md` → `30_open_questions.md`) by deliberate choice — see `README.md` — since neither criterion involves a real design decision to weigh.

## Plan summary

Three independent steps, in increasing order of what they touch. **Step 1 (success-path logging)** closes criterion 5 entirely — it's pure code, four repos, no infrastructure change. **Step 2 (horizontal scaling)** closes the "Ideal" tier of criterion 6 — one `deploy/deployment.yaml` edit, verified live. **Step 3 (resilience)** reaches for criterion 6's "Maximal" tier (timeouts/retries/circuit-breaker) via one line of first-party .NET resilience middleware on the project's only synchronous service-to-service call.

**A finding from this plan's own investigation that changes Step 2's scope from what `inputs.md`'s notes assumed:** the message-contracts-hardening plan (already merged) added an `EventId` dedup guard to `PayBeancoins`/`CookerBeaners`/`BeanNotifs`'s consumers — but that guard is a plain in-memory `ConcurrentDictionary` *per pod*. Scaling `CookerBeaners` (the candidate `inputs.md` suggested alongside OrderBeans) to multiple replicas would mean each replica tracks its own independent set of seen `EventId`s — a redelivery RabbitMQ round-robins to a *different* replica than the one that originally handled it would no longer be caught. `OrderBeans` has no consumer and no idempotency state at all (it only publishes), so it's the cleaner, zero-side-effect choice for this plan's scaling demo. This isn't a bug to fix here — it's a reason to pick a different service, noted for the record.

**Post-execution note:** all three steps done and live-verified exactly as planned. Both Step 2 and Step 3 hit Argo CD's `selfHeal` reverting a manual test edit mid-verification — by now an established, quickly-handled pattern (pause sync on the child + root Applications, test, restore) rather than a surprise. Step 2's first load-test attempt gave a false negative from a `kubectl port-forward` quirk (it pins to one pod, unlike real Service traffic) — caught and corrected by testing from inside the cluster instead.

## Steps

### Step 1 — Success-path structured logging with `OrderId` correlation

✅ **Done.** PRs: [Order #7](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Order/pull/7), [Pay #7](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Pay/pull/7), [Cooker #6](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Cooker/pull/6), [Notifs #8](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Notifs/pull/8). Exactly as planned — one `LogInformation` call per success point in all four services, each carrying `OrderId`.

**Verified live:** placed one real order and grepped all four services' logs for its `OrderId` — found in the expected sequence: `OrderBeans` ("placed") → `PayBeancoins` ("Payment succeeded") → `CookerBeaners` ("Cooking started" / "Cooking finished") → `BeanNotifs` (three "Notification logged" lines, one per downstream event). Full cross-service correlation demonstrated end-to-end, not just implemented.

---

### Step 2 — Horizontal scaling: `OrderBeans` to 2 replicas

✅ **Done.** [PR #8](https://github.com/Timposter8107/M321_TBZ_Phaseolus_Order/pull/8). `replicas: 1` → `2`, no code change, exactly as planned.

**Verified live:** Argo CD's `selfHeal` reverted the first manual apply within seconds (git still said `replicas: 1`) — had to pause sync on both the `orderbeans` Application and the root `phaseolus-root` App-of-Apps, same pattern established in prior plans, restored immediately after. Confirmed both pods `Running`. First load test via `kubectl port-forward` showed all requests landing on one pod — a `port-forward` artifact (it pins to a single endpoint for the connection's lifetime, bypassing Service-level balancing), not a real finding. Retested by issuing requests from a throwaway in-cluster pod directly against the Service DNS name, which genuinely goes through kube-proxy: confirmed via Step 1's log lines that both pods handled real requests (a 14/5 split across 19 total requests), proving actual Service-level load distribution.

---

### Step 3 — Timeouts, retries, and a circuit breaker on the one synchronous call

✅ **Done.** [PR #11](https://github.com/Timposter8107/M321_TBZ_Phaseolus_WebApp/pull/11). Added `Microsoft.Extensions.Http.Resilience` and chained `.AddStandardResilienceHandler()` onto the `"BeanNotifs"` registration, exactly as planned, defaults untouched.

**Verified live:** simulated a full browser login as the admin (curl-based OIDC flow) rather than just hitting an API, so the Admin page's real auth path was exercised too. Scaled `BeanNotifs` to 0 (again required pausing Argo CD sync on `beannotifs` + the root Application, restored after), then hit the Admin page: the request took 9 seconds (vs. near-instant with no retries) and BeanApp's logs showed multiple `Polly`/`OnRetry` events against the real `Connection refused (beannotifs.phaseolus.svc.cluster.local:8080)` failure, up to "Attempt: 3", before the existing `catch` block's "Could not reach BeanNotifs" message was shown. Scaled `BeanNotifs` back to 1 and confirmed the next request succeeded in ~1s with no BeanApp restart.

**Not independently verified:** the circuit breaker specifically — only retries were directly observed firing. The standard handler's circuit breaker needs a minimum sampling window/failure rate before it trips open, which a single short outage-and-recovery test doesn't necessarily exercise. Noted honestly rather than claimed as proven; see `50_followups.md`.

## Rollback / blast radius

All three steps are trivially reversible. Step 1 is pure additive logging (no behavior change). Step 2 is a one-line replica-count revert if scaling causes any unexpected issue (none expected, given the statelessness check above). Step 3 is a one-line removal of `.AddStandardResilienceHandler()` if its defaults ever cause unwanted retry amplification against a genuinely down dependency — worth watching for during Step 3's verification, not just assuming away.

## Quality gates before merging

- `dotnet build` clean in every repo touched by a given step (`OrderBeans`, `PayBeancoins`, `CookerBeaners`, `BeanNotifs` for Step 1; `OrderBeans` for Step 2 — manifest only, no build; `WebApp` for Step 3).
- Live verification per step against the dev `minikube` cluster — this project has no automated test suite.

---

**Exit criterion:** Every step ✅, gates green, PR merged. Mark ✅ in `README.md` when complete.
