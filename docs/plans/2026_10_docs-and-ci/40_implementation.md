# 40 — Implementation

Step plan for the chosen option from `20_options.md`. **Do not start this phase while `30_open_questions.md` has any ⏳ items** — that's the discipline this folder structure exists to enforce.

Each step has a verification: how do we know the step is done? Strong verification turns the plan into a checklist you can run independently.

## Plan summary

<One paragraph: what we're doing, in what order, and why the order matters (dependencies, reversibility, deploy considerations).>

## Steps

### Step 1 — <action>

⏳ **Do.** <The concrete change. File paths, migration names, model changes.>

**Verify.** <How to know it's done. A passing spec, a query result, a manual check.>

---

### Step 2 — <action>

⏳ **Do.** <…>

**Verify.** <…>

---

<Add more `### Step n` blocks as needed. Tick ⏳ → ✅ as each step completes.>

## Rollback / blast radius

<What's reversible vs. not. If a step writes/migrates data, name how to undo it. Skip this section only if every step is trivially reversible (e.g. additive code with no data changes).>

## Quality gates before merging

<Run the project's quality gate sequence as defined in `CLAUDE.md`. List the specific commands here so this plan is self-contained and a reviewer doesn't need to re-derive them.>

---

**Exit criterion:** Every step ✅, gates green, PR merged. Mark ✅ in `README.md` when complete and archive the folder per the project's plan-archive convention in `CLAUDE.md`.
