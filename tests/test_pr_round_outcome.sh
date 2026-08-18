#!/bin/sh
# test_pr_round_outcome.sh — E99-F126 + E99-F116: a round's OUTCOME is stated, not inferred
# from the length of an array, and the trend counts what the loop ACTUALLY treated as
# blocking rather than what the configured severity filter would have kept.
#
# Both defects were measured, and both live in one file, `round-<n>/blocking.json`:
#
#   E99-F126  an empty array meant two opposite things. On araozmd/harness-sdd#141 the rounds
#             went 2 blocking → round 2 WATCHER TIMEOUT (exit 2, zero Codex activity) → 2
#             blocking; recording the timed-out round as `[]` made pr-round-trend.sh answer
#             "converging — one more round is rational". Deleting that one file changed the
#             verdict. The flat 2,2 was the honest signal and the tool never saw it.
#
#   E99-F116  on viernes-ai/viernes-web PR #85 three consecutive Codex P2s were each judged
#             blocking and fixed, but P2 sat outside pr_loop.blocking_severities, so every
#             blocking.json was empty and the tool reported "nothing to trend" through a
#             textbook non-converging run.
#
# The assertions here are about the VERDICT, the EXIT CODE and the machine interface, never
# about phrasing — except where the report's job IS to say something (a timeout that is not
# named has been dropped, which is the defect).
#
# Zero dependencies beyond POSIX sh; self-cleaning temp dir. Parses and runs under /bin/dash.

set -eu
LC_ALL=C; export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TREND="$SRC/tools/pr-round-trend.sh"
GATE="$SRC/tools/pr-gate.sh"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-pro)"
trap 'rm -rf "$T"' EXIT INT TERM

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }
skip() { echo "skip - $1"; }
have_jq() { command -v jq >/dev/null 2>&1; }

BOT='chatgpt-codex-connector'
SINCE='2026-08-01T00:00:00Z'
LATER='2026-08-01T00:05:00Z'

# ── fixture builders ─────────────────────────────────────────────────────────────
# reviewed <round-dir> <head> <n-findings> — the four watcher artifacts for a round where
# Codex really answered. `wait-for-codex.sh evaluate` resolves these OFFLINE, which is what
# lets the trend derive an outcome for a cache written before `outcome` existed.
reviewed() {
  _rd="$1"; _rh="$2"; _rn="$3"; mkdir -p "$_rd"
  printf '%s\n' "$SINCE" > "$_rd/trigger-ts.txt"
  printf '[]' > "$_rd/reactions.json"
  printf '[]' > "$_rd/issue-comments.json"
  printf '{"headRefOid":"%s","reviews":[]}' "$_rh" > "$_rd/pr.json"
  _ri=1
  printf '[' > "$_rd/review-comments.json"
  while [ "$_ri" -le "$_rn" ]; do
    [ "$_ri" = 1 ] || printf ',' >> "$_rd/review-comments.json"
    printf '{"id":%s,"user":{"login":"%s"},"commit_id":"%s","created_at":"%s","path":"src/one.ts","line":%s,"body":"P1 finding %s"}' \
      "$_ri" "$BOT" "$_rh" "$LATER" "$((100 + _ri))" "$_ri" >> "$_rd/review-comments.json"
    _ri=$((_ri + 1))
  done
  printf ']' >> "$_rd/review-comments.json"
}

# timed_out <round-dir> <head> — what the watcher leaves behind when it polls to the ceiling
# and exits 2: every source file staged, and not one word from Codex in any of them.
timed_out() {
  _td="$1"; _th="$2"; mkdir -p "$_td"
  printf '%s\n' "$SINCE" > "$_td/trigger-ts.txt"
  printf '[]' > "$_td/reactions.json"
  printf '[]' > "$_td/issue-comments.json"
  printf '[]' > "$_td/review-comments.json"
  printf '{"headRefOid":"%s","reviews":[]}' "$_th" > "$_td/pr.json"
}

# findings_json <n> <path> — n rows, the shape blocking.json/acted.json carry.
findings_json() {
  _fn="$1"; _fp="$2"; _fi=1
  printf '['
  while [ "$_fi" -le "$_fn" ]; do
    [ "$_fi" = 1 ] || printf ','
    printf '{"id":%s,"path":"%s","line":%s,"severity":"P1","override":false}' "$_fi" "$_fp" "$((10 + _fi))"
    _fi=$((_fi + 1))
  done
  printf ']'
}

verdict_of() { sh "$TREND" --cache "$1" --format json | sed -n 's/.*"verdict":"\([a-z-]*\)".*/\1/p'; }
jqf() { sh "$TREND" --cache "$1" --format json | jq -r "$2"; }

# ══ E99-F126 ═══════════════════════════════════════════════════════════════════════

test_recorded_timeout_is_not_a_clean_round() {
  have_jq || { skip "recorded_timeout_is_not_a_clean_round (jq not installed)"; return 0; }
  # The #141 shape, as the REPAIRED loop writes it: the timed-out round states its outcome
  # and classifies nothing, because nothing was reviewed.
  _c="$T/f126-recorded"
  reviewed "$_c/round-1" aaaaaaa1 2; findings_json 2 src/one.ts > "$_c/round-1/blocking.json"
  printf 'findings\n' > "$_c/round-1/outcome"
  timed_out "$_c/round-2" bbbbbbb2; printf 'timeout\n' > "$_c/round-2/outcome"
  reviewed "$_c/round-3" ccccccc3 2; findings_json 2 src/one.ts > "$_c/round-3/blocking.json"
  printf 'findings\n' > "$_c/round-3/outcome"

  [ "$(verdict_of "$_c")" != "converging" ] \
    || fail "E99-F126: 2 → TIMEOUT → 2 still reads 'converging' — the timed-out round is being counted as a clean round"
  [ "$(jqf "$_c" '.series | join(",")')" = "2,2" ] \
    || fail "E99-F126: the rate is $(jqf "$_c" '.series|join(",")'), expected 2,2 — only REVIEWED rounds may enter the rate"
  [ "$(jqf "$_c" '.round_ids | join(",")')" = "1,3" ] \
    || fail "E99-F126: the rate included round 2, which was never reviewed"

  # NOT DROPPED EITHER. Silently omitting the round would answer `insufficient` while hiding
  # a run that is failing to get reviewed at all — the board item names that as the wrong fix.
  [ "$(jqf "$_c" '.not_reviewed | length')" = "1" ] \
    || fail "E99-F126: the timed-out round is not reported — it was dropped, not reported separately"
  [ "$(jqf "$_c" '.not_reviewed[0].round')" = "2" ] \
    || fail "E99-F126: the not_reviewed report names round $(jqf "$_c" '.not_reviewed[0].round'), expected 2"
  [ "$(jqf "$_c" '.not_reviewed[0].outcome')" = "timeout" ] \
    || fail "E99-F126: round 2 is reported as $(jqf "$_c" '.not_reviewed[0].outcome'), not as a timeout"
  [ "$(jqf "$_c" '.not_reviewed[0].source')" = "recorded" ] \
    || fail "E99-F126: the timeout was inferred, not read from the outcome the loop recorded"
  sh "$TREND" --cache "$_c" | grep -q 'NEVER REVIEWED' \
    || fail "E99-F126: the TEXT report — the one a human reads at the cap — never says a round went unreviewed"

  # The contrast that proves the assertion above detects the MECHANISM and not something
  # else: the same three rounds, recorded the way the loop USED to record them (a timeout
  # written as an empty blocking set, no outcome, no evidence), read `converging`.
  _o="$T/f126-old-shape"
  for _r in 1 2 3; do mkdir -p "$_o/round-$_r"; done
  findings_json 2 src/one.ts > "$_o/round-1/blocking.json"
  printf '[]' > "$_o/round-2/blocking.json"
  findings_json 2 src/one.ts > "$_o/round-3/blocking.json"
  [ "$(verdict_of "$_o")" = "converging" ] \
    || fail "E99-F126: the pre-fix shape no longer reads 'converging' — the contrast this test rests on is gone, so the assertion above proves nothing"
  pass "E99-F126 recorded_timeout_is_not_a_clean_round: 2/timeout/2 leaves the rate flat and REPORTS the timeout"
}

test_legacy_cache_derives_the_timeout_it_never_recorded() {
  have_jq || { skip "legacy_cache_derives_the_timeout_it_never_recorded (jq not installed)"; return 0; }
  # A cache written BEFORE `outcome` existed has no outcome file anywhere — but it does have
  # the watcher's own artifacts, so the same offline probe the MERGE gate uses can tell a
  # clean round from one that never resolved. Without this, every pre-existing cache keeps
  # reading its timeouts as clean rounds forever.
  _c="$T/f126-legacy"
  reviewed "$_c/round-1" aaaaaaa1 2; findings_json 2 src/one.ts > "$_c/round-1/blocking.json"
  timed_out "$_c/round-2" bbbbbbb2; printf '[]' > "$_c/round-2/blocking.json"
  reviewed "$_c/round-3" ccccccc3 2; findings_json 2 src/one.ts > "$_c/round-3/blocking.json"
  [ -e "$_c/round-2/outcome" ] && fail "E99-F126 setup: the legacy fixture must carry no outcome file"

  [ "$(verdict_of "$_c")" != "converging" ] \
    || fail "E99-F126: a LEGACY cache still reads 2/timeout/2 as converging"
  [ "$(jqf "$_c" '.not_reviewed[0].outcome')" = "timeout" ] \
    || fail "E99-F126: the timeout was not derived from the round's own watcher artifacts"
  [ "$(jqf "$_c" '.not_reviewed[0].source')" = "derived" ] \
    || fail "E99-F126: the derivation is reported as $(jqf "$_c" '.not_reviewed[0].source') — a derived outcome must not claim to be recorded"

  # And the derivation must not fire on a round that genuinely WAS clean: a legacy round with
  # a zero-findings banner on head is a real clean round and belongs in the rate as a 0.
  _k="$T/f126-legacy-clean"
  reviewed "$_k/round-1" aaaaaaa1 1; findings_json 1 src/one.ts > "$_k/round-1/blocking.json"
  mkdir -p "$_k/round-2"
  printf '%s\n' "$SINCE" > "$_k/round-2/trigger-ts.txt"
  printf '[]' > "$_k/round-2/review-comments.json"
  printf '[]' > "$_k/round-2/reactions.json"
  printf '[]' > "$_k/round-2/issue-comments.json"
  printf '{"headRefOid":"bbbbbbb2","reviews":[{"author":{"login":"%s"},"submittedAt":"%s","body":"Reviewed commit: bbbbbbb"}]}' \
    "$BOT" "$LATER" > "$_k/round-2/pr.json"
  printf '[]' > "$_k/round-2/blocking.json"
  [ "$(jqf "$_k" '.series | join(",")')" = "1,0" ] \
    || fail "E99-F126: a genuinely CLEAN legacy round was pushed out of the rate — the probe must separate clean from timed-out, not reject both"
  [ "$(jqf "$_k" '.not_reviewed | length')" = "0" ] \
    || fail "E99-F126: a clean round was reported as never reviewed"
  pass "E99-F126 legacy_cache_derives_the_timeout_it_never_recorded: clean and timed-out legacy rounds are told apart"
}

test_an_unrecorded_outcome_is_never_silently_clean() {
  have_jq || { skip "an_unrecorded_outcome_is_never_silently_clean (jq not installed)"; return 0; }
  # The residual ambiguity: an empty blocking set, no outcome file, and no watcher artifacts
  # to probe. Nothing can prove what that round was. It is still counted, so a pre-existing
  # cache keeps trending, but the report has to SAY the verdict rests on a round nobody
  # recorded — otherwise it is exactly the silent "counted as clean" that F126 is about.
  _c="$T/f126-unknown"
  for _r in 1 2 3; do mkdir -p "$_c/round-$_r"; done
  findings_json 3 src/one.ts > "$_c/round-1/blocking.json"
  findings_json 1 src/one.ts > "$_c/round-2/blocking.json"
  printf '[]' > "$_c/round-3/blocking.json"

  [ "$(jqf "$_c" '.unrecorded_rounds | join(",")')" = "3" ] \
    || fail "E99-F126: round 3 has no recorded outcome and is not named in unrecorded_rounds"
  [ "$(jqf "$_c" '.series | join(",")')" = "3,1,0" ] \
    || fail "E99-F126: a legacy cache stopped trending — backward compatibility broke"
  sh "$TREND" --cache "$_c" | grep -q 'no outcome was recorded' \
    || fail "E99-F126: the text report counts an unrecorded round without saying so"
  # A round WITH a recorded outcome must not be flagged — the caveat has to be earned, or it
  # is noise that operators learn to skip.
  printf 'clean\n' > "$_c/round-3/outcome"
  [ "$(jqf "$_c" '.unrecorded_rounds | length')" = "0" ] \
    || fail "E99-F126: a round that DID record its outcome is still flagged as unrecorded"
  pass "E99-F126 an_unrecorded_outcome_is_never_silently_clean: counted, but named"
}

# ══ E99-F116 ═══════════════════════════════════════════════════════════════════════

test_the_trend_counts_what_was_acted_on() {
  have_jq || { skip "the_trend_counts_what_was_acted_on (jq not installed)"; return 0; }
  # PR #85's shape: pr_loop.blocking_severities is P0,P1, every round's finding is a P2, and
  # every one of them was judged blocking and fixed. blocking.json is therefore `[]` in every
  # round — and the tool built to detect non-convergence said nothing for three rounds.
  _c="$T/f116-acted"
  _r=1
  while [ "$_r" -le 3 ]; do
    mkdir -p "$_c/round-$_r"
    printf 'findings\n' > "$_c/round-$_r/outcome"
    printf '[]' > "$_c/round-$_r/blocking.json"          # the CONFIGURED filter: nothing
    printf '[{"id":%s,"path":"src/page.tsx","line":%s,"severity":"P2","override":true}]' \
      "$_r" "$((180 + _r))" > "$_c/round-$_r/acted.json"  # what was ACTUALLY treated as blocking
    _r=$((_r + 1))
  done

  [ "$(verdict_of "$_c")" = "non-converging" ] \
    || fail "E99-F116: three rounds of overridden-severity findings read as $(verdict_of "$_c"), expected non-converging"
  [ "$(jqf "$_c" '.series | join(",")')" = "1,1,1" ] \
    || fail "E99-F116: the rate is $(jqf "$_c" '.series|join(",")') — it is still reading the configured filter, not what was acted on"
  # Severity survives PER ROW, so an override is visible AS an override rather than as an
  # unexplained finding the configuration says should not exist.
  [ "$(jqf "$_c" '.overrides')" = "3" ] \
    || fail "E99-F116: $(jqf "$_c" '.overrides') overrides reported, expected 3"
  [ "$(jqf "$_c" '.override_severities | join(",")')" = "P2" ] \
    || fail "E99-F116: the report does not name the severity that was overridden"
  sh "$TREND" --cache "$_c" | grep -q 'SEVERITY OVERRIDES' \
    || fail "E99-F116: the text report presents overridden findings as ordinary ones"
  [ "$(jqf "$_c" '.top_files[0].path')" = "src/page.tsx" ] \
    || fail "E99-F116: the concentration pass ignored acted.json, so the seams come from the empty configured set"

  # The contrast: strip acted.json and the very same cache goes quiet again — proving the
  # verdict above comes from acted.json and from nothing else.
  _r=1; while [ "$_r" -le 3 ]; do rm -f "$_c/round-$_r/acted.json"; _r=$((_r + 1)); done
  [ "$(verdict_of "$_c")" != "non-converging" ] \
    || fail "E99-F116: the non-converging verdict survives deleting every acted.json — it is not being produced by the file this feature adds"
  pass "E99-F116 the_trend_counts_what_was_acted_on: an overridden P2 is in the rate and named as an override"
}

test_the_merge_gate_still_reads_the_configured_filter() {
  have_jq || { skip "the_merge_gate_still_reads_the_configured_filter (jq not installed)"; return 0; }
  # acted.json must NOT leak into the merge decision. Whether a P2 blocks a MERGE is a
  # separate call from whether it counts as review work, and it stays conservative: the gate
  # reads blocking.json, which is filtered to pr_loop.blocking_severities.
  _d="$T/f116-gate/round-1"
  reviewed "$_d" aaaaaaa1 1                      # a real review landed, with one finding
  printf '[]' > "$_d/blocking.json"              # ...that the configured filter excluded
  printf '[{"id":1,"path":"src/page.tsx","severity":"P2","override":true}]' > "$_d/acted.json"
  printf 'findings\n' > "$_d/outcome"
  _rc=0
  _v="$(sh "$GATE" evaluate "$_d" --round 1 --max-rounds 4 2>/dev/null)" || _rc=$?
  [ "$_rc" = 0 ] && [ "$_v" = "merge" ] \
    || fail "E99-F116: the merge gate answered '$_v' (exit $_rc) — adding acted.json changed a merge decision it must not touch"
  pass "E99-F116 the_merge_gate_still_reads_the_configured_filter: acted.json changes the trend, never the gate"
}

# ══ the remedy has to be followable ════════════════════════════════════════════════

test_the_remedy_fits_the_diff() {
  have_jq || { skip "the_remedy_fits_the_diff (jq not installed)"; return 0; }
  # "SPLIT THIS PR" was right for the 17,202-addition diff this tool was built on. On PR #85
  # — 2 files, ~150 lines, all four findings in ONE function — it could not be followed, and
  # the operator overrode it by hand in the handover. Advice that cannot be followed teaches
  # operators to ignore the tool.
  _c="$T/remedy-one-file"
  _r=1
  while [ "$_r" -le 3 ]; do
    mkdir -p "$_c/round-$_r"; printf 'findings\n' > "$_c/round-$_r/outcome"
    findings_json 1 src/page.tsx > "$_c/round-$_r/blocking.json"
    _r=$((_r + 1))
  done
  [ "$(verdict_of "$_c")" = "non-converging" ] || fail "setup: the remedy fixture is not non-converging"

  # Told the diff is 2 files wide AND seeing every finding in one file, it must stop saying
  # split — there is no seam.
  sh "$TREND" --cache "$_c" --diff-files 2 --diff-lines 150 | grep -qi 'SPLIT THIS PR' \
    && fail "E99-F126/F116: a 2-file diff whose findings all land in ONE file is still told to SPLIT THIS PR" || :
  [ "$(sh "$TREND" --cache "$_c" --diff-files 2 --format json | jq -r '.remedy')" = "concentrate" ] \
    || fail "E99-F126/F116: --diff-files 2 with a single concentrating file did not switch the remedy"
  sh "$TREND" --cache "$_c" --diff-files 2 --diff-lines 150 | grep -q 'DO NOT SPLIT' \
    || fail "E99-F126/F116: the concentrated remedy does not tell the operator what to do instead"

  # The downgrade needs BOTH facts. Without the diff width the tool cannot know how wide the
  # diff is, so the split remedy stands — the pre-existing behaviour, unchanged.
  sh "$TREND" --cache "$_c" | grep -qi 'SPLIT THIS PR' \
    || fail "E99-F126/F116: the split remedy vanished when no diff width was supplied — the downgrade must be earned, not the default"
  # ...and a wide spread of findings is splittable however small the diff is.
  _m="$T/remedy-many-files"
  _r=1
  while [ "$_r" -le 3 ]; do
    mkdir -p "$_m/round-$_r"; printf 'findings\n' > "$_m/round-$_r/outcome"
    printf '[{"id":%s,"path":"src/a%s.ts","severity":"P1"}]' "$_r" "$_r" > "$_m/round-$_r/blocking.json"
    _r=$((_r + 1))
  done
  [ "$(sh "$TREND" --cache "$_m" --diff-files 2 --format json | jq -r '.remedy')" = "split" ] \
    || fail "E99-F126/F116: findings spread over three files were told not to split"
  pass "E99-F126/F116 the_remedy_fits_the_diff: split only where there is a seam to cut"
}

test_the_tool_stays_advisory() {
  have_jq || { skip "the_tool_stays_advisory (jq not installed)"; return 0; }
  # Every new report path must still exit 0. A trend that can fail a run is a gate, and this
  # tool is explicitly not one.
  _c="$T/advisory"
  timed_out "$_c/round-1" aaaaaaa1; printf 'timeout\n' > "$_c/round-1/outcome"
  sh "$TREND" --cache "$_c" >/dev/null 2>&1 \
    || fail "E99-F126: a cache with nothing but a timed-out round exited non-zero — the trend must never block"
  sh "$TREND" --cache "$_c" | grep -q 'NEVER REVIEWED' \
    || fail "E99-F126: with NO reviewed round at all the timeout is not reported — 'nothing to trend' hides a run that never got reviewed"
  sh "$TREND" --cache "$_c" --format json | jq -e '.not_reviewed | length == 1' >/dev/null \
    || fail "E99-F126: the machine interface drops the timeout when there is no rate to print"
  pass "E99-F126 the_tool_stays_advisory: exit 0 on every new path, and the timeout is reported even with no rate"
}

# ══ the runbook must WRITE what the trend now READS ═════════════════════════════════

# section <file> <heading-substring> — extract one section by heading. A whole-file grep is
# satisfied by any unrelated occurrence of the phrase (including one in a nearby section), so
# the assertion's failure message would name a guarantee it cannot detect.
#
# Fence-aware on purpose. This runbook is mostly ```bash blocks, and a shell COMMENT inside
# one (`# classify severities from fresh-comments.json …`) matches `^#+ ` just as a Markdown
# heading does. The naive one-liner therefore ended the section at the first commented line
# of the first code block and silently returned a fragment — an extractor that under-reads is
# as bad as a whole-file grep, in the opposite direction.
section() {
  awk -v h="$2" '
    /^```/    { fence = !fence; if (k) print; next }
    !fence && /^#+ / { k = (index($0, h) > 0); next }
    k
  ' "$1"
}

check_runbook() { # check_runbook <file> <label>
  _f="$1"; _l="$2"
  _s2b="$(section "$_f" 'Record the round')"
  [ -n "$_s2b" ] \
    || fail "$_l: no section instructs the loop to record the round's outcome — the trend would read a file nobody writes"
  printf '%s' "$_s2b" | grep -qF '$round_dir/outcome' \
    || fail "$_l: the outcome section never names \$round_dir/outcome"
  for _w in findings clean timeout unresolved; do
    printf '%s' "$_s2b" | grep -qw "$_w" \
      || fail "$_l: the outcome section does not cover the '$_w' terminal state"
  done
  printf '%s' "$_s2b" | grep -q 'omitting `blocking.json`' \
    || fail "$_l: the outcome section does not warn against 'fixing' the timeout by omitting blocking.json"

  _s3="$(section "$_f" 'Parse and classify comments')"
  [ -n "$_s3" ] || fail "$_l: the classification section is missing"
  printf '%s' "$_s3" | grep -qF 'acted.json' \
    || fail "$_l: the classification section never tells the loop to write acted.json"
  printf '%s' "$_s3" | grep -qF '"override": true' \
    || fail "$_l: the classification section does not tell the loop to flag a severity override"
  printf '%s' "$_s3" | grep -qF 'severity' \
    || fail "$_l: the classification section does not require severity to survive per row"

  _s4b="$(section "$_f" 'Convergence trend')"
  [ -n "$_s4b" ] || fail "$_l: the convergence-trend section is missing"
  printf '%s' "$_s4b" | grep -qF -- '--diff-files' \
    || fail "$_l: the trend step never passes the diff width, so the remedy can never be conditioned on it"
}

test_the_runbook_writes_what_the_trend_reads() {
  check_runbook "$SRC/.claude/commands/sdd-pr-loop.md" "source-layout /sdd-pr-loop"
  # The INSTALLED body is a separate heredoc inside harness-install.sh. Editing only the
  # source-layout copy ships a loop that writes none of this to any consumer.
  _t="$T/install"
  mkdir -p "$_t"
  HARNESS_PR_LOOP_ENABLED=true CODEX_HOME="$_t/ch" \
    sh "$SRC/harness-install.sh" --agents=claude "$_t" >"$_t/.out" 2>"$_t/.err" \
    || { cat "$_t/.err" >&2; fail "installer exited non-zero"; }
  _cmd="$_t/.claude/commands/sdd-pr-loop.md"
  [ -f "$_cmd" ] || fail "setup: gate-on install did not stamp /sdd-pr-loop"
  check_runbook "$_cmd" "INSTALLED /sdd-pr-loop"
  [ -x "$_t/.harness/tools/pr-round-trend.sh" ] \
    || fail "installed tools/pr-round-trend.sh missing or not executable"
  pass "E99-F126/F116 the_runbook_writes_what_the_trend_reads: both the source-layout and the INSTALLED body"
}

test_recorded_timeout_is_not_a_clean_round
test_legacy_cache_derives_the_timeout_it_never_recorded
test_an_unrecorded_outcome_is_never_silently_clean
test_the_trend_counts_what_was_acted_on
test_the_merge_gate_still_reads_the_configured_filter
test_the_remedy_fits_the_diff
test_the_tool_stays_advisory
test_the_runbook_writes_what_the_trend_reads

echo "ok - test_pr_round_outcome.sh: all cases passed"
