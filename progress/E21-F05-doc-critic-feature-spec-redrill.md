# Doc-critic — `feature-spec` — E21-F05 (re-drill)

- **target-type:** `feature-spec`
- **Files reviewed:** `specs/epics/E21-change-size-discipline/F05-stacked-pr-doctrine/E21-F05.{spec,plan,tasks,tests}.md`
  (branch `spec/E21-F05-doctrine-redrill`)
- **Context read:** `progress/inbox/E21-F05.md`, `docs/WORKFLOW.md` (lane at 559–641),
  `specs/epics/E21-change-size-discipline/F04-stacked-pr-lane/F04-stacked-pr-lane.spec.md`,
  `harness-install.sh` (700 / 2466 / 4325), `tests/test_pr_loop.sh`, `tools/run-tests.sh`,
  `harness.config.yaml`, `agents/builder.md:79–91`, `AGENTS.md` → *Versioning*,
  `state/tasks.json`, the withdrawn predecessor spec (read-only export).
- **Posture:** advisory. **No edit made to the four spec files.**

## Verdict

Materially better than the withdrawn predecessor. Every measurement in the spec was
re-verified against `main` and **all of them hold** (13 `wave` lines, 3 `(R<n>)`, 1 `E21-F01`,
1 `atomic`, 2 `feature flag`, 0 `independently safe`, 0 `verification.test_command`;
fence-blind vs fence-aware `gh pr create` = 1 vs 4). Scope, the atomicity ban, the
no-`VERSION`-freeze / no-diff-vs-`main` rules and the withdrawn-requirement quarantine are all
clean. **Seven findings**, none fatal; two (F1, F2) would produce a test the Builder cannot
honor as written.

## Findings (7)

1. **F1 (highest)** — `grep -c` counts *lines*, not occurrences, so the three "stated once"
   assertions (R1 `independently safe` / `verification.test_command` = 1, R2 `feature flag` = 1)
   pass on two occurrences in one wrapped line. Uniqueness is the actual requirement (plan 47–48).
   Fix: `grep -o … | wc -l`.
2. **F2** — R8's installed-half assertion passes on `main` today and can only be mutated by
   editing DO-NOT-TOUCH `harness-install.sh`, contradicting T12's "there is no carve-out in this
   feature". Fix: declare it a regression guard and name the exemption in T12.
3. **F3** — `plan.md` → *Sequencing* is off by one against `tasks.md` from T9 onward
   (plan: suite=T10, mutation=T11, VERSION=T12, gate=T13; tasks: T11/T12/T13/T14).
4. **F4** — `span()` is not fence-aware while `sect()` is; `span` carries every ban sweep and
   every uniqueness count, and the Builder is rewriting the very fences the exemption rests on.
5. **F5** — R6's `sed … | head -1` does not assert the derivation is unique; a second
   `docs/WORKFLOW.md '…'` message (E21-F06 owns that surface) silently redirects the assertion.
6. **F6** — `plan.md:155` cites `AGENTS.md` → *Versioning* as "explicit"; it is not (it lists
   `docs/` in the body **and** says "Docs-only … get no bump"). PATCH is still the right level.
7. **F7 (minor, grouped)** — R9's anchors omit any supersession verb; R7's `(R[0-9])` misses
   `(R10)`; R3's `still open` already passes today; R8's `documentation is stamped` ban is
   subsection- rather than lane-scoped; `spec.md:31`'s "scope stated once" omits
   `VERSION`/`CHANGELOG.md`.

## Dimensions verified clean

- **Budget** — 9 `R-id`s vs `max_requirements: 12`; nothing hidden to stay under the cap.
  R2/R5/R8 are multi-clause, but splitting them lands at 12, not over.
- **Atomicity language** — the token appears in all four files only as the string R3's sweep
  bans. No surviving delivery claim in the withdrawn vocabulary.
- **Scope** — no `agents/*.md`, no production code, no `harness-install.sh`,
  no `tools/pr-stack-guard.sh`, no `verification.test_command` edit. `## Change-size discipline`
  (the new pointer target) exists at `docs/WORKFLOW.md:83`. `## Re-spec notes` exists at
  `F04-stacked-pr-lane.spec.md:111` and holds none of R9's four tokens.
- **Predecessor delta** — nothing withdrawn crept back (predecessor R3/R4/R5-role-half/R7 all
  stay in E21-F06). One survivor was dropped with a stated reason: predecessor R6
  (unowned-base `exit 6` recovery), which the predecessor's own split table had assigned to this
  half. E21-F06 must actually carry it.
- **Test anti-patterns** — no `VERSION` freeze, no diff against `main`, the two legal
  `grep -c` forms stated in four places, section-scoped (never whole-file) prose greps.
