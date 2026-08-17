#!/bin/sh
# test_stacked_doctrine.sh — E21-F05: the stacked-PR lane's doctrine document.
#
# The whole deliverable of E21-F05 is prose, so every requirement's value lives in
# whether its assertion can FAIL. Three mechanics make that true here, and none of them
# is decoration:
#
#   1. EXTRACT THE SECTION FIRST, WITH THE FENCE-AWARE EXTRACTOR. `agents/builder.md`
#      mandates grepping the section a prose contract names, not the whole file — a
#      whole-file grep is satisfied by any unrelated occurrence elsewhere, including one
#      the same change just added. The house idiom at `agents/builder.md:87` is fence-
#      BLIND, and every shell fence in `docs/WORKFLOW.md` carries `#` comments: measured
#      on the very section this feature edits, the bare idiom reads a `gh pr create`
#      count of 1 where the fence-aware one reads 4. Any assertion counting inside a
#      fenced section would have passed on a section it never read. Hence sect()/span()
#      below, both carrying the `/^```/{f=!f}` toggle.
#
#   2. COUNT OCCURRENCES WITH `grep -o | wc -l`, NEVER WITH `grep -c`. `grep -c` counts
#      matching LINES: this document wraps at ~92 columns, so two copies of an anchor on
#      one physical line would report 1 and let the very duplication the "stated once"
#      requirements forbid pass. And a possibly-zero `grep -c` bound under `set -eu`
#      exits 1 and kills the suite on its PASSING path. `wc` is the pipeline's last
#      command and exits 0 on empty input, so no `|| true` is needed.
#
#   3. ANCHOR ON IDENTIFIERS, NOT ON ENGLISH. Where the requirement has a name the system
#      already owns — `verification.test_command`, `pr_loop.enabled`, `baseRefName`,
#      `change_size`, `E21-F01`, `(R<n>)` — this suite asserts THAT. An editor may reword
#      freely around a config key; they cannot delete the key and still mean the same
#      thing. Freezing whole sentences would turn every copy-edit into a red build.
#
# LOAD-BEARING ANCHORS. Four anchors have no system identifier available and are short
# English phrases; each failing message below says so, because "reword the sentence
# around it, not the phrase" is the instruction a future editor needs:
#
#   `independently safe`, `first increment PR`      (R1) — docs/WORKFLOW.md `### Entry condition`
#   `this epic does not solve`, `not a candidate`   (R2) — same subsection
#   `feature flag`                                  (R2) — same subsection, exactly once in the lane
#   `default branch`, `still open`                  (R3) — the lane's opening paragraphs
#   `per-increment`                                 (R4) — `### What the board shows`
#   `ships with the harness body`                   (R8) — `### Opt-in and inert-when-disabled`
#   BANNED in the lane: `atomic` (R3), `wave` + `E21-F01` (R5), `(R<n>)` (R7),
#   `separate independent features` (R2), `documentation is stamped` (R8).
#
# Anti-patterns this suite does NOT commit, all previously paid for in this repo:
# no assertion on a VERSION value in any form; no diff of any file against `main`; no
# whole-file grep for a prose contract; no `grep -c` anywhere. Zero dependencies beyond
# POSIX sh (no python3, no jq — so no skip guard); per-case fixtures under one
# self-cleaning temp dir; no writes into state/, specs/ or progress/.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-stacked-doctrine)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

WF="$SRC/docs/WORKFLOW.md"
LANE='Stacked-PR lane'
F04SPEC="$SRC/specs/epics/E21-change-size-discipline/F04-stacked-pr-lane/F04-stacked-pr-lane.spec.md"

# sect <file> <heading-text> — ONE section body; stops at the next heading of ANY level.
# FENCE-AWARE: `#` opens a comment in every shell fence in these docs, so the bare house
# idiom treats `# Increment 1 targets main` as a heading and stops extracting there.
sect() { awk -v h="$2" '/^```/{f=!f} !f && /^#+ /{k=(index($0,h)>0);next} k' "$1"; }

# span <file> <h2-heading-text> — a WHOLE `## ` section INCLUDING its `###` subsections;
# stops at the next `## `. Used for every lane-wide sweep and every uniqueness count.
# ALSO fence-aware: no shell comment in this file begins with `## ` TODAY, but this feature
# rewrites those very fences (T4, T6), and a `## ` comment introduced inside one would
# truncate the span and make three bans pass vacuously.
span() { awk -v h="$2" '/^```/{f=!f} !f && /^## /{k=(index($0,h)>0);next} k' "$1"; }

# lane_count <pattern> [-i] — OCCURRENCES of <pattern> in the lane span. Never `grep -c`.
lane_count() {
  if [ "${2:-}" = "-i" ]; then
    span "$WF" "$LANE" | grep -oi "$1" | wc -l | tr -d ' '
  else
    span "$WF" "$LANE" | grep -o "$1" | wc -l | tr -d ' '
  fi
}

# ── R1 ────────────────────────────────────────────────────────────────────────────────
# The entry condition is stated ONCE, in `### Entry condition`, naming both conditions
# checked before the first increment PR is opened.
test_entry_condition_stated_once() {
  _ec="$(sect "$WF" '### Entry condition')"
  [ -n "$_ec" ] \
    || fail "R1: docs/WORKFLOW.md has no '### Entry condition' subsection in the $LANE section — the lane's entry condition must live in exactly one subsection, and this suite extracts it by that heading"
  printf '%s\n' "$_ec" | grep -q 'verification.test_command' \
    || fail "R1: '### Entry condition' does not name the config key [verification.test_command] — the second condition is that every increment passes it on its own"
  for _a in 'independently safe' 'first increment PR'; do
    printf '%s\n' "$_ec" | grep -q "$_a" \
      || fail "R1: '### Entry condition' does not contain the load-bearing phrase [$_a], asserted by tests/test_stacked_doctrine.sh — reword the sentence around it, not the phrase"
  done
  # Uniqueness IS the requirement: a presence check cannot see a second copy, and a second
  # copy of the condition is the defect this feature exists to remove.
  for _a in 'independently safe' 'verification.test_command'; do
    _n="$(lane_count "$_a")"
    [ "$_n" = "1" ] \
      || fail "R1: the anchor [$_a] occurs $_n time(s) in the '$LANE' section, want exactly 1 — the entry condition is stated in ONE subsection and every other part of the lane points at it; a condition stated twice will disagree with itself"
  done
  pass "E21-F05 R1 entry_condition_stated_once"
}

# ── R2 ────────────────────────────────────────────────────────────────────────────────
# A feature that cannot meet the entry condition is refused the lane, the alternatives are
# named in exactly one place, and the case is recorded as an open problem.
test_not_served_case_refused_once() {
  _ec="$(sect "$WF" '### Entry condition')"
  [ -n "$_ec" ] \
    || fail "R2: '### Entry condition' is empty or absent, so the refusal it must carry cannot be read"
  printf '%s\n' "$_ec" | grep -qi 'feature flag' \
    || fail "R2: '### Entry condition' does not name [feature flag] as an alternative for a feature the lane refuses"
  printf '%s\n' "$_ec" | grep -q 'this epic does not solve' \
    || fail "R2: '### Entry condition' does not contain the load-bearing phrase [this epic does not solve], asserted by tests/test_stacked_doctrine.sh — reword the sentence around it, not the phrase; the unsolved case must be recorded as unsolved, not left implied"
  if printf '%s\n' "$_ec" | grep -q 'not a candidate'; then :
  elif printf '%s\n' "$_ec" | grep -q 'do not stack'; then :
  else
    fail "R2: '### Entry condition' carries no refusal token — it must say [not a candidate] or [do not stack]; naming alternatives without refusing the lane leaves the reader to guess"
  fi
  # One list, one place. Today's defect is the lane naming feature flags TWICE, in two
  # subsections that disagree about what the alternatives are.
  _n="$(lane_count 'feature flag' -i)"
  [ "$_n" = "1" ] \
    || fail "R2: [feature flag] occurs $_n time(s) in the '$LANE' section, want exactly 1 — the alternatives are listed in '### Entry condition' and nowhere else"
  if span "$WF" "$LANE" | grep -q 'separate independent features'; then
    fail "R2: the '$LANE' section still carries the competing alternative list [separate independent features] — it disagreed with the paragraph above it, which is why the alternatives now live in exactly one place"
  fi
  pass "E21-F05 R2 not_served_case_refused_once"
}

# ── R3 ────────────────────────────────────────────────────────────────────────────────
# The outcome is stated mechanically in the lane's OPENING paragraphs, and the withdrawn
# vocabulary is absent from the lane.
test_outcome_stated_mechanically() {
  # `sect`, not `span`: the opening paragraphs only, so a mechanical sentence filed under
  # a later subheading does not satisfy this.
  _open="$(sect "$WF" "## $LANE")"
  [ -n "$_open" ] \
    || fail "R3: the '$LANE' section has no opening paragraphs between its '##' heading and the first '###' — that is where the lane's outcome is stated"
  printf '%s\n' "$_open" | grep -q 'default branch' \
    || fail "R3: the lane's opening paragraphs do not say [default branch] — the outcome is mechanical (merging an increment publishes that increment's work to the default branch), and the loop computes the default branch rather than assuming 'main'"
  printf '%s\n' "$_open" | grep -q 'still open' \
    || fail "R3: the lane's opening paragraphs do not say [still open] — the mechanical statement is that the LATER increments are still open when an earlier one merges"
  # A banned TOKEN, not a claim: it cannot be paraphrased around. Scoped to the lane
  # because tools/pr-stack-guard.sh's header states the doctrine in the denial form and is
  # DO NOT TOUCH — so this makes no repo-wide uniqueness claim.
  if span "$WF" "$LANE" | grep -qi 'atomic'; then
    fail "R3: the '$LANE' section contains the banned token [atomic] — this vocabulary got the predecessor spec withdrawn after four review rounds; state the outcome mechanically (what merging an increment publishes, and what is still open) instead"
  fi
  pass "E21-F05 R3 outcome_stated_mechanically"
}

# ── R4 ────────────────────────────────────────────────────────────────────────────────
# The lane records what the board shows while a stack is in flight.
test_board_shows_one_feature() {
  _bd="$(sect "$WF" '### What the board shows')"
  [ -n "$_bd" ] \
    || fail "R4: docs/WORKFLOW.md has no '### What the board shows' subsection in the $LANE section — a reader has nowhere to learn that a stacked feature is ONE feature record"
  printf '%s\n' "$_bd" | grep -q 'baseRefName' \
    || fail "R4: '### What the board shows' does not name the GitHub field [baseRefName] — that field is where the increment order actually lives, since the board does not record it"
  printf '%s\n' "$_bd" | grep -q 'per-increment' \
    || fail "R4: '### What the board shows' does not contain the load-bearing phrase [per-increment], asserted by tests/test_stacked_doctrine.sh — reword around it, not it; the harness writes NO per-increment board record and the section has to say so"
  pass "E21-F05 R4 board_shows_one_feature"
}

# ── R5 ────────────────────────────────────────────────────────────────────────────────
# No citation attributing a decomposition structure to a source that defines none.
test_seam_guidance_has_no_dangling_citation() {
  _wc="$(sect "$WF" '### Where to cut')"
  [ -n "$_wc" ] \
    || fail "R5: docs/WORKFLOW.md has no '### Where to cut' subsection in the $LANE section — the seam guidance that replaced the dangling decomposition citation lives under that heading"
  printf '%s\n' "$_wc" | grep -q 'change_size' \
    || fail "R5: '### Where to cut' does not name the config key [change_size] — the seam guidance points at the budget thresholds, not at an epic id"
  printf '%s\n' "$_wc" | grep -q 'Entry condition' \
    || fail "R5: '### Where to cut' does not point at [Entry condition] — the test an increment boundary must pass is the lane's own entry condition, and that is the only thing the seam guidance can honestly cite"
  # One sweep covers all four carriers of the old vocabulary: the dangling "wave
  # structure" citation, the opening paragraph, "publishes wave 1", and the feat/wave-N
  # example branches in the creation AND restack fences.
  if span "$WF" "$LANE" | grep -qi 'wave'; then
    fail "R5: the '$LANE' section still contains [wave] vocabulary — E21-F01 defines no wave structure, so the word cites nothing; the example branches and PR titles are part of this sweep"
  fi
  if span "$WF" "$LANE" | grep -q 'E21-F01'; then
    fail "R5: the '$LANE' section still cites [E21-F01] — deleting the word 'wave' while keeping the attribution leaves the same dangling claim, and docs/WORKFLOW.md ships into target repos where an epic id resolves to nothing"
  fi
  pass "E21-F05 R5 seam_guidance_has_no_dangling_citation"
}

# ── R6 ────────────────────────────────────────────────────────────────────────────────
# The section name the installer's shipped restack diagnostic points at resolves to a
# heading in docs/WORKFLOW.md. DERIVED from the message, never frozen: freezing the
# heading would fail a correct future rename that moved heading and message together, and
# the derived form catches the only failure that matters — the two drifting apart.
test_installer_restack_pointer_resolves() {
  sed -n "s/.*docs\/WORKFLOW\.md '\([^']*\)'.*/\1/p" "$SRC/harness-install.sh" > "$T/wf-pointers"
  [ -s "$T/wf-pointers" ] \
    || fail "R6: no \"See docs/WORKFLOW.md '<section>'\" diagnostic was found in harness-install.sh — the derivation yielded nothing, so this test would assert over an empty list and prove nothing"
  # EVERY name, not `head -1`: there is one such message today, but nothing pins that, and
  # a second one landing earlier in the file would make a `head -1` assertion silently
  # check something other than what this message names.
  while read -r _named; do
    [ -n "$_named" ] || continue
    grep '^### ' "$WF" | grep -qF -- "$_named" \
      || fail "R6: harness-install.sh points readers at docs/WORKFLOW.md '$_named', but no '### ' heading in docs/WORKFLOW.md contains that name — the pointer resolves to nothing. The heading moves to match the message, never the reverse (harness-install.sh is DO NOT TOUCH for this feature)"
  done < "$T/wf-pointers"
  pass "E21-F05 R6 installer_restack_pointer_resolves"
}

# ── R7 ────────────────────────────────────────────────────────────────────────────────
# The lane leaks no bare spec-requirement id. `(R[0-9][0-9]*)` is a BRE in which the
# parentheses are literal (BSD grep, no -E and no escaping); the trailing `[0-9]*` is not
# cosmetic — `(R[0-9])` alone would miss `(R10)`, and this epic's specs are already at R9.
test_lane_leaks_no_spec_ids() {
  if span "$WF" "$LANE" | grep -q '(R[0-9][0-9]*)'; then
    _leak="$(span "$WF" "$LANE" | grep -o '(R[0-9][0-9]*)' | tr '\n' ' ')"
    fail "R7: the '$LANE' section leaks bare spec-requirement id(s) [ $_leak] into a user-facing document — a reader of docs/WORKFLOW.md cannot resolve them, and they name requirements of a spec that no longer matches the text"
  fi
  pass "E21-F05 R7 lane_leaks_no_spec_ids"
}

# ── R8 ────────────────────────────────────────────────────────────────────────────────
# The lane's DOCUMENTATION ships with the harness body regardless of pr_loop.enabled; only
# the lane's BEHAVIOR is gated. Two halves, and the second is labelled for what it is.
test_lane_ships_when_pr_loop_disabled() {
  _oi="$(sect "$WF" '### Opt-in and inert-when-disabled')"
  [ -n "$_oi" ] \
    || fail "R8: docs/WORKFLOW.md has no '### Opt-in and inert-when-disabled' subsection in the $LANE section"
  printf '%s\n' "$_oi" | grep -q 'ships with the harness body' \
    || fail "R8: '### Opt-in and inert-when-disabled' does not contain the load-bearing phrase [ships with the harness body], asserted by tests/test_stacked_doctrine.sh — reword the sentence around it, not the phrase; the harness has ONE body, not a per-flag variant of it"
  printf '%s\n' "$_oi" | grep -q 'pr_loop.enabled' \
    || fail "R8: '### Opt-in and inert-when-disabled' does not name the config key [pr_loop.enabled] — the subsection has to say which flag gates the lane's behavior"
  # Lane-scoped, not subsection-scoped: a subsection-scoped ban would pass if the false
  # claim simply migrated one subsection over.
  if span "$WF" "$LANE" | grep -q 'documentation is stamped'; then
    fail "R8: the '$LANE' section still claims that stacking [documentation is stamped] conditionally — harness-install.sh copies HARNESS_BODY_PROSE (which contains 'docs') with no pr_loop condition, so every install carries this section; the installed-half assertion in this same test disproves the claim"
  fi

  # ── Installed half — A REGRESSION GUARD, and labelled as one. ───────────────────────
  # It passes on an unedited tree by construction (the prose copy has no pr_loop branch),
  # and that is the point: it is what a reader actually RECEIVES, and it fails the day
  # someone makes that copy conditional. It is the one assertion in this suite whose only
  # mutation lives in DO-NOT-TOUCH harness-install.sh; see progress/ for the fixture-copy
  # proof that it discriminates.
  _tgt="$T/r8-gate-off"
  mkdir -p "$_tgt/home" "$_tgt/ch" "$_tgt/target"
  # HOME is sandboxed as well as CODEX_HOME: install_at() in tests/test_pr_loop.sh sets
  # only the latter, and harness-install.sh falls back to ${HOME}/.codex/prompts when
  # CODEX_HOME is unset — so a future refactor of that fallback must not be able to reach
  # the developer's home. A fresh install seeds `pr_loop.enabled: false`, so the gate is
  # already off and no flag is needed.
  HOME="$_tgt/home" CODEX_HOME="$_tgt/ch" \
    sh "$SRC/harness-install.sh" "$_tgt/target" >"$_tgt/.out" 2>"$_tgt/.err" \
    || { cat "$_tgt/.err" >&2; fail "R8: the installer exited non-zero installing into a gate-off fixture, so the installed-half assertion could not run"; }
  _inst="$_tgt/target/.harness/docs/WORKFLOW.md"
  [ -f "$_inst" ] \
    || fail "R8: a gate-off install produced no $_inst at all — docs/ is part of HARNESS_BODY_PROSE and must be stamped whatever pr_loop.enabled says"
  grep -q "$LANE" "$_inst" \
    || fail "R8: the installed docs/WORKFLOW.md of a gate-off install carries no '$LANE' section — the lane's documentation ships with the harness body regardless of the flag; only its behavior is gated"
  pass "E21-F05 R8 lane_ships_when_pr_loop_disabled"
}

# ── R9 ────────────────────────────────────────────────────────────────────────────────
# E21-F04's own shipped spec records that E21-F05 supersedes its R6, R7 and R8
# documentation requirements. One producing path: that section carried none of these five
# tokens before this feature (F04's R-ids live in `## Acceptance criteria (EARS)`, which
# `sect` does not read), so nothing pre-existing can satisfy it.
test_f04_supersession_recorded() {
  _rn="$(sect "$F04SPEC" '## Re-spec notes')"
  [ -n "$_rn" ] \
    || fail "R9: E21-F04's spec has no readable '## Re-spec notes' section — the supersession record is appended there"
  printf '%s\n' "$_rn" | grep -q 'E21-F05' \
    || fail "R9: E21-F04's '## Re-spec notes' does not name [E21-F05] — a reader of the done feature is left with a spec the shipped document contradicts"
  printf '%s\n' "$_rn" | grep -qi 'supersede' \
    || fail "R9: E21-F04's '## Re-spec notes' never says [supersede] — the verb is load-bearing: a note that merely MENTIONS R6/R7/R8 records nothing, and the requirement is that the supersession is recorded"
  for _r in R6 R7 R8; do
    printf '%s\n' "$_rn" | grep -q "$_r" \
      || fail "R9: E21-F04's '## Re-spec notes' does not name [$_r] among the superseded requirements — all three of R6, R7 and R8's documentation clauses are superseded by E21-F05"
  done
  pass "E21-F05 R9 f04_supersession_recorded"
}

test_entry_condition_stated_once
test_not_served_case_refused_once
test_outcome_stated_mechanically
test_board_shows_one_feature
test_seam_guidance_has_no_dangling_citation
test_installer_restack_pointer_resolves
test_lane_leaks_no_spec_ids
test_lane_ships_when_pr_loop_disabled
test_f04_supersession_recorded

echo "All stacked-PR doctrine tests passed."
