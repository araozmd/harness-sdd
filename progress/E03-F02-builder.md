# E03-F02 Cascade installer — Builder hand-off

Feature: **E03-F02 — Cascade installer** (status confirmed `in-progress` in
`state/tasks.json`, human-approved). Branch: `feat/cascade-installer`.

## Tasks completed (T1–T14, all ticked in cascade-installer.tasks.md)
- **T1** — Refactored the entire single-target install body (sections 1–6) into
  `install_one <target>` in `harness-install.sh`. The single-target path is now
  `install_one "$TGT"`. The function sets `LAST_UPGRADE` (0 fresh / 1 upgrade).
  Per-target header + "Next steps" output preserved verbatim, so single-target output
  is unchanged (R5, R10, R16, R17, R22, R24).
- **T2** — Arg parsing: `--umbrella <dir>` (consumes next token, resolves to abs path,
  keeps the `!= SRC` self-target guard), boolean `--recursive`, unknown-flag rejection.
  Bare `<target>` positional form preserved exactly. No-target / bad-`--umbrella`-dir →
  usage error, non-zero, before any write (R1, R2, R3, R4).
- **T3** — `migrate_config <config-path>`: append-only, zero-dep POSIX sh. Explicit
  default table (`verification.integration_command`, `umbrella.manifest`). Missing key
  with existing section header → inserted after header (`_mc_insert_after` via awk);
  missing header → full header+key block appended at EOF. Never rewrites a line
  (R18, R19, R20, R21).
- **T4** — `migrate_config "$H/harness.config.yaml"` called on the UPGRADE branch inside
  `install_one` (the preserved-config branch), so coordinator AND child upgrades pick up
  missing keys (R18, R21).
- **T5** — Umbrella driver: `install_one "$UMB"` for the coordinator, then
  `migrate_config` on its config, then set `umbrella.manifest` to
  `"../umbrella.manifest.yaml"` only when blank. No extra coordinator `test_command`
  (R5, R6, R7).
- **T6** — Depth-1 child discovery: iterate `"$UMB"/*/`, skip names starting with `.`
  and `.harness`, select iff `[ -e "$child/.git" ]` (matches `.git` dir OR file)
  (R4, R8, R9).
- **T7** — Name validation against `^[a-z0-9-]+$`; mismatch prints a clear warning naming
  the child + grammar and `continue`s (no install, no entry) (R13).
- **T8** — `install_one "$UMB/$name"` per kept child (R10).
- **T9** — `umbrella.manifest.yaml` created with `repos:` header if absent (R11).
- **T10** — `manifest_upsert`: append-only; existing two-space key → left untouched;
  new key → block with `path: ./<name>` + TODO `init`/`test_command`/`delegate_cmd`
  (R12, R14, R15).
- **T11** — `manifest.txt` now lists `umbrella.manifest.yaml` as a project-owned
  artifact. Generated uniformly by `install_one`, so child `manifest.txt` == single-target
  `manifest.txt` (R23).
- **T12** — Docs: `docs/INSTALL.md` got an "Umbrella mode (cascade install)" section + a
  "Config migration on upgrade" section; `docs/UMBRELLA.md` got an "Installing the
  umbrella (cascade)" pointer.
- **T13** — Created `tests/test_cascade.sh` (zero-dep POSIX sh, self-cleaning) covering
  every R-id per the test contract; appended `&& sh tests/test_cascade.sh` to
  `verification.test_command` in `harness.config.yaml`.
- **T14** — Full verification run (below).

## Files changed (all absolute)
- `/Users/araozmd/repos/harness-sdd/harness-install.sh` — `install_one` refactor,
  `migrate_config` + `_mc_insert_after`, `manifest_upsert`, arg parsing, umbrella driver.
- `/Users/araozmd/repos/harness-sdd/harness.config.yaml` — `test_command` extended with
  the cascade suite.
- `/Users/araozmd/repos/harness-sdd/docs/INSTALL.md` — umbrella + migration sections.
- `/Users/araozmd/repos/harness-sdd/docs/UMBRELLA.md` — cascade install pointer.
- `/Users/araozmd/repos/harness-sdd/tests/test_cascade.sh` — new suite (24 R-ids).
- `/Users/araozmd/repos/harness-sdd/specs/epics/E03-multi-repo/F02-cascade-installer/cascade-installer.tasks.md`
  — T1–T14 ticked.

## Verification (T14) — all PASS
- `./init.sh` → PASS (exit 0, "environment ready").
- `sh tests/test_install.sh` → PASS (10/10, non-regression intact, R24).
- `sh tests/test_umbrella.sh` → PASS (all F01 checks green, unchanged).
- `sh tests/test_cascade.sh` → PASS (24/24 R-ids: R1–R24).

## Smoke test (manual, per the instructions) — all confirmed
Temp umbrella with `viernes-bff/.git` (dir), `lia-api/.git` (file), `not_a_repo/`,
`bad_Name/.git` (invalid name), `.hidden/.git`, `.harness/`:
- Fresh run: coordinator `.harness/` present; `umbrella.manifest` →
  `"../umbrella.manifest.yaml"`; `integration_command` present; both valid git children
  installed; manifest has `viernes-bff` + `lia-api` with `path: ./<name>` + TODO
  placeholders; `bad_Name` skipped with a warning; `not_a_repo`/`.hidden`/`.harness`
  absent from manifest.
- `( cd <umbrella> && ./.harness/init.sh )` → exit 0, prints "umbrella mode: manifest
  present", NO repo-key grammar warning, NO missing-path warning (R15).
- Re-run: manifest byte-stable for existing entries (bootstrap-filled `delegate_cmd`
  survived), new git child appended, no duplicate entries, child project files preserved,
  child pointer block not duplicated, child config migrated keeping its bootstrap value.
- Pre-F01 config (no `umbrella:` block, `test_command: "pytest -q"` + trailing comment):
  upgrade appended `integration_command` under `verification:` and a new `umbrella:`
  header+`manifest:` block at EOF; `test_command` value+comment retained byte-for-byte;
  second upgrade left the file byte-identical (R18/R19/R20).

## Design notes the Reviewer should scrutinize
1. **Non-regression (R24).** `install_one` is the old body verbatim wrapped in a
   function; single-target is `install_one "$TGT"`. `tests/test_install.sh` is unchanged
   and green. The ONLY new effect on single-target is `migrate_config` on the upgrade
   branch, which is strictly additive/value-preserving (asserted by R19/R20 + the new
   `single_target_unchanged` check).
2. **`migrate_config`.** Append-only via `_mc_insert_after` (awk, prints every line then
   inserts after the first header match) and EOF block append. Idempotency is by the
   anchored `grep -Eq` presence guards. The pre-F01 case (no `umbrella:` block) is the
   tricky one and is explicitly fixtured. Worth a close read of the awk insert and the
   grep anchors.
3. **R6 manifest path.** The coordinator config points at `"../umbrella.manifest.yaml"`
   (NOT `"umbrella.manifest.yaml"`): `init.sh` resolves `umbrella.manifest` relative to
   the `.harness/` dir, while the manifest lives at the umbrella root. The manifest's
   internal `path: ./<name>` entries are resolved by `init.sh` relative to the manifest's
   own dir (umbrella root), so they resolve correctly. Verified by running the installed
   `init.sh` against the populated manifest.
4. **`manifest.txt` (R23) is uniform.** All installs (single-target, coordinator, child)
   now list `umbrella.manifest.yaml`. This keeps child == single-target output identical;
   the line is documentation only and harmless for single-repo targets.

## Open / not done
- **VERSION bump + CHANGELOG.** I did NOT bump `VERSION` or edit `CHANGELOG.md`. They are
  not in the spec's `.plan.md` "Files to change" and the spec defines no requirement for
  them, so I stayed inside the spec. However, this PR changes the installed body
  (`harness-install.sh`, `harness.config.yaml`, `docs/`), so per repo `CLAUDE.md`
  versioning policy a **MINOR** bump (✨ new capability) is due before merge
  (`0.2.0` → `0.3.0`) plus a CHANGELOG entry and a `v0.3.0` tag on the merge commit.
  Flagging for the Orchestrator/human to action at release time.
- **`--recursive`** ships as accepted-but-deferred (prints a note, scans depth 1) per the
  approved open-question default — solid depth-1 over a fragile recursive mode.

Status NOT advanced by me — leaving the feature `in-progress` for the Orchestrator to
move to `in-review`.
