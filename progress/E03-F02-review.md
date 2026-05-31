# E03-F02 Cascade installer — Reviewer verdict: APPROVE

Branch `feat/cascade-installer`. Verified independently against the approved spec (R1–R24).

## Gate
`./init.sh` → exit 0, "environment ready".

## Suites (run by Reviewer, full output captured)
- `sh tests/test_install.sh` → exit 0, 10/10 ok (non-regression R24 intact).
- `sh tests/test_umbrella.sh` → exit 0, 26/26 ok (F01 unchanged).
- `sh tests/test_cascade.sh` → exit 0, 24/24 ok (R1–R24).
- Full configured `test_command` (all three chained) → green.

## Independent smoke tests (not trusting the suite)
1. Fresh cascade over a hand-built umbrella (`viernes-bff/.git` dir, `lia-api/.git` FILE,
   `not_a_repo`, `Bad_Name/.git` invalid, `.hidden_repo/.git`, pre-existing `.harness`):
   - coordinator `.harness/` written; `umbrella.manifest: "../umbrella.manifest.yaml"`;
     `verification.integration_command: ""` present; no extra `test_command`.
   - `.harness/` only in `viernes-bff` + `lia-api`. `not_a_repo`, `Bad_Name`, `.hidden_repo`,
     own `.harness` all absent.
   - manifest auto-populated with the two valid repos (`path: ./<name>` + TODO placeholders).
   - `Bad_Name` skipped with: "skipping child 'Bad_Name': name must match ^[a-z0-9-]+$ ...".
   - `( cd <umbrella> && ./.harness/init.sh )` → exit 0, "umbrella mode: manifest present",
     NO grammar/path warning (R15).
2. Re-run idempotency/preservation: bootstrap-filled a manifest `delegate_cmd`, mutated a
   child `state/tasks.json`, added a new git child → re-run appended `new-svc` only,
   `viernes-bff` entry singular, filled `delegate_cmd` survived, child file byte-identical +
   sentinel intact, child `CLAUDE.md` begin-block count = 1 (R14/R16/R17).
3. Pre-F01 migration (no `umbrella:` block, `test_command: "pytest -q"   # keep me exactly`):
   upgrade appended `integration_command` after `verification:` and a new `umbrella:`+`manifest:`
   block at EOF; the bootstrap value+comment retained byte-for-byte; second upgrade left the
   file byte-identical; no key duplicated (R18/R19/R20).

## Non-regression (R24)
`install_one` is the historical single-target body wrapped verbatim in a function; the
single-target path is `install_one "$TGT"`. The only added effect is `migrate_config` on the
upgrade branch, which is strictly append-only/value-preserving. `tests/test_install.sh`
(unchanged) stays green. Confirmed.

## Conventions / DO-NOT-TOUCH
- POSIX sh, zero-dep: no yq/jq/python/perl used (only grep/awk/sed/cp/mkdir). Shebang `#!/bin/sh`.
- `agents/`, `store/tasks.schema.json`, `init.sh` untouched (git diff --stat empty).
- F01 manifest shape + config-key names reused; example manifest unchanged.
- `harness.config.yaml` diff = test_command extended with cascade suite only.

## Traceability
All 24 R-ids (R1–R24) map to a passing, non-tautological test in `tests/test_cascade.sh`
(R24 also via the whole `tests/test_install.sh`). Test names match the `.tests.md` matrix exactly.

## Notes (not blocking)
- VERSION/CHANGELOG bump not done (Builder flagged it). Per repo CLAUDE.md this PR changes the
  installed body, so a MINOR bump (✨) + CHANGELOG + tag is due at merge time — an
  Orchestrator/human release action, outside the spec's requirements. Does not block APPROVE.
- `--recursive` ships accepted-but-deferred (depth-1 + note), matching the spec's open-question
  default.
