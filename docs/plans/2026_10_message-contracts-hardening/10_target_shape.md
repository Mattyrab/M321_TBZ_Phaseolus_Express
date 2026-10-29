# 10 — Target shape

What the change must produce. **Requirements, not solutions.** This is the interpretation of `inputs.md` against `00_current_state.md`. If you find yourself naming a model, table, or implementation detail, you're in `20_options.md` territory — back up.

## Goals

<Bullet list. Each goal is a concrete, verifiable outcome. "Two effective levels of grouping" is a goal. "Add a `bucket_groups` table" is not — that's an option.>

## Non-goals

<What is *not* in scope, especially adjacent things a reader might assume are. Naming non-goals up front prevents scope creep later.>

## Constraints

<Things the solution must respect: existing schema, performance, auth, UI conventions, deployment, data migration risk. Reference CLAUDE.md gotchas where they apply.>

## Success criteria

<How we'll know the change is correct. Test scenarios, user-visible behavior, queries that must keep working. Strong criteria here make `40_implementation.md`'s verification steps trivial to write.>

---

**Exit criterion:** Requirements are testable, not vague. Mark ✅ in `README.md` when complete.
