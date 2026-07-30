# Doc-critic: feature-spec — E21-F04 (re-spec, 2026-07-29)

**target-type:** feature-spec
**files reviewed:**
- `specs/epics/E21-change-size-discipline/F04-stacked-pr-lane/F04-stacked-pr-lane.spec.md`
- `specs/epics/E21-change-size-discipline/F04-stacked-pr-lane/F04-stacked-pr-lane.plan.md`
- `specs/epics/E21-change-size-discipline/F04-stacked-pr-lane/F04-stacked-pr-lane.tasks.md`
- `specs/epics/E21-change-size-discipline/F04-stacked-pr-lane/F04-stacked-pr-lane.tests.md`

**Issues found and fixed:**

1. **Plan/tasks inconsistency — `baseRefOid` fetch location.** The plan had `baseRefName` added to `wait-for-codex.sh` (T2) but `baseRefOid` added in `sdd-pr-loop.md` (T3). Since `wait-for-codex.sh` is the component that actually executes `gh pr view --json`, both fields must be added there so the round cache's `pr.json` carries them. Fixed: T2 now adds both `baseRefName,baseRefOid` to the watcher; T3 simplified to consume the cached data. Plan's API table and "Files to change" section updated to match.

2. **T5 missing R9 test.** The traceability table maps R9 (`test_stacked_pr_opt_in`) as a unit test, but T5's enumeration of tests omitted it. Fixed: T5 now includes `test_stacked_pr_opt_in` in its list and the task header cites `R9`.

**No issues found in:**
- Completeness: all scope boundaries, acceptance criteria, and verification paths are present.
- Clarity: all R-ids are testable as written; terms are defined; the "base branch head" concept maps to `baseRefOid` in the plan.
- Scope: the feature stays within reviewability/stacking; atomic delivery is explicitly out of scope.
- YAGNI: all 9 requirements serve the stated outcomes; base-change detection (R5) is justified by the inbox brief's explicit inclusion of restack handling.
- Consistency: titles, ids, and R-id citations match across all four files. ADR-0001 is correctly cited as untouched.
