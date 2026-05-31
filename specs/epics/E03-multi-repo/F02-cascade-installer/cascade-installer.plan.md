# Cascade installer — Technical Plan

> Translates cascade-installer.spec.md into design. Each decision cites the R-id(s) it
> serves. This is a harness feature: it EXTENDS `harness-install.sh` (one new mode + one
> reusable migration helper) rather than forking a new script. POSIX `sh`, zero deps,
> matching the existing installer ethos. The single-target path is reused verbatim — the
> cascade is a thin orchestration layer that calls the existing install logic per repo.

## Stack & dependencies
- POSIX `sh` (the installer's existing dialect), `cp -R`, `sed`, `grep`, `mkdir`, `test`.
- No new runtime dependencies. YAML is handled with the same line-grammar approach
  `init.sh` already uses (two-space `repos:` keys, `path:` lines) — no YAML parser.
- Reuses F01 artifacts verbatim: `umbrella.manifest.example.yaml` shape (R12/R15), the
  `umbrella.manifest` + `verification.integration_command` config keys (R6/R7/R18), and
  `init.sh`'s `^[a-z0-9-]+$` repo-key grammar (R13/R15).

## Design overview
`harness-install.sh` gains:
1. **Arg parsing** that recognizes `--umbrella <dir>` and `--recursive`, keeping the bare
   `<target>` form 100% intact (R1, R2, R3, R4, R24).
2. A refactor that wraps the current body-copy + seed + stamp + pointer + glue sequence into
   an `install_one <target>` function so it can be called once (single-target) or once per
   repo (cascade), with **no behavior change** for the single-target call (R10, R16, R17,
   R22, R24).
3. An **umbrella driver** that, in umbrella mode, calls `install_one` on the umbrella dir
   (coordinator), discovers git children, calls `install_one` on each, and populates the
   manifest (R5–R15).
4. A **config-migration helper** `migrate_config <config-path>` invoked inside `install_one`
   on the UPGRADE branch (where the config is preserved), appending missing default keys
   (R18–R21).

> Implementation latitude: the Builder may keep the existing top-to-bottom script and gate
> the new behavior with functions, or split helpers — provided the single-target output is
> unchanged (verified by the existing `tests/test_install.sh`).

## CLI / interface  (serves: R1, R2, R3, R4)
| Invocation | Behavior | R-id |
|---|---|---|
| `harness-install.sh <target>` | single-target install/upgrade — unchanged | R2, R24 |
| `harness-install.sh --umbrella <dir>` | cascade: coordinator + children + manifest | R1, R5–R15 |
| `harness-install.sh --umbrella <dir> --recursive` | as above, descending past non-git children (see open question) | R4 |
| (no target, or `--umbrella` value not a dir) | usage error, exit non-zero, no writes | R3 |

- Parse flags before the positional check. `--umbrella` consumes the next token as the dir;
  `--recursive` is a boolean. Resolve `<umbrella-dir>` to an absolute path the same way the
  current `TARGET` resolution does, and keep the self-target guard (`!= "$SRC"`).

## Refactor: `install_one <target>`  (serves: R5, R10, R16, R17, R22, R24)
Wrap today's sections 1–6 (body copy → project seed → version stamp/manifest → pointer
blocks → `.claude` glue → `opencode.json`) into a function taking the resolved target path.
The current single-target flow becomes `install_one "$TARGET"`. This guarantees children get
the identical child profile (R10) with identical fresh/upgrade, preservation (R16), in-place
pointer (R17), and stamp/manifest (R22) semantics, and keeps single-target byte-for-byte
unchanged (R24). `install_one` returns the UPGRADE flag value so callers can branch on
fresh-vs-upgrade for the migration step.

## Config migration helper  (serves: R18, R19, R20, R21)
`migrate_config <config-path>` runs only on the **upgrade** branch (the only path where a
preserved config can be stale; a fresh seed already ships current keys). Approach, in POSIX
`sh`, zero-dep:

- Maintain a small, explicit table of **default keys → default value + parent section** that
  the harness guarantees: at least `verification.integration_command: ""` and
  `umbrella.manifest: ""` (the F01 keys), structured so future keys are added by extending the
  table only.
- For each default key, detect presence with an anchored `grep` (e.g. a `^[[:space:]]*manifest:`
  under the `umbrella:` section / `^[[:space:]]*integration_command:` under `verification:`).
  If the **section header** (`umbrella:` / `verification:`) is absent, append the whole block;
  if the header exists but the key is missing, append the key line at the end of that section.
- **Append-only, value-preserving (R19):** never rewrite an existing line; only add missing
  lines. Existing values, ordering, and comments are untouched. Idempotent (R20): a second
  run finds every key present and writes nothing.
- Because YAML nesting is handled by line-grammar (not a parser), the Builder must place an
  appended nested key under its header. Simplest correct strategy: if a header exists but its
  key is missing, append a correctly-indented key line immediately after the header line
  (using `sed`/`awk` insert-after-pattern), else append the full header+key block at EOF.
- Used by BOTH coordinator and child upgrades (R21) — it is generic, not umbrella-specific.

> Edge case the Builder must handle: a config where `verification:` exists but `umbrella:`
> does not (today's single-repo config DOES ship `umbrella:` since F01, but a config installed
> BEFORE F01 will lack it — that is exactly the Codex-flagged case). Test fixtures must cover
> the pre-F01 config (no `umbrella:` block at all).

## Umbrella driver  (serves: R5–R15)
Pseudo-sequence when `--umbrella` is set:
1. `install_one "$UMBRELLA"` (coordinator profile) — R5. Then ensure coordinator config has
   `umbrella.manifest` pointed at the manifest (R6) and an `integration_command` key (R7).
   On fresh install, set `umbrella.manifest: "umbrella.manifest.yaml"` in the coordinator
   config; on upgrade, `migrate_config` guarantees the key exists, then set it if still blank.
2. **Discover** immediate children (R4, R8, R9): iterate `"$UMBRELLA"/*/`; for each dir,
   skip if name begins with `.` or equals `.harness` (R9); select iff `[ -e "$child/.git" ]`
   (matches dir OR file — R8).
3. For each selected child: validate name against `^[a-z0-9-]+$` (R13). On mismatch, print a
   clear skip message naming the child + grammar and `continue` (no install, no entry). On
   match, `install_one "$child"` (R10) then upsert its manifest entry (R12, R14).
4. **Manifest upsert** (R11–R15): if `umbrella.manifest.yaml` absent, create it with a
   `repos:` header (R11). For each kept child, if its key is not already present under
   `repos:` (anchored two-space `grep`), append a block:
   ```
     <name>:
       path: ./<name>          # discovered relative to umbrella root
       init: ./init.sh         # TODO: confirm child init
       test_command: ""        # TODO: set during bootstrap
       delegate_cmd: ""        # TODO: wire executor
   ```
   If the key already exists, leave its block untouched (R14). Keys are literal directory
   names already validated to `^[a-z0-9-]+$` (R15), matching `init.sh`'s check.

> The manifest writer must be append/upsert only — never rewrite existing entries — so a
> bootstrap-filled `test_command`/`delegate_cmd` survives re-runs (R14), mirroring the
> never-clobber guarantee for `harness.config.yaml`.

## Coordinator vs child profile  (serves: R5, R6, R7, R10)
The body is identical (no second copy of the harness). The difference is post-install config:
- **Coordinator:** `umbrella.manifest` set (R6); `integration_command` present (R7); no per-repo
  `test_command` beyond the existing blank-on-seed (R7).
- **Child:** the existing single-target install, no umbrella keys touched beyond the generic
  migration (R10). Children remain inert single-repo harnesses until a manifest is pointed at
  them — which the cascade does NOT do for children (only the coordinator gets a manifest).

## Files to change  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `harness-install.sh` | modify — add `--umbrella`/`--recursive` arg parsing; refactor body into `install_one`; add `migrate_config`; add the umbrella driver (discover + per-child install + manifest upsert); call `migrate_config` on upgrades | R1–R24 |
| `umbrella.manifest.example.yaml` | (reference only) — auto-populated manifest must match this shape; no change expected unless the placeholder comment wording is aligned | R12, R15 |
| `docs/INSTALL.md` | modify — document the umbrella/cascade invocation, the two profiles, depth-1 git-gating, idempotency, and the config migration | R1, R5, R8, R18 |
| `docs/UMBRELLA.md` | modify — add a short "Installing the umbrella (cascade)" pointer to the installer command | R1, R5 |
| `tests/test_cascade.sh` | create — executable contract for every F02 R-id (see .tests.md); zero-dep POSIX sh, self-cleaning temp tree with fake git children (`.git` as dir AND as file) | all |
| `verification.test_command` (harness.config.yaml) | modify — append `&& sh tests/test_cascade.sh` to run the new suite | all |

## DO NOT TOUCH
- The single-target code path's observable behavior — `install_one("$TARGET")` must produce
  byte-for-byte the same result as today (guarded by `tests/test_install.sh`) (R2, R24).
- `agents/*.md`, `store/tasks.schema.json`, `store/local.md`, `init.sh`'s validation logic —
  F02 is install mechanics only; F01 owns the runtime/schema. (init.sh is reused as the
  child/coordinator gate, not modified.)
- F01's manifest shape and config-key names — reuse verbatim, do not rename.
- The existing seed-once-never-clobber logic for `harness.config.yaml`, `product.md`,
  `tasks.json`, `init.project.sh`, `progress/` — the cascade relies on it per child (R16).

## Approach notes
- **Reuse, don't fork:** one script, one body copy per target, a single `install_one`. The
  cascade is orchestration over the existing primitive.
- **Append-only everywhere new:** both `migrate_config` and the manifest upsert are strictly
  additive (never rewrite a present line/entry), which is what makes re-runs idempotent
  (R14, R19, R20) and protects project-owned values.
- **`.git` detection uses `-e`, not `-d`:** `[ -e "$child/.git" ]` matches a dir (normal
  clone) and a file (worktree/submodule gitlink) in one test (R8).
- **Resolve relative paths from the umbrella root:** manifest `path` is written as `./<name>`
  so `init.sh`'s manifest check (which joins relative paths to the manifest's dir) resolves
  it (R12, R15).
- **Migration only on upgrade:** a fresh install already seeds the current shipped config, so
  `migrate_config` is a no-op there; running it only on the upgrade branch avoids touching a
  freshly-correct file (R18, R20).
- **Test the pre-F01 config explicitly:** the genuinely tricky regression (Codex's note) is a
  config with NO `umbrella:` block. The test must build that fixture, upgrade, and assert the
  key was appended while bootstrap values (e.g. a set `test_command`) survived (R18, R19).
- Leave `--recursive`'s deep semantics minimal/deferred per the spec's open question; if
  shipped, keep it git-gated and dotfile/`.harness`-skipping (R4, R8, R9).
