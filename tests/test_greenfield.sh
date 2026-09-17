#!/bin/sh
# test_greenfield.sh — E28-F01: the greenfield single-repo front door.
#
# Covers R1–R10 of
# specs/epics/E28-greenfield-to-umbrella/F01-greenfield-single-path/E28-F01.spec.md:
#   R1  "Starting from nothing (new product)" documents the ordered front door
#   R2  the section states the empty/non-git facts and who runs `git init`
#   R3  exactly one `/sdd-plan`-before-`/sdd-next` order, in both sections
#   R4  "Bootstrap (first run)" keeps its heading and routes E00-F01 after /sdd-plan
#   R5  the fresh-install `Next steps` banner presents the ordered front door per host
#       (/sdd-plan → /sdd-drill → /sdd-next; Codex: $sdd-plan → $sdd-drill → $sdd-next)
#       AND names the human `git init` + initial commit step before those commands
#
# Round-4 review addition:
#   * R5 also requires the `git init` + initial-commit step in the fresh-install
#     banner, before the host-specific planning commands (4041736459). The installer
#     still performs no `git init` (R6); this is an instruction to the human, because
#     the installed workflow needs feature branches and PRs.
#   R6  a single-target install creates no `.git`
#   R7  the one install runs into an asserted-empty, non-git fixture
#   R8  the installed layout is usable (AGENTS.md, .harness, board, /sdd-plan)
#   R9  the installed init.sh exits 0 in the still-non-git target
#   R10 the installed version stamp is read from $SRC/VERSION at run time
#
# Round-5 review addition:
#   * R5/R2 must not overclaim: a local-only `git init` + commit cannot open a PR
#     (4041813522). The git step must name the remote (`gh repo create` / `git remote
#     add` + push) and the one-feature-branch-per-feature discipline the PR is opened
#     from. Anchored as positive tokens plus folded two-token pairs, never a
#     fail-open negative.
#
# Round-3 review addition:
#   * R1 also requires the product-constitution edit step (specs/product.md, fill
#     the TODOs) to be present and ordered BEFORE /sdd-plan (4041680863). The
#     Planner cannot repair the omission (agents/planner.md forbids rewriting the
#     constitution), so the standalone path must instruct the edit itself.
#
# Round-2 review additions:
#   * R1/R4 also pin the drill step's required `<epic-id>` argument
#     (4041566961), so the advertised sequence is directly executable.
#   * `test_installed_product_md_points_at_sdd_plan` pins that the seeded
#     `specs/product.md` names `/sdd-plan` for a new product's epics and never
#     `/sdd-next` (4041566967). It carries a positive SHAPE control before the
#     negative, per the dead-predicate lesson (progress/lessons.md).
#   * `test_installed_entrypoint_points_at_sdd_plan` pins the installed root
#     `AGENTS.md` pointer's new-product branch (4041566967).
#
# Round-6 review addition:
#   * R1/R4/R5 must commit the planning baseline before feature work (4041879995):
#     `/sdd-plan` and `/sdd-drill` leave `product.md`, the vision, architecture, ADRs,
#     the decomposition and the TaskStore dirty/untracked, so the sequence must commit
#     and push them and create the first feature branch before `/sdd-next` — otherwise
#     the first feature PR carries the planning changes. Anchored as positive tokens
#     plus folded two-token pairs and first-occurrence order; no fail-open predicate.
#
# Round-8 review addition:
#   * The fresh-install banner emits exactly ONE numbered workflow for any selection:
#     a multi-host selection (`--agents=all`, or any CSV with >1 host) lists the
#     host-specific invocation forms as alternatives WITHIN each step, instead of
#     printing steps 3-6 plus the baseline commit once per host (4042015434). The
#     pre-change loop made the banner read as "run the whole workflow three times",
#     and a sequential reader hit /sdd-plan's re-run guard on the second pass.
#     `test_multi_host_banner_emits_one_workflow` pins exactly one step 3/4/5/6 line,
#     exactly one baseline step and one planning step, and both `/sdd-*` + `$sdd-*`
#     forms in that single planning step.
#   * The generated entrypoint pointer (`write_pointer AGENTS.md` / `CLAUDE.md`) is
#     host-neutral: it names both `/sdd-plan`/`$sdd-plan` forms (and the drill/next
#     equivalents), so a Codex-only install is not told to use slash commands it does
#     not have (4042015445). R8c's anchors are unchanged by the wording.
#
# Round-7 review addition:
#   * `test_installed_entrypoint_points_at_sdd_plan` also pins the drill step in the
#     installed root AGENTS.md pointer (4041951737). Without it, the pointer sends a
#     new product from `/sdd-plan` straight to `/sdd-next`; `/sdd-plan` leaves the
#     epics `draft`, so `/sdd-next` reports their features as `gated-epic`. Presence
#     plus folded `/sdd-plan → /sdd-drill → /sdd-next` pairs, not a whole-file grep.
#   * The fresh-install banner's human git step (`git init` + initial commit) now
#     precedes the constitution edit, matching `docs/INSTALL.md`'s ordered section and
#     its "second item, after `git init`" cross-reference (the unchanged R5 anchors
#     still hold; the banner asserts order by first occurrence, not step labels).
#
# CONVENTIONS THIS SUITE HONOURS (progress/lessons.md):
#   * No `VERSION` literal anywhere. R10 reads $SRC/VERSION at run time; the
#     no-literal half is only falsifiable by the Reviewer's bump mutation, not by
#     an in-suite self-grep (which would be a dead predicate).
#   * Every prose assertion extracts the SECTION it names (heading → next `## `)
#     and guards it non-empty with a line-count floor before asserting, so a
#     rename or move reds instead of silently passing on an empty span.
#   * Every ordering assertion has a positive presence control first, so an
#     absent anchor cannot make the position comparison vacuous.
#   * The fixture is created empty and asserted non-git before installing — never
#     a copy of the repo, which would inherit the artifact under test.
#   * stdout is captured separately from stderr: the banner contract names stdout.
#
# Zero dependencies; self-cleaning temp dir; POSIX sh only.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-greenfield)"
trap 'rm -rf "$T"' EXIT

DOC="$SRC/docs/INSTALL.md"
README="$SRC/README.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── extraction / assertion helpers ────────────────────────────────────────────

# section_span <file> <exact H2 line> — print the span from that heading to the
# next `## ` heading (exclusive). Empty output means the heading is stale/moved.
# Fence-aware via tests/lib/fence.awk, the ONE shared CommonMark rule
# (test_change_size.sh R9d): a `## ` line inside a fenced block must not end the
# span. The awk program is passed through the shell verbatim; the fence file's
# backticks are not re-scanned because command-substitution output is not re-expanded.
section_span() {
  SECTION_HEADING="$2" awk "$(cat "$SRC/tests/lib/fence.awk")"'
    BEGIN { h = ENVIRON["SECTION_HEADING"] }
    fence_delim($0) { if (k) print; next }
    !k && !fence && $0 == h { k = 1 }
    k && !fence && /^## / && $0 != h { exit }
    k { print }
  ' "$1"
}

# line_count <text>
line_count() { printf '%s\n' "$1" | grep -c ''; }

# assert_contains <label> <haystack> <needle> — positive control.
assert_contains() {
  printf '%s\n' "$2" | grep -qF -- "$3" \
    || fail "$1: missing required anchor '$3' — the assertion set is incomplete, not just mis-ordered"
}

# require_order <label> <span> <A> <B> [le|lt] — first A must precede first B.
# Both anchors must be present, so a missing token can never make this vacuous.
require_order() {
  _ro_lbl="$1"; _ro_sp="$2"; _ro_a="$3"; _ro_b="$4"; _ro_op="${5:-lt}"
  _ro_pa="$(printf '%s\n' "$_ro_sp" | awk -v n="$_ro_a" 'index($0,n){print NR; exit}')"
  _ro_pb="$(printf '%s\n' "$_ro_sp" | awk -v n="$_ro_b" 'index($0,n){print NR; exit}')"
  [ -n "$_ro_pa" ] || fail "$_ro_lbl: anchor '$_ro_a' is absent — ordering check would be vacuous"
  [ -n "$_ro_pb" ] || fail "$_ro_lbl: anchor '$_ro_b' is absent — ordering check would be vacuous"
  case "$_ro_op" in
    le) [ "$_ro_pa" -le "$_ro_pb" ] \
          || fail "$_ro_lbl: '$_ro_a' (line $_ro_pa) is AFTER '$_ro_b' (line $_ro_pb)" ;;
    *)  [ "$_ro_pa" -lt "$_ro_pb" ] \
          || fail "$_ro_lbl: '$_ro_a' (line $_ro_pa) is NOT before '$_ro_b' (line $_ro_pb)" ;;
  esac
}

# front_door_in <label> <span> — /sdd-plan before /sdd-next, both present.
front_door_in() {
  assert_contains "$1" "$2" '/sdd-plan'
  assert_contains "$1" "$2" '/sdd-next'
  require_order "$1" "$2" '/sdd-plan' '/sdd-next' lt
}

# banner_block <file> — the fresh-install `Next steps:` block of <file>, from the
# heading to the next blank line (exclusive). Empty output means the banner is gone.
banner_block() {
  awk '/^Next steps:/{k=1} k{ if ($0 == "") exit; print }' "$1"
}

# ── R1 (static) ───────────────────────────────────────────────────────────────

test_greenfield_section_documents_sequence() {
  _gf="$(section_span "$DOC" '## Starting from nothing (new product)')"
  [ -n "$_gf" ] \
    || fail "R1: docs/INSTALL.md has no '## Starting from nothing (new product)' section — the new-product front door is undocumented"
  [ "$(line_count "$_gf")" -ge 6 ] \
    || fail "R1: the 'Starting from nothing' section is fewer than 6 lines — it is stale, truncated or moved"
  for _a in 'harness-install.sh' 'git init' '/sdd-plan' '/sdd-drill' '/sdd-next'; do
    assert_contains "R1 section" "$_gf" "$_a"
  done
  # Round-2 (4041566961): the drill step must name the epic id it requires, or the
  # advertised sequence stalls on a command that stops to ask. `/sdd-drill` is kept
  # as a substring so the ordering assertions above stay on the same anchor.
  assert_contains "R1 section" "$_gf" '/sdd-drill <epic-id>'
  # Round-3 (4041680863): the standalone sequence must include the
  # product-constitution edit before /sdd-plan. The Planner cannot repair an
  # omission — agents/planner.md defines the vision as complementary to
  # specs/product.md and forbids rewriting it — so a greenfield reader who
  # follows this section alone would keep the seeded stub TODOs forever.
  assert_contains "R1 section" "$_gf" 'specs/product.md'
  _gf_flat="$(printf '%s\n' "$_gf" | tr '\n' ' ')"
  printf '%s\n' "$_gf_flat" | grep -qiE 'edit.{0,80}specs/product\.md' \
    || fail "R1 section: the sequence names specs/product.md but never tells the reader to EDIT it — naming the constitution is not the required edit step"
  printf '%s\n' "$_gf_flat" | grep -qiE 'specs/product\.md[^.]{0,80}(TODO|constitution)' \
    || fail "R1 section: the product-constitution edit (specs/product.md, fill its TODOs) is not stated in one sentence — a standalone greenfield reader keeps the stub constitution and /sdd-plan cannot repair it"
  require_order "R1 sequence" "$_gf" 'specs/product.md' '/sdd-plan' lt
  require_order "R1 sequence" "$_gf" 'harness-install.sh' 'git init' le
  require_order "R1 sequence" "$_gf" 'git init' '/sdd-plan' le
  require_order "R1 sequence" "$_gf" '/sdd-plan' '/sdd-drill' le
  require_order "R1 sequence" "$_gf" '/sdd-drill' '/sdd-next' le
  # Round-6 (4041879995): the sequence must not hand /sdd-next a dirty planning tree.
  # Positive tokens first, then folded pairs that keep both halves in the same sentence
  # of the relevant step (the initial `git init` + commit at step 3 is NOT the planning
  # baseline), then first-occurrence order: drill → baseline commit → feature branch →
  # the /sdd-next execution step.
  assert_contains "R1 section" "$_gf" 'planning baseline'
  assert_contains "R1 section" "$_gf" 'first feature branch'
  printf '%s\n' "$_gf_flat" | grep -qiE 'push[^.]{0,80}planning baseline' \
    || fail "R1 section: the baseline step does not name both the push and the planning baseline in one sentence — a local-only commit leaves the remote baseline without the planning artifacts"
  printf '%s\n' "$_gf_flat" | grep -qiE 'first feature branch[^.]{0,320}first feature PR' \
    || fail "R1 section: the feature-branch step does not state that committing the baseline first keeps the planning artifacts out of the first feature PR — the reason for the order is missing"
  require_order "R1 sequence" "$_gf" '/sdd-drill <epic-id>' 'planning baseline' lt
  require_order "R1 sequence" "$_gf" 'planning baseline' 'first feature branch' lt
  require_order "R1 sequence" "$_gf" 'first feature branch' '/sdd-next' lt
  pass "greenfield section documents the ordered front door (R1) [greenfield_section_documents_sequence]"
}

# ── R2 (static) ───────────────────────────────────────────────────────────────

test_greenfield_section_states_non_git_and_human_git_init() {
  _gf="$(section_span "$DOC" '## Starting from nothing (new product)')"
  [ -n "$_gf" ] \
    || fail "R2: the 'Starting from nothing' section is missing — cannot state the empty/non-git facts"
  for _a in empty non-git commit drift; do
    assert_contains "R2 section" "$_gf" "$_a"
  done
  printf '%s\n' "$_gf" | grep -qF 'The installer does not create a git repository.' \
    || fail "R2: the section does not state 'The installer does not create a git repository.' — a reader cannot tell who owns version control"
  # Round-5 (4041813522): the documented git step must not overclaim either. A
  # local-only `git init` + commit cannot open a PR, so the section must name the
  # remote and the per-feature branch discipline alongside it. The two-token anchors
  # keep both halves in one sentence of the human-git step, not anywhere in the span.
  assert_contains "R2 section" "$_gf" 'remote'
  assert_contains "R2 section" "$_gf" 'feature branch'
  _gf_r2_flat="$(printf '%s\n' "$_gf" | tr '\n' ' ')"
  printf '%s\n' "$_gf_r2_flat" | grep -qiE 'local only[^.]{0,80}remote' \
    || fail "R2: the git step calls itself local only but does not tie that to the required remote in one sentence — a reader can keep a local-only init and believe PRs work"
  printf '%s\n' "$_gf_r2_flat" | grep -qiE 'remote[^.]{0,200}feature branch' \
    || fail "R2: the git step names a remote but does not state the one-feature-branch-per-feature discipline in the same sentence — the PR source branch can be dropped while the remote stays"
  pass "greenfield section states the non-git target and the human git-init step (R2) [greenfield_section_states_non_git_and_human_git_init]"
}

# ── R3 (static) ───────────────────────────────────────────────────────────────

test_one_front_door_story() {
  _gf="$(section_span "$DOC" '## Starting from nothing (new product)')"
  _bs="$(section_span "$DOC" '## Bootstrap (first run)')"
  [ -n "$_gf" ] || fail "R3: the 'Starting from nothing' section is missing"
  [ -n "$_bs" ] || fail "R3: the 'Bootstrap (first run)' section is missing — README's anchor cannot resolve"
  [ "$(line_count "$_gf")" -ge 6 ] || fail "R3: 'Starting from nothing' is shorter than 6 lines — stale extraction"
  [ "$(line_count "$_bs")" -ge 4 ] || fail "R3: 'Bootstrap (first run)' is shorter than 4 lines — stale extraction"
  front_door_in "R3 greenfield section" "$_gf"
  front_door_in "R3 Bootstrap section" "$_bs"
  pass "exactly one front-door order (/sdd-plan before /sdd-next) in both sections (R3) [one_front_door_story]"
}

# ── R4 (static) ───────────────────────────────────────────────────────────────

test_bootstrap_section_reconciled() {
  grep -qF 'docs/INSTALL.md#bootstrap-first-run' "$README" \
    || fail "R4: README.md no longer links to docs/INSTALL.md#bootstrap-first-run — the anchor consumer was dropped"
  grep -qF '## Bootstrap (first run)' "$DOC" \
    || fail "R4: docs/INSTALL.md no longer carries the heading '## Bootstrap (first run)' — README's anchor cannot resolve"
  _bs="$(section_span "$DOC" '## Bootstrap (first run)')"
  [ -n "$_bs" ] || fail "R4: the 'Bootstrap (first run)' span is empty"
  assert_contains "R4 Bootstrap" "$_bs" 'E00-F01'
  assert_contains "R4 Bootstrap" "$_bs" '/sdd-next'
  assert_contains "R4 Bootstrap" "$_bs" '/sdd-plan'
  assert_contains "R4 Bootstrap" "$_bs" '/sdd-drill <epic-id>'
  require_order "R4 Bootstrap" "$_bs" '/sdd-plan' '/sdd-next' lt
  # Round-6 (4041879995): the Bootstrap section describes the same planning → feature
  # handoff, so it must tell the reader to commit/push the baseline and create the first
  # feature branch before /sdd-next — one story, not two.
  assert_contains "R4 Bootstrap" "$_bs" 'planning baseline'
  assert_contains "R4 Bootstrap" "$_bs" 'first feature branch'
  _bs_flat="$(printf '%s\n' "$_bs" | tr '\n' ' ')"
  printf '%s\n' "$_bs_flat" | grep -qiE 'push[^.]{0,80}planning baseline' \
    || fail "R4 Bootstrap: the baseline step does not name both the push and the planning baseline in one sentence — a local-only commit leaves the remote baseline without the planning artifacts"
  require_order "R4 Bootstrap" "$_bs" '/sdd-drill <epic-id>' 'planning baseline' lt
  require_order "R4 Bootstrap" "$_bs" 'planning baseline' 'first feature branch' lt
  require_order "R4 Bootstrap" "$_bs" 'first feature branch' '/sdd-next' lt
  pass "Bootstrap section routes the seeded E00-F01 after /sdd-plan and keeps its heading (R4) [bootstrap_section_reconciled]"
}

# ── The single install (R7 preconditions) ─────────────────────────────────────

TGT="$T/target"
mkdir -p "$TGT"
HOME_SANDBOX="$T/home"
CODEX_SANDBOX="$T/codex-home"
mkdir -p "$HOME_SANDBOX" "$CODEX_SANDBOX"
INSTALL_OUT="$T/install.out"
INSTALL_ERR="$T/install.err"
INSTALLED=0

test_empty_non_git_install_succeeds() {
  [ -d "$TGT" ] || fail "R7: fixture directory does not exist"
  [ -z "$(ls -A "$TGT")" ] \
    || fail "R7: fixture '$TGT' is not empty before install — the case would test an inherited tree, not a greenfield install"
  [ ! -e "$TGT/.git" ] \
    || fail "R7: fixture is already a git work tree — this is not the empty, non-git target the case names"
  _rc=0
  env -i PATH="$PATH" HOME="$HOME_SANDBOX" CODEX_HOME="$CODEX_SANDBOX" \
    sh "$SRC/harness-install.sh" --agents=claude --builder-backend=in-session \
      --pr-loop=false "$TGT" \
    >"$INSTALL_OUT" 2>"$INSTALL_ERR" || _rc=$?
  if [ "$_rc" -ne 0 ]; then
    echo "--- installer stderr ---" >&2
    sed -n '1,60p' "$INSTALL_ERR" >&2 || true
    fail "R7: install into an empty, non-git directory exited $_rc — the documented greenfield path is broken"
  fi
  INSTALLED=1
  [ -f "$TGT/.harness/.harness-version" ] \
    || fail "R7: install exited 0 but left no .harness/.harness-version — it did not land in THIS fixture"
  pass "empty, non-git install succeeds and lands in the fixture (R7) [empty_non_git_install_succeeds]"
}

# ── R5 (integration) ──────────────────────────────────────────────────────────

test_banner_points_at_sdd_plan() {
  [ "$INSTALLED" -eq 1 ] || fail "R5: no install ran (R7 must succeed first)"
  _banner="$(banner_block "$INSTALL_OUT")"
  [ -n "$_banner" ] \
    || fail "R5: fresh-install stdout has no 'Next steps:' banner block — the greenfield pointer is gone"
  [ "$(line_count "$_banner")" -ge 2 ] \
    || fail "R5: the 'Next steps:' block is fewer than 2 lines — stale extraction"
  # The selected (Claude) host gets the whole ordered front door: plan → drill → next.
  for _a in '/sdd-plan' '/sdd-drill' '/sdd-next'; do
    assert_contains "R5 banner" "$_banner" "$_a"
  done
  require_order "R5 banner" "$_banner" '/sdd-plan' '/sdd-drill' lt
  require_order "R5 banner" "$_banner" '/sdd-drill' '/sdd-next' lt
  require_order "R5 banner" "$_banner" '/sdd-plan' '/sdd-next' lt
  # Round-4 (4041736459): the installer never creates .git (R6) and the installed
  # workflow needs feature branches and PRs, so the banner must name the human's git
  # step before the host-specific planning commands. Positive tokens first, then the
  # folded two-token anchor proves the step names BOTH `git init` and the commit.
  assert_contains "R5 banner" "$_banner" 'git init'
  assert_contains "R5 banner" "$_banner" 'commit'
  _banner_flat="$(printf '%s\n' "$_banner" | tr '\n' ' ')"
  printf '%s\n' "$_banner_flat" | grep -qiE 'git init[^.]{0,60}commit' \
    || fail "R5 banner: the git step does not name both \`git init\` and the initial commit in one sentence — a greenfield reader stops at an uncommitted tree"
  require_order "R5 banner" "$_banner" 'git init' '/sdd-plan' lt
  # Round-5 (4041813522): a local-only `git init` + commit cannot open a PR. The git
  # step must name the remote (gh repo create / git remote add + push) and the
  # one-feature-branch discipline the PR is opened from. The folded two-token anchors
  # prove both halves sit in the git step's own sentence, so deleting either reds here.
  assert_contains "R5 banner" "$_banner" 'remote'
  assert_contains "R5 banner" "$_banner" 'feature branch'
  printf '%s\n' "$_banner_flat" | grep -qiE 'commit[^.]{0,120}remote' \
    || fail "R5 banner: the git step does not tie the initial commit to the required remote in one sentence — a local-only init cannot open a PR, and the banner overclaims that it can"
  printf '%s\n' "$_banner_flat" | grep -qiE 'remote[^.]{0,200}feature branch' \
    || fail "R5 banner: the git step names a remote but does not state the one-feature-branch-per-feature discipline in the same sentence — the PR source branch can be dropped while the remote stays"
  # Round-6 (4041879995): the banner must commit the planning baseline and branch before
  # /sdd-next, or the fresh install hands the first feature PR the planning artifacts.
  # The baseline line is host-neutral, so it appears for every selected host; the folded
  # pair keeps commit/branch in the baseline step's own sentence, not step 2's git step.
  assert_contains "R5 banner" "$_banner" 'planning baseline'
  assert_contains "R5 banner" "$_banner" 'first feature branch'
  printf '%s\n' "$_banner_flat" | grep -qiE 'planning baseline[^.]{0,160}first feature branch' \
    || fail "R5 banner: the planning baseline step does not name the first feature branch in the same sentence — the planning artifacts can still ride into the first feature PR"
  require_order "R5 banner" "$_banner" '/sdd-drill' 'planning baseline' lt
  require_order "R5 banner" "$_banner" 'planning baseline' '/sdd-next' lt
  require_order "R5 banner" "$_banner" 'first feature branch' '/sdd-next' lt
  # Round 7: the human `git init` + initial-commit step precedes the constitution edit,
  # matching docs/INSTALL.md's ordered section and its "second item, after `git init`"
  # cross-reference — the edit stays uncommitted until the planning baseline.
  assert_contains "R5 banner" "$_banner" 'specs/product.md'
  require_order "R5 banner" "$_banner" 'git init' 'specs/product.md' lt
  # Non-Codex keeps the slash form: a Claude-only install must not advertise the
  # Codex `$sdd-*` spelling (the instruction varies by host).
  if printf '%s\n' "$_banner" | grep -qF '$sdd-plan'; then
    fail "R5 banner: a Claude-only install advertises the Codex form '\$sdd-plan' — the front-door step must vary by host"
  fi

  # A Codex-only install must be told the Codex skill form, in the same order.
  _cx_tgt="$T/codex-advice-target"
  _cx_home="$T/codex-advice-home"
  _cx_codex_home="$T/codex-advice-codex-home"
  mkdir -p "$_cx_tgt" "$_cx_home" "$_cx_codex_home"
  _cx_rc=0
  env -i PATH="$PATH" HOME="$_cx_home" CODEX_HOME="$_cx_codex_home" \
    sh "$SRC/harness-install.sh" --agents=codex --builder-backend=in-session \
      --pr-loop=false "$_cx_tgt" \
    >"$T/codex-advice.out" 2>"$T/codex-advice.err" || _cx_rc=$?
  [ "$_cx_rc" -eq 0 ] \
    || fail "R5: a Codex-only install exited $_cx_rc — cannot assert the Codex banner form"
  _banner_cx="$(banner_block "$T/codex-advice.out")"
  [ -n "$_banner_cx" ] \
    || fail "R5: fresh Codex-only install stdout has no 'Next steps:' banner block"
  [ "$(line_count "$_banner_cx")" -ge 2 ] \
    || fail "R5: the Codex 'Next steps:' block is fewer than 2 lines — stale extraction"
  for _a in '$sdd-plan' '$sdd-drill' '$sdd-next'; do
    assert_contains "R5 codex banner" "$_banner_cx" "$_a"
  done
  require_order "R5 codex banner" "$_banner_cx" '$sdd-plan' '$sdd-drill' lt
  require_order "R5 codex banner" "$_banner_cx" '$sdd-drill' '$sdd-next' lt
  require_order "R5 codex banner" "$_banner_cx" '$sdd-plan' '$sdd-next' lt
  # Round-4 (4041736459): the host-neutral git step is present for the Codex banner
  # too, and still precedes that host's planning command.
  assert_contains "R5 codex banner" "$_banner_cx" 'git init'
  assert_contains "R5 codex banner" "$_banner_cx" 'commit'
  _banner_cx_flat="$(printf '%s\n' "$_banner_cx" | tr '\n' ' ')"
  printf '%s\n' "$_banner_cx_flat" | grep -qiE 'git init[^.]{0,60}commit' \
    || fail "R5 codex banner: the git step does not name both \`git init\` and the initial commit in one sentence — a greenfield reader stops at an uncommitted tree"
  require_order "R5 codex banner" "$_banner_cx" 'git init' '$sdd-plan' lt
  # Round-5 (4041813522): the host-neutral git step must not overclaim either — the
  # Codex banner names the remote and the per-feature branch discipline in the step.
  assert_contains "R5 codex banner" "$_banner_cx" 'remote'
  assert_contains "R5 codex banner" "$_banner_cx" 'feature branch'
  printf '%s\n' "$_banner_cx_flat" | grep -qiE 'commit[^.]{0,120}remote' \
    || fail "R5 codex banner: the git step does not tie the initial commit to the required remote in one sentence — a local-only init cannot open a PR, and the banner overclaims that it can"
  printf '%s\n' "$_banner_cx_flat" | grep -qiE 'remote[^.]{0,200}feature branch' \
    || fail "R5 codex banner: the git step names a remote but does not state the one-feature-branch-per-feature discipline in the same sentence — the PR source branch can be dropped while the remote stays"
  # Round-6 (4041879995): the host-neutral baseline step must be present for Codex too.
  assert_contains "R5 codex banner" "$_banner_cx" 'planning baseline'
  assert_contains "R5 codex banner" "$_banner_cx" 'first feature branch'
  printf '%s\n' "$_banner_cx_flat" | grep -qiE 'planning baseline[^.]{0,160}first feature branch' \
    || fail "R5 codex banner: the planning baseline step does not name the first feature branch in the same sentence — the planning artifacts can still ride into the first feature PR"
  require_order "R5 codex banner" "$_banner_cx" '$sdd-drill' 'planning baseline' lt
  require_order "R5 codex banner" "$_banner_cx" 'planning baseline' '$sdd-next' lt
  require_order "R5 codex banner" "$_banner_cx" 'first feature branch' '$sdd-next' lt
  # Round 7: the host-neutral git step precedes the constitution edit for Codex too.
  assert_contains "R5 codex banner" "$_banner_cx" 'specs/product.md'
  require_order "R5 codex banner" "$_banner_cx" 'git init' 'specs/product.md' lt
  pass "fresh-install banner presents /sdd-plan → /sdd-drill → /sdd-next per host (Codex: \$sdd-*) on stdout (R5) [banner_points_at_sdd_plan]"
}

# ── R5 (multi-host regression) ────────────────────────────────────────────────

# Round-8 (4042015434): a multi-host selection must emit ONE numbered workflow, not
# one complete numbered sequence per host. The pre-change loop printed steps 3-6 (and
# the host-neutral baseline commit) once per selected integration, so `--agents=all`
# read as "run the whole workflow three times" and a sequential reader hit /sdd-plan's
# re-run guard on the second pass. The host-specific invocation forms are alternatives
# WITHIN each single step now. This is the regression surface the round-8 fix adds.
test_multi_host_banner_emits_one_workflow() {
  _mh_tgt="$T/multi-advice-target"
  _mh_home="$T/multi-advice-home"
  _mh_codex_home="$T/multi-advice-codex-home"
  mkdir -p "$_mh_tgt" "$_mh_home" "$_mh_codex_home"
  _mh_rc=0
  env -i PATH="$PATH" HOME="$_mh_home" CODEX_HOME="$_mh_codex_home" \
    sh "$SRC/harness-install.sh" --agents=all --builder-backend=in-session \
      --pr-loop=false "$_mh_tgt" \
    >"$T/multi-advice.out" 2>"$T/multi-advice.err" || _mh_rc=$?
  [ "$_mh_rc" -eq 0 ] \
    || fail "R5 multi-host: an --agents=all install exited $_mh_rc — cannot assert the single-workflow banner"
  _banner_all="$(banner_block "$T/multi-advice.out")"
  [ -n "$_banner_all" ] \
    || fail "R5 multi-host: fresh multi-host install stdout has no 'Next steps:' banner block"
  [ "$(line_count "$_banner_all")" -ge 2 ] \
    || fail "R5 multi-host: the 'Next steps:' block is fewer than 2 lines — stale extraction"
  # Exactly ONE line per numbered step 3-6: a per-host workflow repeats them.
  # `|| true` on every `grep -c` assignment: a legitimate zero-match still exits 1
  # from the substitution, and under `set -e` a bare assignment aborts the whole
  # suite with no FAIL: line (progress/lessons.md).
  for _mh_n in 3 4 5 6; do
    _mh_c="$(printf '%s\n' "$_banner_all" | grep -cE "^  ${_mh_n}\." || true)"
    [ "$_mh_c" -eq 1 ] \
      || fail "R5 multi-host: step ${_mh_n} appears ${_mh_c} times — a multi-host selection must emit ONE numbered workflow, not one per host (4042015434)"
  done
  # Exactly ONE baseline-commit step and ONE planning step.
  _mh_base="$(printf '%s\n' "$_banner_all" | grep -cF 'planning baseline' || true)"
  [ "$_mh_base" -eq 1 ] \
    || fail "R5 multi-host: the baseline-commit step appears ${_mh_base} times — --agents=all must not print the baseline per host (4042015434)"
  _mh_plan="$(printf '%s\n' "$_banner_all" | grep -c 'sdd-plan' || true)"
  [ "$_mh_plan" -eq 1 ] \
    || fail "R5 multi-host: the planning step appears ${_mh_plan} times — a multi-host selection must not repeat the whole workflow (4042015434)"
  # The single planning step must name BOTH invocation forms as alternatives in its
  # own line, or the "one workflow" would have collapsed to one host's command.
  _mh_plan_line="$(printf '%s\n' "$_banner_all" | grep 'sdd-plan' || true)"
  [ -n "$_mh_plan_line" ] || fail "R5 multi-host: no planning line found — cannot assert the host alternatives"
  printf '%s\n' "$_mh_plan_line" | grep -qE '/sdd-plan[^.]{0,80}\$sdd-plan' \
    || fail "R5 multi-host: the single planning step does not name both '/sdd-plan' and '\$sdd-plan' as alternatives in one step — the host commands must not collapse to one host's form"
  assert_contains "R5 multi-host banner" "$_banner_all" '/sdd-drill <epic-id>'
  require_order "R5 multi-host banner" "$_banner_all" '/sdd-plan' '/sdd-next' lt
  require_order "R5 multi-host banner" "$_banner_all" '/sdd-drill' 'planning baseline' lt
  require_order "R5 multi-host banner" "$_banner_all" 'planning baseline' '/sdd-next' lt
  pass "multi-host banner emits ONE numbered workflow with per-host alternatives (R5) [multi_host_banner_emits_one_workflow]"
}

# ── R6 (integration) ──────────────────────────────────────────────────────────

test_install_creates_no_git() {
  [ ! -e "$TGT/.git" ] \
    || fail "R6: the installer created a .git in a single-target install — it must stay out of version control"
  [ -n "$(ls -A "$TGT")" ] \
    || fail "R6: target is empty — the 'no .git' result is vacuous (the install never ran)"
  [ -f "$TGT/.harness/.harness-version" ] \
    || fail "R6: no install stamp — 'no .git' is vacuously true and proves nothing"
  pass "single-target install created no .git (R6) [install_creates_no_git]"
}

# ── R8 (integration) ──────────────────────────────────────────────────────────

test_installed_layout_usable() {
  [ -f "$TGT/AGENTS.md" ] || fail "R8: installed target has no AGENTS.md entrypoint"
  [ -d "$TGT/.harness" ] || fail "R8: installed target has no .harness/ body"
  [ -s "$TGT/.harness/state/tasks.json" ] \
    || fail "R8: seeded board .harness/state/tasks.json is missing or empty"
  python3 -c 'import json,sys; raw=open(sys.argv[1]).read(); json.loads(raw); sys.exit(0 if "E00-F01" in raw else 1)' \
      "$TGT/.harness/state/tasks.json" \
    || fail "R8: seeded board is not valid JSON or lacks the E00-F01 bootstrap entry"
  [ -f "$TGT/.claude/commands/sdd-plan.md" ] \
    || fail "R8: the selected front-end's /sdd-plan command artifact (.claude/commands/sdd-plan.md) is missing"
  pass "installed layout is usable (entrypoint, body, seeded board, /sdd-plan command) (R8) [installed_layout_usable]"
}

# ── Round-2 reconciliation: installed product.md front door (4041566967) ───────

# The seeded constitution ships into every target and is the first thing a
# greenfield reader edits. It must point at /sdd-plan to draft the project's
# epics, never at /sdd-next — otherwise a fresh install carries two competing
# front doors and the cheaper-to-read one wins.
test_installed_product_md_points_at_sdd_plan() {
  _prod="$TGT/.harness/specs/product.md"
  [ -s "$_prod" ] \
    || fail "R8b: installed .harness/specs/product.md is missing or empty — the seeded new-product guidance cannot be checked"
  _prod_flat="$(tr '\n' ' ' < "$_prod")"
  # Positive control on the SHAPE before the negative: the document must still
  # carry a <plan>→<epics> instruction, so the negative below cannot pass merely
  # because the guidance vanished (progress/lessons.md: a dead middle predicate
  # is decoration, not a test).
  printf '%s\n' "$_prod_flat" | grep -qE 'sdd-plan[^.]{0,60}draft epics' \
    || fail "R8b: installed product.md no longer points a new product at /sdd-plan to draft its epics — the front-door replacement is absent (stale extraction or dropped guidance)"
  if printf '%s\n' "$_prod_flat" | grep -qiE 'sdd-next[^.]{0,60}draft epics'; then
    fail "R8b: installed product.md still tells a new-product reader that /sdd-next drafts the project's epics — the two front doors conflict on a fresh install"
  fi
  # Round 7 (4041951737): the stub must name the drill step too, or a reader who
  # follows it stops at /sdd-plan and hands /sdd-next a board of draft epics.
  assert_contains "R8b product.md" "$_prod_flat" '/sdd-drill <epic-id>'
  pass "installed product.md points at /sdd-plan → /sdd-drill (not /sdd-next) to draft a new product's epics (round-2 + round-7 reconciliation) [installed_product_md_points_at_sdd_plan]"
}

# The target-root entrypoint pointer is the first instruction an agent reads on a
# fresh install. It must send a new product to /sdd-plan rather than straight into
# the execution loop — otherwise the installed bootstrap text carries a third,
# competing front door (round-2 review 4041566967).
#
# Round 7 (4041951737): it must not send a new product straight from /sdd-plan to
# /sdd-next. /sdd-plan leaves the epics `draft`, so /sdd-next reports their features
# as `gated-epic`; the drill step has to sit between them. Presence kills the
# omission; the folded pairs keep plan → drill → next in one sentence.
test_installed_entrypoint_points_at_sdd_plan() {
  _ep="$TGT/AGENTS.md"
  [ -s "$_ep" ] \
    || fail "R8c: installed target-root AGENTS.md is missing or empty — the session-entry instruction cannot be checked"
  _ep_flat="$(tr '\n' ' ' < "$_ep")"
  # Positive folded anchor: the new-product branch and /sdd-plan must co-occur in
  # one sentence, so removing either half reds here.
  printf '%s\n' "$_ep_flat" | grep -qiE 'sdd-plan[^.]{0,80}new product' \
    || fail "R8c: installed entrypoint does not send a new product to /sdd-plan — a fresh install still starts an agent at /sdd-next"
  assert_contains "R8c entrypoint" "$_ep_flat" '/sdd-drill <epic-id>'
  printf '%s\n' "$_ep_flat" | grep -qiE 'sdd-plan[^.]{0,120}sdd-drill' \
    || fail "R8c: installed entrypoint sends a new product from /sdd-plan but never names /sdd-drill before /sdd-next — the seeded epics stay draft and /sdd-next reports them gated-epic"
  printf '%s\n' "$_ep_flat" | grep -qiE 'sdd-drill[^.]{0,120}sdd-next' \
    || fail "R8c: installed entrypoint names /sdd-drill but does not route on to /sdd-next in the same sentence — the new-product sequence is incomplete"
  # Round 8 (4042015445): the same block is written to AGENTS.md on EVERY install
  # (including Codex-only, where AGENTS.md is the native repository entrypoint), so it
  # must name the Codex `$sdd-*` forms too — otherwise a Codex-only install is told to
  # invoke slash commands it does not have. Both forms must sit in the one sentence.
  assert_contains "R8c entrypoint" "$_ep_flat" '$sdd-plan'
  assert_contains "R8c entrypoint" "$_ep_flat" '$sdd-drill <epic-id>'
  printf '%s\n' "$_ep_flat" | grep -qiE '/sdd-plan[^.]{0,80}\$sdd-plan' \
    || fail "R8c: installed entrypoint names only the slash form — a Codex-only install reads the same block and has no /sdd-plan; name the \$sdd-plan form in the same sentence"
  pass "installed entrypoint sends a new product /sdd-plan → /sdd-drill → /sdd-next, host-neutral (round-7 + round-8 reconciliation) [installed_entrypoint_points_at_sdd_plan]"
}

# ── R9 (integration) ──────────────────────────────────────────────────────────

test_init_passes_in_non_git_target() {
  [ ! -e "$TGT/.git" ] \
    || fail "R9: the target became a git tree before init.sh — the non-git case is not being exercised"
  _rc=0
  _out="$( cd "$TGT" && ./.harness/init.sh 2>&1 )" || _rc=$?
  if [ "$_rc" -ne 0 ]; then
    echo "--- installed init.sh output ---" >&2
    printf '%s\n' "$_out" >&2 || true
    fail "R9: installed .harness/init.sh exited $_rc in a non-git target — the drift guard must skip, never fail"
  fi
  printf '%s\n' "$_out" | grep -qF 'harness-sdd init' \
    || fail "R9: init.sh exited 0 without printing the harness init banner — a zero exit from a file that never ran is not a pass"
  [ ! -e "$TGT/.git" ] \
    || fail "R9: init.sh created a git repository — the drift guard must not initialize version control"
  pass "installed init.sh exits 0 in the still-non-git target (R9) [init_passes_in_non_git_target]"
}

# ── R10 (integration) ─────────────────────────────────────────────────────────

test_version_stamp_reads_source_version() {
  _src_ver="$(cat "$SRC/VERSION")"
  [ -n "$_src_ver" ] || fail "R10: $SRC/VERSION is empty"
  _inst_ver="$(cat "$TGT/.harness/.harness-version")" \
    || fail "R10: installed .harness/.harness-version is missing"
  [ "$_inst_ver" = "$_src_ver" ] \
    || fail "R10: installed version stamp ('$_inst_ver') != source VERSION ('$_src_ver')"
  pass "installed version stamp is derived from \$SRC/VERSION at run time (R10) [version_stamp_reads_source_version]"
}

# ── run ───────────────────────────────────────────────────────────────────────

test_greenfield_section_documents_sequence
test_greenfield_section_states_non_git_and_human_git_init
test_one_front_door_story
test_bootstrap_section_reconciled
test_empty_non_git_install_succeeds
test_banner_points_at_sdd_plan
test_multi_host_banner_emits_one_workflow
test_install_creates_no_git
test_installed_layout_usable
test_installed_product_md_points_at_sdd_plan
test_installed_entrypoint_points_at_sdd_plan
test_init_passes_in_non_git_target
test_version_stamp_reads_source_version
