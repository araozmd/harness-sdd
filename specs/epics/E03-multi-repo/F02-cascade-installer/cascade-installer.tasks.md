# Cascade installer — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom, one at a
> time. Each task names the R-id(s) it satisfies. Check off when done. All paths are inside
> the harness source repo. Do not write application code.

- [x] **T1** (R5, R10, R16, R17, R22, R24) — In `harness-install.sh`, refactor the existing
  install body (sections 1–6: body copy, project seed, version stamp + `manifest.txt`,
  pointer blocks, `.claude` glue, `opencode.json`) into a function `install_one <target>`
  that resolves/validates the target and returns the UPGRADE flag. Call it once as
  `install_one "$TARGET"` for the current single-target path. Verify `tests/test_install.sh`
  still passes unchanged (byte-for-byte single-target behavior).

- [x] **T2** (R1, R2, R3, R4) — Add argument parsing before the install dispatch: recognize
  `--umbrella <dir>` (consume next token, resolve to abs path, keep the self-target guard)
  and a boolean `--recursive`. Preserve the bare `<target>` positional form unchanged. On
  no target and no valid `--umbrella` dir, print usage and exit non-zero before any
  filesystem write.

- [x] **T3** (R18, R19, R20, R21) — Add `migrate_config <config-path>`: an append-only,
  zero-dep POSIX `sh` helper driven by an explicit table of guaranteed default keys (at
  least `umbrella.manifest: ""` and `verification.integration_command: ""`). For each
  missing key: if its section header exists, insert the indented key line after the header;
  if the header is absent, append the full header+key block at EOF. Never rewrite an
  existing line. Idempotent on a fully-populated config.

- [x] **T4** (R18, R21) — Call `migrate_config "$H/harness.config.yaml"` on the UPGRADE
  branch inside `install_one` (the branch that preserves an existing config), so both
  coordinator and child upgrades pick up missing default keys.

- [x] **T5** (R5, R6, R7) — Add the umbrella driver entry: when `--umbrella` is set, call
  `install_one "$UMBRELLA"` (coordinator), then ensure the coordinator config has an
  `integration_command` key (via the same migration) and set `umbrella.manifest` to
  `umbrella.manifest.yaml` when it is unset/blank. Do not add a coordinator per-repo
  `test_command` beyond the existing blank-on-seed default.

- [x] **T6** (R4, R8, R9) — In the umbrella driver, discover immediate children: iterate the
  umbrella's direct subdirectories (depth 1 unless `--recursive`), skip names beginning with
  `.` and the `.harness` dir, and select a child iff `[ -e "$child/.git" ]` (matches `.git`
  as a directory OR a file).

- [x] **T7** (R13) — For each selected child, validate its directory name against
  `^[a-z0-9-]+$`. On mismatch, print a clear message naming the child and the required
  grammar, then skip it (no child install, no manifest entry).

- [x] **T8** (R10) — For each kept child, call `install_one "$child"` so it receives the
  normal child profile with the same fresh/upgrade, preservation, pointer, and stamp
  semantics as a direct single-target install.

- [x] **T9** (R11) — In the umbrella driver, create `<umbrella>/umbrella.manifest.yaml` with
  a top-level `repos:` header if it does not already exist.

- [x] **T10** (R12, R14, R15) — Add an append-only manifest upsert: for each kept child, if
  its key is not already present under `repos:` (anchored two-space grep), append a block
  with `path: ./<name>` and TODO placeholders for `init`/`test_command`/`delegate_cmd`;
  if the key already exists, leave its block untouched. Keys are the literal validated
  directory names (matching `init.sh`'s `^[a-z0-9-]+$`).

- [x] **T11** (R23) — Ensure the coordinator's `manifest.txt` lists `umbrella.manifest.yaml`
  as a project-owned (seeded-once, never-clobbered) artifact. Confirm child `manifest.txt`
  output is unchanged from single-target.

- [x] **T12** (R1, R5, R8, R18) — Update `docs/INSTALL.md` with the umbrella/cascade
  invocation, the two-profile model, depth-1 git-gating, idempotency, and the config
  migration; add a short "Installing the umbrella (cascade)" pointer in `docs/UMBRELLA.md`.

- [x] **T13** — Create `tests/test_cascade.sh` (zero-dep POSIX sh, self-cleaning temp tree)
  covering every R-id per `cascade-installer.tests.md`, including fixtures with `.git` as a
  directory AND as a file, an invalid-named child, a pre-F01 config (no `umbrella:` block)
  for migration, and a re-run idempotency pass. Append `&& sh tests/test_cascade.sh` to
  `verification.test_command` in `harness.config.yaml`.

- [x] **T14** — Run `./init.sh`, then `sh tests/test_install.sh` (non-regression),
  `sh tests/test_umbrella.sh`, and `sh tests/test_cascade.sh`; ensure all green before
  hand-off.
