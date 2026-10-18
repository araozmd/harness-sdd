#!/bin/sh
# test_pr_loop_hardening.sh — E99-F170: three defects a downstream Codex review found in
# the stamped /sdd-pr-loop glue, pinned by EXECUTING the runbook's own snippets rather than
# grepping for prose about them.
#
#   P1  the auto_merge:false hand-back posted "all gates green" and wrote `handback` with no
#       reviewed-head receipt — a commit pushed after pr.json was captured was reported
#       green although Codex reviewed an older head.
#   P1  HARNESS_DRY_RUN=1 skipped only the trigger comment; ready/checkout/labels/fixer
#       pushes/thread resolution/terminal comments/merge all still ran.
#   P2  re-entering an interrupted findings round re-dispatched every original blocking
#       comment, ignoring the fixes the round had already completed.
#   P1  (E99-F171) a clean/non-blocking `merge` verdict left the loop before step 6, the
#       only `gh pr checks --required` call: the hand-back posted "all gates green" and
#       wrote `handback` — and auto-merge merged — while required CI was pending or red.
#
# Every body that ships is checked: the three self-hosted copies AND a freshly installed
# target (the installer heredoc is the canonical source; a fix to only one copy ships the
# defect to every consumer).
#
# Zero dependencies beyond POSIX sh + python3 (and jq/git for the executed snippets, which
# print `skip -` when absent); self-cleaning temp dir. Parses and runs under /bin/dash.

set -eu
LC_ALL=C; export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-prh)"
trap 'rm -rf "$T"' EXIT INT TERM
export CODEX_HOME="$T/codex-home"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }
skip() { echo "skip - $1"; }
have_jq() { command -v jq >/dev/null 2>&1; }

# ── the bodies under test ────────────────────────────────────────────────────────
INST="$T/inst"; mkdir -p "$INST"
HARNESS_PR_LOOP_ENABLED=true HARNESS_AGENTS="claude,codex,opencode" \
  sh "$SRC/harness-install.sh" "$INST" >"$T/install.out" 2>"$T/install.err" \
  || { cat "$T/install.err" >&2; fail "setup: gate-on install failed"; }
BODIES="$SRC/.claude/commands/sdd-pr-loop.md
$SRC/.agents/skills/sdd-pr-loop/SKILL.md
$SRC/.opencode/command/sdd-pr-loop.md
$INST/.claude/commands/sdd-pr-loop.md"
for _b in $BODIES; do [ -f "$_b" ] || fail "setup: body missing: $_b"; done

# block <body> <marker> — print the FIRST fenced ```bash block containing <marker>.
block() {
  python3 - "$1" "$2" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
for m in re.finditer(r"^```bash\n(.*?)^```", s, re.S | re.M):
    if sys.argv[2] in m.group(1):
        sys.stdout.write(m.group(1)); sys.exit(0)
sys.exit(1)
PY
}

# fn <body> <name> — lift one shell function definition out of the body.
fn() { awk -v n="$2() {" '$0 == n { p = 1 } p { print } p && /^\}$/ { exit }' "$1"; }

# lift_fns <body> — mut + ci_required_gate + the thread helpers + merge_land, lifted out of
# the body (ts.sh also carries thread_fingerprint and merge_land, which the snippets call).
lift_fns() {
  fn "$1" mut > "$T/mut.sh"; fn "$1" ci_required_gate > "$T/ci.sh"
  { fn "$1" thread_scan; fn "$1" thread_fingerprint; fn "$1" merge_land; } > "$T/ts.sh"
}

# The `gh pr view --json` fields that exist in real gh (2.102.0). NOT isInMergeQueue.
PRVIEW_FIELDS="additions assignees author autoMergeRequest baseRefName baseRefOid body changedFiles closed closedAt closingIssuesReferences comments commits createdAt deletions files fullDatabaseId headRefName headRefOid headRepository headRepositoryOwner id isCrossRepository isDraft labels latestReviews maintainerCanModify mergeCommit mergeStateStatus mergeable mergedAt mergedBy milestone number potentialMergeCommit projectCards projectItems reactionGroups reviewDecision reviewRequests reviews state statusCheckRollup title updatedAt url"

# mk_env <dir> <current-head> — a sandbox: stub `gh` (logs every call to $dir/gh.log and
# answers the reads the snippets make), the REAL watcher at .harness/tools/, a round dir
# whose pr.json says the reviewed head is `aaaa…`.
mk_env() {
  _e="$1"; mkdir -p "$_e/bin" "$_e/.harness/tools" "$_e/tools" "$_e/round"
  # Both layouts: an installed body says `.harness/tools/`, a self-hosted one `tools/`.
  cp "$SRC/tools/wait-for-codex.sh" "$_e/.harness/tools/wait-for-codex.sh"
  cp "$SRC/tools/wait-for-codex.sh" "$_e/tools/wait-for-codex.sh"
  printf '{"headRefOid":"%s"}\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa > "$_e/round/pr.json"
  printf 'summary\n' > "$_e/handover-summary.md"
  cat > "$_e/bin/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$_e/gh.log"
# Real gh rejects a pr-view --json field outside its list (gh 2.102.0); so does this stub.
case "\$*" in *"pr view"*"--json "*)
  for _x in \$(printf '%s' "\$*" | sed 's/.*--json \([^ ]*\).*/\1/' | tr ',' ' '); do
    case " $PRVIEW_FIELDS " in *" \$_x "*) ;; *) echo "Unknown JSON field: \"\$_x\"" >&2; exit 1 ;; esac
  done ;;
esac
case "\$*" in
  *"--json headRefOid"*) echo "$2" ;;
  *"--json state,mergedAt,mergeCommit"*)
    # Post-receipt state. Absent \$_e/mvstate ⇒ MERGED. Otherwise scripted one line per read
    # (the last repeats), and \$_e/mv_after_cancel makes it MERGED once a cancel was issued.
    if [ -e "$_e/mv_after_cancel" ] && [ -e "$_e/cancelled" ]; then echo "MERGED 2026-10-10T00:00:00Z bbbb"; exit 0; fi
    if [ -s "$_e/mvstate" ]; then
      head -n 1 "$_e/mvstate"
      [ "\$(wc -l < "$_e/mvstate")" -gt 1 ] && { tail -n +2 "$_e/mvstate" > "$_e/mvstate.n"; mv "$_e/mvstate.n" "$_e/mvstate"; }
    else echo "MERGED 2026-10-10T00:00:00Z bbbb"; fi ;;
  *"api graphql"*"isInMergeQueue"*)
    # Answer ONLY a query that selects state + isInMergeQueue + autoMergeRequest for PR 7.
    case "\$*" in
      *"state isInMergeQueue autoMergeRequest"*"pr=7"*) cat "$_e/qstate" 2>/dev/null; : ;;
      *) echo "bad merge-state query" >&2; exit 1 ;;
    esac ;;
  *"--json id"*) echo PR_NODE_7 ;;
  *"pr merge"*"--disable-auto"*|*"dequeuePullRequest"*)
    touch "$_e/cancelled"; [ -e "$_e/cancel_fail" ] && exit 1; : ;;
  *"resolveReviewThread"*) [ -f "$_e/fp_after_resolve" ] && cp "$_e/fp_after_resolve" "$_e/fp"; : ;;
  *"api graphql"*"ThreadFingerprint"*)
    # Every-thread fingerprint ("<id> <isResolved> <count>" lines) from \$_e/fp; absent ⇒ none.
    [ -e "$_e/fp_fail" ] && exit 1
    cat "$_e/fp" 2>/dev/null; : ;;
  *"--json baseRefName"*) cat "$_e/base" 2>/dev/null || echo main ;;
  *"defaultBranchRef"*) echo main ;;
  *"api graphql"*"reviewThreads"*)
    # Unresolved-thread scan ("<allcodex> <id>" lines, already --jq-filtered), from
    # \$_e/threads; absent ⇒ none.
    [ -e "$_e/threads_fail" ] && exit 1
    cat "$_e/threads" 2>/dev/null; : ;;
  *"pr comment"*) echo "https://github.com/o/r/pull/7#issuecomment-1" ;;
  *"/rules/branches/"*)
    # Ruleset JSON as gh --paginate --slurp returns it (an array of pages):
    # \$_e/req_rules lists required_status_checks contexts and \$_e/req_wf required
    # workflows ("<repository_id> <path>"); both land on PAGE 2 when \$_e/rules_p2 exists.
    [ -e "$_e/api_fail" ] && exit 1
    _rc="\$(sed 's/.*/{"context":"&"}/' "$_e/req_rules" 2>/dev/null | paste -sd, -)"
    _rw="\$(awk '{printf "%s{\\"repository_id\\":%s,\\"path\\":\\"%s\\"}", (NR>1?",":""), \$1, \$2}' "$_e/req_wf" 2>/dev/null)"
    _sc=""; [ -n "\$_rc" ] && _sc=',{"type":"required_status_checks","parameters":{"required_status_checks":['"\$_rc"']}}'
    _wf=""; [ -n "\$_rw" ] && _wf=',{"type":"workflows","parameters":{"workflows":['"\$_rw"']}}'
    if [ -e "$_e/rules_p2" ]; then
      printf '[[{"type":"deletion","parameters":null}],[{"type":"non_fast_forward","parameters":null}%s%s]]\n' "\$_sc" "\$_wf"
    else
      printf '[[{"type":"deletion","parameters":null}%s%s]]\n' "\$_sc" "\$_wf"
    fi ;;
  *"api repos/"*"/branches/"*)
    # Raw branch JSON with classic protection contexts. Absent \$_e/req ⇒ "build"; empty ⇒ none.
    [ -e "$_e/api_fail" ] && exit 1
    if [ -f "$_e/req" ]; then _c="\$(sed 's/.*/"&"/' "$_e/req" | paste -sd, -)"; else _c='"build"'; fi
    printf '{"protected":true,"protection":{"required_status_checks":{"contexts":[%s]}}}\n' "\$_c" ;;
  *"pr checks"*)
    # Anything staged as *_next lands the moment CI is read — i.e. DURING the CI wait.
    [ -f "$_e/base_next" ] && mv "$_e/base_next" "$_e/base"
    [ -f "$_e/threads_next" ] && mv "$_e/threads_next" "$_e/threads"
    [ -f "$_e/fp_next" ] && mv "$_e/fp_next" "$_e/fp"
    [ -f "$_e/fp_fail_next" ] && mv "$_e/fp_fail_next" "$_e/fp_fail"
    [ -f "$_e/fp_fail_clear" ] && rm -f "$_e/fp_fail" "$_e/fp_fail_clear"
    # Required-CI answer, scripted by \$_e/ci (one mode per line, consumed in order; the
    # last line repeats). Absent ⇒ pass. Shapes mirror gh --json name,bucket; "none" is
    # gh's empty-rollup diagnostic, and a cancelled check exits 0 exactly as gh does.
    _m=pass
    if [ -s "$_e/ci" ]; then
      _m="\$(head -n 1 "$_e/ci")"
      [ "\$(wc -l < "$_e/ci")" -gt 1 ] && { tail -n +2 "$_e/ci" > "$_e/ci.n"; mv "$_e/ci.n" "$_e/ci"; }
    fi
    case "\$_m" in
      pass)    echo '[{"name":"build","bucket":"pass"}]'; exit 0 ;;
      skip)    echo '[{"name":"build","bucket":"skipping"}]'; exit 0 ;;
      fail)    echo '[{"name":"build","bucket":"fail"}]'; exit 1 ;;
      cancel)  echo '[{"name":"build","bucket":"cancel"}]'; exit 0 ;;
      pending) echo '[{"name":"build","bucket":"pending"}]'; exit 8 ;;
      other)   echo '[{"name":"lint","bucket":"pass"}]'; exit 0 ;;
      none)    echo "no required checks reported on the 'feat' branch" >&2; exit 1 ;;
    esac ;;
esac
exit 0
EOF
  chmod +x "$_e/bin/gh"
  : > "$_e/gh.log"
}

# run_block <env-dir> <snippet-file> <extra-sh> — run a runbook snippet in the sandbox with
# the runbook's own `mut` wrapper in scope; prints nothing, leaves evidence on disk.
run_block() {
  _rd="$1"; _sn="$2"; _pre="$3"
  ( cd "$_rd" && PATH="$_rd/bin:$PATH" HARNESS_MERGE_VERIFY_INTERVAL=1 HARNESS_MERGE_VERIFY_CEILING=2 \
      HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=2 sh -c "$(cat "$T/mut.sh")
$(cat "$T/ci.sh" 2>/dev/null)
$(cat "$T/ts.sh" 2>/dev/null)
pr_number=7; round_dir=round; pr_cache=.; default_branch=main; $_pre
$(cat "$_sn")
printf '%s\n' \"\${merged:-unset} \${handback_ok:-unset}\" > result" ) >/dev/null 2>"$_rd/err" || :
}

# ══ P1 — the hand-back revalidates the reviewed head before it claims anything ══════
test_handback_revalidates_head() {
  have_jq || { skip "handback_revalidates_head (jq not installed)"; return 0; }
  for _b in $BODIES; do
    lift_fns "$_b"
    grep -qF 'mut() {' "$T/mut.sh" || fail "P1: no mut() wrapper in $_b"
    block "$_b" 'echo handback > "$round_dir/disposed"' > "$T/hb.sh" \
      || fail "P1: $_b has no executable hand-back block — the marker is written from prose only"
    # Static ordering: the receipt precedes BOTH the green post and the marker.
    python3 - "$T/hb.sh" <<'PY' || fail "P1: $_b hand-back posts or marks before the head receipt"
import sys
s = open(sys.argv[1]).read()
r = s.index('merge-verify "$round_dir" "$pr_number" pre')
assert r < s.index('handover-summary.md') and r < s.index('echo handback >')
PY
    # Executed: head MOVED since the reviewed round → no green post, no `handback`.
    _e="$T/hb-moved"; rm -rf "$_e"; mk_env "$_e" cccccccccccccccccccccccccccccccccccccccc
    run_block "$_e" "$T/hb.sh" ''
    grep -q 'pr comment' "$_e/gh.log" \
      && fail "P1: $_b posted the green hand-back although the head moved past the reviewed one"
    [ "$(cat "$_e/round/disposed" 2>/dev/null)" = handback ] \
      && fail "P1: $_b wrote a terminal handback marker for an unreviewed head"
    [ "$(cat "$_e/round/disposed" 2>/dev/null)" = stale ] \
      || fail "P1: $_b refused hand-back leaves the round re-enterable on its outdated green verdict (want disposed=stale)"
    grep -q 'add-label needs-human' "$_e/gh.log" \
      || fail "P1: $_b refused hand-back is not routed to needs-human"
    # Executed: head UNCHANGED → the hand-back posts and completes.
    _e="$T/hb-same"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    run_block "$_e" "$T/hb.sh" ''
    grep -q 'pr comment' "$_e/gh.log" || fail "P1: $_b unchanged-head hand-back never posted its summary"
    [ "$(cat "$_e/round/disposed" 2>/dev/null)" = handback ] \
      || fail "P1: $_b unchanged-head hand-back did not record its terminal marker"
    # Executed: a DRY-RUN hand-back posts nothing and leaves no marker behind.
    _e="$T/hb-dry"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    run_block "$_e" "$T/hb.sh" 'HARNESS_DRY_RUN=1'
    grep -q 'pr comment' "$_e/gh.log" && fail "P1: $_b dry-run hand-back posted the green summary"
    [ -e "$_e/round/disposed" ] && fail "P1: $_b dry-run hand-back wrote a disposed marker"
  done
  pass "P1 hand-back: reviewed-head receipt before the green post and the marker; a moved head is refused (all bodies)"
}

# ══ P1 — dry run suppresses EVERY remote and repository mutation ═══════════════════
test_dry_run_suppresses_every_mutation() {
  for _b in $BODIES; do
    # Static sweep: every mutating command in every executable block goes through `mut`.
    python3 - "$_b" <<'PY' || fail "P1 dry-run: $_b calls a mutation outside the mut wrapper"
import re, sys
s = open(sys.argv[1]).read()
mutating = re.compile(r"\b(gh pr (ready|comment|edit|checkout|merge)|git (push|checkout|pull|commit|branch -D|remote prune))\b")
bad = []
for m in re.finditer(r"^```bash\n(.*?)^```", s, re.S | re.M):
    lines = m.group(1).split("\n")
    for i, line in enumerate(lines):
        code = line.split("#", 1)[0] if not line.lstrip().startswith("#") else ""
        for hit in mutating.finditer(code):
            if not code[:hit.start()].endswith("mut "):
                bad.append(line.strip())
        for gql in ("resolveReviewThread", "dequeuePullRequest"):
            if gql in code and "mut gh api graphql" not in lines[i - 1]:
                bad.append(line.strip())
for b in bad: print("unwrapped:", b, file=sys.stderr)
sys.exit(1 if bad else 0)
PY
    grep -qF '.pr-loop/dry-run/$pr_number"' "$_b" \
      || fail "P1 dry-run: $_b dry run writes into the real round cache (budget + handback poisoning)"
    grep -qF 'spawn no fixer' "$_b" || fail "P1 dry-run: $_b still dispatches fixers (they commit) on a dry run"
    # Executed: the wrapper skips under HARNESS_DRY_RUN=1 and runs otherwise.
    lift_fns "$_b"
    _m="$T/mutx"; rm -rf "$_m"; mkdir -p "$_m"
    ( . "$T/mut.sh"; HARNESS_DRY_RUN=1; mut touch "$_m/dry" ) 2>/dev/null
    [ -e "$_m/dry" ] && fail "P1 dry-run: $_b mut ran a mutation under HARNESS_DRY_RUN=1"
    ( . "$T/mut.sh"; HARNESS_DRY_RUN=0; mut touch "$_m/real" ) 2>/dev/null
    [ -e "$_m/real" ] || fail "P1 dry-run: $_b mut does not run the command on a real run"
  done
  # Executed: the merge block on a dry run merges NOTHING; on a real run it merges.
  if have_jq; then
    for _b in $BODIES; do
      lift_fns "$_b"
      block "$_b" '--match-head-commit "$reviewed_head"' > "$T/merge.sh" || fail "setup: no merge block in $_b"
      _e="$T/mg-dry"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      run_block "$_e" "$T/merge.sh" 'merge_ok=1; _mg_fp_pre=; HARNESS_DRY_RUN=1'
      grep -q 'pr merge' "$_e/gh.log" && fail "P1 dry-run: $_b merged a PR under HARNESS_DRY_RUN=1"
      grep -q 'pr edit' "$_e/gh.log" && fail "P1 dry-run: $_b labelled a PR under HARNESS_DRY_RUN=1"
      [ "$(cut -d' ' -f1 "$_e/result")" = 1 ] \
        && fail "P1 dry-run: $_b reached merged=1 on a dry run — the merge path ran instead of stopping"
      grep -q 'DRY-RUN — would merge' "$_e/err" \
        || fail "P1 dry-run: $_b dry run does not say what it would have merged"
      # A dry run with a human/unreadable thread (merge_ok=0) must report the disposition a
      # live run reaches — needs-human — never "would merge" (#4239219016).
      _e="$T/mg-dry-held"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      run_block "$_e" "$T/merge.sh" 'merge_ok=0; HARNESS_DRY_RUN=1'
      grep -q 'would merge' "$_e/err" && fail "P1 dry-run: $_b claims a dry-run merge although merge_ok=0"
      grep -q 'needs-human, not merging' "$_e/err" || fail "P1 dry-run: $_b dry run with merge_ok=0 does not report needs-human"
      _e="$T/mg-real"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      run_block "$_e" "$T/merge.sh" 'merge_ok=1; _mg_fp_pre=; HARNESS_DRY_RUN=0'
      grep -q 'pr merge' "$_e/gh.log" || fail "P1 dry-run: $_b real-run merge block never merged (wrapper broke the live path)"
      [ "$(cut -d' ' -f1 "$_e/result")" = 1 ] || fail "P1 dry-run: $_b real-run merge did not reach merged=1"
    done
  else
    skip "dry-run merge execution (jq not installed)"
  fi
  pass "P1 dry run: every mutation is wrapped, the wrapper skips only on a dry run, a dry run never merges (all bodies)"
}

# ══ P2 — resuming a round skips the fixes it already completed ═════════════════════
test_resume_skips_completed_fixers() {
  if ! have_jq || ! command -v git >/dev/null 2>&1; then
    skip "resume_skips_completed_fixers (jq/git not installed)"; return 0
  fi
  for _b in $BODIES; do
    fn "$_b" fix_done > "$T/fd.sh"; fn "$_b" acted_append > "$T/aa.sh"
    grep -qF 'fix_done() {' "$T/fd.sh" || fail "P2: $_b has no fix_done helper"
    grep -qF 'not already `fix_done`' "$_b" || fail "P2: $_b per-comment dispatch row does not filter completed fixes"
    grep '^| `max_rounds - 1` |' "$_b" | grep -qF 'the SAME per-comment receipts `fix_done` reads' \
      || fail "P2: $_b combined escalation leaves no per-comment receipt, so its resume re-sends fixed comments (#4239187036)"
    _g="$T/repo"; rm -rf "$_g"; mkdir -p "$_g/round"
    ( cd "$_g" && git init -q . && git config user.email t@t && git config user.name t \
      && git commit -q --allow-empty -m "fix: address Codex P1 on a.sh:1 (#333)" \
      && git rev-parse HEAD > reviewed \
      && git commit -q --allow-empty -m "fix: address Codex P1 on a.sh:3 (#111)" )
    printf '{"headRefOid":"%s"}\n' "$(cat "$_g/reviewed")" > "$_g/round/pr.json"
    printf '# Fix for comment 222\n' > "$_g/round/fix-222.md"
    _r="$( cd "$_g" && sh -c '. "$1"; . "$2"; round_dir=round
      for id in 111 222 333 444; do fix_done "$id" && printf "%s " "$id"; done
      acted_append 444 a.sh 4 P1 configured; acted_append 444 a.sh 4 P1 configured
      printf "| %s" "$(jq length round/acted.json)"' _ "$T/fd.sh" "$T/aa.sh" )"
    # 111: committed after the reviewed head (note lost) · 222: note written · 333: a
    # commit BEFORE the reviewed head (an older round) must NOT count · 444: unfinished.
    [ "$_r" = "111 222 | 1" ] \
      || fail "P2: $_b resume reconstruction wrong — got '$_r', want completed '111 222' and one idempotent acted row"
  done
  pass "P2 resume: completed fixes (note or post-review commit) are skipped, acted rows are not duplicated (all bodies)"
}

# ══ P1 (E99-F171) — required CI gates BOTH terminal paths ══════════════════════════
test_required_ci_gates_terminal_paths() {
  have_jq || { skip "required_ci_gates_terminal_paths (jq not installed)"; return 0; }
  for _b in $BODIES; do
    lift_fns "$_b"
    grep -qF 'ci_required_gate() {' "$T/ci.sh" || fail "CI: $_b has no ci_required_gate helper"
    grep -qF 'gh pr checks "$pr_number" --required' "$T/ci.sh" \
      || fail "CI: $_b helper does not read the REQUIRED checks"
    grep -qF 'and go to step 6' "$_b" \
      && fail "CI: $_b step 5 still routes a merge verdict to step 6 (which it skips)"
    block "$_b" 'echo handback > "$round_dir/disposed"' > "$T/hb.sh" || fail "setup: no hand-back block in $_b"
    block "$_b" '--match-head-commit "$reviewed_head"' > "$T/merge.sh" || fail "setup: no merge block in $_b"
    # Static ordering: the gate precedes the green post / marker, and every merge call.
    python3 - "$T/hb.sh" "$T/merge.sh" <<'PY' || fail "CI: $_b claims or merges before the required-CI gate"
import sys
hb = open(sys.argv[1]).read(); mg = open(sys.argv[2]).read()
g = hb.index('ci_required_gate')
assert g < hb.index('handover-summary.md') and g < hb.index('echo handback >')
assert hb.index('_hb_thr_pre="$(thread_scan)"') < g < hb.index('_hb_thr_post="$(thread_scan)"') < hb.index('echo handback >')
assert mg.index('ci_required_gate') < mg.index('mut gh pr merge')
assert mg.index('"${merge_ok:-0}" != "1"') < mg.index('ci_required_gate')
PY
    # ── helper semantics ─────────────────────────────────────────────────────────
    # <ci modes>:<required contexts, "," separated; "-" = none; "!" = API unreadable>:<rc>
    for _case in "pass:build:0" "skip:build:0" "fail:build:1" "cancel:build:1" "pending:build:1" \
                 "pending pending pass:build:0" "none:-:0" "none:build:1" "none none pass:build:0" \
                 "other:build:1" "other:-:0" "pass:!:1" "none:!:1"; do
      _modes="${_case%%:*}"; _rest="${_case#*:}"; _req="${_rest%%:*}"; _want="${_rest##*:}"
      _e="$T/ci-fn"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      printf '%s\n' $_modes > "$_e/ci"
      case "$_req" in
        -) : > "$_e/req" ;;
        !) touch "$_e/api_fail" ;;
        *) printf '%s\n' "$_req" | tr ',' '\n' > "$_e/req" ;;
      esac
      _got=0
      ( cd "$_e" && PATH="$_e/bin:$PATH" HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=3 \
          sh -c ". '$T/ci.sh'; pr_number=7; ci_required_gate" ) 2>/dev/null || _got=$?
      [ "$_got" = "$_want" ] \
        || fail "CI: $_b ci_required_gate on '$_modes' (required: $_req) returned $_got, want $_want"
    done
    # The base branch is URL-encoded as a REST path parameter (a '#' or '/' in its name).
    _e="$T/ci-enc"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    printf 'release#1\n' > "$_e/base"
    ( cd "$_e" && PATH="$_e/bin:$PATH" HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=1 \
        sh -c ". '$T/ci.sh'; pr_number=7; ci_required_gate" ) 2>/dev/null \
      || fail "CI: $_b gate not green for base 'release#1' with passing required checks"
    grep -q 'branches/release%231' "$_e/gh.log" && ! grep -q 'branches/release#1' "$_e/gh.log" \
      || fail "CI: $_b interpolates the base branch into REST paths without URL-encoding it"
    # A CANCELLED required check is red at once, not pending until the ceiling.
    _e="$T/ci-cancel"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    echo cancel > "$_e/ci"
    ( cd "$_e" && PATH="$_e/bin:$PATH" HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=30 \
        sh -c ". '$T/ci.sh'; pr_number=7; ci_required_gate" ) 2>"$_e/err" \
      && fail "CI: $_b passed a cancelled required check"
    grep -q 'failed or cancelled' "$_e/err" \
      || fail "CI: $_b treats a cancelled required check as pending instead of red"
    # A context required only by a RULESET is waited on too (classic protection empty).
    _e="$T/ci-rules"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    : > "$_e/req"; echo build > "$_e/req_rules"; echo none > "$_e/ci"
    ( cd "$_e" && PATH="$_e/bin:$PATH" HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=1 \
        sh -c ". '$T/ci.sh'; pr_number=7; ci_required_gate" ) 2>/dev/null \
      && fail "CI: $_b passed an empty rollup although a ruleset requires 'build'"
    _e="$T/ci-rules-ok"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    : > "$_e/req"; echo build > "$_e/req_rules"; echo pass > "$_e/ci"
    ( cd "$_e" && PATH="$_e/bin:$PATH" HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=1 \
        sh -c ". '$T/ci.sh'; pr_number=7; ci_required_gate" ) 2>/dev/null \
      || fail "CI: $_b ruleset-required 'build' passed but the gate is not green (ruleset filter broken)"
    # A ruleset `workflows` rule (required workflows) cannot be verified from the rollup,
    # so the gate fails CLOSED whatever the checks say — even all-green — and says why.
    for _ci in none pass; do
      _e="$T/ci-wf"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      echo "$_ci" > "$_e/ci"; echo "42 .github/workflows/org-ci.yml" > "$_e/req_wf"
      ( cd "$_e" && PATH="$_e/bin:$PATH" HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=1 \
          sh -c ". '$T/ci.sh'; pr_number=7; ci_required_gate" ) 2>"$_e/err" \
        && fail "CI: $_b declared required CI green although the base requires ruleset workflows (rollup '$_ci')"
      grep -q 'requires ruleset workflows' "$_e/err" \
        || fail "CI: $_b required-workflows refusal does not say why"
    done
    # …including a workflows rule that only appears on a LATER rules page.
    _e="$T/ci-wf-p2"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    : > "$_e/req"; echo pass > "$_e/ci"; touch "$_e/rules_p2"
    echo "42 .github/workflows/org-ci.yml" > "$_e/req_wf"
    ( cd "$_e" && PATH="$_e/bin:$PATH" HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=1 \
        sh -c ". '$T/ci.sh'; pr_number=7; ci_required_gate" ) 2>/dev/null \
      && fail "CI: $_b missed a required-workflows rule on rules page 2"
    # A required-status rule on a LATER rules page is still read (pagination).
    _e="$T/ci-p2"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    : > "$_e/req"; echo build > "$_e/req_rules"; touch "$_e/rules_p2"; echo none > "$_e/ci"
    ( cd "$_e" && PATH="$_e/bin:$PATH" HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=1 \
        sh -c ". '$T/ci.sh'; pr_number=7; ci_required_gate" ) 2>/dev/null \
      && fail "CI: $_b ignored a required check declared on rules page 2"
    grep -q 'api --paginate --slurp repos/{owner}/{repo}/rules/branches/' "$_e/gh.log" \
      || fail "CI: $_b does not paginate the active-rules inventory"
    echo pass > "$_e/ci"
    ( cd "$_e" && PATH="$_e/bin:$PATH" HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=1 \
        sh -c ". '$T/ci.sh'; pr_number=7; ci_required_gate" ) 2>/dev/null \
      || fail "CI: $_b multi-page rules inventory is not combined (page-2 'build' passed, gate not green)"
    # Pending forever is bounded by the ceiling, not an unbounded wait.
    _e="$T/ci-ceil"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    echo pending > "$_e/ci"
    ( cd "$_e" && PATH="$_e/bin:$PATH" HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=2 \
        sh -c ". '$T/ci.sh'; pr_number=7; ci_required_gate" ) 2>"$_e/err" && fail "CI: $_b pending CI passed the gate"
    _polls="$(grep -c 'pr checks' "$_e/gh.log")"
    [ "$_polls" -ge 2 ] && [ "$_polls" -le 4 ] \
      || fail "CI: $_b pending CI polled $_polls times under a 2s ceiling (want a bounded re-poll)"
    grep -q 'not green after 2s' "$_e/err" || fail "CI: $_b pending-at-ceiling is not reported"

    # ── hand-back (auto_merge:false) ────────────────────────────────────────────
    for _mode in fail cancel pending; do
      _e="$T/hb-ci-$_mode"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      echo "$_mode" > "$_e/ci"
      run_block "$_e" "$T/hb.sh" ''
      grep -q 'pr comment' "$_e/gh.log" \
        && fail "CI: $_b hand-back posted 'all gates green' with required CI $_mode"
      [ -e "$_e/round/disposed" ] \
        && fail "CI: $_b hand-back wrote disposed=$(cat "$_e/round/disposed") with required CI $_mode (must stay re-enterable)"
      grep -q 'add-label needs-human' "$_e/gh.log" \
        || fail "CI: $_b hand-back with required CI $_mode is not routed to needs-human"
      [ "$(cut -d' ' -f2 "$_e/result")" = 0 ] || fail "CI: $_b hand-back with required CI $_mode did not return failure"
    done
    # Required CI green after a pending poll → the hand-back completes.
    _e="$T/hb-ci-late"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    printf 'pending\npass\n' > "$_e/ci"
    run_block "$_e" "$T/hb.sh" ''
    [ "$(cat "$_e/round/disposed" 2>/dev/null)" = handback ] \
      || fail "CI: $_b hand-back did not complete once required CI turned green"
    # A base branch that provably requires NO checks is not blocked.
    _e="$T/hb-ci-none"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    echo none > "$_e/ci"; : > "$_e/req"
    run_block "$_e" "$T/hb.sh" ''
    [ "$(cat "$_e/round/disposed" 2>/dev/null)" = handback ] \
      || fail "CI: $_b hand-back blocked on a repo that requires no checks"
    # Dry run with red CI: labels nothing, posts nothing, marks nothing.
    _e="$T/hb-ci-dry"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    echo fail > "$_e/ci"
    run_block "$_e" "$T/hb.sh" 'HARNESS_DRY_RUN=1'
    grep -q 'pr comment\|pr edit' "$_e/gh.log" && fail "CI: $_b dry-run red-CI hand-back mutated the PR"
    [ -e "$_e/round/disposed" ] && fail "CI: $_b dry-run red-CI hand-back wrote a marker"

    # ── auto-merge ───────────────────────────────────────────────────────────────
    for _mode in fail cancel pending; do
      _e="$T/mg-ci-$_mode"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      echo "$_mode" > "$_e/ci"
      run_block "$_e" "$T/merge.sh" 'merge_ok=1; _mg_fp_pre='
      grep -q 'pr merge' "$_e/gh.log" && fail "CI: $_b auto-merged with required CI $_mode"
      [ "$(cut -d' ' -f1 "$_e/result")" = 1 ] && fail "CI: $_b reached merged=1 with required CI $_mode"
      [ -e "$_e/round/disposed" ] && fail "CI: $_b red-CI merge refusal wrote a disposed marker"
      grep -q 'add-label needs-human' "$_e/gh.log" \
        || fail "CI: $_b merge refused on required CI $_mode is not routed to needs-human"
    done
    _e="$T/mg-ci-dry"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    echo fail > "$_e/ci"
    run_block "$_e" "$T/merge.sh" 'merge_ok=1; _mg_fp_pre=; HARNESS_DRY_RUN=1'
    grep -q 'would merge' "$_e/err" && fail "CI: $_b dry run claims it would merge over red required CI"
    grep -q 'pr edit\|pr merge' "$_e/gh.log" && fail "CI: $_b dry-run red-CI merge mutated the PR"
    # Threads are re-read AFTER the CI wait: a human thread that appeared during it blocks.
    grep -qF 'thread_scan() {' "$T/ts.sh" || fail "CI: $_b has no reusable thread_scan"
    python3 - "$T/merge.sh" <<'PY' || fail "CI: $_b merge does not re-read threads after the CI wait"
import sys
mg = open(sys.argv[1]).read()
assert mg.index('ci_required_gate') < mg.index('thread_scan') < mg.index('mut gh pr merge')
PY
    for _th in "false PRRT_human" "!"; do
      _e="$T/mg-thr"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      if [ "$_th" = "!" ]; then
        touch "$_e/threads_fail"     # the enumeration itself FAILS after the wait
      else
        echo "$_th" > "$_e/threads"
      fi
      run_block "$_e" "$T/merge.sh" 'merge_ok=1; _mg_fp_pre='
      grep -q 'pr merge' "$_e/gh.log" && fail "CI: $_b merged although threads changed or were unreadable after the CI wait ($_th)"
      grep -q 'add-label needs-human' "$_e/gh.log" \
        || fail "CI: $_b post-CI thread refusal ($_th) is not routed to needs-human"
    done
    # A DRY run (resolves skipped) still sees the vetted Codex thread: it does not block…
    _e="$T/mg-thr-codex"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    echo "true PRRT_codex" > "$_e/threads"
    run_block "$_e" "$T/merge.sh" 'merge_ok=1; _mg_fp_pre=; unresolved="true PRRT_codex"; HARNESS_DRY_RUN=1'
    grep -q 'would merge' "$_e/err" || fail "CI: $_b dry run blocked on its own vetted (unresolved) Codex thread"
    # …but on a LIVE run every vetted thread was resolved, so one still/again unresolved
    # after the wait (reopened) blocks.
    _e="$T/mg-thr-reopen"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    echo "true PRRT_codex" > "$_e/threads"
    run_block "$_e" "$T/merge.sh" 'merge_ok=1; _mg_fp_pre=; unresolved="true PRRT_codex"'
    grep -q 'pr merge' "$_e/gh.log" && fail "CI: $_b merged over a Codex thread reopened during the CI wait"
    [ "$(cat "$_e/round/disposed" 2>/dev/null)" = stale ] \
      || fail "CI: $_b post-wait thread refusal does not mark the round stale for a fresh review"
    # A PR retargeted away from the default branch DURING the wait is not merged.
    _e="$T/mg-retarget"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    echo release > "$_e/base_next"
    run_block "$_e" "$T/merge.sh" 'merge_ok=1; _mg_fp_pre='
    grep -q 'pr merge' "$_e/gh.log" && fail "CI: $_b merged a PR retargeted during the CI wait"
    grep -q "base changed to 'release'" "$_e/err" || fail "CI: $_b retarget during the CI wait is not reported"
    # An UNREADABLE base after the wait is not the default branch either: no merge.
    _e="$T/mg-base-unread"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    : > "$_e/base_next"
    run_block "$_e" "$T/merge.sh" 'merge_ok=1; _mg_fp_pre='
    grep -q 'pr merge' "$_e/gh.log" && fail "CI: $_b merged although the base was unreadable after the CI wait"
    # Hand-back: a Codex thread posted (or reopened) during the wait ⇒ no green, stale.
    _e="$T/hb-thr-late"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    echo "true PRRT_late" > "$_e/threads_next"
    run_block "$_e" "$T/hb.sh" ''
    grep -q 'pr comment' "$_e/gh.log" && fail "CI: $_b hand-back posted green over a thread that arrived during the CI wait"
    [ "$(cat "$_e/round/disposed" 2>/dev/null)" = stale ] \
      || fail "CI: $_b hand-back thread refusal does not mark the round stale"
    grep -q 'add-label needs-human' "$_e/gh.log" || fail "CI: $_b hand-back thread refusal is not needs-human"
    # …while threads that did not change (e.g. a human thread handed back as feedback) pass.
    _e="$T/hb-thr-same"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    echo "false PRRT_human" > "$_e/threads"
    run_block "$_e" "$T/hb.sh" ''
    [ "$(cat "$_e/round/disposed" 2>/dev/null)" = handback ] \
      || fail "CI: $_b hand-back refused although no thread changed during the CI wait"
    # A thread scan that fails BEFORE the wait refuses too (no green on unread input).
    _e="$T/hb-thr-fail"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    touch "$_e/threads_fail"
    run_block "$_e" "$T/hb.sh" ''
    grep -q 'pr comment' "$_e/gh.log" && fail "CI: $_b hand-back posted green with unreadable threads"
    # …but a Codex thread that ARRIVED during the wait is unreviewed input: it blocks.
    _e="$T/mg-thr-late"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    printf 'true PRRT_codex\ntrue PRRT_late\n' > "$_e/threads"
    run_block "$_e" "$T/merge.sh" 'merge_ok=1; _mg_fp_pre=; unresolved="true PRRT_codex"'
    grep -q 'pr merge' "$_e/gh.log" && fail "CI: $_b merged over a Codex thread that arrived during the CI wait"
    grep -q 'add-label needs-human' "$_e/gh.log" \
      || fail "CI: $_b a late Codex thread is not routed to needs-human"
    _e="$T/mg-ci-pass"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    printf 'pending\npass\n' > "$_e/ci"
    run_block "$_e" "$T/merge.sh" 'merge_ok=1; _mg_fp_pre='
    grep -q 'pr merge' "$_e/gh.log" || fail "CI: $_b never merged once required CI turned green"
  done
  pass "P1 required CI: hand-back and auto-merge wait on required checks; red/pending-at-ceiling ⇒ needs-human, no green post, no marker, no merge (all bodies)"
}

# ══ #259 — late review input during the CI wait: every thread is fingerprinted ═════════
# thread_scan lists only UNRESOLVED threads as "<allcodex> <id>", so a new Codex comment on
# an already-unresolved thread (line unchanged) and a comment on a RESOLVED thread (not
# listed) were both invisible. thread_fingerprint prints "<id> <isResolved> <count>" for
# every thread; the hand-back and the merge path require it byte-identical across the wait.
test_late_comments_refuse_green() {
  have_jq || { skip "late_comments_refuse_green (jq not installed)"; return 0; }
  _H=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  for _b in $BODIES; do
    lift_fns "$_b"
    grep -qF 'thread_fingerprint() {' "$T/ts.sh" || fail "259: $_b has no thread_fingerprint helper"
    grep -qF 'nodes{ id isResolved comments(last:1){ totalCount nodes{ id updatedAt } } }' "$_b" \
      || fail "259: $_b fingerprint does not read isResolved + comment totalCount of every thread"
    fn "$_b" thread_fingerprint | grep -qF -e '--paginate' || fail "259: $_b fingerprint is not paginated"
    # The jq program is NOT exercised by the stub gh (it answers already-filtered lines), so
    # run the REAL expression over a GraphQL-shaped sample: "<id> <isResolved> <count>".
    _jq="$(fn "$_b" thread_fingerprint | python3 -c "import re,sys; print(re.search(r\"--jq '([^']*)'\", sys.stdin.read()).group(1))")"
    _got="$(printf '%s' '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"id":"T1","isResolved":true,"comments":{"totalCount":3,"nodes":[{"id":"C9","updatedAt":"U9"}]}},{"id":"T2","isResolved":false,"comments":{"totalCount":0,"nodes":[]}}]}}}}}' | jq -r "$_jq" 2>&1)" || :
    [ "$_got" = "T1 true 3 C9 U9
T2 false 0 null null" ] || fail "259: $_b fingerprint jq does not print '<id> <isResolved> <totalCount> <last id> <updatedAt>' per thread (got: $_got)"
    block "$_b" 'echo handback > "$round_dir/disposed"' > "$T/hb.sh" || fail "setup: no hand-back block in $_b"
    block "$_b" '--match-head-commit "$reviewed_head"' > "$T/merge.sh" || fail "setup: no merge block in $_b"
    block "$_b" 'merge_ok=0 ' > "$T/res.sh" || fail "setup: no resolve block in $_b"
    python3 - "$T/res.sh" "$T/hb.sh" "$T/merge.sh" <<'PY' || fail "259: $_b fingerprint is not snapshotted at the right place"
import sys
res, hb, mg = (open(a).read() for a in sys.argv[1:4])
assert res.index('resolveReviewThread(input') < res.index('_mg_fp_pre="$(thread_fingerprint)"') < res.index('merge_ok=1')
assert hb.index('_hb_fp_pre="$(thread_fingerprint)"') < hb.index('ci_required_gate') < hb.index('_hb_fp_post="$(thread_fingerprint)"')
assert mg.index('ci_required_gate') < mg.index('_fp_after="$(thread_fingerprint)"') < mg.index('mut gh pr merge')
PY
    python3 - "$_b" "$PRVIEW_FIELDS" <<'PYF' || fail "256: $_b asks gh pr view --json for a field real gh rejects (e.g. isInMergeQueue)"
import re, sys
body, ok = open(sys.argv[1]).read(), set(sys.argv[2].split())
body = re.sub(r"\\\n\s*", " ", body)
bad = [f for m in re.finditer(r"gh pr view[^\n]*?--json ([A-Za-z,]+)", body) for f in m.group(1).split(",") if f not in ok]
sys.exit(1 if bad else 0)
PYF
    # ── hand-back ───────────────────────────────────────────────────────────────
    # <name>|<fp before>|<fp after>|<threads>: growth on an UNRESOLVED thread (scan line
    # unchanged), growth on a RESOLVED thread (not in the scan at all), a resolve flip, a
    # brand-new resolved thread.
    for _c in "unres|PRRT_a false 1|PRRT_a false 2|true PRRT_a" \
              "res|PRRT_a true 1|PRRT_a true 2|" \
              "flip|PRRT_a true 1|PRRT_a false 1|" \
              "lastid|PRRT_a true 2 C1 U1|PRRT_a true 2 C2 U1|" \
              "edit|PRRT_a true 2 C1 U1|PRRT_a true 2 C1 U2|" \
              "new|PRRT_a true 1|PRRT_a true 1;PRRT_b true 1|"; do
      _n="${_c%%|*}"; _r="${_c#*|}"; _pre="${_r%%|*}"; _r="${_r#*|}"; _post="${_r%%|*}"; _thr="${_r#*|}"
      _e="$T/hb-fp-$_n"; rm -rf "$_e"; mk_env "$_e" "$_H"
      printf '%s\n' "$_pre" > "$_e/fp"; printf '%s\n' "$_post" | tr ';' '\n' > "$_e/fp_next"
      [ -z "$_thr" ] || printf '%s\n' "$_thr" > "$_e/threads"
      run_block "$_e" "$T/hb.sh" ''
      grep -q 'pr comment' "$_e/gh.log" && fail "259: $_b hand-back posted green over late input ($_n) during the CI wait"
      [ "$(cat "$_e/round/disposed" 2>/dev/null)" = stale ] \
        || fail "259: $_b hand-back refusal ($_n) does not mark the round stale for a fresh review"
      grep -q 'add-label needs-human' "$_e/gh.log" || fail "259: $_b hand-back refusal ($_n) is not needs-human"
      [ "$(cut -d' ' -f2 "$_e/result")" = 0 ] || fail "259: $_b hand-back refusal ($_n) did not return failure"
    done
    # An unchanged fingerprint (non-empty) still completes.
    _e="$T/hb-fp-same"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'PRRT_a true 3\nPRRT_b false 1\n' > "$_e/fp"
    run_block "$_e" "$T/hb.sh" ''
    [ "$(cat "$_e/round/disposed" 2>/dev/null)" = handback ] \
      || fail "259: $_b hand-back refused although the fingerprint did not change"
    # A failed scan fails closed: before the wait, and after it.
    _e="$T/hb-fp-fail-pre"; rm -rf "$_e"; mk_env "$_e" "$_H"
    touch "$_e/fp_fail"
    run_block "$_e" "$T/hb.sh" ''
    grep -q 'pr comment' "$_e/gh.log" && fail "259: $_b hand-back posted green with an unreadable fingerprint"
    # ...and a failed scan BEFORE the wait refuses on its own when the post-wait scan succeeds.
    _e="$T/hb-fp-fail-pre-only"; rm -rf "$_e"; mk_env "$_e" "$_H"
    touch "$_e/fp_fail" "$_e/fp_fail_clear"
    run_block "$_e" "$T/hb.sh" ''
    grep -q 'pr comment' "$_e/gh.log" && fail "259: $_b hand-back posted green although the pre-wait fingerprint scan failed (post succeeded)"
    _e="$T/hb-fp-fail-post"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'PRRT_a true 1\n' > "$_e/fp"; touch "$_e/fp_fail_next"
    run_block "$_e" "$T/hb.sh" ''
    grep -q 'pr comment' "$_e/gh.log" && fail "259: $_b hand-back posted green after the post-wait fingerprint scan failed"
    [ "$(cat "$_e/round/disposed" 2>/dev/null)" = stale ] \
      || fail "259: $_b failed post-wait fingerprint scan does not mark the round stale"
    # …also when the snapshot BEFORE the wait was legitimately empty (no threads yet): an
    # empty post-wait string from a FAILED scan must not equal it.
    _e="$T/hb-fp-fail-post-empty"; rm -rf "$_e"; mk_env "$_e" "$_H"
    : > "$_e/fp"; touch "$_e/fp_fail_next"
    run_block "$_e" "$T/hb.sh" ''
    grep -q 'pr comment' "$_e/gh.log" && fail "259: $_b hand-back posted green after a FAILED post-wait scan that equals an empty snapshot"
    # Dry run: refused, but nothing is labelled or marked.
    _e="$T/hb-fp-dry"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'PRRT_a true 1\n' > "$_e/fp"; printf 'PRRT_a true 2\n' > "$_e/fp_next"
    run_block "$_e" "$T/hb.sh" 'HARNESS_DRY_RUN=1'
    grep -q 'pr comment\|pr edit' "$_e/gh.log" && fail "259: $_b dry-run fingerprint refusal mutated the PR"
    [ -e "$_e/round/disposed" ] && fail "259: $_b dry-run fingerprint refusal wrote a marker"

    # ── auto-merge ──────────────────────────────────────────────────────────────
    for _c in "unres|PRRT_a false 1|PRRT_a false 2" "res|PRRT_a true 1|PRRT_a true 2" "flip|PRRT_a true 1|PRRT_a false 1" \
              "lastid|PRRT_a true 2 C1 U1|PRRT_a true 2 C2 U1" "edit|PRRT_a true 2 C1 U1|PRRT_a true 2 C1 U2"; do
      _n="${_c%%|*}"; _r="${_c#*|}"; _pre="${_r%%|*}"; _post="${_r#*|}"
      _e="$T/mg-fp-$_n"; rm -rf "$_e"; mk_env "$_e" "$_H"
      printf '%s\n' "$_post" > "$_e/fp_next"; printf '%s\n' "$_pre" > "$_e/fp"
      # the vetted Codex threads were resolved: the unresolved scan is empty at both ends.
      run_block "$_e" "$T/merge.sh" "merge_ok=1; _mg_fp_pre='$_pre'"
      grep -q 'pr merge' "$_e/gh.log" && fail "259: $_b merged over late input ($_n) added during the CI wait"
      [ "$(cat "$_e/round/disposed" 2>/dev/null)" = stale ] \
        || fail "259: $_b merge refusal ($_n) does not mark the round stale"
      grep -q 'add-label needs-human' "$_e/gh.log" || fail "259: $_b merge refusal ($_n) is not needs-human"
    done
    _e="$T/mg-fp-same"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'PRRT_a true 2\n' > "$_e/fp"
    run_block "$_e" "$T/merge.sh" "merge_ok=1; _mg_fp_pre='PRRT_a true 2'"
    grep -q 'pr merge' "$_e/gh.log" || fail "259: $_b refused to merge although the fingerprint did not change"
    # An unreadable post-wait scan, and a MISSING pre-wait snapshot, both fail closed.
    _e="$T/mg-fp-failpost"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'PRRT_a true 2\n' > "$_e/fp"; touch "$_e/fp_fail_next"
    run_block "$_e" "$T/merge.sh" "merge_ok=1; _mg_fp_pre='PRRT_a true 2'"
    grep -q 'pr merge' "$_e/gh.log" && fail "259: $_b merged although the post-wait fingerprint scan failed"
    _e="$T/mg-fp-failpost-empty"; rm -rf "$_e"; mk_env "$_e" "$_H"
    : > "$_e/fp"; touch "$_e/fp_fail_next"
    run_block "$_e" "$T/merge.sh" "merge_ok=1; _mg_fp_pre="
    grep -q 'pr merge' "$_e/gh.log" && fail "259: $_b merged after a FAILED post-wait scan that equals an empty snapshot"
    _e="$T/mg-fp-nosnap"; rm -rf "$_e"; mk_env "$_e" "$_H"
    : > "$_e/fp"
    run_block "$_e" "$T/merge.sh" "merge_ok=1; unset _mg_fp_pre"
    grep -q 'pr merge' "$_e/gh.log" && fail "259: $_b merged with no pre-wait fingerprint snapshot (empty == unset must not pass)"
    # Dry run: the same refusal, no mutation.
    _e="$T/mg-fp-dry"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'PRRT_a true 1\n' > "$_e/fp"; printf 'PRRT_a true 2\n' > "$_e/fp_next"
    run_block "$_e" "$T/merge.sh" "merge_ok=1; _mg_fp_pre='PRRT_a true 1'; HARNESS_DRY_RUN=1"
    grep -q 'would merge' "$_e/err" && fail "259: $_b dry run says it would merge over late input"
    grep -q 'pr edit\|pr merge' "$_e/gh.log" && fail "259: $_b dry-run fingerprint refusal mutated the PR"

    # ── the snapshot itself: taken AFTER the resolves, fail closed ────────────────
    { printf 'owner=o; repo=r; pr_number=7\n'; cat "$T/res.sh"; } > "$T/res2.sh"
    _e="$T/res-ok"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'true PRRT_c\n' > "$_e/threads"; printf 'PRRT_c false 1\n' > "$_e/fp"
    printf 'PRRT_c true 1\n' > "$_e/fp_after_resolve"
    run_res "$_e"
    [ "$(cat "$_e/res.out" 2>/dev/null)" = "1|PRRT_c true 1" ] \
      || fail "259: $_b snapshot is not the post-resolve state, or merge_ok not raised (got '$(cat "$_e/res.out" 2>/dev/null)')"
    _e="$T/res-fpfail"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'true PRRT_c\n' > "$_e/threads"; touch "$_e/fp_fail"
    run_res "$_e"
    [ "$(cut -d'|' -f1 "$_e/res.out" 2>/dev/null)" = 0 ] \
      || fail "259: $_b merge_ok raised although the thread fingerprint could not be read"
  done
  pass "259 late review input: a fingerprint of EVERY thread must be unchanged across the CI wait on both terminal paths; any change or failed scan refuses green (all bodies)"
}

# run_res <env> — run the resolve block (res2.sh) in the sandbox; leaves "<merge_ok>|<fp>".
run_res() {
  ( cd "$1" && PATH="$1/bin:$PATH" HARNESS_DRY_RUN=0 sh -c "$(cat "$T/mut.sh")
$(cat "$T/res2.sh")
printf '%s|%s\\n' \"\$merge_ok\" \"\$_mg_fp_pre\" > res.out" ) >/dev/null 2>&1 || :
}

# ══ #256 — a queued merge is reconciled, then cancelled, before needs-human ═════════════
test_queued_merge_never_left_live() {
  have_jq || { skip "queued_merge_never_left_live (jq not installed)"; return 0; }
  _H=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  for _b in $BODIES; do
    lift_fns "$_b"
    block "$_b" '--match-head-commit "$reviewed_head"' > "$T/merge.sh" || fail "setup: no merge block in $_b"
    # The state read's REAL jq, over GraphQL-shaped answers (the stub returns canned text).
    _qjq="$(fn "$_b" queued_merge_reconcile | python3 -c "import re,sys; print(re.search(r\"--jq '(\\.data[^']*)'\", sys.stdin.read()).group(1))")"
    for _s in 'OPEN|null|false|OPEN false false' 'OPEN|{"enabledAt":"t"}|false|OPEN true false' 'OPEN|null|true|OPEN false true' 'MERGED|null|false|MERGED false false'; do
      _st="${_s%%|*}"; _r="${_s#*|}"; _am="${_r%%|*}"; _r="${_r#*|}"; _iq="${_r%%|*}"; _want="${_r#*|}"
      _got="$(printf '{"data":{"repository":{"pullRequest":{"state":"%s","isInMergeQueue":%s,"autoMergeRequest":%s}}}}' "$_st" "$_iq" "$_am" | jq -r "$_qjq" 2>&1)" || :
      [ "$_got" = "$_want" ] || fail "256: $_b merge-state jq read '$_want' as '$_got'"
    done
    block "$_b" 'queued_merge_reconcile() {' > "$T/q.sh" || fail "setup: no queued-merge reconcile block in $_b"
    cat "$T/merge.sh" "$T/q.sh" > "$T/mq.sh"
    grep -qF '${HARNESS_QUEUE_RECONCILE_CEILING:-300}' "$T/q.sh" \
      || fail "256: $_b reconcile wait is not the documented HARNESS_QUEUE_RECONCILE_CEILING (default 300s)"
    _Q='merge_ok=1; _mg_fp_pre=; HARNESS_QUEUE_RECONCILE_CEILING=2'
    # merge exits 0, mergedAt stays null, the cancel HOLDS: reconcile first, then cancel
    # through gh (disable-auto + dequeue), then re-read; a quiet needs-human (no merged).
    _e="$T/q-held"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'OPEN  \n' > "$_e/mvstate"; printf 'OPEN false false\n' > "$_e/qstate"
    run_block "$_e" "$T/mq.sh" "$_Q"
    grep -q 'pr merge 7 --disable-auto' "$_e/gh.log" || fail "256: $_b a still-queued merge was never cancelled (--disable-auto)"
    grep -q 'dequeuePullRequest' "$_e/gh.log" || fail "256: $_b a still-queued merge was never dequeued (merge queue)"
    grep -q 'id=PR_NODE_7' "$_e/gh.log" || fail "256: $_b dequeue is not aimed at the PR node id"
    [ "$(cut -d' ' -f1 "$_e/result")" = 1 ] && fail "256: $_b reached merged=1 for a PR that never merged"
    python3 - "$_e/gh.log" <<'PY' || fail "256: $_b cancels without first reconciling (waiting for the queue), or never re-reads the state after"
import sys
L = open(sys.argv[1]).read().split("\n")
c = next(i for i, l in enumerate(L) if '--disable-auto' in l)
assert sum('state,mergedAt,mergeCommit' in l for l in L[:c]) >= 4      # 1st receipt + reconcile wait
assert any('isInMergeQueue' in l for l in L[c:])               # re-read after the cancel
PY
    grep -q 'pr comment.*may still be queued' "$_e/gh.log" && fail "256: $_b warned 'may still be queued' although the cancel was verified"
    grep -q 'pr comment.*cancel was confirmed' "$_e/gh.log" || fail "256: $_b hand-over does not say the cancel was confirmed"
    # The cancel could not be CONFIRMED (still armed / unreadable / calls failing): say so.
    for _qs in "OPEN true false" "OPEN false true" "" "weird"; do
      _e="$T/q-unconfirmed"; rm -rf "$_e"; mk_env "$_e" "$_H"
      printf 'OPEN  \n' > "$_e/mvstate"; printf '%s\n' "$_qs" > "$_e/qstate"; touch "$_e/cancel_fail"
      run_block "$_e" "$T/mq.sh" "$_Q"
      grep -q 'pr comment.*may still be queued' "$_e/gh.log" \
        || fail "256: $_b cancel not confirmed ('$_qs') but the hand-off does not say a merge request may still be queued"
      [ "$(cut -d' ' -f1 "$_e/result")" = 1 ] && fail "256: $_b reached merged=1 after an unconfirmed cancel ('$_qs')"
    done
    # CLOSED after the cancel: nothing live, no scary warning.
    _e="$T/q-closed"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'OPEN  \n' > "$_e/mvstate"; printf 'CLOSED false false\n' > "$_e/qstate"
    run_block "$_e" "$T/mq.sh" "$_Q"
    grep -q 'pr comment.*may still be queued' "$_e/gh.log" && fail "256: $_b warned about a live request on a CLOSED PR"
    grep -q 'pr comment.*nothing is queued; the PR is CLOSED' "$_e/gh.log" || fail "256: $_b CLOSED hand-over does not say nothing is queued"
    grep -q 'pr comment.*cancel was confirmed' "$_e/gh.log" && fail "256: $_b CLOSED hand-over claims a cancel"
    # The queue MERGES during the reconcile wait: merged path, no cancel at all.
    _e="$T/q-late"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'OPEN  \nOPEN  \nOPEN  \nMERGED 2026-10-10T00:00:00Z bbbb\n' > "$_e/mvstate"
    run_block "$_e" "$T/mq.sh" "$_Q"
    [ "$(cut -d' ' -f1 "$_e/result")" = 1 ] || fail "256: $_b a queue that merged during the reconcile did not reach merged=1"
    grep -q -e '--disable-auto\|dequeuePullRequest' "$_e/gh.log" && fail "256: $_b cancelled a request that had already merged"
    # The queue merges while we cancel: the re-read says MERGED => merged path, not needs-human.
    _e="$T/q-race"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'OPEN  \n' > "$_e/mvstate"; touch "$_e/mv_after_cancel"; printf 'MERGED true false\n' > "$_e/qstate"
    run_block "$_e" "$T/mq.sh" "$_Q"
    [ "$(cut -d' ' -f1 "$_e/result")" = 1 ] || fail "256: $_b a merge that won the race against the cancel did not reach merged=1"
    grep -q 'pr comment' "$_e/gh.log" && fail "256: $_b warned 'may still be queued' for a PR that merged"
    # A CLOSED-unmerged receipt (7) is NOT a queued request: no cancel attempted.
    _e="$T/q-closedrc"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'CLOSED  \n' > "$_e/mvstate"
    run_block "$_e" "$T/mq.sh" "$_Q"
    grep -q -e '--disable-auto\|dequeuePullRequest' "$_e/gh.log" && fail "256: $_b ran the queue-cancel path for a CLOSED PR (receipt 7)"
    [ "$(cut -d' ' -f1 "$_e/result")" = 1 ] && fail "256: $_b reached merged=1 for a CLOSED PR"
    # A normal landing never touches the cancel path.
    _e="$T/q-normal"; rm -rf "$_e"; mk_env "$_e" "$_H"
    run_block "$_e" "$T/mq.sh" "$_Q"
    [ "$(cut -d' ' -f1 "$_e/result")" = 1 ] || fail "256: $_b a normal merge no longer reaches merged=1"
    grep -q -e '--disable-auto\|dequeuePullRequest' "$_e/gh.log" && fail "256: $_b cancel path ran after a normal landing"
    # Dry run: the cancel goes through `mut` — no disable-auto, no dequeue, no comment.
    _e="$T/q-dry"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'OPEN  \n' > "$_e/mvstate"; printf 'OPEN true false\n' > "$_e/qstate"
    run_block "$_e" "$T/q.sh" "merged=0; _mv_rc=11; HARNESS_QUEUE_RECONCILE_CEILING=2; HARNESS_DRY_RUN=1"
    grep -q 'pr merge\|dequeuePullRequest\|pr comment\|pr edit' "$_e/gh.log" \
      && fail "256: $_b dry-run queue reconcile mutated the PR"
    # …and so does the CONFIRMED-cancel hand-over comment (state "held").
    _e="$T/q-dry-held"; rm -rf "$_e"; mk_env "$_e" "$_H"
    printf 'OPEN  \n' > "$_e/mvstate"; printf 'OPEN false false\n' > "$_e/qstate"
    run_block "$_e" "$T/q.sh" "merged=0; _mv_rc=11; HARNESS_QUEUE_RECONCILE_CEILING=2; HARNESS_DRY_RUN=1"
    grep -q 'pr comment' "$_e/gh.log" && fail "256: $_b dry-run confirmed-cancel hand-over comment is not routed through mut"
  done
  pass "256 queued merge: post receipt 11 => reconcile then cancel via mut, re-read, MERGED => merged path, unconfirmed cancel says so, dry run read-only (all bodies)"
}

test_handback_revalidates_head
test_required_ci_gates_terminal_paths
test_dry_run_suppresses_every_mutation
test_resume_skips_completed_fixers
test_late_comments_refuse_green
test_queued_merge_never_left_live
echo "All pr-loop hardening tests passed."
