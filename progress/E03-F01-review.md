# E03-F01 Umbrella coordinator — Review

**Verdict: APPROVE.** All checks green, every R-id (R1–R19) has a passing,
non-tautological test, locked decisions honored, additive/opt-in guarantees verified.

## Commands run (Reviewer, not trusting Builder report)

1. `./init.sh` → `✅ environment ready — agents may proceed` — EXIT 0
2. `sh tests/test_install.sh` → `All install tests passed.` — EXIT 0 (no regression)
3. `sh tests/test_umbrella.sh` → `All umbrella tests passed.` — EXIT 0 (20 `ok -` lines)
4. `python3 -c "import jsonschema"` → 4.25.1 present ⇒ tests use the REAL Draft7
   validator, not the zero-dep fallback.
5. Negative schema case (slice missing `repo`) against real validator →
   `errors: ["'repo' is a required property"]` — genuinely rejected.
6. `jsonschema.Draft7Validator.check_schema` on `store/tasks.schema.json` → valid
   draft-07; current `state/tasks.json` validates with `[]` errors (pure superset).
7. Behavioral init.sh umbrella branch: temp copy with manifest naming one present +
   one missing (`ghost-repo`) child repo →
   `⚠️  umbrella manifest: repo 'ghost-repo' path not found: ../ghost-repo` then
   `ℹ️  umbrella mode: manifest present (...)`, EXIT 0 (non-fatal, gate not blocked).
8. Independent re-impl of `select_next` gating confirmed NOT tautological:
   A-pending⇒select A; A-done+merged⇒select B; A-done-but-NOT-merged⇒select EMPTY
   (the `merged` gate is real, honoring the locked depends_on=done+merged decision).

## Traceability (R1–R19) — all covered by a real assertion

- R1/R2 schema: `slices[]` with id+repo and cross-repo depends_on validate; malformed
  (missing repo) rejected by real validator. ✓
- R3/R13/R14–R17 rollup+integration: reference `feature_done` derives done only when
  all slices done+merged AND integration exits 0; integration not run while any slice
  pending (`[ ! -s "$INTLOG" ]`); non-zero integration keeps feature out of done. ✓
- R4/R18/R19 pure superset: current `state/tasks.json` validates; no `required` list
  tightened (`slices` absent from every feature/epic/root required); init.sh inert
  with `manifest: ""`. ✓
- R5/R6 manifest: example parses path/init/test_command/delegate_cmd per repo;
  unknown repo undispatchable + error names the repo. ✓
- R7/R8 contract artifact: UMBRELLA.md pins "exactly one" contract artifact at a
  stable path, referenced by id; every emitted slice references it (doc-presence, the
  strategy explicitly sanctioned by the .tests.md for this structural feature). ✓
- R9/R11/R12 dispatch+gating: real topo select over a fixture chain; downstream gated
  behind upstream done+merged; non-zero delegate exit propagates (rc=7) and halts
  dependents. ✓
- R10 delegate seam: stub invoked verbatim `<feature-id> <abs-spec-path>`; file count
  in child dir unchanged (no source written). ✓

## Guarantee checks

- **Pure superset (R4,R19):** schema diff adds only optional `slices` to the feature
  object; `slices.required:["id","repo","status"]` is internal to the slice object,
  not the feature — a feature without `slices` is unaffected. No existing `required`
  list changed. Confirmed valid draft-07 + current state validates.
- **No role fork:** `git diff --stat` shows only `agents/orchestrator.md` changed
  among role files (architect/builder/reviewer/scout untouched). The change is +39
  append-only lines: an additive "Umbrella mode" section, no existing line modified.
- **Additive config:** `verification.integration_command` and `umbrella.manifest`
  added with `""` defaults; no existing key's meaning changed; single-repo inert.
- **Locked decisions:** slice id pattern `^E[0-9]+-F[0-9]+@[a-z0-9-]+$` in schema;
  delegate seam reused verbatim; depends_on gating requires done+merged; feature
  `done` derived (never set directly) and gated behind `integration_command`.
- **Conventions:** `tests/test_umbrella.sh` is POSIX sh, zero-dep (jsonschema-or-
  fallback), matches `tests/test_install.sh` house style; init.sh branch non-fatal.

## Non-blocking notes (for Orchestrator)

- `verification.test_command` stays `sh tests/test_install.sh`; the new umbrella
  suite is NOT wired into the default command. The .tests.md did not mandate it and I
  ran `tests/test_umbrella.sh` independently (green). Recommend wiring it in
  (e.g. `sh tests/test_install.sh && sh tests/test_umbrella.sh`) so regressions are
  caught by the default gate — a one-line config decision.
- VERSION bump: this PR changes the installed body (store/, harness.config.yaml,
  agents/, docs/, init.sh) and adds a backward-compatible capability ⇒ MINOR bump +
  CHANGELOG entry before merge, per CLAUDE.md. Builder correctly left this as a
  deliberate release call.
