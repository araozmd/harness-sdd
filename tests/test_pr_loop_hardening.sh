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
case "\$*" in
  *"--json headRefOid"*) echo "$2" ;;
  *"--json state,mergedAt,mergeCommit"*) echo "MERGED 2026-10-10T00:00:00Z bbbb" ;;
  *"--json baseRefName"*) cat "$_e/base" 2>/dev/null || echo main ;;
  *"defaultBranchRef"*) echo main ;;
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
pr_number=7; round_dir=round; pr_cache=.; default_branch=main; $_pre
$(cat "$_sn")
printf '%s\n' \"\${merged:-unset} \${handback_ok:-unset}\" > result" ) >/dev/null 2>"$_rd/err" || :
}

# ══ P1 — the hand-back revalidates the reviewed head before it claims anything ══════
test_handback_revalidates_head() {
  have_jq || { skip "handback_revalidates_head (jq not installed)"; return 0; }
  for _b in $BODIES; do
    fn "$_b" mut > "$T/mut.sh"; fn "$_b" ci_required_gate > "$T/ci.sh"
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
        if "resolveReviewThread" in code and "mut gh api graphql" not in lines[i - 1]:
            bad.append(line.strip())
for b in bad: print("unwrapped:", b, file=sys.stderr)
sys.exit(1 if bad else 0)
PY
    grep -qF '.pr-loop/dry-run/$pr_number"' "$_b" \
      || fail "P1 dry-run: $_b dry run writes into the real round cache (budget + handback poisoning)"
    grep -qF 'spawn no fixer' "$_b" || fail "P1 dry-run: $_b still dispatches fixers (they commit) on a dry run"
    # Executed: the wrapper skips under HARNESS_DRY_RUN=1 and runs otherwise.
    fn "$_b" mut > "$T/mut.sh"; fn "$_b" ci_required_gate > "$T/ci.sh"
    _m="$T/mutx"; rm -rf "$_m"; mkdir -p "$_m"
    ( . "$T/mut.sh"; HARNESS_DRY_RUN=1; mut touch "$_m/dry" ) 2>/dev/null
    [ -e "$_m/dry" ] && fail "P1 dry-run: $_b mut ran a mutation under HARNESS_DRY_RUN=1"
    ( . "$T/mut.sh"; HARNESS_DRY_RUN=0; mut touch "$_m/real" ) 2>/dev/null
    [ -e "$_m/real" ] || fail "P1 dry-run: $_b mut does not run the command on a real run"
  done
  # Executed: the merge block on a dry run merges NOTHING; on a real run it merges.
  if have_jq; then
    for _b in $BODIES; do
      fn "$_b" mut > "$T/mut.sh"; fn "$_b" ci_required_gate > "$T/ci.sh"
      block "$_b" '--match-head-commit "$reviewed_head"' > "$T/merge.sh" || fail "setup: no merge block in $_b"
      _e="$T/mg-dry"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      run_block "$_e" "$T/merge.sh" 'merge_ok=1; HARNESS_DRY_RUN=1'
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
      run_block "$_e" "$T/merge.sh" 'merge_ok=1; HARNESS_DRY_RUN=0'
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
    fn "$_b" mut > "$T/mut.sh"; fn "$_b" ci_required_gate > "$T/ci.sh"
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
      run_block "$_e" "$T/merge.sh" 'merge_ok=1'
      grep -q 'pr merge' "$_e/gh.log" && fail "CI: $_b auto-merged with required CI $_mode"
      [ "$(cut -d' ' -f1 "$_e/result")" = 1 ] && fail "CI: $_b reached merged=1 with required CI $_mode"
      [ -e "$_e/round/disposed" ] && fail "CI: $_b red-CI merge refusal wrote a disposed marker"
      grep -q 'add-label needs-human' "$_e/gh.log" \
        || fail "CI: $_b merge refused on required CI $_mode is not routed to needs-human"
    done
    _e="$T/mg-ci-dry"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    echo fail > "$_e/ci"
    run_block "$_e" "$T/merge.sh" 'merge_ok=1; HARNESS_DRY_RUN=1'
    grep -q 'would merge' "$_e/err" && fail "CI: $_b dry run claims it would merge over red required CI"
    grep -q 'pr edit\|pr merge' "$_e/gh.log" && fail "CI: $_b dry-run red-CI merge mutated the PR"
    _e="$T/mg-ci-pass"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    printf 'pending\npass\n' > "$_e/ci"
    run_block "$_e" "$T/merge.sh" 'merge_ok=1'
    grep -q 'pr merge' "$_e/gh.log" || fail "CI: $_b never merged once required CI turned green"
  done
  pass "P1 required CI: hand-back and auto-merge wait on required checks; red/pending-at-ceiling ⇒ needs-human, no green post, no marker, no merge (all bodies)"
}

test_handback_revalidates_head
test_required_ci_gates_terminal_paths
test_dry_run_suppresses_every_mutation
test_resume_skips_completed_fixers
echo "All pr-loop hardening tests passed."
