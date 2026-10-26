#!/bin/sh
# test_tasks_pairs.sh — E36-F01: per-requirement red/green task pairs.
#
# Drives tools/tasks-pair-check.py against fixtures (behavioral), and pins the prose/template
# surfaces with fence-aware section slices (tests/lib/fence.awk, never the bare /^#+ / idiom).
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact VERSION
# literal; never git-diff a DO-NOT-TOUCH file against main; never write state/ or a live spec.
# Exit codes are asserted as `rc -eq N`, never a shell-dependent code.

set -eu
LC_ALL=C; export LC_ALL

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL="$ROOT/tools/tasks-pair-check.py"
FENCE_AWK="$(cat "$ROOT/tests/lib/fence.awk")"
T="$(mktemp -d 2>/dev/null || mktemp -d -t taskspairs)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v python3 >/dev/null 2>&1 || fail "python3 is a hard harness dependency and is absent"

# ── fixture writers ───────────────────────────────────────────────────────────────────────
# fx_spec <path> [--decoys] [ids...]: includes a blank and a whitespace-only line so a fence
# port that spins on empty lines hangs here, not in the Reviewer.
fx_spec() {
  _p="$1"; shift
  _dec=0; [ "${1:-}" = "--decoys" ] && { _dec=1; shift; }
  [ "$#" -gt 0 ] || set -- R1 R2 R3
  { printf '# Fixture spec\n\n   \n## Acceptance criteria\n\n'
    for _i in "$@"; do printf -- '- **%s** — the system shall do %s.\n' "$_i" "$_i"; done
    if [ "$_dec" -eq 1 ]; then
      printf '\n```\n- **R9** — decoy\n```\n\n~~~\n- **R8** — decoy\n~~~\n\n   ```\n- **R7** — decoy\n   ```\n'
    fi
  } > "$_p"
}
# fx_tasks_good <path> [--decoys]
fx_tasks_good() {
  _p="$1"
  { printf '# Fixture tasks\n\n'
    if [ "${2:-}" = "--decoys" ]; then
      printf '```\n- [ ] **T9b** (R1) — decoy code task before T1a\n- [ ] **T5** — Write tests per feature.tests.md\n```\n\n'
    fi
    printf -- '- [ ] **T1a** (R1) — write failing test; observe RED\n'
    printf -- '- [ ] **T1b** (R1) — minimal code; observe GREEN\n'
    printf -- '- [ ] **T2a** (R2, R3) — write failing test; observe RED\n'
    printf -- '- [ ] **T2b** (R2, R3) — minimal code; observe GREEN\n'
    printf -- '- [ ] **T3** (R1) — refactor\n'
    printf -- '- [ ] **T4** — Run ./init.sh + sh tools/run-tests.sh\n'
  } > "$_p"
}
run_lint() { set +e; python3 "$TOOL" "$@" >"$T/out" 2>"$T/err"; rc=$?; set -e; }

# ── R5: ok path, fenced decoys ignored ────────────────────────────────────────────────────
fx_spec "$T/s.md"; fx_tasks_good "$T/t.md"
run_lint "$T/t.md" --spec "$T/s.md"
[ "$rc" -eq 0 ] || fail "R5_ok_exit0: expected rc 0, got $rc ($(cat "$T/out" "$T/err" 2>/dev/null))"
tail -n 1 "$T/out" | grep -qE '^tasks-pair-check: ok 3 R-ids, 6 tasks$' \
  || fail "R5_ok_exit0: last stdout line is not 'ok 3 R-ids, 6 tasks': $(tail -n1 "$T/out")"
pass "R5_ok_exit0"

fx_spec "$T/sd.md" --decoys; fx_tasks_good "$T/td.md" --decoys
run_lint "$T/td.md" --spec "$T/sd.md"
[ "$rc" -eq 0 ] || fail "R5_fenced_decoys_ignored: decoys not ignored, rc $rc ($(cat "$T/out"))"
grep -qE '^tasks-pair-check: ok 3 R-ids, 6 tasks$' "$T/out" \
  || fail "R5_fenced_decoys_ignored: counts changed by decoys: $(tail -n1 "$T/out")"
# control: strip the fence delimiter lines -> decoys become live -> must fail
grep -vE '^ *(```|~~~)' "$T/sd.md" > "$T/sd-live.md"
grep -vE '^ *(```|~~~)' "$T/td.md" > "$T/td-live.md"
run_lint "$T/td-live.md" --spec "$T/sd-live.md"
[ "$rc" -eq 1 ] || fail "R5_fenced_decoys_ignored control: unfenced decoys should give rc 1, got $rc"
pass "R5_fenced_decoys_ignored"

# R5 fence parity: iter_unfenced() is a deliberate second copy of tests/lib/fence.awk. Feed
# one edge corpus to both and require byte-identical unfenced output. Each segment exists
# for one clause, and removing that clause from either copy changes the output:
#   closer length · closer char · closer info string · backtick-in-info opener (backtick
#   only) · run >= 3 · indent 0-3 · trailing blanks on a closer.
{ printf '%s\n' 'P0 outside' \
    '````md' 'P1 in: a 3-run cannot close a 4-run' '```' 'P2 in' '````' 'P3 out' \
    '```' 'P4 in: a tilde run cannot close a backtick fence' '~~~' 'P5 in' '```' 'P6 out' \
    '```' 'P7 in: a closer carries no info string' '```sh' 'P8 in' '```' 'P9 out' \
    '```a`b' 'P10 out: backtick in a backtick info string is not an opener' \
    '~~~a`b' 'P11 in: a tilde opener may carry a backtick' '~~~' 'P12 out' \
    '``' 'P13 out: a 2-run is not a fence' '~~' 'P14 out' \
    '    ```' 'P15 out: 4-space indent is not a fence' \
    '   ~~~' 'P16 in: 3-space indent is' '~~~  ' 'P17 out: closer with trailing blanks'
} > "$T/fence-corpus.md"
awk "$FENCE_AWK"'fence_delim($0) { next } !fence' "$T/fence-corpus.md" > "$T/fence-awk.out"
python3 - "$TOOL" "$T/fence-corpus.md" > "$T/fence-py.out" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("tasks_pair_check", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
with open(sys.argv[2], encoding="utf-8") as fh:
    for line in mod.iter_unfenced(fh.readlines()):
        print(line)
PY
# precondition: the corpus exercises both sides (fence.awk itself is pinned by test_change_size R9d)
printf '%s\n' 'P0 outside' 'P3 out' 'P6 out' 'P9 out' '```a`b' \
  'P10 out: backtick in a backtick info string is not an opener' 'P12 out' '``' \
  'P13 out: a 2-run is not a fence' '~~' 'P14 out' '    ```' 'P15 out: 4-space indent is not a fence' \
  'P17 out: closer with trailing blanks' > "$T/fence-want.out"
cmp -s "$T/fence-want.out" "$T/fence-awk.out" \
  || fail "R5_fence_parity: fence.awk reads the corpus differently than the suite expects: $(diff "$T/fence-want.out" "$T/fence-awk.out" | tr '\n' '|')"
cmp -s "$T/fence-awk.out" "$T/fence-py.out" \
  || fail "R5_fence_parity: iter_unfenced() diverges from tests/lib/fence.awk: $(diff "$T/fence-awk.out" "$T/fence-py.out" | tr '\n' '|')"
pass "R5_fence_parity"

# ── R8: usage / input errors => exit 2 ────────────────────────────────────────────────────
chk_exit2() { # chk_exit2 <row>
  [ "$rc" -eq 2 ] || fail "$1: expected rc 2, got $rc"
  grep -qF 'tasks-pair-check: error:' "$T/err" || fail "$1: stderr lacks 'tasks-pair-check: error:'"
  grep -qi 'usage' "$T/err" || fail "$1: stderr lacks usage"
  grep -qF 'tasks-pair-check: ok' "$T/out" && fail "$1: printed an ok line"
  pass "$1"
}
run_lint "$T/t.md"; chk_exit2 R8_missing_spec_flag_exit2
run_lint "$T/nonexistent.md" --spec "$T/s.md"
grep -qF 'tasks-pair-check: error:' "$T/err" || fail "R8_unreadable_file_exit2: tasks path"
chk_exit2 R8_unreadable_file_exit2
run_lint "$T/t.md" --spec "$T/nonexistent-spec.md"; chk_exit2 R8_unreadable_file_exit2
printf '# spec\n\n```\n- **R1** — only in a fence\n```\n' > "$T/s-zero.md"
run_lint "$T/t.md" --spec "$T/s-zero.md"; chk_exit2 R8_zero_rids_exit2

# ── R6: first task not a test task / no task ──────────────────────────────────────────────
chk_exit1() { # chk_exit1 <row> <expected-line>
  [ "$rc" -eq 1 ] || fail "$1: expected rc 1, got $rc ($(cat "$T/out" "$T/err"))"
  grep -qxF "$2" "$T/out" || fail "$1: missing line '$2' in: $(cat "$T/out")"
  [ "$(tail -n 1 "$T/out")" = "tasks-pair-check: FAIL 1 violation(s)" ] || fail "$1: last line is not FAIL 1: $(tail -n1 "$T/out")"
  grep -qF 'tasks-pair-check: ok' "$T/out" && fail "$1: printed an ok line"
  pass "$1"
}
{ printf -- '- [ ] **T1a** (R1) — t\n- [ ] **T2b** (R2) — code first\n- [ ] **T2a** (R2) — t\n- [ ] **T3a** (R3) — t\n'; } > "$T/t6a.md"
run_lint "$T/t6a.md" --spec "$T/s.md"
chk_exit1 R6_first_task_code_exit1 'tasks-pair-check: first-task-not-test R2 T2b'
printf -- '- [ ] **T1a** (R1) — t\n- [ ] **T2** (R2) — add code\n- [ ] **T3a** (R3) — t\n' > "$T/t6b.md"
run_lint "$T/t6b.md" --spec "$T/s.md"
chk_exit1 R6_first_task_unsuffixed_exit1 'tasks-pair-check: first-task-not-test R2 T2'
printf -- '- [ ] **T1a** (R1) — t\n- [ ] **T2c** (R2) — odd suffix\n- [ ] **T3a** (R3) — t\n' > "$T/t6c.md"
run_lint "$T/t6c.md" --spec "$T/s.md"
chk_exit1 R6_first_task_unsuffixed_exit1 'tasks-pair-check: first-task-not-test R2 T2c'
# A suffix that is not exactly one `a`/`b` (any case, any length) is "other", never dropped:
# a dropped line would let the code-first T2B / T2ab / t2b through to the later T2a.
for _sx in 'T2B' 'T2ab' 't2b'; do
  printf -- '- [ ] **T1a** (R1) — t\n- [ ] **%s** (R2) — code first\n- [ ] **T2a** (R2) — t\n- [ ] **T3a** (R3) — t\n' "$_sx" > "$T/t6s.md"
  run_lint "$T/t6s.md" --spec "$T/s.md"
  chk_exit1 "R6_suffix_not_dropped_exit1[$_sx]" "tasks-pair-check: first-task-not-test R2 $_sx"
done
# ...and the suffix is case-normalised: an upper-case `A` is still the test task.
printf -- '- [ ] **T1a** (R1) — t\n- [ ] **T2A** (R2) — t\n- [ ] **T2B** (R2) — c\n- [ ] **T3a** (R3) — t\n' > "$T/t6u.md"
run_lint "$T/t6u.md" --spec "$T/s.md"
[ "$rc" -eq 0 ] || fail "R6_suffix_case_normalised: T2A first should pass, rc $rc ($(cat "$T/out"))"
grep -qxF 'tasks-pair-check: ok 3 R-ids, 4 tasks' "$T/out" || fail "R6_suffix_case_normalised: $(cat "$T/out")"
pass "R6_suffix_case_normalised"
printf -- '- [ ] **T1a** (R1) — t\n- [ ] **T2a** (R2) — t\n' > "$T/t6d.md"
run_lint "$T/t6d.md" --spec "$T/s.md"
chk_exit1 R6_no_task_exit1 'tasks-pair-check: no-task R3'

# ── R7: un-cited "write ... tests" task ───────────────────────────────────────────────────
{ cat "$T/t.md"; printf -- '- [ ] **T5** — Write tests per feature.tests.md\n'; } > "$T/t7a.md"
run_lint "$T/t7a.md" --spec "$T/s.md"
chk_exit1 R7_trailing_write_tests_exit1 'tasks-pair-check: write-tests-task T5'
{ printf -- '- [ ] **T0** — Write tests per feature.tests.md\n'; cat "$T/t.md"; } > "$T/t7b.md"
run_lint "$T/t7b.md" --spec "$T/s.md"
chk_exit1 R7_leading_write_tests_exit1 'tasks-pair-check: write-tests-task T0'
{ printf -- '- [ ] **T1a** (R1) — write the failing tests; observe RED\n'; sed 1d "$T/t.md" | grep -v 'T1a'; } > "$T/t7c.md"
run_lint "$T/t7c.md" --spec "$T/s.md"
[ "$rc" -eq 0 ] || fail "R7_cited_write_test_passes: rc $rc ($(cat "$T/out"))"
pass "R7_cited_write_test_passes"
# "write" and "tests" are WHOLE words: one row per word boundary of \bwrite\b.*\btests\b,
# plus the combined case. Each un-cited task must pass (rc 0).
for _txt in 'rewrite the contests table' 'rewrite the tests fixture' 'write the contests table' \
            'writers for the tests' 'write testsuite docs'; do
  { cat "$T/t.md"; printf -- '- [ ] **T5** — %s\n' "$_txt"; } > "$T/t7w.md"
  run_lint "$T/t7w.md" --spec "$T/s.md"
  [ "$rc" -eq 0 ] || fail "R7_whole_words_only[$_txt]: an un-cited '$_txt' task was read as write-tests, rc $rc ($(cat "$T/out"))"
  grep -qxF 'tasks-pair-check: ok 3 R-ids, 7 tasks' "$T/out" || fail "R7_whole_words_only[$_txt]: $(cat "$T/out")"
done
pass "R7_whole_words_only"

# ── R9 grandfather rule: --grandfathered (exit 0 flag / 1 reject class / 2 error) ─────────
# The tool's date is its MERGE into the default branch: the committer time of the first
# first-parent commit on that branch touching the tool. The .tasks.md date is the AUTHOR time
# of the commit that added it (a rebase rewrites committer time, never author time). Fixture
# repos are hermetic: bounded discovery, no host config, fixed dates.
GIT_CEILING_DIRECTORIES="$T"; export GIT_CEILING_DIRECTORIES
GIT_CONFIG_GLOBAL=/dev/null; GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
gq() { git -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
gci() { # gci <author-epoch> <committer-epoch> <msg>  (stage first)
  GIT_AUTHOR_DATE="@$1 +0000" GIT_COMMITTER_DATE="@$2 +0000" gq commit -q -m "$3" || fail "fixture commit '$3' failed"
}
gf_run() { # gf_run <repo> <tasks-relpath> [args...]
  _r="$1"; _f="$2"; shift 2
  set +e; (cd "$_r" && python3 "$TOOL" --grandfathered "$_f" "$@") >"$T/out" 2>"$T/err"; rc=$?; set -e
}
gf_expect() { # gf_expect <row> <rc> <stdout-regex>
  [ "$rc" -eq "$2" ] || fail "$1: expected rc $2, got $rc ($(cat "$T/out" "$T/err"))"
  grep -qE "$3" "$T/out" || fail "$1: stdout does not match '$3': $(cat "$T/out" "$T/err")"
  pass "$1"
}
# G1 (source layout): base@1000; branch tool adds tools/tasks-pair-check.py @1100; branch sib
# adds sib.tasks.md @1200 (after the tool's BRANCH commit, before its merge); main merges tool
# --no-ff (committed @1300, authored @1150 — the merge's COMMITTER time is its date) and
# edits the tool again @1350; later branches add tasks files @1300/@1400; branch readd adds a
# tasks file @1200, deletes it @1210 and re-adds it after the merge @1400 (earliest add wins).
G="$T/g1"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
gq checkout -q -b tool; mkdir -p tools; echo v1 > tools/tasks-pair-check.py; gq add tools; gci 1100 1100 tool
gq checkout -q main; gq checkout -q -b sib; mkdir -p s; echo x > s/sib.tasks.md; gq add s; gci 1200 1200 sib
gq checkout -q -b sibrebased main; mkdir -p s; echo x > s/reb.tasks.md; gq add s; gci 1200 1500 rebased
gq checkout -q -b readd main; mkdir -p s; echo x > s/re.tasks.md; gq add s; gci 1200 1200 re-add-1
gq rm -q s/re.tasks.md; gci 1210 1210 re-del
gq checkout -q main
GIT_AUTHOR_DATE="@1150 +0000" GIT_COMMITTER_DATE="@1300 +0000" gq merge -q --no-ff -m merge-tool tool || fail "fixture merge failed"
echo v2 > tools/tasks-pair-check.py; gq add tools; gci 1350 1350 tool-v2
gq checkout -q -b late; mkdir -p s; echo x > s/late.tasks.md; gq add s; gci 1400 1400 late
gq checkout -q -b same main; mkdir -p s; echo x > s/same.tasks.md; gq add s; gci 1300 1400 same
gq checkout -q readd; mkdir -p s; echo x > s/re.tasks.md; gq add s; gci 1400 1400 re-add-2
gq checkout -q -b dirty main; mkdir -p s; echo x > s/new.tasks.md
cd "$ROOT"
gq -C "$G" checkout -q sib;  gf_run "$G" s/sib.tasks.md;  gf_expect R9_grandfather_sibling_before_merge_flags 0 '^tasks-pair-check: grandfather flag: '
gq -C "$G" checkout -q late; gf_run "$G" s/late.tasks.md; gf_expect R9_grandfather_after_merge_rejects 1 '^tasks-pair-check: grandfather reject: '
grep -qF ' 1300' "$T/out" || fail "R9_grandfather_after_merge_rejects: the tool date is not the merge time 1300: $(cat "$T/out")"
gq -C "$G" checkout -q same; gf_run "$G" s/same.tasks.md; gf_expect R9_grandfather_same_second_rejects 1 '^tasks-pair-check: grandfather reject: '
gq -C "$G" checkout -q sibrebased; gf_run "$G" s/reb.tasks.md; gf_expect R9_grandfather_rebased_sibling_flags 0 '^tasks-pair-check: grandfather flag: '
gq -C "$G" checkout -q dirty; gf_run "$G" s/new.tasks.md; gf_expect R9_grandfather_uncommitted_rejects 1 '^tasks-pair-check: grandfather reject: .*no commit'
gq -C "$G" checkout -q readd; gf_run "$G" s/re.tasks.md; gf_expect R9_grandfather_earliest_add_wins 0 '^tasks-pair-check: grandfather flag: .*authored 1200'
ln -s "$G" "$T/g1-link"
# Absolute and symlinked paths must reach the SAME verdict as the relative one. Both rows are
# FLAG cases on purpose: a path the tool cannot map into the repo finds no commit, and that
# reads as "reject", so a reject-case row here could not see a broken path ($T itself sits
# under a symlink on macOS: /var -> /private/var).
gq -C "$G" checkout -q sib
gf_run "$ROOT" "$G/s/sib.tasks.md"; gf_expect R9_grandfather_absolute_path 0 '^tasks-pair-check: grandfather flag: s/sib\.tasks\.md authored 1200'
gf_run "$ROOT" "$T/g1-link/s/sib.tasks.md"; gf_expect R9_grandfather_symlinked_path 0 '^tasks-pair-check: grandfather flag: s/sib\.tasks\.md authored 1200'
gq -C "$G" checkout -q late
# origin/HEAD is asked first: point it at a remote-tracking trunk that never merged the tool.
gq -C "$G" update-ref refs/remotes/origin/trunk "$(git -C "$G" rev-parse main~2)"
gq -C "$G" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
gf_run "$G" s/late.tasks.md; gf_expect R9_grandfather_origin_head_first 0 '^tasks-pair-check: grandfather flag: .*origin/trunk'
gf_run "$G" s/late.tasks.md --base main; gf_expect R9_grandfather_base_override 1 '^tasks-pair-check: grandfather reject: .*main'
gf_run "$G" s/late.tasks.md --base=main; gf_expect R9_grandfather_base_override_eq_form 1 '^tasks-pair-check: grandfather reject: .*main'
for _bad in '--base' '--spec'; do  # a trailing --base, or a lint-only flag, is a usage error
  gf_run "$G" s/late.tasks.md $_bad; [ "$rc" -eq 2 ] || fail "R9_grandfather_usage_exit2[$_bad]: rc $rc ($(cat "$T/out" "$T/err"))"
  grep -qi 'usage' "$T/err" || fail "R9_grandfather_usage_exit2[$_bad]: no usage on stderr"; pass "R9_grandfather_usage_exit2[$_bad]"
done
gf_run "$G" s/late.tasks.md --base no-such-ref; [ "$rc" -eq 2 ] || fail "R9_grandfather_bad_base_exit2: rc $rc"
grep -qF 'tasks-pair-check: error:' "$T/err" || fail "R9_grandfather_bad_base_exit2: no error line"; pass R9_grandfather_bad_base_exit2
# G2: the tool is not on the default branch yet -> every .tasks.md is grandfathered, even one
# authored after the tool's branch commit.
G="$T/g2"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
gq checkout -q -b feat; mkdir -p tools s; echo v1 > tools/tasks-pair-check.py; gq add tools; gci 1100 1100 tool
echo x > s/own.tasks.md; gq add s; gci 1400 1400 own
cd "$ROOT"
gf_run "$G" s/own.tasks.md; gf_expect R9_grandfather_tool_not_on_default_flags 0 '^tasks-pair-check: grandfather flag: .*not on'
# G3 (installed-target layout): the tool lives at .harness/tools/tasks-pair-check.py.
G="$T/g3"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
mkdir -p .harness/tools s; echo v1 > .harness/tools/tasks-pair-check.py; gq add .harness; gci 1100 1100 upgrade
echo x > s/old.tasks.md; gq add s; gci 1050 1050 old-authored-before-upgrade
echo x > s/new.tasks.md; gq add s; gci 1200 1200 new
cd "$ROOT"
gf_run "$G" s/new.tasks.md; gf_expect R9_grandfather_consumer_layout_rejects 1 '^tasks-pair-check: grandfather reject: '
gf_run "$G" s/old.tasks.md; gf_expect R9_grandfather_consumer_layout_old_flags 0 '^tasks-pair-check: grandfather flag: '
# Every fallback default-branch name resolves (no origin/HEAD): the tool on it, a later file.
for _b in origin/main main origin/master master origin/trunk trunk; do
  G="$T/g4-$(printf '%s' "$_b" | tr / -)"; mkdir -p "$G"; cd "$G"; gq init -q -b work .
  mkdir -p tools s; echo v1 > tools/tasks-pair-check.py; gq add tools; gci 1100 1100 tool
  echo x > s/n.tasks.md; gq add s; gci 1200 1200 n
  case "$_b" in origin/*) gq update-ref "refs/remotes/$_b" HEAD ;; *) gq branch "$_b" ;; esac
  cd "$ROOT"
  gf_run "$G" s/n.tasks.md; gf_expect "R9_grandfather_fallback_branch[$_b]" 1 "^tasks-pair-check: grandfather reject: .*$_b"
done
G="$T/g5"; mkdir -p "$G"; cd "$G"; gq init -q -b work .; echo x > a.tasks.md; gq add a.tasks.md; gci 1000 1000 a; cd "$ROOT"
gf_run "$G" a.tasks.md; [ "$rc" -eq 2 ] || fail "R9_grandfather_no_default_branch_exit2: rc $rc ($(cat "$T/out"))"; pass R9_grandfather_no_default_branch_exit2
mkdir -p "$T/nogit"; echo x > "$T/nogit/a.tasks.md"
gf_run "$T/nogit" a.tasks.md; [ "$rc" -eq 2 ] || fail "R9_grandfather_not_a_repo_exit2: rc $rc ($(cat "$T/out"))"
grep -qF 'tasks-pair-check: error:' "$T/err" || fail "R9_grandfather_not_a_repo_exit2: no error line"
grep -qF 'is not inside a git work tree' "$T/err" || fail "R9_grandfather_not_a_repo_exit2: wrong reason: $(cat "$T/err")"; pass R9_grandfather_not_a_repo_exit2

# ── prose helpers: fence-aware slicers (fence.awk), never the bare /^#+ / idiom ───────────
unfenced() { awk "$FENCE_AWK"'fence_delim($0) { next } !fence' "$1"; }   # unfenced <file>
slice() { # slice <file> <heading-prefix>: one section up to the next "## " heading, delimiters kept
  awk -v h="$2" "$FENCE_AWK"'
    fence_delim($0) { if (keep) print; next }
    !fence && /^## / { keep = (index($0, h) == 1); next }
    keep' "$1"
}
folded() { tr '\n' ' ' | tr -s ' '; }
# anch <text-file> <regex> <row> <what>
anch() { folded < "$1" | grep -qiE "$2" || fail "$3: missing anchor: $4"; }

# ── R1: the shipped template is pair form ─────────────────────────────────────────────────
run_lint "$ROOT/specs/_templates/feature.tasks.md" --spec "$ROOT/specs/_templates/feature.spec.md"
[ "$rc" -eq 0 ] || fail "R1_template_passes_lint: rc $rc ($(cat "$T/out" "$T/err"))"
grep -qE '^tasks-pair-check: ok' "$T/out" || fail "R1_template_passes_lint: no ok line"
pass "R1_template_passes_lint"
unfenced "$ROOT/specs/_templates/feature.tasks.md" > "$T/tpl.txt"
for n in 1 2 3 4 5; do
  _a="$(grep -n "\*\*T${n}a\*\* (R${n})" "$T/tpl.txt" | head -n1)"
  _b="$(grep -n "\*\*T${n}b\*\* (R${n})" "$T/tpl.txt" | head -n1)"
  [ -n "$_a" ] && [ -n "$_b" ] || fail "R1_template_shape: T${n}a/T${n}b missing"
  [ "${_a%%:*}" -lt "${_b%%:*}" ] || fail "R1_template_shape: T${n}a does not precede T${n}b"
  printf '%s\n' "$_a" | grep -q 'RED' || fail "R1_template_shape: T${n}a does not name RED"
  printf '%s\n' "$_b" | grep -q 'GREEN' || fail "R1_template_shape: T${n}b does not name GREEN"
done
grep -qE '\*\*T6\*\* \(R1, R2\) — refactor' "$T/tpl.txt" || fail "R1_template_shape: no explicit refactor task citing R-ids"
grep -q 'Write tests per' "$ROOT/specs/_templates/feature.tasks.md" && fail "R1_template_shape: old 'Write tests per' task survives"
pass "R1_template_shape"

# ── R2: architect item 3 ──────────────────────────────────────────────────────────────────
slice "$ROOT/agents/architect.md" '## Your output (the 4-file spec)' > "$T/arch.txt"
[ -s "$T/arch.txt" ] || fail "R2_architect_item3_pairs: section not found"
anch "$T/arch.txt" 'T<n>a.{0,160}RED' R2_architect_item3_pairs 'T<n>a ... RED'
anch "$T/arch.txt" 'T<n>b.{0,160}GREEN' R2_architect_item3_pairs 'T<n>b ... GREEN'
anch "$T/arch.txt" 'walking.{0,160}first' R2_architect_item3_pairs 'walking ... first'
anch "$T/arch.txt" 'refactor.{0,160}R-id' R2_architect_item3_pairs 'refactor ... R-id'
anch "$T/arch.txt" 'tasks-pair-check\.py.{0,160}hand-off' R2_architect_item3_pairs 'tasks-pair-check.py ... hand-off'
grep -qF 'Sequential, independent, small steps' "$T/arch.txt" && fail "R2_architect_item3_pairs: old item-3 text survives"
pass "R2_architect_item3_pairs"

# ── R3: SPEC-FORMAT section + table row, WORKFLOW step 5 ──────────────────────────────────
slice "$ROOT/docs/SPEC-FORMAT.md" '## Tasks — red/green pairs per requirement' > "$T/sf.txt"
[ -s "$T/sf.txt" ] || fail "R3_spec_format_pairs_section: section '## Tasks — red/green pairs per requirement' not found"
grep -qE '^ *(```|~~~)' "$T/sf.txt" || fail "R3_spec_format_pairs_section: slice has no fence delimiter — it did not read through the fenced example"
for a in 'T<n>a.{0,160}RED' 'T<n>b.{0,160}GREEN' 'write.{0,160}tests.{0,160}reject' \
         'fenced.{0,160}ignored' 'range.{0,160}not expanded' 'own pair' \
         'co-cit.{0,160}`a` task' 'never.{0,160}code-only'; do
  anch "$T/sf.txt" "$a" R3_spec_format_pairs_section "$a"
done
pass "R3_spec_format_pairs_section"
slice "$ROOT/docs/SPEC-FORMAT.md" '## The four files' | grep -F '| `.tasks.md`' | grep -qi 'red/green pair' \
  || fail "R3_spec_format_table_row: .tasks.md row lacks 'red/green pair'"
pass "R3_spec_format_table_row"
slice "$ROOT/docs/WORKFLOW.md" '## One run, end to end' | grep -E '^5\.' | grep -i 'pair' | grep -qi 'commit' \
  || fail "R3_workflow_step5: step 5 lacks pair/commit"
pass "R3_workflow_step5"

# ── R4: builder Loop A ────────────────────────────────────────────────────────────────────
slice "$ROOT/agents/builder.md" '## Loop A — in-session (you implement)' > "$T/la.txt"
[ -s "$T/la.txt" ] || fail "R4_builder_loop_a_pairs: Loop A section not found"
if ! folded < "$T/la.txt" | grep -qiE 'never.{0,160}code.{0,160}RED|RED.{0,160}before.{0,160}code'; then
  fail "R4_builder_loop_a_pairs: no 'no code before RED' rule"
fi
anch "$T/la.txt" 'commit.{0,160}GREEN' R4_builder_loop_a_pairs 'commit ... GREEN'
for a in 'in-progress' 'DO NOT TOUCH' './init.sh' 'tasks.md'; do
  grep -qF "$a" "$T/la.txt" || fail "R4_builder_loop_a_pairs: retained anchor missing: $a"
done
pass "R4_builder_loop_a_pairs"

# ── R9: reviewer item 7 inside "What you check" ───────────────────────────────────────────
slice "$ROOT/agents/reviewer.md" '## What you check' > "$T/rv.txt"
[ -s "$T/rv.txt" ] || fail "R9_reviewer_item7_in_what_you_check: section not found"
grep -qE '^7\. ' "$T/rv.txt" || fail "R9_reviewer_item7_in_what_you_check: no item 7 inside '## What you check'"
anch "$T/rv.txt" '7\. \*\*Task-pair shape' R9_reviewer_item7_in_what_you_check 'Task-pair shape'
anch "$T/rv.txt" 'tasks-pair-check\.py.{0,160}--spec' R9_reviewer_item7_in_what_you_check 'tasks-pair-check.py ... --spec'
anch "$T/rv.txt" 'non-zero.{0,160}reject' R9_reviewer_item7_in_what_you_check 'non-zero ... reject'
anch "$T/rv.txt" 'predates.{0,160}flag' R9_reviewer_item7_in_what_you_check 'predates ... flag'
anch "$T/rv.txt" 'diff-filter=A' R9_reviewer_item7_in_what_you_check 'diff-filter=A'
anch "$T/rv.txt" 'tasks-pair-check\.py.{0,40}--grandfathered.{0,200}exit 0.{0,120}flag' R9_reviewer_item7_in_what_you_check '--grandfathered ... exit 0 ... flag'
anch "$T/rv.txt" 'merge.{0,80}default branch' R9_reviewer_item7_in_what_you_check 'merge ... default branch (the tool date is its merge)'
anch "$T/rv.txt" 'first-parent' R9_reviewer_item7_in_what_you_check 'first-parent'
grep -qF '.harness/tools/tasks-pair-check.py' "$T/rv.txt" || fail "R9_reviewer_item7_in_what_you_check: item 7 does not name the installed-target path .harness/tools/tasks-pair-check.py"
grep -qF "the tool's first commit" "$T/rv.txt" && fail "R9_reviewer_item7_in_what_you_check: stale commit-time grandfather wording survives"
anch "$T/rv.txt" 'sdd: false.{0,160}exempt' R9_reviewer_item7_in_what_you_check 'sdd: false ... exempt'
anch "$T/rv.txt" 'confirm +`<feature>\.tests\.md` has a test' R9_reviewer_item7_in_what_you_check 'check #2 text retained'
pass "R9_reviewer_item7_in_what_you_check"

# ── R10: source mode 100755 (installer-wiring pin is the source grep in test_install.sh) ──
_mode="$(git -C "$ROOT" ls-files -s tools/tasks-pair-check.py | cut -c1-6)"
[ "$_mode" = "100755" ] || fail "R10_source_mode_100755: git mode is '$_mode'"
[ -x "$TOOL" ] || fail "R10_source_mode_100755: tool is not executable on disk"
pass "R10_source_mode_100755"

# ── R11: ledger row C9 ────────────────────────────────────────────────────────────────────
slice "$ROOT/docs/RATIONALE.md" '## Deletion ledger' > "$T/led.txt"
_c9="$(grep -F '| C9 — Task-pair shape lint |' "$T/led.txt" || true)"
[ -n "$_c9" ] || fail "R11_ledger_c9_ablation: no '| C9 — Task-pair shape lint |' row in the Deletion ledger section"
printf '%s\n' "$_c9" | grep -qF '| Capability compensation |' || fail "R11_ledger_c9_ablation: C9 layer is not Capability compensation"
printf '%s\n' "$_c9" | grep -qF 'tasks-pair-check' || fail "R11_ledger_c9_ablation: C9 does not name tasks-pair-check"
printf '%s\n' "$_c9" | grep -qF 'Ablation' || fail "R11_ledger_c9_ablation: C9 evidence cell lacks the Ablation condition"
pass "R11_ledger_c9_ablation"

# ── R12: VERSION / CHANGELOG paired at runtime (no literal) ───────────────────────────────
_v="$(cat "$ROOT/VERSION")"
_head="$(grep -m1 '^## \[' "$ROOT/CHANGELOG.md")"
case "$_head" in "## [$_v]"*) ;; *) fail "R12_version_changelog_paired: newest CHANGELOG heading '$_head' != VERSION '$_v'" ;; esac
awk '/^## \[/ { if (sec ~ /E36-F01/ && sec ~ /tasks-pair-check/) ok = 1; sec = ""; next } { sec = sec "\n" $0 }
     END { if (sec ~ /E36-F01/ && sec ~ /tasks-pair-check/) ok = 1; exit ok ? 0 : 1 }' "$ROOT/CHANGELOG.md" \
  || fail "R12_version_changelog_paired: no CHANGELOG section names both E36-F01 and tasks-pair-check"
pass "R12_version_changelog_paired"

echo "all tasks-pairs checks passed"
