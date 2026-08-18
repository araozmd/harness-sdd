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

test_an_uncounted_round_is_not_a_missing_review() {
  have_jq || { skip "an_uncounted_round_is_not_a_missing_review (jq not installed)"; return 0; }
  # The defect this whole item exists to end, recursed one level: one bucket standing for two
  # states, with the report confidently asserting the wrong one. A round whose `outcome` says
  # `findings` but whose count file is missing was filed under `not_reviewed` and printed as
  # "NEVER REVIEWED", sending the operator to check the Codex GitHub App and the watcher —
  # while the recorded outcome PROVES a review landed and the step that actually failed is
  # classification. Healthy component inspected, broken step unnamed.
  #
  # ONE cache carries BOTH states, so the two blocks are proven distinct in the same run: if
  # they are ever merged back together, the wording assertions below cannot all hold at once.
  _c="$T/buckets"
  mkdir -p "$_c/round-1" "$_c/round-2" "$_c/round-3" "$_c/round-4" "$_c/round-5"
  printf 'findings\n' > "$_c/round-1/outcome"; findings_json 2 src/one.ts > "$_c/round-1/acted.json"
  printf 'timeout\n'  > "$_c/round-2/outcome"                      # the review did NOT resolve
  printf 'findings\n' > "$_c/round-3/outcome"; printf '{ truncated' > "$_c/round-3/acted.json"
  printf 'findings\n' > "$_c/round-4/outcome"; findings_json 2 src/one.ts > "$_c/round-4/acted.json"
  #                     round-5: nothing on disk at all

  # ── the buckets are separate, and each round is in the right one ────────────────
  [ "$(jqf "$_c" '.not_reviewed | length')" = "1" ] \
    || fail "E99-F126: not_reviewed holds $(jqf "$_c" '.not_reviewed | length') rounds — only the round whose REVIEW failed belongs there"
  [ "$(jqf "$_c" '.not_reviewed[0].round')" = "2" ] \
    || fail "E99-F126: not_reviewed names round $(jqf "$_c" '.not_reviewed[0].round'), expected only the timed-out round 2"
  [ "$(jqf "$_c" '[.uncounted[].round] | join(",")')" = "3,5" ] \
    || fail "E99-F126: uncounted holds rounds $(jqf "$_c" '[.uncounted[].round] | join(",")'), expected 3 and 5"
  [ "$(jqf "$_c" '.uncounted[] | select(.round == 3) | .status')" = "reviewed-uncounted" ] \
    || fail "E99-F126: round 3 has outcome=findings on disk and is reported as '$(jqf "$_c" '.uncounted[] | select(.round==3) | .status')' — a review provably landed there"
  [ "$(jqf "$_c" '.uncounted[] | select(.round == 5) | .status')" = "no-record" ] \
    || fail "E99-F126: round 5 has nothing on disk and is reported as '$(jqf "$_c" '.uncounted[] | select(.round==5) | .status')' — the tool must not claim to know"
  # Neither bucket enters the rate. That part of the old behaviour was right.
  [ "$(jqf "$_c" '.series | join(",")')" = "2,2" ] \
    || fail "E99-F126: the rate is $(jqf "$_c" '.series|join(",")'), expected 2,2 — an uncounted round is not evidence of convergence"

  # ── the WORDING, which is what actually misdirects an operator ──────────────────
  _out="$(sh "$TREND" --cache "$_c")"
  _nr_line="$(printf '%s\n' "$_out" | grep 'round 3' || true)"
  printf '%s' "$_nr_line" | grep -q 'review DID land' \
    || fail "E99-F126: round 3's line does not say a review landed — its recorded outcome proves one did: '$_nr_line'"
  printf '%s\n' "$_out" | grep -q 'NEVER REVIEWED' \
    || fail "E99-F126: the genuinely unreviewed round 2 lost its NEVER REVIEWED header — the contrast this test rests on is gone"
  printf '%s\n' "$_out" | grep -q 'NOT COUNTED' \
    || fail "E99-F126: there is no separate NOT COUNTED block — an uncounted round is being reported as an unreviewed one"
  # The two headers must not be the same string, or "distinct buckets" is cosmetic.
  [ "$(printf '%s\n' "$_out" | grep -c 'NEVER REVIEWED')" = "1" ] \
    || fail "E99-F126: the NEVER REVIEWED header appears more than once — the uncounted block is reusing it"
  # The upstream remedy belongs to exactly ONE block. If the uncounted rounds are merged back
  # in, this remedy is printed for a round whose review already landed.
  _codex_hits="$(printf '%s\n' "$_out" | grep -c 'Codex GitHub App' || true)"
  [ "${_codex_hits:-0}" = "1" ] \
    || fail "E99-F126: the 'check the Codex GitHub App' remedy is printed $_codex_hits times — it belongs only to the block for rounds whose review did not resolve"
  printf '%s\n' "$_out" | grep -q 'round CACHE, not necessarily its review' \
    || fail "E99-F126: the NOT COUNTED block does not direct the operator at the failed cache/classification step"
  printf '%s\n' "$_out" | grep -q 'wait-for-codex.sh evaluate' \
    || fail "E99-F126: the NOT COUNTED block names no way to re-derive the round offline"

  # ── the contrast: a cache with ONLY the reviewed-uncounted round must not print the
  # unreviewed header or its remedy at all. This is the assertion that fails the moment the
  # two buckets collapse back into one, whichever direction the collapse goes.
  _u="$T/buckets-uncounted-only"
  mkdir -p "$_u/round-1"
  printf 'findings\n' > "$_u/round-1/outcome"; printf '{ truncated' > "$_u/round-1/acted.json"
  _uout="$(sh "$TREND" --cache "$_u")"
  printf '%s\n' "$_uout" | grep -q 'NEVER REVIEWED' \
    && fail "E99-F126: a round whose outcome file records a LANDED review is still reported as NEVER REVIEWED" || :
  printf '%s\n' "$_uout" | grep -q 'Codex GitHub App' \
    && fail "E99-F126: an operator with an uncounted round is still sent to inspect the Codex App — the healthy component" || :
  printf '%s\n' "$_uout" | grep -q 'NOT COUNTED' \
    || fail "E99-F126: the uncounted round is not reported at all — it was dropped, which is the other half of this defect"
  sh "$TREND" --cache "$_u" >/dev/null 2>&1 \
    || fail "E99-F126: the tool exited non-zero on a cache of only uncounted rounds — it must never block"
  pass "E99-F126 an_uncounted_round_is_not_a_missing_review: NEVER REVIEWED and NOT COUNTED are separate blocks with separate remedies"
}

# extract_fn <runbook> <section-heading> <fn-name> — a shell function lifted out of the prose.
extract_fn() {
  section "$1" "$2" \
    | awk -v f="$3" 'index($0, f "() {") == 1 { p = 1 } p { print } p && /^\}$/ { exit }'
}

test_a_landed_outcome_survives_an_unreadable_cache() {
  have_jq || { skip "a_landed_outcome_survives_an_unreadable_cache (jq not installed)"; return 0; }
  # The bucket split is undone at the WRITE path if a later step clobbers a recorded
  # `findings` with `unresolved`. Two steps did: step 3's unreadable-headRefOid abort and
  # step 5's `pr-gate.sh` exit 4. Neither observed the review — one failed to read pr.json,
  # the other failed to read blocking.json — and an exit code about UNREADABLE INPUT carries
  # no information about whether Codex answered. Overwriting there destroys the evidence and
  # then misreports it as NEVER REVIEWED, sending the operator to a healthy component.
  _fn="$(extract_fn "$SRC/.claude/commands/sdd-pr-loop.md" 'Record the round' outcome_mark_unresolved)"
  printf '%s' "$_fn" | grep -qF 'outcome_mark_unresolved() {' \
    || fail "evidence: outcome_mark_unresolved could not be extracted from the runbook — the preserving write path is prose only"
  _d="$T/evidence"; mkdir -p "$_d"
  _f="$T/evidence/fn.sh"; printf '%s\n' "$_fn" > "$_f"
  # shellcheck disable=SC1090
  . "$_f"

  # A review that landed SURVIVES a step that only failed to read the cache.
  for _o in findings clean; do
    mkdir -p "$_d/$_o"; printf '%s\n' "$_o" > "$_d/$_o/outcome"
    outcome_mark_unresolved "$_d/$_o"
    [ "$(cat "$_d/$_o/outcome")" = "$_o" ] \
      || fail "evidence: a recorded '$_o' was overwritten with '$(cat "$_d/$_o/outcome")' by a step that never observed the review"
  done
  # Everything else is still demoted — the guard must not become "never write unresolved".
  mkdir -p "$_d/timeout"; printf 'timeout\n' > "$_d/timeout/outcome"
  outcome_mark_unresolved "$_d/timeout"
  [ "$(cat "$_d/timeout/outcome")" = "unresolved" ] \
    || fail "evidence: a round whose review never resolved was not demoted to unresolved"
  mkdir -p "$_d/absent"
  outcome_mark_unresolved "$_d/absent"
  [ "$(cat "$_d/absent/outcome" 2>/dev/null)" = "unresolved" ] \
    || fail "evidence: a round with no outcome at all was not marked unresolved"

  # End to end, on the report an operator actually reads. Round 2 is the gate-exit-4 shape:
  # the watcher recorded `findings`, classification left blocking.json unreadable.
  _c="$T/evidence-cache"
  mkdir -p "$_c/round-1" "$_c/round-2" "$_c/round-3"
  printf 'findings\n' > "$_c/round-1/outcome"; findings_json 2 src/one.ts > "$_c/round-1/acted.json"
  printf 'findings\n' > "$_c/round-2/outcome"; printf '{ truncated' > "$_c/round-2/blocking.json"
  printf 'findings\n' > "$_c/round-3/outcome"; findings_json 2 src/one.ts > "$_c/round-3/acted.json"
  outcome_mark_unresolved "$_c/round-2"          # what step 5 now does on gate exit 4
  [ "$(cat "$_c/round-2/outcome")" = "findings" ] \
    || fail "evidence: gate exit 4 clobbered the landed outcome — the round will report as NEVER REVIEWED"
  [ "$(jqf "$_c" '.uncounted[] | select(.round == 2) | .status')" = "reviewed-uncounted" ] \
    || fail "evidence: after a gate exit 4 the round is '$(jqf "$_c" '.uncounted[] | select(.round==2) | .status')', expected reviewed-uncounted"
  [ "$(jqf "$_c" '.not_reviewed | length')" = "0" ] \
    || fail "evidence: a round whose review landed was filed under not_reviewed after an unreadable-input abort"
  _out="$(sh "$TREND" --cache "$_c")"
  printf '%s\n' "$_out" | grep 'round 2' | grep -q 'review DID land' \
    || fail "evidence: the report does not say a review landed for the round whose outcome file records one"
  printf '%s\n' "$_out" | grep -q 'NEVER REVIEWED' \
    && fail "evidence: the operator is told a review never landed for a round the outcome file says was reviewed" || :
  printf '%s\n' "$_out" | grep -q 'Codex GitHub App' \
    && fail "evidence: the operator is sent to the Codex App — the healthy component — for a failed classification" || :

  # The CONTRAST that keeps the rule from degenerating into "never demote": exit 9 IS an
  # observation (the gate ran wait-for-codex.sh evaluate and nothing resolved), so it may
  # replace, and that round DOES belong under NEVER REVIEWED with the upstream remedy.
  printf 'unresolved\n' > "$_c/round-2/outcome"   # what step 5 does on gate exit 9
  [ "$(jqf "$_c" '.not_reviewed[0].round')" = "2" ] \
    || fail "evidence: an exit-9 demotion no longer reaches not_reviewed — exit 9 must still be able to replace a recorded outcome"
  sh "$TREND" --cache "$_c" | grep -q 'NEVER REVIEWED' \
    || fail "evidence: an exit-9 round lost the NEVER REVIEWED header, so the two exit codes are no longer distinguishable in the report"
  pass "evidence a_landed_outcome_survives_an_unreadable_cache: exit 4 preserves, exit 9 replaces"
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
  _s3_headok="$(section "$_f" 'Parse and classify comments')"
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
  # An outcome file is evidence. The later `unresolved` writers must be able to tell an exit
  # code that OBSERVED the review from one that merely failed to read the cache, or the
  # not_reviewed/uncounted distinction is undone one step upstream by the thing that writes it.
  printf '%s' "$_s2b" | grep -qF 'outcome_mark_unresolved() {' \
    || fail "$_l: the outcome section defines no preserving writer — a later step will clobber a landed review with 'unresolved'"
  printf '%s' "$_s2b" | grep -qF 'findings|clean) : ;;' \
    || fail "$_l: the preserving writer does not exempt a recorded findings/clean outcome"
  printf '%s' "$_s2b" | grep -q 'may not overwrite' \
    || fail "$_l: the outcome section does not state the principle that a step which did not observe the review may not overwrite it"

  _s5="$(section "$_f" 'Branch on round')"
  [ -n "$_s5" ] || fail "$_l: the gate-branch section is missing"
  printf '%s' "$_s5" | grep -qF 'outcome_mark_unresolved "$round_dir"' \
    || fail "$_l: the gate's unreadable-input path still writes unresolved unconditionally — a landed review is clobbered and reported as NEVER REVIEWED"
  printf '%s' "$_s5" | grep -q 'Exit `9` is an OBSERVATION' \
    || fail "$_l: the gate-branch section does not distinguish exit 9 (observed) from exit 4 (unreadable input)"
  printf '%s' "$_s3_headok" | grep -qF 'outcome_mark_unresolved "$round_dir"' \
    || fail "$_l: step 3's unreadable-headRefOid abort still overwrites the outcome unconditionally"

  # ── THE ORDERING (Codex round 1, P2) ──────────────────────────────────────────
  # `acted.json` is recorded at DISPATCH, never at classification. The first version of this
  # feature told step 3 to pre-compute it from blocking.json and then append override rows
  # "for every finding you hand to a fixer" — but at step 3 nothing has been handed to
  # anyone, the gate has not been asked, and its answer can be `merge`, after which step 5
  # forbids fixing non-blocking findings outright. So a COMPLIANT loop could never produce
  # an override row, and F116 stayed broken in practice while the runbook read as if it were
  # fixed. These two assertions are a pair: one forbids the old location, the other requires
  # the new one. Deleting either half restores the defect with the suite still green.
  _s3="$(section "$_f" 'Parse and classify comments')"
  [ -n "$_s3" ] || fail "$_l: the classification section is missing"
  printf '%s' "$_s3" | grep -qF 'acted.json' \
    || fail "$_l: the classification section never mentions acted.json — it must say the set is NOT written here"
  printf '%s' "$_s3" | grep -qE 'Do NOT write .?acted\.json.? here' \
    || fail "$_l: the classification section does not forbid writing acted.json at classification time"
  printf '%s' "$_s3" | grep -qF '> "$round_dir/acted.json"' \
    && fail "$_l: the classification section WRITES acted.json — that is the pre-gate ordering this fix removed; a compliant loop can never act on a finding the gate excluded, so the override row could never exist" || :
  printf '%s' "$_s3" | grep -qF '"override": true' \
    && fail "$_l: the classification section still builds override rows before anything is dispatched" || :

  # Two honest moves when the badge is wrong, and neither of them is silence. This is what
  # makes an override reachable by a loop that follows its own rules.
  _sov="$(section "$_f" 'When you judge the badge wrong')"
  [ -n "$_sov" ] \
    || fail "$_l: nothing tells the loop what to do when a finding outside blocking_severities is substantively blocking — the override path is unreachable and F116 stays broken in practice"
  printf '%s' "$_sov" | grep -qF 'pr_loop.blocking_severities' \
    || fail "$_l: the override clause never names raising the configured threshold as the first move"
  printf '%s' "$_sov" | grep -qF 'acted_append' \
    || fail "$_l: the override clause does not require the override to be recorded"
  printf '%s' "$_sov" | grep -qF 'Recording is not permission' \
    || fail "$_l: the override clause reads as a licence — it must say the record does not authorize the work"

  # The dispatch section: the helper is defined here, and every path that disposes of a
  # finding calls it.
  _sd="$(section "$_f" 'Record what this round acted on')"
  [ -n "$_sd" ] \
    || fail "$_l: no section records the acted-on set at dispatch — the trend would read a file nobody writes"
  printf '%s' "$_sd" | grep -qF 'acted_append() {' \
    || fail "$_l: the dispatch section does not define acted_append"
  printf '%s' "$_sd" | grep -qF '$round_dir/acted.json' \
    || fail "$_l: the dispatch section never names \$round_dir/acted.json"
  printf '%s' "$_sd" | grep -qF 'at the MOMENT a finding is disposed of as blocking' \
    || fail "$_l: the dispatch section does not pin the call to the moment of disposal — without that, 'record what you acted on' drifts back to 'record what you plan to act on'"
  grep -qF '#### Record what this round acted on — at DISPATCH, never in advance' "$_f" \
    || fail "$_l: the dispatch section's heading no longer says the record is written at dispatch, never in advance"
  # One call per disposal path, checked ROW BY ROW. A count of `acted_append` mentions across
  # the section is not enough: deleting the cap row's call still leaves the definition, its
  # usage comment and two rows behind, so a threshold passes while a whole disposal path goes
  # unrecorded. Each row is named and checked on its own line.
  #
  # The cap row is the one that most looks droppable and least is. It fixes nothing, but a
  # finding DECLARED blocking in the hand-over is acted on all the same — leave those rows out
  # and the last round reads as a quiet zero, which is exactly the trailing zero that turns a
  # flat series back into `converging` on the report that exists to stop that. viernes-web
  # PR #85's real handover recorded 1,1,1,1 with round 4 a declared residual.
  _row_fix="$(printf '%s\n' "$_sd" | grep '^| below `max_rounds - 1` |' || true)"
  _row_esc="$(printf '%s\n' "$_sd" | grep '^| `max_rounds - 1` |' || true)"
  _row_cap="$(printf '%s\n' "$_sd" | grep '^| `max_rounds` (cap) |' || true)"
  [ -n "$_row_fix" ] || fail "$_l: the per-comment fixer row is missing from the dispatch table"
  [ -n "$_row_esc" ] || fail "$_l: the combined-escalation row is missing from the dispatch table"
  [ -n "$_row_cap" ] || fail "$_l: the cap row is missing from the dispatch table"
  printf '%s' "$_row_fix" | grep -qF 'acted_append' \
    || fail "$_l: the per-comment fixer row dispatches findings without recording them"
  printf '%s' "$_row_esc" | grep -qF 'acted_append' \
    || fail "$_l: the combined-escalation row dispatches findings without recording them"
  printf '%s' "$_row_cap" | grep -qF 'acted_append' \
    || fail "$_l: the cap row declares surviving blocking comments without recording them — the last round then reads as a zero and a flat series flips back to 'converging'"
  printf '%s' "$_sd" | grep -q 'acted on whether or not it was fixed' \
    || fail "$_l: nothing states that a declared-blocking finding counts as acted on — the cap row's call reads as optional"
  printf '%s' "$_sd" | grep -qF 'in-session' \
    || fail "$_l: the front-end-without-pr-fixer path is not held to the same record"

  _s4b="$(section "$_f" 'Convergence trend')"
  [ -n "$_s4b" ] || fail "$_l: the convergence-trend section is missing"
  printf '%s' "$_s4b" | grep -qF -- '--diff-files' \
    || fail "$_l: the trend step never passes the diff width, so the remedy can never be conditioned on it"
  # Step 4b runs BEFORE dispatch, so the current round has no acted.json yet. If the loop
  # never re-reads the trend after dispatch, a terminal message reports a verdict computed
  # from an incomplete last round.
  printf '%s' "$_s4b" | grep -qF 'does not exist yet' \
    || fail "$_l: step 4b does not say that the current round's acted.json is not written yet"
  # Both buckets, and their OPPOSITE remedies, must be described where the operator reads
  # the trend. A runbook that documents only `not_reviewed` teaches the very misreading the
  # tool was just fixed to stop making.
  printf '%s' "$_s4b" | grep -qF 'not_reviewed[]' \
    || fail "$_l: the trend section does not name the not_reviewed bucket"
  printf '%s' "$_s4b" | grep -qF 'uncounted[]' \
    || fail "$_l: the trend section does not name the uncounted bucket — an operator reading it will take a landed review for a missing one"
  printf '%s' "$_s4b" | grep -qF 'reviewed-uncounted' \
    || fail "$_l: the trend section does not distinguish a reviewed-but-uncounted round from one that was never reviewed"
  _sh="$(section "$_f" 'Handover summary')"
  [ -n "$_sh" ] || fail "$_l: the handover-summary section is missing"
  printf '%s' "$_sh" | grep -qF 'pr-round-trend.sh' \
    || fail "$_l: the handover summary never re-runs the trend, so a terminal message carries the pre-dispatch verdict"
}

# extract_acted_append <runbook> — the helper's source, lifted out of the runbook.
extract_acted_append() {
  section "$1" 'Record what this round acted on' \
    | awk '/^acted_append\(\) \{/ { p = 1 } p { print } p && /^\}$/ { exit }'
}

test_the_runbook_helper_actually_works() {
  have_jq || { skip "the_runbook_helper_actually_works (jq not installed)"; return 0; }
  # A runbook snippet nobody executes is a snippet nobody has checked. Lift acted_append out
  # of the prose, run it, and assert it produces the exact rows tools/pr-round-trend.sh reads
  # — otherwise the ordering could be perfectly documented and still write nothing usable.
  _src_fn="$(extract_acted_append "$SRC/.claude/commands/sdd-pr-loop.md")"
  printf '%s' "$_src_fn" | grep -qF 'acted_append() {' \
    || fail "ordering: acted_append could not be extracted from the runbook"
  round_dir="$T/helper/round-1"; mkdir -p "$round_dir"
  _f="$T/helper/fn.sh"; printf '%s\n' "$_src_fn" > "$_f"
  # shellcheck disable=SC1090
  . "$_f"
  acted_append 3786922846 src/page.tsx 187 P2 override
  acted_append 42 src/other.ts 9 P1 configured
  [ -f "$round_dir/acted.json" ] || fail "ordering: the runbook's acted_append wrote no acted.json"
  jq -e 'length == 2' "$round_dir/acted.json" >/dev/null \
    || fail "ordering: two dispatches produced $(jq -c length "$round_dir/acted.json") rows — the helper overwrites instead of appending"
  jq -e '.[0].override == true and .[0].severity == "P2" and .[0].id == 3786922846 and .[0].path == "src/page.tsx"' \
    "$round_dir/acted.json" >/dev/null \
    || fail "ordering: the override row is not the shape the trend reads: $(jq -c '.[0]' "$round_dir/acted.json")"
  jq -e '.[1].override == false and .[1].severity == "P1"' "$round_dir/acted.json" >/dev/null \
    || fail "ordering: a configured-severity dispatch was recorded as an override"
  # And the tool must actually read what the runbook wrote — the two halves of this feature
  # meeting in the middle, on a file neither of them mocked.
  printf 'findings\n' > "$round_dir/outcome"
  [ "$(jqf "$T/helper" '.overrides')" = "1" ] \
    || fail "ordering: pr-round-trend.sh counted $(jqf "$T/helper" '.overrides') overrides in the rows the runbook's own helper produced"
  [ "$(jqf "$T/helper" '.series | join(",")')" = "2" ] \
    || fail "ordering: the trend did not take its count from the helper-written acted.json"
  unset round_dir
  pass "ordering the_runbook_helper_actually_works: the runbook's acted_append appends rows the trend reads"
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
test_an_uncounted_round_is_not_a_missing_review
test_a_landed_outcome_survives_an_unreadable_cache
test_the_remedy_fits_the_diff
test_the_tool_stays_advisory
test_the_runbook_writes_what_the_trend_reads
test_the_runbook_helper_actually_works

echo "ok - test_pr_round_outcome.sh: all cases passed"
