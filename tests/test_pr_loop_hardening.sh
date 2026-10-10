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
  *"--json baseRefName"*|*"defaultBranchRef"*) echo main ;;
  *"pr comment"*) echo "https://github.com/o/r/pull/7#issuecomment-1" ;;
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
      sh -c "$(cat "$T/mut.sh")
pr_number=7; round_dir=round; pr_cache=.; default_branch=main; $_pre
$(cat "$_sn")
printf '%s\n' \"\${merged:-unset} \${handback_ok:-unset}\" > result" ) >/dev/null 2>"$_rd/err" || :
}

# ══ P1 — the hand-back revalidates the reviewed head before it claims anything ══════
test_handback_revalidates_head() {
  have_jq || { skip "handback_revalidates_head (jq not installed)"; return 0; }
  for _b in $BODIES; do
    fn "$_b" mut > "$T/mut.sh"
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
    fn "$_b" mut > "$T/mut.sh"
    _m="$T/mutx"; rm -rf "$_m"; mkdir -p "$_m"
    ( . "$T/mut.sh"; HARNESS_DRY_RUN=1; mut touch "$_m/dry" ) 2>/dev/null
    [ -e "$_m/dry" ] && fail "P1 dry-run: $_b mut ran a mutation under HARNESS_DRY_RUN=1"
    ( . "$T/mut.sh"; HARNESS_DRY_RUN=0; mut touch "$_m/real" ) 2>/dev/null
    [ -e "$_m/real" ] || fail "P1 dry-run: $_b mut does not run the command on a real run"
  done
  # Executed: the merge block on a dry run merges NOTHING; on a real run it merges.
  if have_jq; then
    for _b in $BODIES; do
      fn "$_b" mut > "$T/mut.sh"
      block "$_b" '--match-head-commit "$reviewed_head"' > "$T/merge.sh" || fail "setup: no merge block in $_b"
      _e="$T/mg-dry"; rm -rf "$_e"; mk_env "$_e" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      run_block "$_e" "$T/merge.sh" 'merge_ok=1; HARNESS_DRY_RUN=1'
      grep -q 'pr merge' "$_e/gh.log" && fail "P1 dry-run: $_b merged a PR under HARNESS_DRY_RUN=1"
      grep -q 'pr edit' "$_e/gh.log" && fail "P1 dry-run: $_b labelled a PR under HARNESS_DRY_RUN=1"
      [ "$(cut -d' ' -f1 "$_e/result")" = 1 ] \
        && fail "P1 dry-run: $_b reached merged=1 on a dry run — the merge path ran instead of stopping"
      grep -q 'DRY-RUN — would merge' "$_e/err" \
        || fail "P1 dry-run: $_b dry run does not say what it would have merged"
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

test_handback_revalidates_head
test_dry_run_suppresses_every_mutation
test_resume_skips_completed_fixers
echo "All pr-loop hardening tests passed."
