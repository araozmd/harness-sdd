#!/bin/sh
# test_scratch_and_disk_preconditions.sh — E99-F73: pin the two campaign preconditions
# that `agents/reviewer.md` (3d, 3e) and `agents/builder.md` now carry.
#
# WHY THIS SUITE EXISTS (read this before weakening anything in it):
#
#   Both rules were written because a parallel lane silently destroyed a review's work.
#
#   (3d) SCRATCH NAMESPACING. While the E10-F03 round-2 Reviewer was running a mutation
#        campaign in viernes-bookings-calendar, a different agent working E99-F54 in
#        viernes-bookings-api wrote an unrelated script to the SAME path —
#        `scratchpad/mut.py` — overwriting the running runner mid-campaign and crashing
#        it. No repo damage: the collision stayed inside the scratchpad and the Reviewer
#        confirmed the repo byte-clean. The danger is that NOTHING WARNED EITHER AGENT.
#        Recovery depended on one of them noticing.
#
#   (3e) DISK PRECONDITION. During the E10-F03 round-3 review the volume hit ENOSPC at 0
#        bytes free — a concurrent agent's `npm install` transiently took ~18 GB. The
#        backups survived (md5-verified, restored, a diff against the index came back
#        empty). The danger there is
#        THE SIGNAL, not the outage: an entire M1-M8 run came back PARSE-FAIL and failing
#        across the board, which is the exact shape of a set of REAL KILLS. A less careful
#        reader would have read a broken machine as evidence that the code was pinned.
#
#   Both are prose rules in role files, and a prose rule that nothing tests gets silently
#   weakened — that is the whole lesson of E99-F67 (#133), which spent seven rounds on
#   exactly this. Hence this suite.
#
# HOW IT ASSERTS — SCOPED, THEN ANCHORED (technique borrowed from
# tests/test_reviewer_mutation_mandate.sh, which earned it the hard way):
#
#   1. SECTION-SCOPED. Nothing here greps a whole file. `agents/reviewer.md` is narrowed to
#      numbered check 3 of `## What you check` (keyed on the list NUMBER, because "check 3d"
#      is a citation of that number), then to the `(3d)` / `(3e)` sub-block.
#      `agents/builder.md` is narrowed by HEADING, using the very extraction recipe that
#      file's own Principles section prescribes. A whole-file grep would be satisfied by any
#      unrelated occurrence — including one the change itself added.
#   2. SENTENCE-ANCHORED. Each load-bearing assertion pins a semantic to the token that
#      carries it through `[^.]{0,N}`, which keeps the match inside ONE SENTENCE. Presence
#      of the right vocabulary somewhere in the block is not force; #133's round 1 shipped
#      an INVERTED revert rule that stayed green on independent un-anchored greps.
#   3. NEGATIVE SPACE. R7 fails on optionality markers anywhere in the two new blocks. #133
#      measured that a mutation which keeps every label and keyword while negating every
#      obligation passes a presence check and fails an absence check.
#   4. BOTH FILES, SAME ASSERTIONS. `scratch_checks()` and `disk_checks()` are run once
#      against the Reviewer's blocks and once against the Builder's section, so deleting the
#      rule from EITHER file reddens. The brief for E99-F73 named both files; a suite that
#      checked one of them would let the other rot.
#
# WHAT THIS SUITE DOES *NOT* PIN — a MEASUREMENT LOG, not a closure claim.
#
# #133 had FOUR consecutive drafts of this paragraph assert that a CLASS of edit was closed,
# and all four were false in the same direction: over-claiming. So no claim about a class is
# made here. What follows is what was RUN and what CAME BACK. Mutations were applied to
# `agents/reviewer.md` or `agents/builder.md` ONE AT A TIME, backed up with `cp <file>
# <file>.mutbak` and restored with `mv`, never `git checkout -- <file>`, with every restore
# confirmed by a diff rather than by a test run. Free space was 426.0 GiB before the campaign
# and 426.0 GiB after, and 12 of 14 vectors came back red — so this was NOT a mass-failure
# run and its output is readable as evidence (which is check (3e), applied to itself).
# "red" = the suite exits 1.
#
#   vector                                                          result
#   ── STRAIGHT DELETIONS (the rule removed) ───────────────────────────────────
#   M1  (3d) block deleted from agents/reviewer.md                   red (R1)
#   M2  (3e) block deleted from agents/reviewer.md                   red (R1)
#   M3  `## Scratch files and campaign preconditions` section
#       deleted from agents/builder.md                               red (R6)
#   ── HARDER: LABEL AND VOCABULARY KEPT, OBLIGATION DROPPED ───────────────────
#   M4  (3d) keeps its label and the whole incident narrative; the
#       path template and the write-obligation are replaced by
#       "Scratch files from different lanes have collided here
#       before."                                                     red (R2, on the
#                                                                    missing template)
#   M5  ⚠️ THE ONE THAT MATTERED. M4's twin with NOTHING left out but
#       the instruction: the narrative itself supplies the path
#       template ("writes its scratch straight to the scratchpad root
#       instead of under `scratchpad/<feature-id>-<role>/`"), the
#       prohibition ("it had never been told to keep out of the
#       scratchpad root"), the consequence and the rationale. Every
#       sentence is description; no sentence instructs anyone.       GREEN 10/10 at first
#                                                                    — all six substance
#                                                                    checks satisfied by
#                                                                    an anecdote. FIXED by
#                                                                    the R3 prefix anchor;
#                                                                    red (R3) since.
#   M12 M5's twin aimed at agents/builder.md                         red (R6 anchor)
#   M6  (3e) keeps its label, the ENOSPC narrative and the words
#       "free space", "suspect" and "healthy", but the before/after
#       obligation becomes a description of what happened once
#       ("the reviewer had read the free space beforehand")          red (R4)
#   M7  (3e) with "A mass-failure run is never evidence" deleted and
#       everything else byte-identical                               red (R5)
#   M8  builder.md section keeps its heading and both bullet labels;
#       both obligation sentences deleted, narratives kept           red (R6)
#   ── NEGATIVE SPACE ─────────────────────────────────────────────────────────
#   M9  one word added to (3e): "…is SUSPECT" -> "…is optionally
#       SUSPECT", everything else intact                             red (R7; also reddens
#                                                                    #133's R2c, which
#                                                                    scans all of check 3)
#   ── COUNTERMAND: THE ASSERTION SURVIVES, THE RULE DOES NOT ──────────────────
#   M10 (3d)'s obligation left BYTE-IDENTICAL, one sentence APPENDED:
#       "In practice a flat `scratchpad/` is fine for a short run,
#       and the template above is a convention for long campaigns
#       rather than a requirement."                                  GREEN
#   M11 #133's P1 vector aimed at the NEW R3 anchor: the span's head
#       is a byte-verbatim copy of the obligation clause, followed by
#       "*That was the rule as it stood before it was retired*" and a
#       repeal. A copy that IS first satisfies a prefix anchor.      GREEN
#   ── LEGITIMATE REFORMATS (must NOT be red) ─────────────────────────────────
#   X1  (3d) re-wrapped across different line breaks                 GREEN
#   X2  builder section's list marker "-" -> "*"                     GREEN (was a FALSE
#                                                                    RED until the span
#                                                                    markers dropped the
#                                                                    hard-coded "- ")
#
# ⚠️ TWO GREENS REMAIN, M10 AND M11, AND NEITHER IS FIXED. They are one shape — TEXT THAT
# COUNTERMANDS AN ASSERTION THE CHECKS STILL FIND — and it is the same residual #133 measured
# across eight probes (M12, M21, X7, X8, X9, B1, B2, P1) and deliberately declined to close,
# because "no later sentence may rehabilitate what an earlier one forbids" is open-ended with
# no provably bounded cost. Nothing here closes it either. M11 is the sharper of the two: it
# reasons past R3's own aside that "a copy further down does not count" — true as written, and
# silent on a copy that is FIRST.
#
# Do not read a green run as proof that these blocks MEAN what they say — only that they
# still SAY it, in the words recorded here. The log above is the set that was TRIED, not the
# set that EXISTS.
#   - Also unpinnable by construction: whether an agent actually RAN `df` or actually
#     namespaced its scratch. That is behaviour; these are text files. Only a review of the
#     review can see it.
#   - R8's "reachable from verification.test_command" half is evaluated from INSIDE this
#     suite, so it can only ever run where the answer is already yes. The guard that
#     survives a rename out of the `tests/test_*.sh` glob lives in a DIFFERENT suite —
#     `tests/test_reviewer.sh` R17 — and R8 asserts that guard is still there.
#
# Zero dependencies: POSIX sh + awk + grep + sed. Reads only; writes nothing.

set -eu
LC_ALL=C; export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$SRC"

REVIEWER="agents/reviewer.md"
BUILDER="agents/builder.md"
BUILDER_HEADING="Scratch files and campaign preconditions"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

[ -f "$REVIEWER" ] || fail "R1: $REVIEWER is missing"
[ -f "$BUILDER" ]  || fail "R1: $BUILDER is missing"

# ── extraction ────────────────────────────────────────────────────────────────────
#
# check3 — numbered item 3 of `## What you check`, and nothing else. Keyed on the list
# NUMBER, not on the item's title: "check 3d" is a citation of that number, so if the
# sub-checks are renumbered or moved under another item every citation in the wild breaks
# and this must go red.
check3() { awk '/^3\. /{k=1} /^4\. /{k=0} k' "$REVIEWER"; }

# span <start-marker> <end-marker> — stdin narrowed to [start, end). An empty <end-marker>
# runs to the end of the input.
span() {
  awk -v s="$1" -v e="$2" '
    index($0, s) { k = 1 }
    e != "" && index($0, e) { k = 0 }
    k
  '
}

# section <heading-text> — the body under a markdown heading containing <heading-text>, up
# to the next heading of any level. This is VERBATIM the recipe agents/builder.md prescribes
# for exactly this situation ("A test that asserts a PROSE contract must grep the SECTION it
# names"); using the documented recipe means a reader can check this extraction against the
# rule it implements without reverse-engineering it.
section() { awk -v h="$1" '/^#+ /{k=(index($0,h)>0);next} k' "$BUILDER"; }

# flat — one line, markdown emphasis removed, runs of BLANKS (spaces AND tabs) squeezed to
# one space. Wrapping is a formatting choice; the contract is the sentence. Squeezing is
# also what makes the `[^.]{0,N}` sentence anchors work across a line break. Blanks, not
# spaces: #133 shipped `tr -s ' '` under a comment claiming "whitespace" and a tab used as a
# continuation indent produced a FALSE RED.
flat() { sed 's/[*`]//g' | tr '\n' ' ' | sed 's/[[:blank:]][[:blank:]]*/ /g'; }

C3="$(check3)"
[ -n "$C3" ] || fail "R1: could not extract check 3 from $REVIEWER — the '## What you check' list is not numbered as expected"

D3="$(printf '%s\n' "$C3" | span '**(3d)' '**(3e)' | flat)"
E3="$(printf '%s\n' "$C3" | span '**(3e)' ''       | flat)"
BSEC="$(section "$BUILDER_HEADING" | flat)"
# ⚠️ The span markers carry NO list marker. Spelling them `- **Namespace…` was a FALSE RED
# on probe X2, a repo-wide markdown reformat of `-` to `*`: the bullet still existed and
# still said everything it had to, and R6 failed claiming it was absent. `head_of()` below
# already tolerates either marker; the span has to as well, or the tolerance is decorative.
# A false red conceals no hole, but it is exactly what pushes the next maintainer to relax
# the check.
BNS="$(section "$BUILDER_HEADING" | span '**Namespace every scratch file' '**Check the free disk' | flat)"

# head_of — a block's opening text with leading whitespace (INCLUDING TABS) and a `-`/`+`
# list marker stripped. Used only by the prefix anchors below. This normalises LIST SYNTAX
# around the sentence; it introduces no window over the sentence itself. (`flat()`'s
# `sed 's/[*`]//g'` already deletes a `*` marker outright, so only `-` and `+` survive to be
# stripped here. A tab-indented or re-markered block would otherwise be a FALSE RED, which is
# exactly what teaches the next maintainer to relax a check.)
head_of() { printf '%s' "$1" | sed 's/^[[:space:]]*//; s/^[-+][[:space:]]*//'; }

# ── R1: the citations resolve — 3d and 3e are labelled, under check 3 ────────────
printf '%s\n' "$C3" | grep -qF '(3d)' \
  || fail "R1: check 3 of $REVIEWER contains no literal '(3d)' label — every 'reviewer.md check 3d' citation resolves to nothing"
printf '%s\n' "$C3" | grep -qF '(3e)' \
  || fail "R1: check 3 of $REVIEWER contains no literal '(3e)' label — every 'reviewer.md check 3e' citation resolves to nothing"
[ -n "$D3" ] || fail "R1: the (3d) sub-block extracted empty"
[ -n "$E3" ] || fail "R1: the (3e) sub-block extracted empty"
pass "R1 labels_3d_3e_present_under_check_3"

# ── shared substance checks, run against BOTH role files ─────────────────────────
#
# $1 = flattened block, $2 = "<rule-id> <file>" for the failure message. Every assertion
# below is about SUBSTANCE — an obligation tied to the thing it obliges, inside one sentence
# — not about a keyword being present somewhere in the block.

scratch_checks() {
  _b="$1"; _w="$2"

  # (a) THE PATH TEMPLATE, LITERALLY. The rule is worthless without the shape it mandates:
  # "namespace your scratch" with no template is advice nobody can follow identically, and
  # two agents that namespace differently collide exactly as before. Pinned as a literal
  # rather than a pattern so it is auditable BY READING.
  printf '%s\n' "$_b" | grep -qF 'scratchpad/<feature-id>-<role>/' \
    || fail "$_w: the scratch rule does not give the literal path template 'scratchpad/<feature-id>-<role>/' — a namespacing rule with no agreed shape does not prevent a collision, it just moves it. ⚠️ IF YOU LEGITIMATELY CHANGED THE TEMPLATE, EDIT THIS LITERAL IN THE SAME COMMIT."

  # (b) THE TEMPLATE IS THE DESTINATION OF A WRITE — not decoration. Anchored to one
  # sentence so a template quoted inside the incident narrative ("it wrote to X rather than
  # Y") cannot satisfy the obligation on its own.
  printf '%s\n' "$_b" | grep -qiE '(write|writes|written|goes|go|put|placed?) [^.]{0,160}scratchpad/<feature-id>-<role>/' \
    || fail "$_w: the scratch rule never ties the act of WRITING a scratch file to 'scratchpad/<feature-id>-<role>/' in one sentence — a template that appears without an instruction attached is an illustration, not a rule"

  # (c) BOTH DISCRIMINANTS. Feature id alone collides across roles in the same lane; role
  # alone collides across lanes. The brief specified both, so both are pinned.
  printf '%s\n' "$_b" | grep -qiE 'feature[- ]?id[^.]{0,25}(and|plus|\+)[^.]{0,25}role' \
    || fail "$_w: the scratch rule does not require namespacing by FEATURE ID **and** ROLE together — either one alone still collides (same lane, two roles; or two lanes, same role)"

  # (d) NEGATIVE SPACE, spelled out. The incident path was the scratchpad ROOT, so the rule
  # has to close it by name; "prefer a subdirectory" leaves the crash reachable.
  printf '%s\n' "$_b" | grep -qiE 'never[^.]{0,60}scratchpad root' \
    || fail "$_w: the scratch rule does not forbid writing at the SCRATCHPAD ROOT by name — that is the exact path the E10-F03 collision used (scratchpad/mut.py)"

  # (e) THE CONSEQUENCE. Without it an agent that notices the overwrite still has to decide
  # what the half-run means, and the tempting answer is "mostly fine".
  printf '%s\n' "$_b" | grep -qiE '(replaced|overwritten|overwrote|clobbered)[^.]{0,90}(produced no result|is not a result|no result|void)' \
    || fail "$_w: the scratch rule does not say what a run whose runner was REPLACED under it is worth — it must state that such a run produced NO RESULT, or the agent is left to salvage a corrupted campaign"

  # (f) THE REASON. #133's R9 is the model: a rule whose rationale is missing reads as
  # ceremony and gets waived. The rationale here is specifically that nothing warns you.
  printf '%s\n' "$_b" | grep -qiE 'collision is silent' \
    || fail "$_w: the scratch rule does not record that the collision is SILENT — that is the entire reason it needs a convention rather than vigilance"
}

disk_checks() {
  _b="$1"; _w="$2"

  # (a) BEFORE. A campaign that starts on a sick machine produces nothing readable.
  printf '%s\n' "$_b" | grep -qiE 'free space[^.]{0,120}before the first mutation' \
    || fail "$_w: the disk rule does not require reading the FREE SPACE BEFORE THE FIRST MUTATION, in one sentence — a precondition checked at some unspecified time is not a precondition"

  # (b) AND AGAIN AFTER. This is the half that actually caught the ENOSPC: the volume was
  # healthy at the start and empty by the end. A single up-front check would have passed and
  # the run would still have been noise.
  printf '%s\n' "$_b" | grep -qiE '(again|re-?read|re-?check)[^.]{0,40}before you trust' \
    || fail "$_w: the disk rule does not require RE-READING the free space BEFORE THE RESULTS ARE TRUSTED — the E10-F03 volume was healthy at the start of the run and at 0 bytes by the end, so an up-front-only check passes and still yields noise"

  # (c) THE VERDICT RULE — mass failure is SUSPECT. Anchored: 'suspect' has to be the
  # verdict ON a mass-failure run, not a word used about something else in the block.
  printf '%s\n' "$_b" | grep -qiE '(most mutations fail|fail to parse|failing across the board|mass[- ]failure)[^.]{0,90}suspect' \
    || fail "$_w: the disk rule does not declare a MASS-FAILURE / PARSE-FAIL run SUSPECT, in one sentence — that run shape is the whole hazard: it is indistinguishable from a set of real kills"

  # (d) SUSPECT UNTIL WHAT? An open-ended suspicion is discharged by shrugging. The rule has
  # to name the condition that lifts it.
  printf '%s\n' "$_b" | grep -qiE 'suspect[^.]{0,60}until[^.]{0,60}(environment|machine)[^.]{0,40}(healthy|health)' \
    || fail "$_w: the disk rule marks a run suspect but does not say what LIFTS the suspicion (the environment being confirmed healthy) — a suspicion with no discharge condition is discharged by whoever is in a hurry"

  # (e) THE BRIGHT LINE. (c) and (d) tell the agent to doubt; this one forbids the specific
  # misreading that motivated the whole rule. Pinned tightly because it is one sentence and
  # it is the point.
  printf '%s\n' "$_b" | grep -qiE 'mass[- ]failure run is never evidence' \
    || fail "$_w: the disk rule does not state flatly that a MASS-FAILURE RUN IS NEVER EVIDENCE — 'treat with care' leaves the reading that produced this rule available, which is that a broken machine proved the code was pinned"

  # (f) THE REASON, again: the outage does not look like an outage.
  printf '%s\n' "$_b" | grep -qiE 'shape of[^.]{0,25}real kills' \
    || fail "$_w: the disk rule does not record WHY a mass failure is dangerous — that it has the exact shape of a set of REAL KILLS. Without that, the rule reads as generic machine hygiene and gets skipped"
}

# ── R2: the Reviewer's (3d) ──────────────────────────────────────────────────────
scratch_checks "$D3" "R2: reviewer.md (3d)"
pass "R2 reviewer_3d_namespaces_scratch_by_feature_and_role"

# ── R3: the scratch rule must OPEN with its obligation, literally ────────────────
# WHY A PREFIX ANCHOR AND NOT A WIDER REGEX. Every assertion in `scratch_checks()` is
# satisfiable by DESCRIPTION rather than instruction, and that is measured, not feared:
# probe M5 rewrote (3d) so that no sentence told the reader to do anything — the incident
# narrative alone supplied the path template ("writes its scratch straight to the scratchpad
# root instead of under `scratchpad/<feature-id>-<role>/`"), the prohibition ("it had never
# been told to keep out of the scratchpad root"), the consequence and the rationale — and it
# was GREEN on all six. The obligation had been deleted and nothing noticed.
#
# The tempting repair is to tighten each window until M5 stops fitting. That is precisely the
# METHOD `tests/test_reviewer_mutation_mandate.sh` spent three rounds discovering to be
# wrong: windows re-sized by hand, each time declared closed, each time walked around by the
# next probe. So there is no new window here. The obligation clause is pinned as a LITERAL
# PREFIX via a shell `case` — no pattern language, one string to read — which is satisfied
# only by what the block STARTS with, so a copy of the wording quoted further down does not
# count.
#
# WHAT THIS DOES NOT CLOSE. #133's probe P1 defeated the same construction by making a decoy
# bullet that itself carries the label and quotes the clause verbatim into the span's HEAD,
# so the operative text below it is free to repeal the rule. That vector was re-run here as
# M11 and the result is in the header log. Read it there.
_h="$(head_of "$D3")"
case "$_h" in
  "(3d) Namespace every scratch file by feature id and role. Everything a campaign writes outside the repo under review — the mutation runner, a probe script, a captured log — is written under scratchpad/<feature-id>-<role>/"*) : ;;
  *) fail "R3: reviewer.md (3d) does not OPEN with its obligation. After the list marker the block must BEGIN with, literally: \"(3d) Namespace every scratch file by feature id and role. Everything a campaign writes outside the repo under review — the mutation runner, a probe script, a captured log — is written under scratchpad/<feature-id>-<role>/\" — nothing before it, nothing inserted anywhere in it, and a copy of it further down the block does not count. ⚠️ IF YOU REACHED THIS BY LEGITIMATELY REWORDING THAT CLAUSE, EDIT THIS LITERAL IN THE SAME COMMIT — do NOT relax it into a '[^.]{0,N}' window. Probe M5 showed that every other assertion in this suite is satisfied by an incident NARRATIVE with the instruction removed, and the window-widening method is how the equivalent check in tests/test_reviewer_mutation_mandate.sh was walked around three rounds running." ;;
esac
pass "R3 reviewer_3d_opens_with_the_obligation"

# ── R4/R5: the Reviewer's (3e) ───────────────────────────────────────────────────
disk_checks "$E3" "R4: reviewer.md (3e)"
pass "R4 reviewer_3e_free_space_precondition_and_recheck"

printf '%s\n' "$E3" | grep -qiE 'mass[- ]failure run is never evidence' \
  || fail "R5: reviewer.md (3e) lost the 'a mass-failure run is never evidence' bright line"
pass "R5 reviewer_3e_mass_failure_is_never_evidence"

# ── R6: the SAME two rules in agents/builder.md ──────────────────────────────────
# Builders mutate routinely (the Principles section sends them to revert a fix in place and
# watch the test fail) and write scratch files while doing it, so the Reviewer-side rule
# alone leaves half the agents that cause collisions ungoverned. E99-F73 named both files.
[ -n "$BSEC" ] \
  || fail "R6: agents/builder.md has no '## $BUILDER_HEADING' section — the Builder mutates routinely and writes scratch files, so pinning these rules only in reviewer.md leaves the other half of the collision surface unruled"
scratch_checks "$BSEC" "R6: builder.md '$BUILDER_HEADING'"
disk_checks    "$BSEC" "R6: builder.md '$BUILDER_HEADING'"
[ -n "$BNS" ] \
  || fail "R6: the builder.md section has no '- **Namespace every scratch file' bullet to anchor — the two rules must stay separable, or the prefix anchor below silently stops covering anything"
# Same prefix anchor as R3, for the same measured reason (M5), against the Builder's copy.
# The wording differs from the Reviewer's on purpose — that file addresses "the campaign",
# this one addresses "you" — so the literal is per-file rather than shared.
_hb="$(head_of "$BNS")"
case "$_hb" in
  "Namespace every scratch file by feature id and role. Everything you write outside the repo — a mutation runner, a probe script, a captured log — goes under scratchpad/<feature-id>-<role>/"*) : ;;
  *) fail "R6: the builder.md scratch bullet does not OPEN with its obligation. After the list marker it must BEGIN with, literally: \"Namespace every scratch file by feature id and role. Everything you write outside the repo — a mutation runner, a probe script, a captured log — goes under scratchpad/<feature-id>-<role>/\" — nothing before it, nothing inserted anywhere in it, and a copy further down does not count. ⚠️ IF YOU REWORDED IT LEGITIMATELY, EDIT THIS LITERAL IN THE SAME COMMIT — do NOT relax it into a '[^.]{0,N}' window (see R3's note and probe M5)." ;;
esac
pass "R6 builder.md_carries_both_preconditions"

# ── R6b: builder.md declares its GAP rather than implying completeness (3c) ──────
# reviewer.md (3b) records that builder.md carries no mutation-revert rule at all, and
# tests/test_reviewer_mutation_mandate.sh R7b pins that record. Adding a mutation-adjacent
# section to builder.md without saying what is still missing would make that record read as
# stale and quietly over-claim — the (3c) defect. So the section must name its own limit and
# its follow-up item.
printf '%s\n' "$BSEC" | grep -qiE 'not[^.]{0,20}the whole mutation-revert discipline|carries no rule for' \
  || fail "R6b: the builder.md section does not declare that it is NOT the whole mutation-revert discipline — a mutation-adjacent section that reads as complete is the (3c) over-claim, and reviewer.md (3b) still records builder.md as carrying no revert rule"
printf '%s\n' "$BSEC" | grep -qiE 'not yet enforced[^.]{0,40}E99-F102' \
  || fail "R6b: the builder.md section defers the revert half without naming the follow-up item (E99-F102) in the same sentence — reviewer.md (3c) requires the claim and its gap to travel together"
pass "R6b builder_section_declares_its_gap_and_names_the_followup"

# ── R7: NEGATIVE SPACE — no optionality marker in either new block ───────────────
# #133 measured that a mutation keeping every label and keyword while negating every
# obligation passes a presence check (14/14 green) and fails an absence check. Bare `may` is
# banned deliberately: in a precondition block there is no legitimate hedge, and carving out
# an exception is how this check rots. Measured before it was made — the alternations return
# zero matches over the current text, so it costs nothing today.
_NEW="$(printf '%s\n%s\n%s\n' "$D3" "$E3" "$BSEC")"
_opt="$(printf '%s\n' "$_NEW" | grep -oiwE 'may|optional|optionally|discretionary' | head -1 || :)"
[ -z "$_opt" ] \
  || fail "R7: the new precondition blocks contain the optionality marker '$_opt' — a precondition does not hedge"
_opt2="$(printf '%s\n' "$_NEW" | grep -oiE 'if time allows|not required|at your discretion|purely a convenience|nice to have|need not|only if you|where practical|when convenient|best effort' | head -1 || :)"
[ -z "$_opt2" ] \
  || fail "R7: the new precondition blocks contain the opt-out phrase '$_opt2' — a precondition does not offer an out"
pass "R7 new_blocks_carry_no_optionality"

# ── R8: reachable from verification.test_command + the CROSS-SUITE existence guard ─
# Two halves, and only the second survives this suite being renamed away:
#   (a) the config either names this suite or delegates to tools/run-tests.sh, which
#       DISCOVERS tests/test_*.sh. Asserting only one spelling would freeze a config detail
#       this suite has no stake in.
#   (b) tests/test_reviewer.sh R17 asserts THIS FILE EXISTS. That is the guard that goes red
#       when the suite is renamed out of the glob — #133 measured a rename that left the
#       runner cheerfully reporting "all N suites passed". A self-check cannot catch that:
#       it is only ever evaluated in the world where the answer is already yes.
_tc="$(sed -n 's/^[[:space:]]*test_command:[[:space:]]*"\([^"]*\)".*$/\1/p' "$SRC/harness.config.yaml")"
[ -n "$_tc" ] || fail "R8: harness.config.yaml declares no verification.test_command"
printf '%s\n' "$_tc" | grep -qF 'tests/test_scratch_and_disk_preconditions.sh' \
  || printf '%s\n' "$_tc" | grep -qF 'tools/run-tests.sh' \
  || fail "R8: this suite is not reachable from verification.test_command ('$_tc')"
[ -f "$SRC/tests/test_reviewer.sh" ] || fail "R8: tests/test_reviewer.sh is missing"
grep -qF 'tests/test_scratch_and_disk_preconditions.sh' "$SRC/tests/test_reviewer.sh" \
  || fail "R8: tests/test_reviewer.sh no longer carries the cross-suite existence guard (R17) — without it, renaming this file out of the tests/test_*.sh glob makes the (3d)/(3e) preconditions silently stop being checked while the runner still reports success"
pass "R8 reachable_and_externally_guarded"

# ── R9: the preconditions are recorded in the CHANGELOG ──────────────────────────
# Anywhere in the file, never pinned to the current release: the entry is append-only
# history, so a later version must not be forced to re-mention it.
#
# ⚠️ SEARCHED AS THE PARENTHESISED LABEL, NOT AS THE BARE TOKEN. The first draft of this
# assertion copied #133's R13 and grepped `-F '3d'` / `-F '3e'`, and it PASSED before the
# CHANGELOG entry was written: `3d` was supplied by "`test_board_lock.sh` gains R13dup" and
# `3e` by an unrelated line ~2130. Two green assertions naming a record that did not exist —
# the expected value was reachable by a path other than the one the message names, which is
# the defect agents/builder.md Principles describe. It survives here as the reason for the
# parentheses.
grep -qF '(3d)' CHANGELOG.md || fail "R9: CHANGELOG.md never records check (3d) — the scratch-namespacing precondition is absent from the release history"
grep -qF '(3e)' CHANGELOG.md || fail "R9: CHANGELOG.md never records check (3e) — the free-disk precondition is absent from the release history"
pass "R9 changelog_records_the_preconditions"

# ── R10: this suite's own hygiene ────────────────────────────────────────────────
# Permanent-suite rules (same as tests/test_agents_host.sh R29 and #133's R14): never diff
# against git, never freeze the VERSION string. The searched pattern is spelled with a
# character class and the message says "git's diff subcommand" rather than the literal two
# tokens, so neither line matches itself.
_self="$SRC/tests/test_scratch_and_disk_preconditions.sh"
grep -q 'git[[:space:]][[:space:]]*diff' "$_self" \
  && fail "R10: this suite invokes git's diff subcommand — a permanent suite must never diff a file against git"
grep -qF "$(tr -d ' \n\r\t' < VERSION)" "$_self" \
  && fail "R10: this suite contains the current VERSION string — a permanent suite must not freeze it"
pass "R10 suite_hygiene"

echo "All scratch/disk precondition tests passed."
