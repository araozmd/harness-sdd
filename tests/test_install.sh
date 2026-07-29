#!/bin/sh
# test_install.sh — the harness's own product tests.
# Exercises harness-install.sh end to end: fresh install layout, idempotent
# upgrade, project-file preservation, entrypoint merge, and that the installed
# init.sh passes from the target. Zero dependencies; self-cleaning temp dir.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
trap 'rm -rf "$T"' EXIT

# Sandbox CODEX_HOME under the temp dir for the WHOLE suite. Current Codex installs must
# never write there; migration cases below seed legacy prompts explicitly.
export CODEX_HOME="$T/codex-home"

# E18-F01: `pr_loop.enabled` is an OPT-IN gate — a fresh install seeds `false` and stamps
# no /sdd-pr-loop glue at all. This suite's job is the COMMAND-SURFACE contract (generated
# into every selected front-end, reclaimed on deselect), which only has a subject when the
# loop is on, so arm the gate for the whole suite via the env override. The opt-in default
# itself is owned by tests/test_pr_loop.sh (R3/R15/R18/R18b), which never sets this.
export HARNESS_PR_LOOP_ENABLED=true

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

test_root_gitignore_seeds_local_prompt_files() {
  [ -f "$T/.gitignore" ] || fail "project-root .gitignore not seeded"
  for _p in AGENTS.local.md CLAUDE.local.md AGENTS.override.md; do
    grep -qxF "$_p" "$T/.gitignore" || fail "root .gitignore missing local prompt ignore $_p"
  done
}

# E99-F06: per-run agent output under .harness/progress/ must not be committable in a
# consumer — the harness source has always ignored `progress/*/`, but that ignore was never
# propagated by the installer, so run dirs shipped inside product diffs (796 lines / 5% of
# viernes-bookings-api PR #76, re-read by the reviewer on all twelve rounds).
#
# Asserted as BEHAVIOR via `git check-ignore`, not as string presence: the re-inclusion of
# progress/inbox/ only works if it FOLLOWS `progress/*/` in the file, and no grep can see
# ordering. A string-only test would pass on a .gitignore that silently ignores every brief.
test_progress_run_dirs_gitignored() {
  grep -qxF 'progress/*/' "$T/.harness/.gitignore" \
    || fail ".harness/.gitignore does not ignore per-run progress dirs (progress/*/) — agent scratch would ship in the product diff"
  command -v git >/dev/null 2>&1 || return 0
  _g="$T/.gitignore-probe"
  rm -rf "$_g"
  mkdir -p "$_g"
  git -C "$_g" init -q >/dev/null 2>&1 || { rm -rf "$_g"; return 0; }
  mkdir -p "$_g/.harness/progress/E01-F01-run" "$_g/.harness/progress/inbox"
  cp "$T/.harness/.gitignore" "$_g/.harness/.gitignore"
  : > "$_g/.harness/progress/E01-F01-run/build.md"
  : > "$_g/.harness/progress/inbox/E01-F01.md"
  : > "$_g/.harness/progress/history.md"
  git -C "$_g" check-ignore -q .harness/progress/E01-F01-run/build.md \
    || fail "per-run progress output is NOT ignored by the seeded .harness/.gitignore — agent scratch would be committed into the product diff"
  ! git -C "$_g" check-ignore -q .harness/progress/inbox/E01-F01.md \
    || fail "progress/inbox briefs ARE ignored by the seeded .harness/.gitignore — the Architect's durable per-feature seeds would be lost (re-inclusion must follow progress/*/)"
  ! git -C "$_g" check-ignore -q .harness/progress/history.md \
    || fail "progress/history.md IS ignored by the seeded .harness/.gitignore — project history would be lost"
  rm -rf "$_g"
}

# E21-F01: the change_size budget must reach a consumer both as config (the numbers, which a
# target may retune) and as prompt text in the INSTALLED role files (the rule, which it may
# not). Config-only would ship numbers nobody reads; prompt-only would hard-code a per-repo
# budget into a harness-OWNED file that the next upgrade clobbers.
test_change_size_block_seeded() {
  _c="$T/.harness/harness.config.yaml"
  grep -Eq '^change_size:[[:space:]]*(#.*)?$' "$_c" \
    || fail "installed harness.config.yaml has no top-level change_size: block (E21-F01 R1)"
  for _kv in 'advise_lines: 1500' 'escalate_lines: 3000' 'advise_files: 25' \
             'escalate_files: 50' 'max_requirements: 12'; do
    grep -qF "$_kv" "$_c" || fail "installed change_size block missing default: $_kv (E21-F01 R1/R2)"
  done
  grep -qF 'change_size.max_requirements' "$T/.harness/agents/driller.md" \
    || fail "installed driller.md does not carry the size budget rule (E21-F01 R10)"
  grep -qF 'change_size.max_requirements' "$T/.harness/agents/architect.md" \
    || fail "installed architect.md does not carry the size budget rule (E21-F01 R10)"
  grep -qF 'change_size' "$T/.harness/docs/WORKFLOW.md" \
    || fail "installed docs/WORKFLOW.md does not document change_size (E21-F01 R9)"
  # E21-F02: the pre-PR check ships as a runnable tool, not just a rule in a prompt. A role
  # file that tells the Reviewer to run a script the installer never made executable is a
  # silent no-op in every consumer.
  [ -f "$T/.harness/tools/change-size.sh" ] \
    || fail "tools/change-size.sh not installed (the pre-PR size check would be missing in consumers) (E21-F02)"
  [ -x "$T/.harness/tools/change-size.sh" ] \
    || fail "installed tools/change-size.sh is not executable (the pre-PR size check would not run) (E21-F02)"
  grep -qF 'tools/change-size.sh' "$T/.harness/agents/reviewer.md" \
    || fail "installed reviewer.md does not run the pre-PR change-size check (E21-F02)"
  grep -qF 'tools/change-size.sh' "$T/.harness/agents/orchestrator.md" \
    || fail "installed orchestrator.md does not run the pre-PR change-size check (E21-F02)"
  for _k in 'test_paths:' 'generated_paths:'; do
    grep -qF "$_k" "$T/.harness/harness.config.yaml" \
      || fail "installed change_size block missing classifier key $_k (E21-F02)"
  done
}

test_entrypoints_reference_local_overrides() {
  test_entrypoints_reference_agents_local
  test_local_override_guidance_is_conditional
  test_local_override_precedence_wording
}

test_entrypoints_reference_agents_local() {
  for _ep in AGENTS.md CLAUDE.md GEMINI.md; do
    grep -qF 'AGENTS.local.md' "$T/$_ep" \
      || fail "$_ep missing AGENTS.local.md local override guidance"
  done
}

test_local_override_guidance_is_conditional() {
  for _ep in AGENTS.md CLAUDE.md GEMINI.md; do
    grep -qF 'if present' "$T/$_ep" \
      || fail "$_ep local override guidance is not conditional"
  done
  [ ! -e "$T/AGENTS.local.md" ] || fail "installer must not require or create AGENTS.local.md"
}

test_local_override_precedence_wording() {
  for _ep in AGENTS.md CLAUDE.md GEMINI.md; do
    grep -qF 'committed instructions remain authoritative' "$T/$_ep" \
      || fail "$_ep missing committed-instructions precedence wording"
  done
}

test_existing_entrypoint_prose_preserved() {
  grep -qF 'Custom instructions here.' "$T/CLAUDE.md" || fail "custom CLAUDE.md content lost"
}

test_config_layering_documents_personal_prompt_layer() {
  grep -qF 'personal prompt' "$T/.harness/docs/CONFIG-LAYERING.md" \
    || fail "CONFIG-LAYERING.md missing personal prompt layer"
  grep -qF 'AGENTS.local.md' "$T/.harness/docs/CONFIG-LAYERING.md" \
    || fail "CONFIG-LAYERING.md missing portable AGENTS.local.md convention"
  grep -qF 'additive' "$T/.harness/docs/CONFIG-LAYERING.md" \
    || fail "CONFIG-LAYERING.md missing additive local prompt guidance"
}

test_config_layering_documents_native_local_prompt_files() {
  grep -qF 'CLAUDE.local.md' "$T/.harness/docs/CONFIG-LAYERING.md" \
    || fail "CONFIG-LAYERING.md missing Claude native local prompt file"
  grep -qF 'AGENTS.override.md' "$T/.harness/docs/CONFIG-LAYERING.md" \
    || fail "CONFIG-LAYERING.md missing Codex native override file"
}

test_config_layering_documents_local_prompt_caveats() {
  grep -qF 'fresh worktrees' "$T/.harness/docs/CONFIG-LAYERING.md" \
    || fail "CONFIG-LAYERING.md missing fresh-worktree caveat"
  grep -qF 'native local-file support differs by CLI' "$T/.harness/docs/CONFIG-LAYERING.md" \
    || fail "CONFIG-LAYERING.md missing per-tool native support caveat"
}

test_umbrella_gitignore_example_includes_local_prompt_files() {
  for _p in AGENTS.local.md CLAUDE.local.md AGENTS.override.md; do
    grep -qxF "$_p" "$T/.harness/umbrella.gitignore.example" \
      || fail "umbrella.gitignore.example missing local prompt ignore $_p"
  done
}

test_version_and_changelog_for_local_overrides() {
  # Assert the E09-F02 CHANGELOG entry landed (not a frozen exact VERSION, which
  # recurs as a permanent-suite anti-pattern and breaks on later PATCH bumps).
  grep -qF '## [0.27.0]' "$SRC/CHANGELOG.md" || fail "CHANGELOG missing 0.27.0 entry"
  grep -qF 'local prompt override' "$SRC/CHANGELOG.md" \
    || fail "CHANGELOG missing local prompt override summary"
}

test_root_gitignore_preserves_user_entries() {
  grep -qF 'my-secret-dir/' "$T/.gitignore" || fail "user entry in root .gitignore clobbered on upgrade"
}

test_root_gitignore_local_prompt_entries_idempotent() {
  for _p in AGENTS.local.md CLAUDE.local.md AGENTS.override.md; do
    [ "$(grep -cxF "$_p" "$T/.gitignore")" = "1" ] \
      || fail "root .gitignore local prompt seed duplicated on upgrade: $_p"
  done
}

test_fix_worktree_helper_installed_executable() {
  [ -x "$T/.harness/tools/fix-worktree.sh" ] ||
    fail "installed tools/fix-worktree.sh is missing or not executable"
}

test_dependency_diagnostics_installed_contract() {
  [ -x "$T/.harness/tools/task-diagnostics.py" ] ||
    fail "E16-F01: installed task-diagnostics.py missing or not executable"
  cmp -s "$SRC/tools/task-diagnostics.py" "$T/.harness/tools/task-diagnostics.py" ||
    fail "E16-F01: installed diagnostic helper differs from source"
  grep -qF 'chmod +x "$H/tools/task-diagnostics.py"' "$SRC/harness-install.sh" ||
    fail "E16-F01: installer lacks explicit diagnostic-helper executable wiring"
  grep -qF 'tools/task-diagnostics.py cycles state/tasks.json' "$T/.harness/init.sh" ||
    fail "E16-F01: installed init does not invoke diagnostic helper"
  for code in dependency-cycle gated-epic unmet-dependency human-gate \
    owner-excluded owner-unresolved no-candidates
  do
    grep -qF "\`$code\`" "$T/.harness/agents/orchestrator.md" ||
      fail "E16-F01: installed Orchestrator missing reason $code"
  done
  grep -qF 'top-level selection returns a sliced feature' \
    "$T/.harness/agents/orchestrator.md" ||
    fail "E16-F01: installed Orchestrator missing sliced-parent no-result trigger"
  grep -qF 'whole-board top-level diagnostics' \
    "$T/.harness/agents/orchestrator.md" ||
    fail "E16-F01: installed Orchestrator missing sliced-parent diagnostic scope"

  cp "$T/.harness/state/tasks.json" "$T/.harness/state/tasks.json.e16-backup"
  cat >"$T/.harness/state/tasks.json" <<'JSON'
{"project":"fixture","epics":[{"id":"E16","title":"x","status":"planned","features":[
 {"id":"E16-F1","title":"a","status":"pending","sdd":true,"autonomous":true,
  "depends_on":["E16-F2"],"spec_path":"a/"},
 {"id":"E16-F2","title":"b","status":"pending","sdd":true,"autonomous":true,
  "depends_on":["E16-F1"],"spec_path":"b/"}
]}]}
JSON
  "$T/.harness/init.sh" >"$T/e16-installed-init.out" 2>"$T/e16-installed-init.err" ||
    fail "E16-F01: installed init failed for a schema-valid cyclic board"
  grep -qF 'TaskStore dependency-cycle [feature]: E16-F1 -> E16-F2 -> E16-F1 (warn-only)' \
    "$T/e16-installed-init.out" ||
    fail "E16-F01: installed init did not execute full-path warn-only diagnostic"
  mv "$T/.harness/state/tasks.json.e16-backup" "$T/.harness/state/tasks.json"
}

test_next_task_installed_contract() {
  [ -x "$T/.harness/tools/next-task.mjs" ] ||
    fail "E16-F03: installed next-task.mjs missing or not executable"
  cmp -s "$SRC/tools/next-task.mjs" "$T/.harness/tools/next-task.mjs" ||
    fail "E16-F03: installed selector differs from source"
  grep -qF 'chmod +x "$H/tools/next-task.mjs"' "$SRC/harness-install.sh" ||
    fail "E16-F03: installer lacks explicit selector executable wiring"

  cp "$T/.harness/state/tasks.json" "$T/.harness/state/tasks.json.e16f03-backup"
  cat >"$T/.harness/state/tasks.json" <<'JSON'
{"project":"installed-fixture","epics":[{"id":"E2","title":"two","status":"planned","features":[
 {"id":"E2-F1","title":"next","status":"in-progress","sdd":true,"spec_path":"specs/next/"}
]}]}
JSON
  _actual="$(cd / && node "$T/.harness/tools/next-task.mjs" --json)" ||
    fail "E16-F03: installed-layout default-path selector failed outside target cwd"
  printf '%s\n' "$_actual" | grep -qF '"feature_id":"E2-F1"' ||
    fail "E16-F03: installed selector did not resolve its own TaskStore"
  printf '%s\n' "$_actual" | grep -qF '"route":"builder"' ||
    fail "E16-F03: installed selector returned wrong route"
  mv "$T/.harness/state/tasks.json.e16f03-backup" "$T/.harness/state/tasks.json"
}

test_rationale_docs_installed_contract() {
  [ -f "$T/.harness/docs/RATIONALE.md" ] ||
    fail "E16-F02: installed rationale document missing"
  cmp -s "$SRC/docs/RATIONALE.md" "$T/.harness/docs/RATIONALE.md" ||
    fail "E16-F02: installed rationale differs from source"
  grep -qF '| `docs/RATIONALE.md` |' "$T/.harness/AGENTS.md" ||
    fail "E16-F02: installed AGENTS docs map does not point to rationale"
  grep -qF '[rationale and deletion ledger](RATIONALE.md)' \
    "$T/.harness/docs/HARNESS.md" ||
    fail "E16-F02: installed HARNESS overview does not point to rationale"
}

test_worktree_ignore_seed_preserved_idempotent() {
  [ "$(grep -cxF '.claude/worktrees/' "$T/.gitignore")" = "1" ] ||
    fail "root .gitignore must contain exactly one .claude/worktrees/ entry"
  grep -qF 'my-secret-dir/' "$T/.gitignore" ||
    fail "worktree ignore seeding clobbered a user entry"
}

test_fix_worktree_version_policy() {
  _versions="$(awk '
    /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ {
      version=$2; gsub(/[][]/, "", version)
      if (feature != "" && older == "") { older=version; print feature; print older; exit }
      section=version
    }
    /E15-F02/ && feature == "" { feature=section }
  ' "$SRC/CHANGELOG.md")"
  _feature="$(printf '%s\n' "$_versions" | sed -n '1p')"
  _older="$(printf '%s\n' "$_versions" | sed -n '2p')"
  [ -n "$_feature" ] && [ -n "$_older" ] ||
    fail "could not locate E15-F02 changelog section and immediately older section"
  IFS=. read -r _fmaj _fmin _fpatch <<EOF
$_feature
EOF
  IFS=. read -r _omaj _omin _opatch <<EOF
$_older
EOF
  [ "$_fmaj" -eq "$_omaj" ] && [ "$_fmin" -eq $((_omin + 1)) ] && [ "$_fpatch" -eq 0 ] ||
    fail "E15-F02 version $_feature is not one MINOR above $_older"
  _current="$(cat "$SRC/VERSION")"
  [ "$(printf '%s\n%s\n' "$_feature" "$_current" | sort -V | tail -1)" = "$_current" ] ||
    fail "current VERSION $_current is older than E15-F02 feature version $_feature"
}

# A pre-existing entrypoint with custom prose that MUST survive.
printf '# My Project\n\nCustom instructions here.\n' > "$T/CLAUDE.md"

# ── fresh install ─────────────────────────────────────────────────────────────
sh "$SRC/harness-install.sh" "$T" >/dev/null || fail "installer exited non-zero"

[ -f "$T/.harness/AGENTS.md" ]                 || fail ".harness/AGENTS.md missing"          # R1
[ -f "$T/.harness/agents/orchestrator.md" ]    || fail "role bodies missing"                 # R1
[ -d "$T/.harness/docs" ]                      || fail "docs/ missing"                       # R1
[ -f "$T/.harness/store/tasks.schema.json" ]   || fail "schema missing"                      # R1
[ -f "$T/.harness/umbrella.manifest.example.yaml" ] || fail "umbrella manifest example not installed" # R1
[ -f "$T/.harness/umbrella.gitignore.example" ] || fail "umbrella .gitignore example not installed"    # R1
[ -f "$T/.harness/tools/telemetry-report.py" ] || fail "tools/telemetry-report.py not installed (telemetry summary would fail in consumers)" # R1
# E11-F01 R12: the github-projects board mirror tool must ship in the body AND be executable
# (installer wiring asserted, not just emitted) [sync_board_tool_installed_executable].
[ -f "$T/.harness/tools/sync-board.mjs" ] || fail "tools/sync-board.mjs not installed (board mirror would be missing in consumers)" # R12
[ -x "$T/.harness/tools/sync-board.mjs" ] || fail "installed tools/sync-board.mjs is not executable (board mirror not runnable)"      # R12
# E15-F01 R10: the board write-lock helper must ship in the body AND be executable
# (installer wiring asserted, not just emitted) so set_status can run the guarded write.
[ -f "$T/.harness/tools/tasks-lock.py" ] || fail "tools/tasks-lock.py not installed (board write lock would be missing in consumers)" # R10
[ -x "$T/.harness/tools/tasks-lock.py" ] || fail "installed tools/tasks-lock.py is not executable (board write lock not runnable)"     # R10
test_fix_worktree_helper_installed_executable
test_dependency_diagnostics_installed_contract
test_next_task_installed_contract
test_rationale_docs_installed_contract
# E15-F01 (Codex #46 r2 P1): the SHARED board validator must ship in the body AND be
# executable — init.sh runs it as a CLI and tasks-lock.py imports its validate(); if it
# is missing the gate and the guarded write both break in consumers.
[ -f "$T/.harness/tools/validate-board.py" ] || fail "tools/validate-board.py not installed (shared board validator missing; init.sh + tasks-lock would break)" # R10
[ -x "$T/.harness/tools/validate-board.py" ] || fail "installed tools/validate-board.py is not executable (shared board validator not runnable)"                # R10
# E12-F01 R16: a fresh install must gitignore the default Jira mirror PAT file
# (mirror.board.pat_file default `jira.pat`, resolved under the harness dir ⇒
# `.harness/jira.pat`, i.e. `jira.pat` relative to the .harness/ .gitignore where the tool
# reads it) so a provisioned Jira PAT can never be committed by default
# [jira_pat_file_gitignored]. Assert the seeded .harness/.gitignore covers it.
[ -f "$T/.harness/.gitignore" ]                    || fail ".harness/.gitignore not seeded (Jira PAT would not be ignored)" # R16
grep -qxF 'jira.pat' "$T/.harness/.gitignore"      || fail ".harness/.gitignore does not ignore the default Jira PAT file (jira.pat) — a PAT could be committed" # R16
test_progress_run_dirs_gitignored   # E99-F06
test_change_size_block_seeded       # E21-F01
[ -x "$T/.harness/init.sh" ]                   || fail ".harness/init.sh not executable"     # R1
[ -f "$T/.harness/specs/product.md" ]          || fail "product.md stub not seeded"          # R6
[ -f "$T/.harness/state/tasks.json" ]          || fail "bootstrap tasks.json missing"        # R6
# E09-F01: doc-critic role is installed and the generating-agent contracts reference it.
[ -f "$T/.harness/agents/doc-critic.md" ]      || fail "doc-critic role not installed"       # R13
grep -qF 'doc-critic' "$T/.harness/agents/planner.md"   || fail "installed planner does not reference doc-critic"   # R14
grep -qF 'doc-critic' "$T/.harness/agents/driller.md"   || fail "installed driller does not reference doc-critic"   # R14
grep -qF 'doc-critic' "$T/.harness/agents/architect.md" || fail "installed architect does not reference doc-critic" # R14
grep -qF 'target-type=plan-output' "$T/.harness/agents/planner.md"     || fail "installed planner missing target-type=plan-output"     # R14
grep -qF 'target-type=epic-decomposition' "$T/.harness/agents/driller.md" || fail "installed driller missing target-type=epic-decomposition" # R14
grep -qF 'target-type=feature-spec' "$T/.harness/agents/architect.md"   || fail "installed architect missing target-type=feature-spec"   # R14
pass "fresh install layout correct (R1, R6) + doc-critic installed and referenced (R13, R14)"

# project-root .gitignore append-seeded with personal/runtime agent state, ignoring
# SPECIFIC .claude/ files (never the whole dir, so generated agents/commands stay tracked).
[ -f "$T/.gitignore" ]                                  || fail "project-root .gitignore not seeded"
grep -qF '.claude/settings.local.json' "$T/.gitignore"  || fail "root .gitignore missing settings.local.json"
grep -qF '.claude/scheduled_tasks.lock' "$T/.gitignore" || fail "root .gitignore missing scheduler-lock"
for _p in AGENTS.local.md CLAUDE.local.md AGENTS.override.md; do
  grep -qxF "$_p" "$T/.gitignore" || fail "root .gitignore missing local prompt ignore $_p"
done
test_root_gitignore_seeds_local_prompt_files
grep -qxF '.claude/' "$T/.gitignore"                    && fail "root .gitignore over-ignores the whole .claude/ dir"
grep -qxF '.claude/worktrees/' "$T/.gitignore"          || fail "root .gitignore missing worktree runtime directory"
[ -f "$T/.harness/docs/CONFIG-LAYERING.md" ]            || fail "CONFIG-LAYERING.md not installed"
pass "project-root .gitignore seeds personal/runtime and local prompt ignores (config layering)"

# E09-F02: generated entrypoint marker blocks document optional local prompt guidance.
for _ep in AGENTS.md CLAUDE.md GEMINI.md; do
  grep -qF 'AGENTS.local.md' "$T/$_ep" \
    || fail "$_ep missing AGENTS.local.md local override guidance"
  grep -qF 'if present' "$T/$_ep" \
    || fail "$_ep local override guidance is not conditional"
  grep -qF 'committed instructions remain authoritative' "$T/$_ep" \
    || fail "$_ep missing committed-instructions precedence wording"
done
[ ! -e "$T/AGENTS.local.md" ] || fail "installer must not require or create AGENTS.local.md"
test_entrypoints_reference_local_overrides
pass "entrypoints reference optional local overrides with committed-instructions precedence"

# E09-F02: config layering docs describe the personal prompt layer and caveats.
grep -qF 'personal prompt' "$T/.harness/docs/CONFIG-LAYERING.md" \
  || fail "CONFIG-LAYERING.md missing personal prompt layer"
grep -qF 'AGENTS.local.md' "$T/.harness/docs/CONFIG-LAYERING.md" \
  || fail "CONFIG-LAYERING.md missing portable AGENTS.local.md convention"
grep -qF 'CLAUDE.local.md' "$T/.harness/docs/CONFIG-LAYERING.md" \
  || fail "CONFIG-LAYERING.md missing Claude native local prompt file"
grep -qF 'AGENTS.override.md' "$T/.harness/docs/CONFIG-LAYERING.md" \
  || fail "CONFIG-LAYERING.md missing Codex native override file"
grep -qF 'additive' "$T/.harness/docs/CONFIG-LAYERING.md" \
  || fail "CONFIG-LAYERING.md missing additive local prompt guidance"
grep -qF 'fresh worktrees' "$T/.harness/docs/CONFIG-LAYERING.md" \
  || fail "CONFIG-LAYERING.md missing fresh-worktree caveat"
grep -qF 'native local-file support differs by CLI' "$T/.harness/docs/CONFIG-LAYERING.md" \
  || fail "CONFIG-LAYERING.md missing per-tool native support caveat"
grep -qF '.claude/worktrees/' "$T/.harness/docs/CONFIG-LAYERING.md" \
  || fail "CONFIG-LAYERING.md missing worktree local-only directory"
grep -qF 'absolute symlink' "$T/.harness/docs/CONFIG-LAYERING.md" \
  || fail "CONFIG-LAYERING.md missing worktree personal-layer link policy"
test_config_layering_documents_personal_prompt_layer
test_config_layering_documents_native_local_prompt_files
test_config_layering_documents_local_prompt_caveats
pass "CONFIG-LAYERING.md documents personal prompt files and caveats"

# E09-F02: umbrella/shared-spec .gitignore example carries the same local prompt ignores.
for _p in AGENTS.local.md CLAUDE.local.md AGENTS.override.md; do
  grep -qxF "$_p" "$T/.harness/umbrella.gitignore.example" \
    || fail "umbrella.gitignore.example missing local prompt ignore $_p"
done
test_umbrella_gitignore_example_includes_local_prompt_files
pass "umbrella gitignore example includes local prompt ignores"

# E09-F02: installed-body change is versioned (assert the CHANGELOG entry landed, not a
# frozen exact VERSION — freezing VERSION recurs as an anti-pattern and breaks on PATCH bumps).
grep -qF '## [0.27.0]' "$SRC/CHANGELOG.md" || fail "CHANGELOG missing 0.27.0 entry"
grep -qF 'local prompt override' "$SRC/CHANGELOG.md" \
  || fail "CHANGELOG missing local prompt override summary"
test_version_and_changelog_for_local_overrides
test_fix_worktree_version_policy
pass "VERSION and CHANGELOG record local overrides convention"

# version stamp matches source VERSION                                                        # R2
[ "$(cat "$T/.harness/.harness-version")" = "$(cat "$SRC/VERSION")" ] || fail "version mismatch"
pass "version stamped (R2)"

# entrypoint: custom prose preserved AND a single harness block added                          # R3
grep -qF 'Custom instructions here.' "$T/CLAUDE.md" || fail "custom CLAUDE.md content lost"
grep -qF '<!-- harness:begin -->'     "$T/CLAUDE.md" || fail "harness block not added"
[ -f "$T/AGENTS.md" ] && [ -f "$T/GEMINI.md" ]      || fail "AGENTS.md/GEMINI.md not created"
test_existing_entrypoint_prose_preserved
pass "entrypoint merge preserves prose + adds block (R3)"

# Claude Code glue points at .harness/                                                         # R7
[ -f "$T/.claude/commands/sdd-next.md" ] || fail "sdd-next command missing"
# E10-F01: the generated /sdd-next glue forwards $ARGUMENTS and carries the --mine
# scoped-selection wiring (owned-only, delegating to the Orchestrator contract).
grep -qF '$ARGUMENTS' "$T/.claude/commands/sdd-next.md" \
  || fail "sdd-next does not forward \$ARGUMENTS (E10-F01 scope wiring)"
grep -qF -- '--mine' "$T/.claude/commands/sdd-next.md" \
  || fail "sdd-next does not carry the --mine scoped-selection wiring (E10-F01)"
grep -qiF 'effective owner' "$T/.claude/commands/sdd-next.md" \
  || fail "sdd-next --mine wiring does not reference the effective-owner scope (E10-F01)"
[ -f "$T/.claude/commands/sdd-new.md" ]  || fail "sdd-new command missing"
[ -f "$T/.claude/commands/sdd-plan.md" ] || fail "sdd-plan command missing"
# installed /sdd-plan must act as Planner, resolved against .harness/, and carry args
grep -qF '.harness/agents/planner.md' "$T/.claude/commands/sdd-plan.md" \
  || fail "sdd-plan does not resolve planner against .harness/"
grep -qF '$ARGUMENTS' "$T/.claude/commands/sdd-plan.md" \
  || fail "sdd-plan does not carry \$ARGUMENTS"
[ -f "$T/.claude/commands/sdd-drill.md" ] || fail "sdd-drill command missing"
# installed /sdd-drill must act as Driller, resolved against .harness/, and carry args
grep -qF '.harness/agents/driller.md' "$T/.claude/commands/sdd-drill.md" \
  || fail "sdd-drill does not resolve driller against .harness/"
grep -qF '$ARGUMENTS' "$T/.claude/commands/sdd-drill.md" \
  || fail "sdd-drill does not carry \$ARGUMENTS"
[ -f "$T/.harness/agents/driller.md" ] \
  || fail "driller role not installed into profile"
# R15/R16: installed /sdd-fix must act as Fixer, resolved against .harness/, carry args
[ -f "$T/.claude/commands/sdd-fix.md" ] || fail "sdd-fix command missing"
grep -qF '.harness/agents/fixer.md' "$T/.claude/commands/sdd-fix.md" \
  || fail "sdd-fix does not resolve fixer against .harness/"
grep -qF '$ARGUMENTS' "$T/.claude/commands/sdd-fix.md" \
  || fail "sdd-fix does not carry \$ARGUMENTS"
[ -f "$T/.harness/agents/fixer.md" ] \
  || fail "fixer role not installed into profile"
# test_sdd_fix_parallel_generated_all_frontends
# E15-F03: sixth command + installed defaults resolve through the same Fixer body.
[ -f "$T/.claude/commands/sdd-fix-parallel.md" ] ||
  fail "sdd-fix-parallel command missing"
grep -qF '.harness/agents/fixer.md' "$T/.claude/commands/sdd-fix-parallel.md" ||
  fail "sdd-fix-parallel does not resolve Fixer against .harness/"
grep -qF 'Targeted parallel-fix worker mode' "$T/.claude/commands/sdd-fix-parallel.md" ||
  fail "sdd-fix-parallel does not route targeted workers"
grep -qF 'execution.builder.backend: delegate' "$T/.claude/commands/sdd-fix-parallel.md" ||
  fail "sdd-fix-parallel installed body lacks delegate preflight"
grep -qF 'bookkeeping PR reconciliation' "$T/.claude/commands/sdd-fix-parallel.md" ||
  fail "sdd-fix-parallel installed body lacks bookkeeping reconciliation"
grep -qF 'pre-provisioned branch/worktree' "$T/.claude/commands/sdd-fix-parallel.md" ||
  fail "sdd-fix-parallel installed body can recreate F02 resources"
grep -qF 'one-time F02 provisioning while the primary is clean, complete' \
  "$T/.claude/commands/sdd-fix-parallel.md" ||
  fail "sdd-fix-parallel installed command writes manifest before provisioning"
# E18-F01 R52: the gated /sdd-pr-loop command ships alongside the six ungated ones on a
# default install (pr_loop.enabled defaults to true), resolves the watcher + the pr-fixer
# role against .harness/, and carries $ARGUMENTS.
[ -f "$T/.claude/commands/sdd-pr-loop.md" ] || fail "sdd-pr-loop command missing"
grep -qF '.harness/tools/wait-for-codex.sh' "$T/.claude/commands/sdd-pr-loop.md" \
  || fail "sdd-pr-loop does not resolve the watcher against .harness/"
grep -qF '$ARGUMENTS' "$T/.claude/commands/sdd-pr-loop.md" \
  || fail "sdd-pr-loop does not carry \$ARGUMENTS"
[ -f "$T/.harness/agents/pr-fixer.md" ] \
  || fail "pr-fixer role not installed into profile"
[ -f "$T/.claude/agents/pr-fixer.md" ] \
  || fail "pr-fixer Claude sub-agent shim not emitted"
grep -qF '.harness/agents/pr-fixer.md' "$T/.claude/agents/pr-fixer.md" \
  || fail "pr-fixer shim does not resolve against .harness/"
[ -x "$T/.harness/tools/wait-for-codex.sh" ] \
  || fail "wait-for-codex.sh not installed executable"
if ! python3 - "$T/.harness/agents/fixer.md" <<'PY'
import sys
text = open(sys.argv[1]).read()
provision = text.index("P2 — provision selected worktrees while primary is clean")
manifest = text.index("P3 — complete pre-dispatch manifest")
claim = text.index("P4 — atomic locked batch claim")
assert provision < manifest < claim
PY
then
  fail "installed Fixer manifest phase does not follow clean-primary provisioning"
fi
grep -Eq '^fix_lane:' "$T/.harness/harness.config.yaml" ||
  fail "fresh installed config missing fix_lane"
grep -Eq '^[[:space:]]+max_parallel:[[:space:]]+3' "$T/.harness/harness.config.yaml" ||
  fail "fresh installed config missing max_parallel default"
grep -Eq '^[[:space:]]+shared_paths:[[:space:]]+\[\]' "$T/.harness/harness.config.yaml" ||
  fail "fresh installed config missing shared_paths default"
grep -qF '.harness/agents/orchestrator.md' "$T/.claude/agents/orchestrator.md" \
  || fail "agent shim does not resolve against .harness/"
grep -qF '.harness/agents/inception.md' "$T/.claude/commands/sdd-new.md" \
  || fail "sdd-new does not resolve inception against .harness/"
grep -qE '(^|[^/])agents/inception\.md' "$T/.claude/commands/sdd-new.md" \
  && fail "sdd-new references a bare agents/inception.md (missing .harness/ prefix)"
# installed wrapper must mirror the source: durable template path, not the un-shipped example
grep -qF '.harness/specs/_templates/inbox-brief.md' "$T/.claude/commands/sdd-new.md" \
  || fail "sdd-new does not reference the installed inbox-brief template"
grep -qF 'E04-F01' "$T/.claude/commands/sdd-new.md" \
  && fail "sdd-new references the un-shipped E04-F01.md example brief"
[ -f "$T/.harness/specs/_templates/inbox-brief.md" ] \
  || fail "inbox-brief template not installed into profile"
# installed wrapper must carry the altitude-1 status branch
grep -qF 'pending' "$T/.claude/commands/sdd-new.md" \
  || fail "sdd-new missing altitude-1 pending branch"
grep -qE 'spec-ready|in-review' "$T/.claude/commands/sdd-new.md" \
  || fail "sdd-new missing altitude-1 consumed-status branch"
pass "Claude Code glue generated (R7)"

# ── E09: doc-critic wired into the installed Claude workflow (Codex #39 r1 P1) ────
# The advertised pre-`spec-ready` doc-critic checkpoint must be executable in the
# primary installed Claude path: a doc-critic subagent shim exists, and the generating
# architect subagent can spawn it (Task tool present). Mirrors the .harness role bodies.
[ -f "$T/.claude/agents/doc-critic.md" ] \
  || fail "E09: .claude/agents/doc-critic.md shim not emitted (critic cannot be spawned)"
grep -qF '.harness/agents/doc-critic.md' "$T/.claude/agents/doc-critic.md" \
  || fail "E09: doc-critic shim does not resolve against .harness/"
grep -qE '^tools:.*\bTask\b' "$T/.claude/agents/architect.md" \
  || fail "E09: architect shim lacks the Task tool — cannot spawn the doc-critic checkpoint"
# The critic writes an auditable progress/<run>/doc-critic-<checkpoint>.md note (R7); its shim
# must grant Write or the checkpoint leaves no file-based handoff (Codex #39 r2 P2).
grep -qE '^tools:.*\bWrite\b' "$T/.claude/agents/doc-critic.md" \
  || fail "E09: doc-critic shim lacks the Write tool — cannot record its progress/ note (R7)"
pass "E09: doc-critic spawnable in the installed Claude workflow (shim + architect Task + Write)"

# ── E09: /sdd-plan glue mirrors the drillable-minimum + doc-critic step (Codex #39 r1 P2) ─
# Fresh installs run the slash-command body, so the installed /sdd-plan must require the
# five drillable-minimum epic.md fields AND run the target-type=plan-output checkpoint.
grep -qF 'drillable-minimum' "$T/.claude/commands/sdd-plan.md" \
  || fail "E09: /sdd-plan glue missing the drillable-minimum requirement"
grep -qF 'Business brief' "$T/.claude/commands/sdd-plan.md" \
  || fail "E09: /sdd-plan glue missing drillable-minimum: business brief"
grep -qF 'success criteria' "$T/.claude/commands/sdd-plan.md" \
  || fail "E09: /sdd-plan glue missing drillable-minimum: epic-level success criteria"
grep -qF 'non-goals' "$T/.claude/commands/sdd-plan.md" \
  || fail "E09: /sdd-plan glue missing drillable-minimum: technical considerations/non-goals"
grep -qF 'Cross-epic dependencies' "$T/.claude/commands/sdd-plan.md" \
  || fail "E09: /sdd-plan glue missing drillable-minimum: cross-epic dependencies and boundaries"
grep -qF 'shared ADRs' "$T/.claude/commands/sdd-plan.md" \
  || fail "E09: /sdd-plan glue missing drillable-minimum: pointers to relevant shared ADRs"
grep -qF 'target-type=plan-output' "$T/.claude/commands/sdd-plan.md" \
  || fail "E09: /sdd-plan glue missing the target-type=plan-output doc-critic checkpoint"
grep -qF 'Doc-critic' "$T/.claude/commands/sdd-plan.md" \
  || fail "E09: /sdd-plan glue does not name the Doc-critic"
# and /sdd-drill mirrors its own epic-decomposition checkpoint
grep -qF 'target-type=epic-decomposition' "$T/.claude/commands/sdd-drill.md" \
  || fail "E09: /sdd-drill glue missing the target-type=epic-decomposition doc-critic checkpoint"
pass "E09: /sdd-plan + /sdd-drill glue carry drillable-minimum + doc-critic checkpoints"

# OpenCode glue: same slash commands installed under .opencode/command/                        # R7
[ -f "$T/.opencode/command/sdd-next.md" ] || fail "opencode sdd-next command missing"
[ -f "$T/.opencode/command/sdd-new.md" ]  || fail "opencode sdd-new command missing"
[ -f "$T/.opencode/command/sdd-plan.md" ] || fail "opencode sdd-plan command missing"
[ -f "$T/.opencode/command/sdd-drill.md" ] || fail "opencode sdd-drill command missing"
[ -f "$T/.opencode/command/sdd-fix.md" ] || fail "opencode sdd-fix command missing"
# E22-F01: /sdd-fix-parallel requires concurrent subagents, which OpenCode may not provide.
# It is skipped by default; only the probe command is installed.
[ -f "$T/.opencode/command/sdd-test-concurrency.md" ] \
  || fail "opencode sdd-test-concurrency command missing"
[ ! -f "$T/.opencode/command/sdd-fix-parallel.md" ] \
  || fail "opencode sdd-fix-parallel installed by default (should be opt-in)"
cmp -s "$T/.claude/commands/sdd-next.md" "$T/.opencode/command/sdd-next.md" \
  || fail "opencode sdd-next differs from claude sdd-next"
cmp -s "$T/.claude/commands/sdd-new.md" "$T/.opencode/command/sdd-new.md" \
  || fail "opencode sdd-new differs from claude sdd-new"
cmp -s "$T/.claude/commands/sdd-plan.md" "$T/.opencode/command/sdd-plan.md" \
  || fail "opencode sdd-plan differs from claude sdd-plan"
cmp -s "$T/.claude/commands/sdd-drill.md" "$T/.opencode/command/sdd-drill.md" \
  || fail "opencode sdd-drill differs from claude sdd-drill"
cmp -s "$T/.claude/commands/sdd-fix.md" "$T/.opencode/command/sdd-fix.md" \
  || fail "opencode sdd-fix differs from claude sdd-fix"
# E18-F01 R52/R11: the gated command mirrors into OpenCode byte-identically, and the
# file-based pr-fixer sub-agent is emitted with `mode: subagent`.
[ -f "$T/.opencode/command/sdd-pr-loop.md" ] || fail "opencode sdd-pr-loop command missing"
cmp -s "$T/.claude/commands/sdd-pr-loop.md" "$T/.opencode/command/sdd-pr-loop.md" \
  || fail "opencode sdd-pr-loop differs from claude sdd-pr-loop"
[ -f "$T/.opencode/agent/pr-fixer.md" ] || fail "opencode pr-fixer sub-agent missing"
grep -qE '^mode: subagent$' "$T/.opencode/agent/pr-fixer.md" \
  || fail "opencode pr-fixer is not declared mode: subagent"
pass "OpenCode commands generated (R7)"

# ── Antigravity glue (.agents/, E07-F01 R1–R12) ───────────────────────────────────────────────
# Mirrors the .claude/ + .opencode/ assertions above. A sentinel of canonical orchestrator
# prose proves the glue POINTS at the roles and never forks a body (R3/R5). The default
# install (no override) stamps ALL agents, so antigravity glue is present here.
AG_SENTINEL='You are the **Orchestrator**. You are the project manager of the harness.'

# R1: GEMINI.md managed block boots the Orchestrator against .harness/AGENTS.md.
grep -qF '<!-- harness:begin -->' "$T/GEMINI.md" || fail "GEMINI.md missing harness block (R1)"
grep -qF '.harness/AGENTS.md' "$T/GEMINI.md"     || fail "GEMINI.md block does not point at .harness/AGENTS.md (R1)"

# R2: Antigravity entrypoint rule written + points at the harness source of truth + entry role.
[ -f "$T/.agents/rules/harness.md" ]                                  || fail "antigravity rule .agents/rules/harness.md missing (R2)"
grep -qF '.harness/AGENTS.md' "$T/.agents/rules/harness.md"           || fail "antigravity rule does not point at .harness/AGENTS.md (R2)"
grep -qF '.harness/agents/orchestrator.md' "$T/.agents/rules/harness.md" || fail "antigravity rule does not point at the orchestrator role (R2)"
# R3: rule points at canonical roles, no copied role body (sentinel must be ABSENT).
grep -qF "$AG_SENTINEL" "$T/.agents/rules/harness.md" && fail "antigravity rule embeds a copied role body (R3)"

# R4/R5 (best-effort, SHAPE only — never registration): one persona per role, each with a
# `description`, deferring to .harness/agents/<role>.md, mandating init.sh + progress/ hand-off,
# with no copied role body. Bare-file persona discovery is unconfirmed, so these assert shape
# (correct plural dir, description, defers to canonical role, sentinel absent) — NOT that the
# persona registers as an Antigravity subagent.
for r in orchestrator architect builder reviewer scout doc-critic; do
  [ -f "$T/.agents/agents/$r.md" ]                       || fail "antigravity persona $r missing (R4)"
  grep -qE '^description:' "$T/.agents/agents/$r.md"      || fail "antigravity persona $r has no description (R4)"
  grep -qF ".harness/agents/$r.md" "$T/.agents/agents/$r.md" || fail "antigravity persona $r does not defer to .harness/agents/$r.md (R5)"
  grep -qF '.harness/init.sh' "$T/.agents/agents/$r.md"  || fail "antigravity persona $r does not mandate .harness/init.sh (R5)"
  grep -qF '.harness/progress/' "$T/.agents/agents/$r.md" || fail "antigravity persona $r does not hand off via .harness/progress/ (R5)"
  grep -qF "$AG_SENTINEL" "$T/.agents/agents/$r.md"      && fail "antigravity persona $r embeds a copied role body (R5)"
done

# R6/R7: all five workflows generated, each carrying a `description` (slash-command registration).
for w in sdd-next sdd-new sdd-plan sdd-drill sdd-fix sdd-fix-parallel sdd-pr-loop; do
  [ -f "$T/.agents/workflows/$w.md" ]                    || fail "antigravity workflow $w missing (R6)"
  grep -qE '^description:' "$T/.agents/workflows/$w.md"   || fail "antigravity workflow $w has no description (R7)"
  grep -qF '$ARGUMENTS' "$T/.agents/workflows/$w.md"      || fail "antigravity workflow $w does not carry \$ARGUMENTS (R8)"
done
# E18-F01 R13/R52: the gated pr-fixer persona is emitted for antigravity too, pointing at
# the canonical role — and it is NOT part of the model-routing persona map.
[ -f "$T/.agents/agents/pr-fixer.md" ] || fail "antigravity pr-fixer persona missing (E18-F01 R13)"
grep -qF '.harness/agents/pr-fixer.md' "$T/.agents/agents/pr-fixer.md" \
  || fail "antigravity pr-fixer persona does not defer to .harness/agents/pr-fixer.md" 

# R8: each workflow acts as its role, resolved against .harness/agents/*.md.
grep -qF '.harness/agents/orchestrator.md' "$T/.agents/workflows/sdd-next.md" || fail "sdd-next workflow does not resolve orchestrator against .harness/ (R8)"
grep -qF '.harness/agents/inception.md'    "$T/.agents/workflows/sdd-new.md"  || fail "sdd-new workflow does not resolve inception against .harness/ (R8)"
grep -qF '.harness/agents/planner.md'      "$T/.agents/workflows/sdd-plan.md" || fail "sdd-plan workflow does not resolve planner against .harness/ (R8)"
grep -qF '.harness/agents/driller.md'      "$T/.agents/workflows/sdd-drill.md" || fail "sdd-drill workflow does not resolve driller against .harness/ (R8)"
grep -qF '.harness/agents/fixer.md'        "$T/.agents/workflows/sdd-fix.md"  || fail "sdd-fix workflow does not resolve fixer against .harness/ (R8)"
grep -qF '.harness/agents/fixer.md' "$T/.agents/workflows/sdd-fix-parallel.md" || fail "sdd-fix-parallel workflow does not resolve fixer"

# R9: each workflow body is byte-identical to the Claude command of the same name (no drift).
for w in sdd-next sdd-new sdd-plan sdd-drill sdd-fix sdd-fix-parallel sdd-pr-loop; do
  cmp -s "$T/.claude/commands/$w.md" "$T/.agents/workflows/$w.md" || fail "antigravity workflow $w differs from claude $w (R9)"
done
pass "Antigravity glue generated (R11)"

# E10-F01 R12/R13: the /sdd-next scoped-selection front-end is generated into EVERY selected
# target (Claude/OpenCode/Antigravity here; Codex repository skills in its select case),
# byte-identical, and each carries the --mine wiring + forwards $ARGUMENTS. The cmp -s chains
# above prove byte-identity across targets; assert the scope token reached each generated body.
for _b in "$T/.claude/commands/sdd-next.md" "$T/.opencode/command/sdd-next.md" "$T/.agents/workflows/sdd-next.md"; do
  grep -qF -- '--mine' "$_b"      || fail "generated /sdd-next glue missing --mine scope wiring: $_b (E10-F01 R12/R13)"
  grep -qF '$ARGUMENTS' "$_b"     || fail "generated /sdd-next glue does not forward \$ARGUMENTS: $_b (E10-F01 R13)"
done
pass "E10-F01: /sdd-next glue generated per target, byte-identical, carries --mine + \$ARGUMENTS [sdd_next_glue_generated_all_targets][sdd_next_scope_wiring_asserted]"

# target verification commands reset to blank                                                  # R8
grep -q 'test_command: ""' "$T/.harness/harness.config.yaml" || fail "test_command not blanked"
pass "target verification commands reset (R8)"

# installed init.sh passes from the target root (self-locating + valid stub schema).           # R10
# Invoke the executable directly (its bash shebang) — NOT via `sh`, which would force
# bash-only `init.sh` through dash on Debian/Ubuntu where /bin/sh is dash.
( cd "$T" && ./.harness/init.sh >/dev/null 2>&1 ) || fail "installed init.sh failed"
pass "installed init.sh passes (R10)"

# ── upgrade: mutate project files, re-run, assert preserved + idempotent ──────
echo 'SENTINEL-PRODUCT' >> "$T/.harness/specs/product.md"
cp "$T/.harness/state/tasks.json" "$T/.harness/state/tasks.json.orig"

sh "$SRC/harness-install.sh" "$T" >/dev/null || fail "upgrade run failed"

grep -qF 'SENTINEL-PRODUCT' "$T/.harness/specs/product.md" || fail "product.md clobbered on upgrade"  # R5
cmp -s "$T/.harness/state/tasks.json" "$T/.harness/state/tasks.json.orig" \
  || fail "tasks.json clobbered on upgrade"                                                          # R5
[ "$(grep -cF '<!-- harness:begin -->' "$T/CLAUDE.md")" = "1" ] \
  || fail "harness block duplicated on upgrade"                                                      # R4
pass "upgrade preserves project files + is idempotent (R4, R5)"

# root .gitignore is append-only: a user-added entry survives upgrade, and a re-run does
# not duplicate the seeded entries (idempotent — the default/inert path is a no-op).
printf 'my-secret-dir/\n' >> "$T/.gitignore"
sh "$SRC/harness-install.sh" "$T" >/dev/null || fail "upgrade run (root .gitignore) failed"
grep -qF 'my-secret-dir/' "$T/.gitignore" || fail "user entry in root .gitignore clobbered on upgrade"
[ "$(grep -cF '.claude/settings.local.json' "$T/.gitignore")" = "1" ] \
  || fail "root .gitignore seed duplicated on upgrade (not idempotent)"
for _p in AGENTS.local.md CLAUDE.local.md AGENTS.override.md; do
  [ "$(grep -cxF "$_p" "$T/.gitignore")" = "1" ] \
    || fail "root .gitignore local prompt seed duplicated on upgrade: $_p"
done
test_root_gitignore_preserves_user_entries
test_root_gitignore_local_prompt_entries_idempotent
test_worktree_ignore_seed_preserved_idempotent
pass "project-root .gitignore is append-only + idempotent on upgrade"

# E99-F06: the .harness/.gitignore APPEND path (a file already exists from the fresh install)
# must add the progress patterns exactly once and must not clobber a target's own entries —
# and the resulting file must still behave correctly, not merely contain the right strings.
printf 'my-harness-scratch/\n' >> "$T/.harness/.gitignore"
sh "$SRC/harness-install.sh" "$T" >/dev/null || fail "upgrade run (.harness/.gitignore) failed"
grep -qxF 'my-harness-scratch/' "$T/.harness/.gitignore" \
  || fail "user entry in .harness/.gitignore clobbered on upgrade"
for _p in 'progress/*/' '!progress/inbox/' '!progress/inbox/**'; do
  [ "$(grep -cxF "$_p" "$T/.harness/.gitignore")" = "1" ] \
    || fail ".harness/.gitignore progress seed duplicated on upgrade (not idempotent): $_p"
done
test_progress_run_dirs_gitignored
pass ".harness/.gitignore progress seed is append-only + idempotent on upgrade (E99-F06)"

# E21-F01 R3: the MIGRATION path. A fresh install copies harness.config.yaml verbatim, so it
# proves nothing about a target whose config predates the block. Strip the block to simulate
# that target, re-run, and assert the installer appends it — then annotate the `change_size:`
# line with a trailing comment (what a target that retuned the budget actually looks like) and
# re-run again: the presence check must tolerate the comment or the target gets a SECOND block
# whose defaults silently shadow the tuned ones.
python3 - "$T/.harness/harness.config.yaml" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s2 = re.sub(r'\n# Change-size discipline.*?\n  max_requirements: \d+\n', '\n', s, flags=re.S)
assert s2 != s, "fixture setup: change_size block not found to strip"
p.write_text(s2)
PY
grep -Eq '^change_size:' "$T/.harness/harness.config.yaml" && fail "fixture setup: change_size block survived the strip"
sh "$SRC/harness-install.sh" "$T" >/dev/null || fail "migration run (change_size) failed"
[ "$(grep -Ec '^change_size:[[:space:]]*(#.*)?$' "$T/.harness/harness.config.yaml")" = "1" ] \
  || fail "installer did not append exactly one change_size: block on migration (E21-F01 R3)"
grep -qF 'max_requirements: 12' "$T/.harness/harness.config.yaml" \
  || fail "migrated change_size block missing max_requirements default (E21-F01 R3)"
# annotated line — the presence check must tolerate a trailing comment
python3 - "$T/.harness/harness.config.yaml" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(re.sub(r'(?m)^change_size:[ \t]*$', 'change_size:   # tuned for this repo', p.read_text()))
PY
sh "$SRC/harness-install.sh" "$T" >/dev/null || fail "upgrade run (annotated change_size) failed"
[ "$(grep -Ec '^change_size:[[:space:]]*(#.*)?$' "$T/.harness/harness.config.yaml")" = "1" ] \
  || fail "installer duplicated the change_size: block over an annotated line (E21-F01 R3)"
grep -qF 'change_size:   # tuned for this repo' "$T/.harness/harness.config.yaml" \
  || fail "installer clobbered the target's annotated change_size: line (E21-F01 R3)"
pass "change_size block migrates once + tolerates an annotated line (E21-F01 R3)"

# root .gitignore seeding uses EXACT-LINE matching (grep -qxF), not substring: a pre-existing
# .gitignore that mentions AGENTS.local.md only inside a COMMENT (or a negation) must still get
# the real ignore line appended, or a personal override could be committed (Codex #39 r2 P3).
TX="$(mktemp -d 2>/dev/null || mktemp -d -t harness-xline)"
printf '# note: AGENTS.local.md is personal — do not commit\n' > "$TX/.gitignore"
HOME="$TX/home" CODEX_HOME="$TX/codex-home" sh "$SRC/harness-install.sh" "$TX" >/dev/null \
  || fail "exact-line gitignore install run exited non-zero"
grep -qxF 'AGENTS.local.md' "$TX/.gitignore" \
  || fail "root .gitignore substring-matched a comment — real AGENTS.local.md ignore not added (exact-line)"
grep -qF '# note: AGENTS.local.md is personal' "$TX/.gitignore" \
  || fail "pre-existing comment mentioning AGENTS.local.md clobbered on install"
rm -rf "$TX"
pass "project-root .gitignore uses exact-line matching (comment mention still gets the real ignore)"

# user content placed AFTER the block must keep its position on upgrade (in-place replace)    # R4
printf 'TRAILING-USER-NOTE\n' >> "$T/CLAUDE.md"
sh "$SRC/harness-install.sh" "$T" >/dev/null || fail "upgrade-with-suffix run failed"
grep -qF 'TRAILING-USER-NOTE' "$T/CLAUDE.md" || fail "trailing user content lost on upgrade"
awk '/<!-- harness:end -->/{seen=1} /TRAILING-USER-NOTE/{print (seen?"AFTER":"BEFORE")}' "$T/CLAUDE.md" \
  | grep -q AFTER || fail "trailing user content reordered before the block on upgrade"
pass "in-place block replacement preserves surrounding order (R4)"

# verification commands set at bootstrap must survive an upgrade (not be reset)                # R11
sed -e 's|^\( *test_command:\).*|\1 "pytest -q"|' "$T/.harness/harness.config.yaml" > "$T/.harness/cfg.b" \
  && mv "$T/.harness/cfg.b" "$T/.harness/harness.config.yaml"
sh "$SRC/harness-install.sh" "$T" >/dev/null || fail "upgrade after bootstrap-config failed"
grep -q 'test_command: "pytest -q"' "$T/.harness/harness.config.yaml" \
  || fail "bootstrap test_command erased on upgrade"
pass "upgrade preserves bootstrap-configured verification commands (R11)"

# ── migrate_config seeds workflow.identity on upgrade (E10-F01, Codex #40 r2 P2) ──
# A preserved pre-E10 config that lacks workflow.identity would make `/sdd-next --mine`
# fail-closed as an unresolved identity. The additive migration must seed the documented
# default under the existing workflow: block, preserve existing values/comments, and be
# idempotent (a second run must not duplicate the key or clobber a user-set value).
TID="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
printf '# My Project\n' > "$TID/CLAUDE.md"
CODEX_HOME="$TID/ch" sh "$SRC/harness-install.sh" "$TID" >/dev/null || fail "identity-migration fresh install exited non-zero"
CFGID="$TID/.harness/harness.config.yaml"
# Simulate a pre-E10 preserved config: a workflow: block WITHOUT identity, plus a
# bootstrap value that must survive verbatim.
cat > "$CFGID" <<'EOF'
store:
  tasks: local
workflow:
  require_spec_approval: true
  context_reset_threshold: 0.40
verification:
  test_command: "pytest -q"   # keep me exactly
EOF
grep -Eq '^[[:space:]]+identity:' "$CFGID" && fail "identity-migration setup: identity present before upgrade (bad fixture)"
CODEX_HOME="$TID/ch" sh "$SRC/harness-install.sh" "$TID" >/dev/null || fail "identity-migration upgrade exited non-zero"
grep -Eq '^[[:space:]]+identity:' "$CFGID" || fail "workflow.identity not seeded on upgrade of a pre-E10 config"
grep -qF 'test_command: "pytest -q"   # keep me exactly' "$CFGID" || fail "identity migration altered an existing value/comment"
pass "upgrade seeds workflow.identity into a pre-E10 preserved config (Codex #40 r2 P2)"
# Idempotent: a second run leaves a now-complete config byte-for-byte identical (no
# duplicate identity: key) and a user-set value survives untouched.
sed -e 's|^\( *identity:\).*|\1 "OctoCat"   # keep me exactly|' "$CFGID" > "$CFGID.b" && mv "$CFGID.b" "$CFGID"
cp "$CFGID" "$TID/after1"
CODEX_HOME="$TID/ch" sh "$SRC/harness-install.sh" "$TID" >/dev/null || fail "identity-migration second upgrade exited non-zero"
cmp -s "$CFGID" "$TID/after1" || { diff "$TID/after1" "$CFGID" || true; fail "workflow.identity migration not idempotent (duplicated or clobbered a user value)"; }
[ "$(grep -cE '^[[:space:]]+identity:' "$CFGID")" = "1" ] || fail "workflow.identity duplicated on re-run (not idempotent)"
rm -rf "$TID"
pass "workflow.identity migration is idempotent + preserves a user-set value (Codex #40 r2 P2)"

# ── identity seeding is scoped to the workflow: section (E10-F01, Codex #40 r3 P2) ──
# A preserved config carrying an unrelated indented `identity:` under ANOTHER section
# (e.g. an auth/tool block) must NOT suppress seeding workflow.identity — the presence
# check is scoped to the top-level workflow: block, not any same-named key file-wide.
TID="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
printf '# My Project\n' > "$TID/CLAUDE.md"
CODEX_HOME="$TID/ch" sh "$SRC/harness-install.sh" "$TID" >/dev/null || fail "identity-scope fresh install exited non-zero"
CFGID="$TID/.harness/harness.config.yaml"
cat > "$CFGID" <<'EOF'
store:
  tasks: local
auth:
  identity: "svc-account"   # unrelated key, keep me exactly
workflow:
  require_spec_approval: true
EOF
CODEX_HOME="$TID/ch" sh "$SRC/harness-install.sh" "$TID" >/dev/null || fail "identity-scope upgrade exited non-zero"
# workflow.identity must now exist INSIDE the workflow: block…
awk '/^workflow:[[:space:]]*(#.*)?$/{w=1;next} w&&/^[^[:space:]#]/{w=0} w&&/^[[:space:]]+identity:/{f=1} END{exit f?0:1}' "$CFGID" \
  || fail "workflow.identity not seeded when an unrelated identity: exists elsewhere (Codex #40 r3 P2)"
# …and the unrelated auth.identity must survive untouched.
grep -qF 'identity: "svc-account"   # unrelated key, keep me exactly' "$CFGID" || fail "identity-scope migration altered the unrelated auth.identity"
rm -rf "$TID"
pass "workflow.identity seeding is scoped to the workflow: section (Codex #40 r3 P2)"

# ── arg guards make no changes ────────────────────────────────────────────────
sh "$SRC/harness-install.sh"            >/dev/null 2>&1 && fail "missing-arg should exit non-zero"   # R9
sh "$SRC/harness-install.sh" "$SRC"     >/dev/null 2>&1 && fail "self-target should exit non-zero"   # R9
pass "arg guards reject bad invocations (R9)"

# ── E08-F01: interactive agent-target selection (non-TTY drives via --agents) ──
# All installer invocations here run via `sh …` with non-TTY stdin, so selection is
# driven deterministically by --agents / HARNESS_AGENTS (never the interactive prompt).

# default_all_when_no_persisted (R1) + all_front_ends_present (R6): a no-override,
# no-TTY run resolves to ALL agents (back-compat: this is the historical behavior,
# and the proxy for "fresh install pre-checks ALL when .harness/.agents is absent").
TA="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
CODEX_HOME="$TA/ch" sh "$SRC/harness-install.sh" "$TA" >/dev/null || fail "no-override install exited non-zero"
[ -f "$TA/CLAUDE.md" ]       || fail "R6: no-override run did not stamp claude (CLAUDE.md)"
[ -f "$TA/GEMINI.md" ]       || fail "R6: no-override run did not stamp gemini (GEMINI.md)"
[ -f "$TA/opencode.json" ]   || fail "R6: no-override run did not stamp opencode (opencode.json)"
[ -d "$TA/.claude/commands" ] || fail "R6: no-override run did not stamp claude glue"
[ -d "$TA/.opencode/command" ] || fail "R6: no-override run did not stamp opencode glue"
[ -f "$TA/.agents/skills/sdd-next/SKILL.md" ] || fail "R6: no-override run did not stamp codex repository skill"
[ -d "$TA/ch/prompts" ] && fail "R4: no-override run wrote deprecated global Codex prompts"
[ -f "$TA/.harness/.agents" ] || fail "R8: .harness/.agents not written on no-override run"
for _k in claude gemini opencode antigravity codex; do
  grep -qx "$_k" "$TA/.harness/.agents" || fail "R1/R6: .harness/.agents missing '$_k' on ALL default"
done
rm -rf "$TA"
pass "no-TTY no-override run stamps ALL front-ends + persists ALL (R1, R6)"

# agents_claude_only_stamps_claude (R2, R3, R4): --agents=claude stamps only Claude.
TB="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
CODEX_HOME="$TB/ch" sh "$SRC/harness-install.sh" --agents=claude "$TB" >/dev/null || fail "--agents=claude exited non-zero"
[ -f "$TB/CLAUDE.md" ]        || fail "R2/R3: --agents=claude did not write CLAUDE.md"
[ -d "$TB/.claude/agents" ]   || fail "R2/R3: --agents=claude did not write .claude/agents"
[ -d "$TB/.claude/commands" ] || fail "R2/R3: --agents=claude did not write .claude/commands"
[ -f "$TB/AGENTS.md" ]        || fail "R2: AGENTS.md (shared entrypoint) must always be written"
[ -f "$TB/GEMINI.md" ]        && fail "R4: --agents=claude must not write GEMINI.md"
[ -f "$TB/opencode.json" ]    && fail "R4: --agents=claude must not write opencode.json"
[ -d "$TB/.opencode" ]        && fail "R4: --agents=claude must not write .opencode/"
[ -d "$TB/.agents" ]          && fail "R4: --agents=claude must not write .agents/"
[ -d "$TB/ch/prompts" ]       && fail "R4: --agents=claude must not write codex global prompts"
rm -rf "$TB"
pass "--agents=claude stamps only Claude, no other front-ends (R2, R3, R4)"

# agents_multi_stamps_each (R3): --agents=claude,opencode stamps both.
TC="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=claude,opencode "$TC" >/dev/null || fail "--agents=claude,opencode exited non-zero"
[ -f "$TC/CLAUDE.md" ]      || fail "R3: claude not stamped in multi-select"
[ -f "$TC/opencode.json" ] || fail "R3: opencode not stamped in multi-select"
[ -d "$TC/.opencode/command" ] || fail "R3: opencode commands not stamped in multi-select"
[ -f "$TC/GEMINI.md" ]     && fail "R4: gemini must be skipped in claude,opencode select"
rm -rf "$TC"
pass "--agents=claude,opencode stamps each selected agent (R3)"

# env_override_selects (R5): HARNESS_AGENTS resolves the set, and --agents wins too.
TD="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
HARNESS_AGENTS=gemini sh "$SRC/harness-install.sh" "$TD" >/dev/null || fail "HARNESS_AGENTS=gemini exited non-zero"
[ -f "$TD/GEMINI.md" ]   || fail "R5: HARNESS_AGENTS=gemini did not stamp gemini"
[ -f "$TD/CLAUDE.md" ]   && fail "R5: HARNESS_AGENTS=gemini must not stamp claude"
[ -f "$TD/opencode.json" ] && fail "R5: HARNESS_AGENTS=gemini must not stamp opencode"
rm -rf "$TD"
# --agents wins over an HARNESS_AGENTS env value at the same time
TD2="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
HARNESS_AGENTS=gemini sh "$SRC/harness-install.sh" --agents=claude "$TD2" >/dev/null || fail "override precedence run failed"
[ -f "$TD2/CLAUDE.md" ]  || fail "R5: --agents=claude must win over HARNESS_AGENTS=gemini"
[ -f "$TD2/GEMINI.md" ]  && fail "R5: --agents must override HARNESS_AGENTS (gemini should be skipped)"
rm -rf "$TD2"
pass "explicit --agents / HARNESS_AGENTS override resolves the set, --agents wins (R5)"

# registry_keys (R10): every registry key is individually selectable.
for _k in claude gemini opencode antigravity codex; do
  TK="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
  sh "$SRC/harness-install.sh" --agents="$_k" "$TK" >/dev/null || fail "R10: --agents=$_k exited non-zero"
  grep -qx "$_k" "$TK/.harness/.agents" || fail "R10: '$_k' not selectable/persisted"
  rm -rf "$TK"
done
pass "every registry key is individually selectable (R10)"

# antigravity_only_writes_gemini_entrypoint (E07-F01 R1, Codex r1 P2 #3404185446):
# GEMINI.md is Antigravity's in-repo bootstrap entrypoint, so an antigravity-only
# install (no gemini) MUST still write GEMINI.md with the harness managed block.
TAG="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=antigravity "$TAG" >/dev/null || fail "--agents=antigravity exited non-zero"
[ -f "$TAG/GEMINI.md" ]                              || fail "R1: --agents=antigravity must write GEMINI.md entrypoint (Codex r1 P2)"
grep -qF '<!-- harness:begin -->' "$TAG/GEMINI.md"   || fail "R1: antigravity-only GEMINI.md missing harness managed block (Codex r1 P2)"
grep -qF '.harness/AGENTS.md' "$TAG/GEMINI.md"       || fail "R1: antigravity-only GEMINI.md does not point at .harness/AGENTS.md"
[ -f "$TAG/.agents/rules/harness.md" ]                || fail "R1: antigravity-only install missing .agents/ glue"
[ -f "$TAG/CLAUDE.md" ]    && fail "R4: antigravity-only must not write CLAUDE.md"
[ -f "$TAG/opencode.json" ] && fail "R4: antigravity-only must not write opencode.json"
rm -rf "$TAG"
pass "--agents=antigravity writes GEMINI.md entrypoint (R1, Codex r1 P2)"

# codex_only_stamps_project_skills: --agents=codex writes repository-local skills with
# deterministic metadata wrapped around the canonical command bodies. It never creates
# the deprecated machine-global prompt surface.
TCX="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
CODEX_HOME="$TCX/ch" sh "$SRC/harness-install.sh" --agents=codex "$TCX" >/dev/null || fail "--agents=codex exited non-zero"
[ -f "$TCX/AGENTS.md" ]                 || fail "codex: AGENTS.md (Codex's native entrypoint) must always be written"
for _c in sdd-next sdd-new sdd-plan sdd-drill sdd-fix sdd-fix-parallel sdd-pr-loop; do
  _skill="$TCX/.agents/skills/$_c/SKILL.md"
  _policy="$TCX/.agents/skills/$_c/agents/openai.yaml"
  [ -f "$_skill" ]                      || fail "codex: project skill $_c/SKILL.md not installed"
  [ -f "$_policy" ]                     || fail "codex: project skill $_c has no agents/openai.yaml"
  [ "$(sed -n '1p' "$_skill")" = "---" ] || fail "codex: $_c skill frontmatter does not open"
  grep -qx "name: $_c" "$_skill"         || fail "codex: $_c skill has no stable name metadata"
  grep -q '^description: .[^ ]' "$_skill" || fail "codex: $_c skill has no non-empty description metadata"
  [ "$(sed -n '4p' "$_skill")" = "---" ] || fail "codex: $_c skill frontmatter does not close deterministically"
  grep -qx 'policy:' "$_policy" \
    || fail "codex: $_c metadata has no policy block"
  grep -qx '  allow_implicit_invocation: false' "$_policy" \
    || fail "codex: $_c is not explicit-invocation-only"
  grep -qF "all text accompanying the explicit \`\$$_c\` mention" "$_skill" \
    || fail "codex: $_c does not map invocation text to the canonical argument term"
  grep -qF 'as the value of `$ARGUMENTS`' "$_skill" \
    || fail "codex: $_c does not define the canonical \$ARGUMENTS mapping"
done
# E18-F01 R14: NO pr-fixer artifact is ever created for the codex front-end.
[ -f "$TCX/.codex/agents/pr-fixer.toml" ] && fail "codex: must not create a pr-fixer artifact (E18-F01 R14)" 
[ -d "$TCX/ch/prompts" ]                 && fail "codex: current install created deprecated global prompts"
# no OTHER front-end stamped
[ -f "$TCX/CLAUDE.md" ]    && fail "R4: --agents=codex must not write CLAUDE.md"
[ -f "$TCX/GEMINI.md" ]    && fail "R4: --agents=codex must not write GEMINI.md"
[ -f "$TCX/opencode.json" ] && fail "R4: --agents=codex must not write opencode.json"
[ -d "$TCX/.claude" ]      && fail "R4: --agents=codex must not write .claude/"
grep -qx codex "$TCX/.harness/.agents" || fail "R8: codex not persisted in .harness/.agents"
# Installed $sdd-next acts as the Orchestrator, resolves against .harness/, and carries args.
grep -qF '.harness/' "$TCX/.agents/skills/sdd-next/SKILL.md" || fail "codex: sdd-next skill does not resolve against .harness/"
grep -qF '$ARGUMENTS' "$TCX/.agents/skills/sdd-next/SKILL.md" || fail "codex: sdd-next skill does not carry \$ARGUMENTS"
grep -qF -- '--mine' "$TCX/.agents/skills/sdd-next/SKILL.md" || fail "codex: sdd-next skill does not carry the --mine scoped-selection wiring (E10-F01)"
# After removing the adapter metadata/instruction, the canonical workflow remains
# byte-identical to Claude.
CODEX_HOME="$TCX/ch2" sh "$SRC/harness-install.sh" --agents=claude,codex "$TCX" >/dev/null || fail "codex+claude install failed"
sed -n '/^## Canonical workflow$/,$p' "$TCX/.agents/skills/sdd-next/SKILL.md" | tail -n +2 > "$TCX/skill.body"
tail -n +5 "$TCX/.claude/commands/sdd-next.md" > "$TCX/command.body"
cmp -s "$TCX/skill.body" "$TCX/command.body" \
  || fail "codex: sdd-next skill instructions differ from the canonical command body"
sed -n '/^## Canonical workflow$/,$p' "$TCX/.agents/skills/sdd-fix-parallel/SKILL.md" | tail -n +2 > "$TCX/parallel-skill.body"
tail -n +5 "$TCX/.claude/commands/sdd-fix-parallel.md" > "$TCX/parallel-command.body"
cmp -s "$TCX/parallel-skill.body" "$TCX/parallel-command.body" \
  || fail "codex: parallel skill instructions differ from the canonical command body"
rm -rf "$TCX"
pass "--agents=codex stamps explicit-only project skills with an argument adapter and canonical bodies"

# Selected installs own a skill only through a last-written two-file unit stamp. A
# foreign unit is preserved byte-for-byte; a harness-owned prior-version unit (live
# bytes still match the remembered bytes) is updated as a whole and remains reclaimable.
TCU="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
mkdir -p "$TCU/.agents/skills/sdd-next/agents"
printf 'foreign skill\n' > "$TCU/.agents/skills/sdd-next/SKILL.md"
printf 'foreign policy\n' > "$TCU/.agents/skills/sdd-next/agents/openai.yaml"
cp "$TCU/.agents/skills/sdd-next/SKILL.md" "$TCU/foreign-skill.ref"
cp "$TCU/.agents/skills/sdd-next/agents/openai.yaml" "$TCU/foreign-policy.ref"
_foreign_warn="$(CODEX_HOME="$TCU/ch" sh "$SRC/harness-install.sh" --agents=codex "$TCU" 2>&1 >/dev/null)" \
  || fail "codex foreign-unit preservation install failed"
cmp -s "$TCU/foreign-skill.ref" "$TCU/.agents/skills/sdd-next/SKILL.md" \
  || fail "R3: selected Codex install overwrote a foreign SKILL.md"
cmp -s "$TCU/foreign-policy.ref" "$TCU/.agents/skills/sdd-next/agents/openai.yaml" \
  || fail "R3: selected Codex install overwrote foreign agents/openai.yaml"
printf '%s\n' "$_foreign_warn" | grep -qF '.agents/skills/sdd-next' \
  || fail "R3: selected foreign skill unit preservation was not diagnosed"
[ -e "$TCU/.harness/.codex-skills/sdd-next" ] \
  && fail "R3: installer claimed a last-written stamp for a foreign skill unit"
rm -rf "$TCU"

TCS="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
CODEX_HOME="$TCS/ch" sh "$SRC/harness-install.sh" --agents=codex "$TCS" >/dev/null \
  || fail "codex skill stamp setup failed"
_live="$TCS/.agents/skills/sdd-next"
_stamp="$TCS/.harness/.codex-skills/sdd-next"
[ -f "$_stamp/SKILL.md" ] && [ -f "$_stamp/agents/openai.yaml" ] \
  || fail "R3: harness-owned skill unit has no two-file last-written stamp"
printf '\nold harness body\n' >> "$_live/SKILL.md"
printf '\nold harness body\n' >> "$_stamp/SKILL.md"
CODEX_HOME="$TCS/ch" sh "$SRC/harness-install.sh" --agents=codex "$TCS" >/dev/null \
  || fail "codex stamped skill update failed"
grep -qF 'old harness body' "$_live/SKILL.md" \
  && fail "R3: stamp-matching harness skill did not update"
cmp -s "$_live/SKILL.md" "$_stamp/SKILL.md" \
  || fail "R3: updated SKILL.md stamp does not match the written file"
cmp -s "$_live/agents/openai.yaml" "$_stamp/agents/openai.yaml" \
  || fail "R3: updated openai.yaml stamp does not match the written file"
CODEX_HOME="$TCS/ch" sh "$SRC/harness-install.sh" --agents=claude "$TCS" >/dev/null \
  || fail "codex stamped skill deselect failed"
[ -e "$_live/SKILL.md" ] && fail "R3: stamped SKILL.md survived deselection"
[ -e "$_live/agents/openai.yaml" ] && fail "R3: stamped agents/openai.yaml survived deselection"
[ -e "$_stamp" ] && fail "R3: skill ownership stamp survived deselection"
rm -rf "$TCS"
pass "selected Codex skill units preserve foreign bytes and update/reclaim only through last-written stamps"

# test_sdd_fix_parallel_registry_cleanup (covered across each deselection block below)
# codex_deselect_reclaims_pristine (§7): re-run dropping codex removes byte-pristine
# skills and warns; a user-EDITED skill and Antigravity/user sibling trees survive.
TCD="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
CH="$TCD/ch"
CODEX_HOME="$CH" sh "$SRC/harness-install.sh" --agents=antigravity,codex "$TCD" >/dev/null || fail "codex deselect setup failed"
[ -f "$TCD/.agents/skills/sdd-next/SKILL.md" ] || fail "codex deselect setup: skills not stamped"
printf '\n# user edit\n' >> "$TCD/.agents/skills/sdd-fix/SKILL.md"
printf 'mine\n' > "$TCD/.agents/user-file.txt"
_cwarn="$(CODEX_HOME="$CH" sh "$SRC/harness-install.sh" --agents=antigravity "$TCD" 2>&1 >/dev/null)" \
  || fail "codex deselect re-run exited non-zero"
[ -f "$TCD/.agents/skills/sdd-next/SKILL.md" ] && fail "R3: deselected pristine Codex skill was not removed"
[ -f "$TCD/.agents/skills/sdd-fix-parallel/SKILL.md" ] && fail "R3: deselected pristine parallel skill was not removed"
[ -f "$TCD/.agents/skills/sdd-pr-loop/SKILL.md" ] && fail "R3: deselected pristine pr-loop skill was not removed"
[ -f "$TCD/.agents/skills/sdd-fix/SKILL.md" ] || fail "R3: user-edited Codex skill must be preserved on deselect"
grep -qF '# user edit' "$TCD/.agents/skills/sdd-fix/SKILL.md" || fail "R3: edited skill content was lost"
[ -f "$TCD/.agents/skills/sdd-fix/agents/openai.yaml" ] \
  || fail "R3: edited skill unit lost its explicit-only companion on deselect"
[ -f "$TCD/.agents/rules/harness.md" ] || fail "R3/R9: Codex deselection damaged Antigravity rules"
[ -f "$TCD/.agents/workflows/sdd-next.md" ] || fail "R3/R9: Codex deselection damaged Antigravity workflows"
[ -f "$TCD/.agents/user-file.txt" ] || fail "R3: Codex deselection deleted a user sibling"
printf '%s' "$_cwarn" | grep -qiF 'codex' || fail "R13: removal of codex glue was not warned about"
grep -qx codex "$TCD/.harness/.agents" && fail "R8: codex must be dropped from .harness/.agents after deselect"
rm -rf "$TCD"
pass "codex deselect reclaims pristine project skills and preserves edited/sibling files"

# Partial skill units on Codex deselection: a stamp-owned SKILL.md remains reclaimable
# when its companion metadata is missing or edited. An edited, unproven companion is
# preserved individually, and only empty directories are pruned.
TCDP="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
CODEX_HOME="$TCDP/ch" sh "$SRC/harness-install.sh" --agents=codex "$TCDP" >/dev/null \
  || fail "codex partial-unit deselect setup failed"
rm -f "$TCDP/.agents/skills/sdd-next/agents/openai.yaml"
printf '\n# user policy edit\n' >> "$TCDP/.agents/skills/sdd-new/agents/openai.yaml"
CODEX_HOME="$TCDP/ch" sh "$SRC/harness-install.sh" --agents=claude "$TCDP" >/dev/null \
  || fail "codex partial-unit deselect failed"
[ -e "$TCDP/.agents/skills/sdd-next/SKILL.md" ] \
  && fail "R3 partial: missing companion stranded a stamp-owned SKILL.md on deselect"
[ -e "$TCDP/.agents/skills/sdd-next" ] \
  && fail "R3 partial: empty skill directory was not pruned after missing-companion deselect"
[ -e "$TCDP/.agents/skills/sdd-new/SKILL.md" ] \
  && fail "R3 partial: edited companion stranded a stamp-owned SKILL.md on deselect"
[ -f "$TCDP/.agents/skills/sdd-new/agents/openai.yaml" ] \
  || fail "R3 partial: edited companion metadata was deleted on deselect"
grep -qF '# user policy edit' "$TCDP/.agents/skills/sdd-new/agents/openai.yaml" \
  || fail "R3 partial: edited companion metadata bytes changed on deselect"
[ -e "$TCDP/.harness/.codex-skills" ] \
  && fail "R3 partial: deselection left stale Codex skill ownership stamps"
rm -rf "$TCDP"
pass "Codex deselection reclaims proven paths from partial units and preserves edited metadata"

# Symlinked Codex skill destinations are never ownership-safe. Cover both a whole
# skill-unit directory redirected outside the target and one redirected destination
# file. The unit case starts with current generated bytes so the old `-f`/`cmp` checks
# would accept it and create a stamp; the file case carries a real last-written stamp so
# deselection would otherwise unlink the symlink after following it for comparison.
TCSYL_SEED="$T/codex-symlink-seed"
TCSYL_UNIT="$T/codex-symlink-unit"
TCSYL_FILE="$T/codex-symlink-file"
TCSYL_UNIT_EXT="$T/codex-symlink-unit.external"
TCSYL_FILE_EXT="$T/codex-symlink-file.external"
mkdir -p "$TCSYL_SEED" "$TCSYL_UNIT/.agents/skills" "$TCSYL_FILE"
CODEX_HOME="$TCSYL_SEED/ch" sh "$SRC/harness-install.sh" --agents=codex "$TCSYL_SEED" >/dev/null \
  || fail "codex symlink seed install failed"
cp -R "$TCSYL_SEED/.agents/skills/sdd-next" "$TCSYL_UNIT_EXT"
cp "$TCSYL_UNIT_EXT/SKILL.md" "$TCSYL_UNIT_EXT/SKILL.ref"
cp "$TCSYL_UNIT_EXT/agents/openai.yaml" "$TCSYL_UNIT_EXT/agents/openai.ref"
ln -s "$TCSYL_UNIT_EXT" "$TCSYL_UNIT/.agents/skills/sdd-next"
CODEX_HOME="$TCSYL_UNIT/ch" sh "$SRC/harness-install.sh" --agents=codex "$TCSYL_UNIT" >/dev/null \
  || fail "codex symlinked skill-unit install failed"
[ -L "$TCSYL_UNIT/.agents/skills/sdd-next" ] \
  || fail "R4 symlink: selected install replaced a symlinked skill unit"
cmp -s "$TCSYL_UNIT_EXT/SKILL.ref" "$TCSYL_UNIT_EXT/SKILL.md" \
  || fail "R4 symlink: selected install changed an external skill-unit SKILL.md"
cmp -s "$TCSYL_UNIT_EXT/agents/openai.ref" "$TCSYL_UNIT_EXT/agents/openai.yaml" \
  || fail "R4 symlink: selected install changed an external skill-unit policy"
[ -e "$TCSYL_UNIT/.harness/.codex-skills/sdd-next" ] \
  && fail "R4 symlink: selected install stamped a rejected symlinked skill unit"

CODEX_HOME="$TCSYL_FILE/ch" sh "$SRC/harness-install.sh" --agents=codex "$TCSYL_FILE" >/dev/null \
  || fail "codex symlinked skill-file setup failed"
mv "$TCSYL_FILE/.agents/skills/sdd-new/SKILL.md" "$TCSYL_FILE_EXT"
cp "$TCSYL_FILE_EXT" "$TCSYL_FILE_EXT.ref"
ln -s "$TCSYL_FILE_EXT" "$TCSYL_FILE/.agents/skills/sdd-new/SKILL.md"
CODEX_HOME="$TCSYL_FILE/ch" sh "$SRC/harness-install.sh" --agents=claude "$TCSYL_FILE" >/dev/null \
  || fail "codex symlinked skill-file deselection failed"
[ -L "$TCSYL_FILE/.agents/skills/sdd-new/SKILL.md" ] \
  || fail "R4 symlink: deselection removed a symlinked SKILL.md"
cmp -s "$TCSYL_FILE_EXT.ref" "$TCSYL_FILE_EXT" \
  || fail "R4 symlink: deselection changed an external SKILL.md target"
[ -f "$TCSYL_FILE/.agents/skills/sdd-new/agents/openai.yaml" ] \
  || fail "R4 symlink: rejection did not preserve the rest of the skill unit"
[ -e "$TCSYL_FILE/.harness/.codex-skills/sdd-new" ] \
  && fail "R4 symlink: rejected symlinked skill file retained an ownership stamp"
pass "Codex skill install/reclamation reject symlinked units and files without touching external targets"

# codex_no_home_required: the current repository-local surface does not resolve HOME or
# CODEX_HOME at all, and remains fully functional when both are absent.
TCH="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
_chwarn="$(env -u HOME -u CODEX_HOME sh "$SRC/harness-install.sh" --agents=codex "$TCH" 2>&1 >/dev/null)" \
  || fail "codex install with no HOME/CODEX_HOME must not abort under set -u"
[ -f "$TCH/AGENTS.md" ]  || fail "codex no-HOME: install must still complete (AGENTS.md written)"
[ -d "$TCH/.harness" ]   || fail "codex no-HOME: install must still complete (.harness written)"
[ -f "$TCH/.agents/skills/sdd-next/SKILL.md" ] || fail "codex no-HOME: project skill was not installed"
printf '%s' "$_chwarn" | grep -q 'skipping GLOBAL' && fail "codex no-HOME: installer still advertised the retired global prompt surface"
rm -rf "$TCH"
pass "codex project skills install without HOME or CODEX_HOME"

# Legacy ungated global prompts have no cross-target ownership ledger. Preserve even a
# byte-identical generated legacy prompt because another pre-0.48 target may still rely
# on it; edited prompts are likewise preserved byte-for-byte. No backup/current prompt
# replacement is created because global prompts are no longer an active surface.
TCP="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
CHP="$TCP/ch/prompts"
mkdir -p "$CHP"
CODEX_HOME="$TCP/ch" sh "$SRC/harness-install.sh" --agents=claude "$TCP" >/dev/null 2>&1 \
  || fail "legacy migration reference setup failed"
cp "$TCP/.claude/commands/sdd-next.md" "$CHP/sdd-next.md"
cp "$TCP/.claude/commands/sdd-next.md" "$TCP/sdd-next.ref"
cp "$TCP/.claude/commands/sdd-fix.md" "$CHP/sdd-fix.md"
printf '\n# user edit survives\n' >> "$CHP/sdd-fix.md"
_legacy_warn="$(CODEX_HOME="$TCP/ch" sh "$SRC/harness-install.sh" --agents=codex "$TCP" 2>&1 >/dev/null)" \
  || fail "codex legacy migration exited non-zero"
[ -f "$CHP/sdd-next.md" ] || fail "R5: ownership-unknown legacy sdd-next prompt was removed"
cmp -s "$TCP/sdd-next.ref" "$CHP/sdd-next.md" \
  || fail "R5: ownership-unknown legacy sdd-next prompt bytes were changed"
[ -f "$CHP/sdd-fix.md" ] || fail "R5: edited legacy prompt was removed"
grep -qF '# user edit survives' "$CHP/sdd-fix.md" || fail "R5: edited legacy prompt bytes were changed"
[ -e "$CHP/sdd-next.md.pre-harness.bak" ] && fail "R4: migration created an obsolete prompt backup"
printf '%s\n' "$_legacy_warn" | grep -qF 'sdd-fix.md' || fail "R5: edited legacy prompt preservation was not diagnosed"
printf '%s\n' "$_legacy_warn" | grep -qF 'sdd-next.md' || fail "R5: ownership-unknown legacy prompt preservation was not diagnosed"
printf '%s\n' "$_legacy_warn" | grep -qiF 'ownership' || fail "R5: legacy preservation warning does not name the ownership reason"
[ -f "$TCP/.agents/skills/sdd-next/SKILL.md" ] || fail "R1: current repository skill missing after legacy migration"
rm -rf "$TCP"
pass "codex preserves ownership-unknown ungated legacy prompts and edited prompts"

# E23-F01 R10: shipped documentation and the installed manifest describe the native
# Codex surface, always-present roles, safe migration, and the public release version.
[ "$(cat "$SRC/VERSION")" = "0.48.0" ] || fail "R10: VERSION is not 0.48.0"
grep -qF '## [0.48.0]' "$SRC/CHANGELOG.md" || fail "R10: CHANGELOG lacks 0.48.0"
for _doc in "$SRC/README.md" "$SRC/docs/HARNESS.md" "$SRC/docs/INSTALL.md"; do
  grep -qF '$sdd-' "$_doc" || fail "R10: $_doc does not document Codex \$sdd-* skills"
  grep -qF '.agents/skills' "$_doc" || fail "R10: $_doc omits the Codex skill layout"
  grep -qiF 'legacy' "$_doc" || fail "R10: $_doc does not document legacy migration"
  grep -qiF 'explicit' "$_doc" || fail "R10: $_doc does not document explicit-only Codex skills"
  grep -qiF 'ownership' "$_doc" || fail "R10: $_doc does not document ownership-safe reconciliation"
done
TDOC="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
env -u HOME -u CODEX_HOME sh "$SRC/harness-install.sh" --agents=codex "$TDOC" >/dev/null \
  || fail "R10: manifest fixture install failed"
grep -qF '.agents/skills/sdd-*/SKILL.md' "$TDOC/.harness/manifest.txt" \
  || fail "R10: installed manifest omits Codex skills"
grep -qF 'agents/openai.yaml' "$TDOC/.harness/manifest.txt" \
  || fail "R10: installed manifest omits explicit-only Codex skill metadata"
grep -qF 'six selected Codex role' "$TDOC/.harness/manifest.txt" \
  || fail "R10: installed manifest does not describe always-present Codex roles"
grep -qF 'Current installs never create or overwrite' "$TDOC/.harness/manifest.txt" \
  || fail "R10: installed manifest does not retire global prompt writes"
rm -rf "$TDOC"
pass "Codex manifest/docs/changelog/VERSION contract is current (R10)"

# unknown_agent_key_rejected (R7): an unknown override exits non-zero, names it, no changes.
TE="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
_err="$(sh "$SRC/harness-install.sh" --agents=claude,bogus "$TE" 2>&1 >/dev/null)" && fail "R7: unknown key must exit non-zero"
printf '%s' "$_err" | grep -qF 'bogus' || fail "R7: error must name the unknown token 'bogus'"
[ -d "$TE/.harness" ] && fail "R7: unknown-key run must make no changes (no .harness/ written)"
[ -f "$TE/CLAUDE.md" ] && fail "R7: unknown-key run must not stamp any front-end"
rm -rf "$TE"
pass "unknown override key exits non-zero, names it, makes no changes (R7)"

# persists_selection (R8): --agents=claude,opencode persists exactly those, sorted, 1/line.
TF="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=opencode,claude "$TF" >/dev/null || fail "persist run failed"
[ -f "$TF/.harness/.agents" ] || fail "R8: .harness/.agents not created"
[ "$(cat "$TF/.harness/.agents")" = "$(printf 'claude\nopencode')" ] \
  || fail "R8: .harness/.agents not exactly {claude,opencode} sorted one-per-line (got: $(cat "$TF/.harness/.agents" | tr '\n' ',' ))"
# .harness/agents/ (the role-bodies DIR) must coexist with the .harness/.agents state FILE
[ -d "$TF/.harness/agents" ] || fail "R8: role-bodies .harness/agents/ dir clobbered by state file"
[ -f "$TF/.harness/agents/orchestrator.md" ] || fail "R8: role bodies missing alongside state file"
rm -rf "$TF"
pass ".harness/.agents persists the selection sorted, coexists with the roles dir (R8)"

# agents_host_end_to_end + agents_host_never_persisted (E19-F01 R28, R18): `host` is a
# RESOLUTION MODE, not a sixth agent key. Run under `env -i` with an explicit marker so
# the verdict cannot depend on whatever CLI happens to be running this suite (and with
# CODEX_HOME sandboxed under the case dir, since the codex front-end writes GLOBAL
# prompts). The detection matrix itself lives in tests/test_agents_host.sh.
TH="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
mkdir -p "$TH/home" "$TH/ch" "$TH/t"
env -i PATH="$PATH" HOME="$TH/home" CODEX_HOME="$TH/ch" CLAUDECODE=1 \
  sh "$SRC/harness-install.sh" --agents=host "$TH/t" >/dev/null 2>&1 \
  || fail "E19-F01 R28: --agents=host exited non-zero"
[ -f "$TH/t/CLAUDE.md" ]     || fail "E19-F01 R28: detected host did not stamp CLAUDE.md"
[ -f "$TH/t/AGENTS.md" ]     || fail "E19-F01 R28: AGENTS.md must always be written"
[ -f "$TH/t/GEMINI.md" ]     && fail "E19-F01 R28: host mode stamped an unselected front-end"
[ -f "$TH/t/opencode.json" ] && fail "E19-F01 R28: host mode stamped opencode.json"
[ -d "$TH/ch/prompts" ]      && fail "E19-F01 R28: host mode stamped the GLOBAL codex prompts"
[ "$(cat "$TH/t/.harness/.agents")" = "claude" ] \
  || fail "E19-F01 R28: host mode persisted '$(cat "$TH/t/.harness/.agents" | tr '\n' ',')', expected claude"
grep -qx 'host' "$TH/t/.harness/.agents" \
  && fail "E19-F01 R18: the token 'host' must NEVER be persisted to .harness/.agents"
rm -rf "$TH"
pass "--agents=host resolves the running front-end end to end; 'host' is never persisted (E19-F01 R28, R18)"

# reconcile_add + reconcile_remove + reprompt_baseline_is_persisted +
# reconcile_without_version_bump (R9, R11, R12, R13): a re-run at the SAME version that
# both adds and removes an agent, using the persisted set as the baseline.
TG="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=claude,gemini "$TG" >/dev/null || fail "reconcile install1 failed"
[ -f "$TG/GEMINI.md" ] || fail "reconcile setup: gemini not stamped in install1"
[ -f "$TG/opencode.json" ] && fail "reconcile setup: opencode should be absent after install1"
# Re-run at the SAME VERSION (R11): drop gemini, add opencode.
_warn="$(sh "$SRC/harness-install.sh" --agents=claude,opencode "$TG" 2>&1 >/dev/null)" \
  || fail "reconcile install2 exited non-zero"
# add applied (R12)
[ -f "$TG/opencode.json" ]     || fail "R12: re-run did not add opencode glue (opencode.json)"
[ -d "$TG/.opencode/command" ] || fail "R12: re-run did not add opencode commands"
# remove applied (R13): gemini glue gone, warning printed
[ -f "$TG/GEMINI.md" ] && fail "R13: deselected gemini glue (GEMINI.md) not removed"
printf '%s' "$_warn" | grep -qiF 'gemini' || fail "R13: removal of gemini was not warned about"
# claude kept, AGENTS.md survives, .harness/ body intact (R13 never-touch invariants)
[ -d "$TG/.claude" ]          || fail "R13: still-selected claude glue must survive"
[ -f "$TG/AGENTS.md" ]        || fail "R13: shared AGENTS.md entrypoint must never be removed"
[ -f "$TG/.harness/AGENTS.md" ] || fail "R13: .harness/ body must never be touched by removal"
# .harness/.agents reflects the new baseline (R9): claude,opencode (not the old set, not ALL)
[ "$(cat "$TG/.harness/.agents")" = "$(printf 'claude\nopencode')" ] \
  || fail "R9: persisted baseline not updated to {claude,opencode} after reconcile"
rm -rf "$TG"
pass "re-run adds + removes agents at same VERSION, persisted baseline updated (R9, R11, R12, R13)"

# legacy_upgrade_baseline_removes_deselected (R12/R13, Codex P2 #3400941300): an
# existing install with NO persisted .harness/.agents (a pre-E08 install that
# stamped ALL front-ends) must be treated as the all-agents baseline, so the first
# selective upgrade actually removes the now-deselected glue rather than leaving it.
TL="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" "$TL" >/dev/null || fail "legacy setup install failed"   # no-override ⇒ ALL
[ -f "$TL/GEMINI.md" ]   || fail "legacy setup: gemini not stamped by ALL default"
[ -f "$TL/opencode.json" ] || fail "legacy setup: opencode not stamped by ALL default"
rm -f "$TL/.harness/.agents"   # simulate a pre-E08 install: stamped all, persisted none
[ -f "$TL/.harness/.harness-version" ] || fail "legacy setup: not detected as an upgrade"
_warn="$(sh "$SRC/harness-install.sh" --agents=claude "$TL" 2>&1 >/dev/null)" \
  || fail "legacy upgrade run exited non-zero"
[ -f "$TL/GEMINI.md" ]     && fail "Codex P2: legacy upgrade must remove deselected GEMINI.md"
[ -f "$TL/opencode.json" ] && fail "Codex P2: legacy upgrade must remove deselected opencode.json"
[ -d "$TL/.claude" ]       || fail "Codex P2: still-selected claude glue must survive legacy upgrade"
[ "$(cat "$TL/.harness/.agents")" = "claude" ] \
  || fail "Codex P2: legacy upgrade must persist the new {claude} baseline"
rm -rf "$TL"
pass "legacy upgrade (no persisted .agents) treats prior set as ALL, removes deselected glue (Codex P2)"

# deselect_preserves_user_authored_files (R13, Codex r2 P1 #3400965003/#3400965008):
# deselecting an agent must delete ONLY harness-generated files, never wipe whole
# .claude/.opencode dirs that also hold the user's own agents/commands.
TM="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=claude,opencode "$TM" >/dev/null || fail "scoped-remove install1 failed"
[ -f "$TM/.claude/agents/orchestrator.md" ] || fail "scoped-remove setup: claude shims not stamped"
[ -f "$TM/.opencode/command/sdd-next.md" ]  || fail "scoped-remove setup: opencode cmds not stamped"
# user-authored artifacts the harness does NOT own, placed in the same dirs:
printf 'mine\n' > "$TM/.claude/agents/my-custom.md"
printf 'mine\n' > "$TM/.claude/commands/my-cmd.md"
printf 'mine\n' > "$TM/.opencode/command/my-oc.md"
# re-run dropping BOTH claude and opencode:
sh "$SRC/harness-install.sh" --agents=gemini "$TM" >/dev/null 2>&1 || fail "scoped-remove rerun failed"
# harness-owned glue removed:
[ -f "$TM/.claude/agents/orchestrator.md" ] && fail "P1: harness claude shim not removed on deselect"
[ -f "$TM/.claude/commands/sdd-next.md" ]   && fail "P1: harness claude command not removed on deselect"
[ -f "$TM/.claude/commands/sdd-fix-parallel.md" ] && fail "E15-F03: harness parallel command not removed on deselect"
[ -f "$TM/.claude/commands/sdd-pr-loop.md" ] && fail "E18-F01 R4: harness sdd-pr-loop command not removed on deselect"
[ -f "$TM/.claude/agents/pr-fixer.md" ] && fail "E18-F01 R4: harness pr-fixer shim not removed on deselect"
[ -f "$TM/.opencode/command/sdd-next.md" ]  && fail "P1: harness opencode command not removed on deselect"
[ -f "$TM/.opencode/command/sdd-fix-parallel.md" ] && fail "E15-F03: opencode parallel command not removed on deselect"
[ -f "$TM/.opencode/command/sdd-pr-loop.md" ] && fail "E18-F01 R4: opencode sdd-pr-loop not removed on deselect"
[ -f "$TM/.opencode/agent/pr-fixer.md" ] && fail "E18-F01 R4: opencode pr-fixer agent not removed on deselect"
# user-authored files PRESERVED (the whole point):
[ -f "$TM/.claude/agents/my-custom.md" ]   || fail "P1: user-authored .claude/agents/my-custom.md was wrongly deleted"
[ -f "$TM/.claude/commands/my-cmd.md" ]     || fail "P1: user-authored .claude/commands/my-cmd.md was wrongly deleted"
[ -f "$TM/.opencode/command/my-oc.md" ]     || fail "P1: user-authored .opencode/command/my-oc.md was wrongly deleted"
# dirs survive because they still hold user files:
[ -d "$TM/.claude/agents" ]   || fail "P1: .claude/agents removed despite user files present"
[ -d "$TM/.opencode/command" ] || fail "P1: .opencode/command removed despite user files present"
rm -rf "$TM"
pass "deselect removes only harness-owned files, preserves user-authored agents/commands (Codex r2 P1)"

# deselect_prunes_empty_dirs (R13): when NO user files remain, the now-empty harness
# dirs are pruned (no stale empty .claude/.opencode left behind).
TN="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=claude,opencode "$TN" >/dev/null || fail "prune setup install failed"
sh "$SRC/harness-install.sh" --agents=gemini "$TN" >/dev/null 2>&1 || fail "prune rerun failed"
[ -d "$TN/.claude" ]   && fail "R13: empty .claude/ not pruned after full claude deselect"
[ -d "$TN/.opencode" ] && fail "R13: empty .opencode/ not pruned after full opencode deselect"
rm -rf "$TN"
pass "deselect prunes harness dirs only when left empty (R13)"

# deselect_antigravity_preserves_user_agent_dir (R13, Codex r3 P1 #3400997183): with the
# E07-F01 .agents/ glue in place, deselecting antigravity removes ONLY the harness-owned
# files (scoped remove_owned) and must NEVER delete a user-authored file or `rm -rf` the
# user's .agents/ dir — the dir survives because it still holds the user's own content.
TP="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" "$TP" >/dev/null || fail "antigravity-noop setup install failed"  # ALL ⇒ persists antigravity
grep -qx antigravity "$TP/.harness/.agents" || fail "setup: antigravity not in persisted baseline"
mkdir -p "$TP/.agents"; printf 'mine\n' > "$TP/.agents/user-config.md"   # user-authored, not harness-owned
sh "$SRC/harness-install.sh" --agents=claude "$TP" >/dev/null 2>&1 || fail "antigravity deselect rerun failed"
[ -d "$TP/.agents" ]                 || fail "Codex r3 P1: user-authored .agents/ dir was wrongly deleted on antigravity deselect"
[ -f "$TP/.agents/user-config.md" ]   || fail "Codex r3 P1: user-authored .agents/user-config.md was wrongly deleted"
rm -rf "$TP"
pass "antigravity deselect is a no-op, never deletes a user-authored .agents/ (Codex r3 P1)"

# antigravity_deselect_is_byte_exact (R13, Codex r2 P1 #3404240336): a pre-this-version
# no-op antigravity install can leave `antigravity` persisted in .harness/.agents while
# the user authored their OWN .agents/agents/<role>.md with a STANDARD name. On deselect,
# the .agents/ glue removal must be byte-compare-and-remove (like opencode.json) — delete
# ONLY a pristine harness-generated file, NEVER a user file that merely shares the name.
TPB="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=antigravity "$TPB" >/dev/null || fail "ag-exact setup install failed"
[ -f "$TPB/.agents/agents/builder.md" ]   || fail "ag-exact setup: generated builder persona missing"
[ -f "$TPB/.agents/agents/reviewer.md" ]  || fail "ag-exact setup: generated reviewer persona missing"
[ -f "$TPB/.agents/workflows/sdd-next.md" ] || fail "ag-exact setup: generated sdd-next workflow missing"
# User overwrites builder.md with their OWN distinctive content (a standard-named file).
printf 'MY CUSTOM ANTIGRAVITY BUILDER\n' > "$TPB/.agents/agents/builder.md"
# Deselect antigravity.
sh "$SRC/harness-install.sh" --agents=claude "$TPB" >/dev/null 2>&1 || fail "ag-exact deselect rerun failed"
# User-authored, standard-named file SURVIVES with its content intact.
[ -f "$TPB/.agents/agents/builder.md" ]                       || fail "Codex r2 P1: user-authored .agents/agents/builder.md was wrongly deleted on deselect"
grep -qF 'MY CUSTOM ANTIGRAVITY BUILDER' "$TPB/.agents/agents/builder.md" || fail "Codex r2 P1: user-authored builder.md content not preserved"
# Pristine harness-generated glue (persona + workflow + rule) IS removed.
[ -f "$TPB/.agents/agents/reviewer.md" ]  && fail "Codex r2 P1: pristine generated reviewer persona must be removed on deselect"
[ -f "$TPB/.agents/workflows/sdd-next.md" ] && fail "Codex r2 P1: pristine generated sdd-next workflow must be removed on deselect"
[ -f "$TPB/.agents/rules/harness.md" ]    && fail "Codex r2 P1: pristine generated .agents/rules/harness.md must be removed on deselect"
# The .agents/ tree survives because the user file kept .agents/agents/ non-empty.
[ -d "$TPB/.agents" ]                    || fail "Codex r2 P1: .agents/ wrongly removed while a user file remains"
rm -rf "$TPB"
pass "antigravity deselect deletes only byte-pristine .agents/ glue, keeps user files (Codex r2 P1)"

# opencode_json_removal_is_byte_exact (R13, Codex r4 P2 #3401025100): on opencode
# deselect, a PRISTINE generated opencode.json is removed, but one the user edited
# (e.g. added a "model" key to the generated file) is preserved.
TQ="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=opencode "$TQ" >/dev/null || fail "oc-exact setup1 failed"
[ -f "$TQ/opencode.json" ] || fail "oc-exact setup: generated opencode.json missing"
sh "$SRC/harness-install.sh" --agents=claude "$TQ" >/dev/null 2>&1 || fail "oc-exact rerun1 failed"
[ -f "$TQ/opencode.json" ] && fail "Codex r4 P2: pristine generated opencode.json must be removed on deselect"
# now the edited-file case: regenerate, then a user adds project settings to it
sh "$SRC/harness-install.sh" --agents=opencode "$TQ" >/dev/null || fail "oc-exact setup2 failed"
# insert a user "model" line after the schema line (started from the generated file)
awk 'NR==2{print "  \"model\": \"anthropic/claude\","} {print}' "$TQ/opencode.json" > "$TQ/opencode.json.tmp" \
  && mv "$TQ/opencode.json.tmp" "$TQ/opencode.json"
grep -q '"model"' "$TQ/opencode.json" || fail "oc-exact setup: user edit not applied"
sh "$SRC/harness-install.sh" --agents=claude "$TQ" >/dev/null 2>&1 || fail "oc-exact rerun2 failed"
[ -f "$TQ/opencode.json" ] || fail "Codex r4 P2: user-edited opencode.json was wrongly deleted on deselect"
grep -q '"model"' "$TQ/opencode.json" || fail "Codex r4 P2: user-edited opencode.json content not preserved"
rm -rf "$TQ"
pass "opencode.json deselect deletes only a byte-pristine generated file, keeps edits (Codex r4 P2)"

# gemini_deselect_keeps_gemini_when_antigravity_remains (E07-F01 R1, Codex r1 P2
# #3404185446): GEMINI.md is SHARED by gemini and antigravity. Deselecting gemini
# while antigravity stays selected must KEEP GEMINI.md (antigravity still owns it),
# and conversely deselecting antigravity-only orphan removal happens only when both
# owners are gone.
TR="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=gemini,antigravity "$TR" >/dev/null || fail "shared-gemini setup install failed"
[ -f "$TR/GEMINI.md" ] || fail "shared-gemini setup: GEMINI.md not stamped for gemini,antigravity"
# Drop gemini, keep antigravity: GEMINI.md must survive (antigravity owns it).
sh "$SRC/harness-install.sh" --agents=antigravity "$TR" >/dev/null 2>&1 || fail "shared-gemini deselect-gemini rerun failed"
[ -f "$TR/GEMINI.md" ]                || fail "R1: deselecting gemini while antigravity remains must KEEP GEMINI.md (Codex r1 P2)"
grep -qF '<!-- harness:begin -->' "$TR/GEMINI.md" || fail "R1: GEMINI.md harness block stripped despite antigravity still selected"
# Now drop antigravity too (last owner gone): GEMINI.md must finally be removed.
sh "$SRC/harness-install.sh" --agents=claude "$TR" >/dev/null 2>&1 || fail "shared-gemini deselect-antigravity rerun failed"
[ -f "$TR/GEMINI.md" ] && fail "R13: GEMINI.md must be removed once NEITHER gemini nor antigravity is selected"
rm -rf "$TR"
pass "GEMINI.md shared by gemini+antigravity: kept until both deselected (R1, R13, Codex r1 P2)"

# ── E99-F01: interactive checkbox picker (tui_select) + graceful fallback ─────────
# The arrow-key + spacebar checkbox UI is the PREFERRED interactive path, but it must
# never change the resolved SELECTED contract and must gracefully fall back to the
# numbered toggle_select when raw mode is unavailable (e.g. non-TTY / piped stdin —
# exactly how this suite runs). We assert the picker + capability probe + fallback
# wiring exist, and that the probe correctly reports "not capable" under no-TTY stdin.

# The new helpers are present in the installer body.
grep -qE '^tui_select\(\)' "$SRC/harness-install.sh"  || fail "E99-F01: tui_select() picker not defined"
grep -qE '^tui_capable\(\)' "$SRC/harness-install.sh" || fail "E99-F01: tui_capable() probe not defined"

# resolve_agents prefers tui_select but keeps toggle_select as the fallback branch.
grep -qF 'if tui_capable; then' "$SRC/harness-install.sh"      || fail "E99-F01: resolve_agents does not gate on tui_capable"
grep -qF 'SELECTED="$(tui_select "$_base")"' "$SRC/harness-install.sh"    || fail "E99-F01: tui_select not wired as preferred interactive picker"
grep -qF 'SELECTED="$(toggle_select "$_base")"' "$SRC/harness-install.sh" || fail "E99-F01: toggle_select fallback branch removed"

# Raw mode is entered AND unconditionally restored via an EXIT/INT/TERM trap so a
# quit/Ctrl-C can never leave the terminal in raw mode.
grep -qF 'trap - EXIT INT TERM' "$SRC/harness-install.sh" || fail "E99-F01: tui_select must clear its EXIT/INT/TERM trap on normal completion"
grep -qE "trap .*EXIT INT TERM" "$SRC/harness-install.sh" || fail "E99-F01: tui_select must install an EXIT/INT/TERM restore trap"

# tui_capable returns NON-ZERO when stdin is not an interactive TTY (so resolve_agents
# falls back to toggle_select). Extract just the helper, then call it with stdin
# explicitly redirected away from any TTY — the `[ -t 0 ]` guard must short-circuit to
# the fallback. Written to a temp script so the redirect applies to the invocation
# itself (not just the pipeline), which is how the non-interactive install path runs.
TUI_PROBE_SH="$(mktemp 2>/dev/null || mktemp -t harness_tui)"
{
  sed -n '/^tui_capable()/,/^}/p' "$SRC/harness-install.sh"
  printf 'tui_capable && echo CAPABLE || echo FALLBACK\n'
} > "$TUI_PROBE_SH"
_probe_out="$(sh "$TUI_PROBE_SH" </dev/null)"
[ "$_probe_out" = "FALLBACK" ] \
  || fail "E99-F01: tui_capable must report not-capable (fallback) under non-TTY stdin (got: '$_probe_out')"
rm -f "$TUI_PROBE_SH"
pass "checkbox picker tui_select + tui_capable probe exist; non-TTY falls back to toggle_select (E99-F01)"

# ── E17-F01: per-role model routing — INSTALLER WIRING ────────────────────────────
# The `models:` block has TWO halves that must ship together: the fresh-install source
# (harness.config.yaml, copied verbatim) and the upgrade path (migrate_config). Missing
# either makes a fresh target and an upgraded target diverge, so both are asserted here,
# in the same change as the installer edit. CODEX_HOME is sandboxed suite-wide (above)
# and per-run below, so no assertion can write into the developer's real ~/.codex.
MODEL_ROLE_NAMES="orchestrator architect builder reviewer scout doc-critic"

test_models_block_seeded() {   # R1
  _mt="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
  CODEX_HOME="$_mt/ch" sh "$SRC/harness-install.sh" --agents=claude "$_mt" >/dev/null \
    || fail "R1: fresh install for models seeding exited non-zero"
  _mc="$_mt/.harness/harness.config.yaml"
  grep -Eq '^models:[[:space:]]*(#.*)?$' "$_mc" || fail "R1: fresh config has no top-level models: block"
  grep -Eq '^  default: inherit' "$_mc"          || fail "R1: fresh config models: block has no default: inherit"
  for _r in $MODEL_ROLE_NAMES; do
    grep -Eq "^  $_r: inherit" "$_mc" || fail "R1: fresh config models: block missing '$_r: inherit'"
  done
  grep -qF 'pin.opencode.' "$_mc" || fail "R1: fresh config models: block missing the commented pin. examples"
  rm -rf "$_mt"
}

test_models_block_migrated() {   # R2
  _mt="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
  CODEX_HOME="$_mt/ch" sh "$SRC/harness-install.sh" --agents=claude "$_mt" >/dev/null \
    || fail "R2: setup install exited non-zero"
  _mc="$_mt/.harness/harness.config.yaml"
  # Simulate a pre-E17 target: strip the whole models: block, then add a user comment +
  # a user value that MUST survive byte-for-byte.
  awk '/^# Per-role model routing/ { drop=1 } !drop { print }' "$_mc" > "$_mc.pre" && mv "$_mc.pre" "$_mc"
  grep -Eq '^models:' "$_mc" && fail "R2: setup failed — models: block not stripped"
  printf '\n# my own note, keep me verbatim\nmy_key: "my value"   # trailing comment\n' >> "$_mc"
  cp "$_mc" "$_mt/before.yaml"
  CODEX_HOME="$_mt/ch" sh "$SRC/harness-install.sh" --agents=claude "$_mt" >/dev/null \
    || fail "R2: upgrade run exited non-zero"
  grep -Eq '^models:[[:space:]]*(#.*)?$' "$_mc" || fail "R2: upgrade did not append the models: block"
  grep -Eq '^  default: inherit' "$_mc"          || fail "R2: migrated models: block has no default: inherit"
  for _r in $MODEL_ROLE_NAMES; do
    grep -Eq "^  $_r: inherit" "$_mc" || fail "R2: migrated models: block missing '$_r: inherit'"
  done
  # Every pre-existing line (values AND comments) survives byte-for-byte as a PREFIX.
  _n="$(wc -l < "$_mt/before.yaml")"
  head -n "$_n" "$_mc" > "$_mt/after-head.yaml"
  cmp -s "$_mt/before.yaml" "$_mt/after-head.yaml" \
    || fail "R2: migration altered pre-existing config lines (must be append-only)"
  rm -rf "$_mt"
}

test_models_block_idempotent() {   # R3
  _mt="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
  CODEX_HOME="$_mt/ch" sh "$SRC/harness-install.sh" --agents=claude "$_mt" >/dev/null \
    || fail "R3: setup install exited non-zero"
  _mc="$_mt/.harness/harness.config.yaml"
  cp "$_mc" "$_mt/run1.yaml"
  CODEX_HOME="$_mt/ch" sh "$SRC/harness-install.sh" --agents=claude "$_mt" >/dev/null \
    || fail "R3: second run exited non-zero"
  cmp -s "$_mt/run1.yaml" "$_mc" || fail "R3: second run did not leave harness.config.yaml byte-identical"
  [ "$(grep -c '^models:' "$_mc")" = "1" ] || fail "R3: models: block duplicated on re-run"
  # A trailing comment on the `models:` line must still count as "present".
  sed 's/^models:$/models:   # my routing/' "$_mc" > "$_mc.t" && mv "$_mc.t" "$_mc"
  cp "$_mc" "$_mt/run2.yaml"
  CODEX_HOME="$_mt/ch" sh "$SRC/harness-install.sh" --agents=claude "$_mt" >/dev/null \
    || fail "R3: trailing-comment run exited non-zero"
  cmp -s "$_mt/run2.yaml" "$_mc" \
    || fail "R3: a trailing comment on the models: line made migration re-append the block"
  rm -rf "$_mt"
}

test_no_models_block_is_byte_identical() {   # R11
  _all=claude,gemini,opencode,antigravity,codex
  _ta="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
  _tb="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
  CODEX_HOME="$_ta/ch" sh "$SRC/harness-install.sh" --agents="$_all" "$_ta" >/dev/null \
    || fail "R11: TA install exited non-zero"
  CODEX_HOME="$_tb/ch" sh "$SRC/harness-install.sh" --agents="$_all" "$_tb" >/dev/null \
    || fail "R11: TB install exited non-zero"
  # TB: strip the whole models: block, then re-run. (migrate_config re-seeds it — that is
  # the point: seeding must be INERT, so the generated tree may not move a byte.)
  _bc="$_tb/.harness/harness.config.yaml"
  awk '/^# Per-role model routing/ { drop=1 } !drop { print }' "$_bc" > "$_bc.pre" && mv "$_bc.pre" "$_bc"
  CODEX_HOME="$_tb/ch" sh "$SRC/harness-install.sh" --agents="$_all" "$_tb" >/dev/null \
    || fail "R11: TB re-run exited non-zero"
  # R11 permits exactly ONE product exclusion — `.harness/harness.config.yaml` (TB's
  # block was stripped and re-seeded, so its bytes legitimately differ). `__pycache__`
  # is a Python runtime artifact. Nothing else may be excluded:
  # manifest.txt in particular MUST be compared, or the strongest test in the suite goes
  # blind to any leak of model state into the manifest.
  diff -r -x 'harness.config.yaml' -x '__pycache__' "$_ta" "$_tb" >/dev/null \
    || fail "R11: an all-inherit target differs from one whose models: block was stripped"
  # Explicit negatives: no unresolved role gains a model key. Gemini stays conditional;
  # selected Codex still registers its six model-less roles.
  grep -rq '^model:' "$_ta/.claude/agents"  && fail "R11: unconfigured install stamped a model: in .claude/agents"
  grep -q '"model"' "$_ta/opencode.json"    && fail "R11: unconfigured install stamped a model member in opencode.json"
  grep -rq '^model:' "$_ta/.agents/agents"  && fail "R11: unconfigured install stamped a model: in .agents/agents"
  [ -d "$_ta/.gemini/agents" ]              && fail "R11: unconfigured install created .gemini/agents/"
  [ "$(find "$_ta/.codex/agents" -type f -name '*.toml' | wc -l | tr -d ' ')" = "6" ] \
    || fail "R6: unconfigured selected Codex did not register exactly six roles"
  grep -q '^model = ' "$_ta/.codex/agents/"*.toml \
    && fail "R7: unconfigured Codex role gained a model key"
  [ -f "$_ta/.harness/.opencode.stamp" ]    && fail "R11: unconfigured install created .harness/.opencode.stamp"
  [ -d "$_ta/.harness/.model-agents/gemini" ] \
    && fail "R11: unconfigured install created Gemini model-agent stamps"
  # And prove the RESOLVER itself treats a config with no models: block as `inherit`
  # (migrate_config always re-seeds the block, so this is the only way to exercise the
  # genuinely block-less config an older target hands us mid-run).
  _probe="$(mktemp 2>/dev/null || mktemp -t harness_mdl)"
  printf 'store:\n  tasks: local\n' > "$_ta/no-models.yaml"
  {
    sed -n '/^_cfg_models_value()/,/^}/p' "$SRC/harness-install.sh"
    printf 'v="$(_cfg_models_value "%s" default)"; [ -z "$v" ] && echo INHERIT || echo "GOT:$v"\n' "$_ta/no-models.yaml"
  } > "$_probe"
  [ "$(sh "$_probe")" = "INHERIT" ] \
    || fail "R11: a config with no models: block must resolve to empty (⇒ inherit ⇒ key omission)"
  rm -f "$_probe"; rm -rf "$_ta" "$_tb"
}

test_claude_model_frontmatter() {   # R12, R18
  _mt="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
  CODEX_HOME="$_mt/ch" sh "$SRC/harness-install.sh" --agents=claude "$_mt" >/dev/null \
    || fail "R12: setup install exited non-zero"
  _mc="$_mt/.harness/harness.config.yaml"
  sed -e 's/^  architect: inherit.*/  architect: reasoning/' \
      -e 's/^  scout: inherit.*/  scout: cheap/' "$_mc" > "$_mc.t" && mv "$_mc.t" "$_mc"
  CODEX_HOME="$_mt/ch" sh "$SRC/harness-install.sh" --agents=claude "$_mt" >/dev/null \
    || fail "R12: re-stamp run exited non-zero"
  _a="$_mt/.claude/agents/architect.md"
  grep -q '^name: architect' "$_a"        || fail "R12: architect.md lost its name: key"
  grep -q '^description: ' "$_a"          || fail "R12: architect.md lost its description: key"
  grep -q '^tools: ' "$_a"                || fail "R12: architect.md lost its tools: key"
  grep -q '^model: ' "$_a"                || fail "R12: architect.md carries no model: frontmatter key"
  [ "$(grep -c '^model:' "$_a")" = "1" ]  || fail "R12: architect.md accumulated more than one model: key"
  grep -q '^model: ' "$_mt/.claude/agents/scout.md" || fail "R12: scout.md carries no model: key"
  [ "$(sed -n 's/^model: //p' "$_a")" != "$(sed -n 's/^model: //p' "$_mt/.claude/agents/scout.md")" ] \
    || fail "R12: reasoning and cheap tiers stamped the same claude value"
  grep -q '^model:' "$_mt/.claude/agents/builder.md" \
    && fail "R12: a role left on inherit must carry NO model: key"
  # R18: only `claude` was selected, so no other front-end may have been stamped.
  [ -d "$_mt/.gemini/agents" ] && fail "R18: unselected gemini was stamped"
  [ -d "$_mt/.codex/agents" ]  && fail "R18: unselected codex was stamped"
  [ -f "$_mt/opencode.json" ]  && fail "R18: unselected opencode was stamped"
  rm -rf "$_mt"
}

test_models_docs_and_manifest() {   # R24
  _mt="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
  CODEX_HOME="$_mt/ch" sh "$SRC/harness-install.sh" --agents=claude "$_mt" >/dev/null \
    || fail "R24: setup install exited non-zero"
  _mf="$_mt/.harness/manifest.txt"
  grep -qF '.gemini/agents/' "$_mf"          || fail "R24: manifest.txt does not list .gemini/agents/"
  grep -qF '.codex/agents/' "$_mf"           || fail "R24: manifest.txt does not list .codex/agents/"
  grep -qF '.harness/.opencode.stamp' "$_mf" || fail "R24: manifest.txt does not list .harness/.opencode.stamp"
  grep -qF 'claude|gemini|opencode|antigravity|codex' "$_mf" \
    || fail "R24: manifest.txt AGENT SELECTION paragraph still omits codex"
  # The docs must SHIP (the installed copy under .harness/docs/), not just exist in SRC.
  _mi="$_mt/.harness/docs/INSTALL.md"
  grep -qF 'models:' "$_mi"          || fail "R24: installed docs/INSTALL.md does not document the models: block"
  grep -qF 'reasoning' "$_mi"        || fail "R24: installed docs/INSTALL.md does not document the tier vocabulary"
  grep -qF 'provider/model' "$_mi"   || fail "R24: installed docs/INSTALL.md does not document the opencode value rule"
  grep -qF 'agy' "$_mi"              || fail "R24: installed docs/INSTALL.md does not document the Antigravity agy floor"
  grep -qF '.gemini/agents/' "$_mi"  || fail "R24: installed docs/INSTALL.md layout tree omits .gemini/agents/"
  grep -qF '.codex/agents/' "$_mi"   || fail "R24: installed docs/INSTALL.md layout tree omits .codex/agents/"
  grep -qF 'tests/test_model_routing.sh' "$SRC/harness.config.yaml" \
    || fail "R24: tests/test_model_routing.sh is not registered in verification.test_command"
  [ -f "$SRC/tests/test_model_routing.sh" ] || fail "R24: tests/test_model_routing.sh does not exist"
  rm -rf "$_mt"
}

test_models_changelog_entry() {   # R25
  # Assert the CHANGELOG heading + summary, never a frozen exact VERSION string (that is
  # a permanent-suite anti-pattern that breaks on the next PATCH bump).
  grep -qF '## [0.38.0]' "$SRC/CHANGELOG.md" || fail "R25: CHANGELOG missing 0.38.0 entry"
  grep -qF 'per-role model' "$SRC/CHANGELOG.md" \
    || fail "R25: CHANGELOG missing the per-role model routing summary"
}

# E22-F01: /sdd-fix-parallel is skipped for OpenCode by default; the probe is installed;
# --with-opencode-parallel=true overrides; and the marker written by the probe is honored.
test_opencode_parallel_optin() {
  _op="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
  CODEX_HOME="$_op/ch" sh "$SRC/harness-install.sh" --agents=opencode "$_op" >/dev/null \
    || fail "E22-F01: default opencode install exited non-zero"
  # Default: probe present, parallel absent.
  [ -f "$_op/.opencode/command/sdd-test-concurrency.md" ] \
    || fail "E22-F01: default opencode install missing sdd-test-concurrency"
  grep -q '.harness/progress/opencode-concurrency-probe/' "$_op/.opencode/command/sdd-test-concurrency.md" \
    || fail "E22-F01: probe does not use the Scout-allowed .harness/progress/ output area"
  [ ! -f "$_op/.opencode/command/sdd-fix-parallel.md" ] \
    || fail "E22-F01: default opencode install stamped sdd-fix-parallel"
  # Force it on.
  CODEX_HOME="$_op/ch" sh "$SRC/harness-install.sh" --agents=opencode --with-opencode-parallel=true "$_op" >/dev/null \
    || fail "E22-F01: --with-opencode-parallel=true install exited non-zero"
  [ -f "$_op/.opencode/command/sdd-fix-parallel.md" ] \
    || fail "E22-F01: --with-opencode-parallel=true did not stamp sdd-fix-parallel"
  [ -f "$_op/.opencode/command/sdd-test-concurrency.md" ] \
    || fail "E22-F01: --with-opencode-parallel=true removed sdd-test-concurrency"
  # Force it off again.
  CODEX_HOME="$_op/ch" sh "$SRC/harness-install.sh" --agents=opencode --with-opencode-parallel=false "$_op" >/dev/null \
    || fail "E22-F01: --with-opencode-parallel=false install exited non-zero"
  [ ! -f "$_op/.opencode/command/sdd-fix-parallel.md" ] \
    || fail "E22-F01: --with-opencode-parallel=false did not remove sdd-fix-parallel"
  # Marker-driven: write a supported marker and re-run without the flag.
  printf 'supported\n' > "$_op/.harness/.opencode-parallel"
  CODEX_HOME="$_op/ch" sh "$SRC/harness-install.sh" --agents=opencode "$_op" >/dev/null \
    || fail "E22-F01: marker-driven install exited non-zero"
  [ -f "$_op/.opencode/command/sdd-fix-parallel.md" ] \
    || fail "E22-F01: supported marker did not cause sdd-fix-parallel to be installed"
  # sequential marker should skip.
  printf 'sequential\n' > "$_op/.harness/.opencode-parallel"
  CODEX_HOME="$_op/ch" sh "$SRC/harness-install.sh" --agents=opencode "$_op" >/dev/null \
    || fail "E22-F01: sequential-marker install exited non-zero"
  [ ! -f "$_op/.opencode/command/sdd-fix-parallel.md" ] \
    || fail "E22-F01: sequential marker did not cause sdd-fix-parallel to be removed"
  # A user-authored sdd-fix-parallel.md must survive when the harness skips it.
  _op2="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
  mkdir -p "$_op2/.opencode/command"
  printf 'user-authored\n' > "$_op2/.opencode/command/sdd-fix-parallel.md"
  CODEX_HOME="$_op2/ch" sh "$SRC/harness-install.sh" --agents=opencode "$_op2" >/dev/null \
    || fail "E22-F01: user-parallel install exited non-zero"
  [ -f "$_op2/.opencode/command/sdd-fix-parallel.md" ] \
    || fail "E22-F01: user-authored sdd-fix-parallel.md was deleted on default install"
  grep -q 'user-authored' "$_op2/.opencode/command/sdd-fix-parallel.md" \
    || fail "E22-F01: user-authored sdd-fix-parallel.md content was overwritten"
  # The marker file is ignored by the seeded .harness/.gitignore.
  grep -qxF '.opencode-parallel' "$_op2/.harness/.gitignore" \
    || fail "E22-F01: .harness/.gitignore does not ignore .opencode-parallel"
  rm -rf "$_op" "$_op2"
}

test_models_block_seeded
test_models_block_migrated
test_models_block_idempotent
pass "models: block seeded on fresh install, appended on upgrade, idempotent (R1, R2, R3)"
test_no_models_block_is_byte_identical
pass "no/all-inherit models: block leaves the generated tree byte-identical, no new dirs (R11)"
test_claude_model_frontmatter
pass "claude .claude/agents/<role>.md carries model: beside name/description/tools; unselected front-ends untouched (R12, R18)"
test_models_docs_and_manifest
test_models_changelog_entry
pass "manifest.txt + docs/INSTALL.md document model routing; new suite registered; CHANGELOG entry present (R24, R25)"
test_opencode_parallel_optin
pass "OpenCode /sdd-fix-parallel is opt-in via --with-opencode-parallel or the /sdd-test-concurrency marker (E22-F01)"

test_opencode_model_helper() {
  _oh="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
  CODEX_HOME="$_oh/ch" sh "$SRC/harness-install.sh" --agents=opencode "$_oh" >/dev/null \
    || fail "E22-F01: model helper install exited non-zero"
  [ -x "$_oh/.harness/tools/opencode-model-helper.sh" ] \
    || fail "E22-F01: opencode-model-helper.sh not installed executable"
  grep -q 'pin.opencode.reasoning' "$_oh/.harness/tools/opencode-model-helper.sh" \
    || fail "E22-F01: helper missing expected reasoning tier placeholder"
  # The installed helper defaults to the installed config path.
  grep -q '\.harness/harness\.config\.yaml' "$_oh/.harness/tools/opencode-model-helper.sh" \
    || fail "E22-F01: installed helper does not default to .harness/harness.config.yaml"
  rm -rf "$_oh"
}

test_opencode_model_helper
pass "OpenCode model helper is installed as an executable tool under .harness/tools (E22-F01)"

echo "All install tests passed."
