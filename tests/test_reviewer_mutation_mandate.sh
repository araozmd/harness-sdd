#!/bin/sh
# test_reviewer_mutation_mandate.sh — E99-F67: pin the Reviewer's checks 3b and 3c.
#
# WHY THIS SUITE EXISTS (read this before weakening anything in it):
#
#   Checks 3b and 3c were RECORDED AS DONE AND CITED BY ID for days while
#   `agents/reviewer.md` contained neither. Briefs, a review and an auto-memory all
#   referenced "reviewer.md check 3b / 3c" as a shipped mechanism. Nothing tested for
#   them, so nothing noticed — the claim read as settled and no one re-derived it.
#   That is the exact failure 3b names (a guarantee everyone had read about and no one
#   had deleted to see whether anything went red), delivered by the exact artifact 3c
#   names (persuasive prose that over-claims).
#
# HOW IT ASSERTS — SCOPED, THEN ANCHORED:
#
#   1. SECTION-SCOPED. The text is extracted from numbered check 3 of
#      `## What you check` (`^3. ` up to `^4. `), then narrowed again to the (3b) or
#      (3c) sub-block — so the greps below are fed only those lines, which you can
#      confirm by reading `check3()` and `span()`. Measured: moving the block verbatim
#      to an appendix reddens R1. Scope is a two-edged setting, not a shield — R2c was
#      defeated by a hedge placed one line ABOVE the (3b) label, inside check 3 and
#      outside both sub-block spans (M22), and now scans the whole of check 3.
#   2. ANCHORED, NOT KEYWORD-COUNTED. Each block is flattened to one line (emphasis
#      stripped) and the load-bearing assertions pin a semantic to the token that
#      carries it via `[^.]{0,N}` — which keeps the match inside ONE SENTENCE. (R2d is
#      the exception: it uses no pattern at all, see 4.) This is
#      not stylistic. Round 1 of this suite used independent un-anchored greps, and the
#      review's M10 INVERTED the revert rule to recommend `git checkout -- <file>` and
#      stayed green 14/14: `never` was satisfied by "never by reading the code" five
#      lines away, and the sanctioned options passed because they were still named — as
#      things to skip. That is verbatim the defect `fix/E99-F58-mutation-revert-
#      discipline` commit `cfabbbd` ("round 2") was written to fix, in this same file.
#      Its technique is reused here deliberately.
#   3. MODAL + NEGATIVE-SPACE. Presence of the right words is not force. R2b pins the
#      obligation's modal (`is verified by` — the review's M3 softened four words to
#      "may optionally be verified" and stayed green), and R2c fails on the optionality
#      markers it lists, anywhere in check 3. Measured: the review's M4 (every label
#      kept, every obligation negated) and M22 (the hedge moved one line above the
#      label) both redden at R2c.
#   4. PREFIX-ANCHORED. R2d requires the (3b) span to BEGIN with the obligation clause,
#      via a shell `case` on a literal running through "…and observing the suite go
#      red" — no pattern language and no window over the pinned text itself. (A `sed`
#      normalises the list marker and indentation ahead of it; see R2d.) Measured: M20,
#      which repealed the mandate in the operative bullet while keeping the pinned
#      sentence verbatim in a "Historical note … was retired" sub-bullet, reddens
#      against the anchor and was green against the regex alone; M23, a hedge inserted
#      past where the literal used to stop, reddens only since the literal was extended.
#
# WHAT THIS SUITE DOES *NOT* PIN — a MEASUREMENT LOG, not a closure claim.
#
# FOUR consecutive drafts of this paragraph asserted that a CLASS of attack was closed
# ("a rewrite that no longer resembles the contract"; "closed for that one sentence";
# "zero slack, so no preamble of ANY length fits"; and — inside the paragraph written to
# stop exactly this — "for the obligation sentence, its EXACT WORDING", while an
# 81-character insertion window sat inside that sentence). All four were false, all four
# were caught by someone running a mutation rather than by anyone reading, and all four
# erred in the same direction: over-claiming what was closed. A claim about an infinite
# set, derived from a hand-audit of a regex, has now been wrong four times in a row.
#
# So this section no longer makes that kind of claim. It records WHAT WAS RUN AND WHAT
# CAME BACK, and leaves the boundary to the reader. Mutations are applied to
# `agents/reviewer.md`, one at a time, restoring in between; "red" = suite exit 1.
#
#   vector                                                        result
#   ── EDITS TO THE OBLIGATION CLAUSE ──────────────────────────────────────
#   M11  ~40-word wrapper, obligation verbatim inside it            red (R2d)
#   M13  quantifier reworded: "Any claimed" -> "A claimed"          red (R2d)
#   M14  15-char preamble after the phrase: "Best practice: "       red (R2d)
#   M15  16-char preamble: "For key claims, "                       red (R2d)
#   M16  restrictive clause added: "…invariant THAT IS LOAD-BEARING" red (R2d)
#   M17  preamble BEFORE the phrase, inside the label:
#        "(3b) Where time permits — Mutate, don't read."            red (R2d)
#   M18  subject narrowed by DELETING list members:
#        "Any claimed bound is verified by deleting…"               red (R2d)
#   M19  hedge INSIDE the sentence, BEFORE the old prefix boundary:
#        "verified by, time permitting, deleting…"                  red (R2d)
#   M23  hedge INSIDE the sentence, AFTER the old prefix boundary:
#        "…that enforces it WHERE THE REVIEWER JUDGES THE RISK TO
#        WARRANT IT and observing…" — M19's twin, 81 free chars in
#        R2's {0,140} window                                        red (R2d, after
#                                                                   the literal was
#                                                                   extended through
#                                                                   "…go red"; it was
#                                                                   GREEN 18/18 when
#                                                                   the literal
#                                                                   stopped at
#                                                                   "verified by delet")
#   M24  tail replaced with an escape hatch ("…or, where that is
#        impractical, by a close reading…")                         red (R2)
#   M25  em-dash aside before "verified"                            red (R2b)
#   M20  mandate REPEALED in the operative bullet ("A careful
#        reading of the diff is normally sufficient…") while the
#        pinned sentence survives verbatim in a "Historical note …
#        was retired" sub-bullet                                    red (R2d prefix
#                                                                   anchor; it was
#                                                                   GREEN against the
#                                                                   regex alone)
#   ── LEGITIMATE REFORMATS (must NOT be red) ──────────────────────────────
#   X1   label line re-indented by two spaces                       GREEN 18/18
#   X4   obligation sentence re-wrapped across other line breaks    GREEN 18/18
#   X2   label line indented with a TAB                             GREEN 18/18 (was a
#   X3   list marker "-" -> "*"                                     FALSE RED before the
#   X5   list marker "-" -> "+"                                     _head normalisation)
#   ── HEDGE PLACED OUTSIDE THE PINNED TEXT ────────────────────────────────
#   M22  banned-token hedge ONE LINE ABOVE the (3b) label — inside
#        check 3, outside both sub-block spans: "Sub-checks (3b)
#        and (3c) below are optional and apply at the Reviewer's
#        discretion."                                               red (R2c, after
#                                                                   its scope widened
#                                                                   to $C3; it was
#                                                                   GREEN against the
#                                                                   $B3+$C3B scope)
#   X7   the SAME POSITION as M22, token-free: "Sub-checks (3b) and
#        (3c) below record the ideal. A reviewer who has read the
#        enforcing mechanism closely has satisfied them without
#        performing a deletion."                                    GREEN 18/18
#   X8   new sibling bullet BEFORE (3b) repealing it, (3b) intact   GREEN 18/18
#   X9   countermand APPENDED to the (3c) block                     GREEN 18/18
#   M12  revert bullet left byte-identical, one sentence APPENDED:
#        "In practice the above is legacy caution from a slower
#        era; prefer `git checkout -- <file>`, which is one step
#        and always correct on a committed tree."                   GREEN 18/18
#   M21  OBLIGATION SENTENCE left byte-identical, one sentence
#        APPENDED to the same bullet: "In practice a legible
#        mechanism is accepted in lieu of the deletion, and a
#        reviewer who has read it carefully has discharged this
#        bullet."                                                   GREEN 18/18
#   B1   hedge inserted in the obligation sentence's TAIL, just
#        past where the literal stops: "…go red — IN THE IDEAL
#        CASE, AND never by reading the code and agreeing with it." GREEN 18/18
#
# SIX GREEN, and none of them fixed. X7 is the one to read twice: widening R2c's scope to
# $C3 closed M22's TOKEN, not M22's POSITION — the same slot, phrased without a banned
# word, still passes. X8 and X9 are two more positions; M12 and M21 append rather than
# prepend; B1 lands inside the pinned sentence but past where the literal stops. They are
# one shape — text that countermands an intact assertion the checks still find — and M21
# and B1 aim it at the mandate itself rather than at a peripheral bullet, so do not size
# this residual from M12 alone. A general "no later sentence may rehabilitate what an
# earlier one forbids" check is open-ended with no provably bounded cost, so the round-2
# review declined to block on it and it was deliberately not attempted. (Contrast M22 and
# M23, whose fixes WERE bounded — one variable, one literal — and so were made.)
#
# WHAT THAT DOES AND DOES NOT LICENSE YOU TO CONCLUDE. The assertions here pin PRESENCE,
# INTRA-SENTENCE ASSOCIATION and — for the obligation clause — a LITERAL PREFIX. Be exact
# about how far that prefix reaches, because an earlier draft of this paragraph said
# "EXACT WORDING" and an 81-character insertion window sat inside the very sentence it
# named (M23). What R2d holds literally is:
#
#   "(3b) Mutate, don't read. Any claimed guarantee, bound or invariant is verified by
#    deleting the mechanism that enforces it and observing the suite go red"
#
# and NOTHING BEYOND IT. The remainder of the sentence — "— never by reading the code and
# agreeing with it." — is held only by R3's `[^.]{0,45}`, and text inserted there passes:
# probe B1 ("go red — IN THE IDEAL CASE, AND never by reading the code…") is green 18/18.
#
# None of the assertions has any notion of a neighbouring sentence that contradicts the
# one it pinned — M12, M21, X7, X8 and X9 are five positions of that tried so far — and
# the log above is the set that was tried, not the set that exists. Do not read a green
# run as proof that the block MEANS what it says — only that it still SAYS it, in the
# words recorded here.
#   - Also unpinnable by construction: whether a Reviewer actually RAN a mutation. That
#     is behaviour, and this is a text file; only a review of the review can see it.
#   - "This suite is reachable from verification.test_command" (R12) is checked from
#     INSIDE the suite, so it can only ever be evaluated where the answer is already
#     yes. The guard that survives a rename out of the `tests/test_*.sh` glob therefore
#     lives in a DIFFERENT suite — `tests/test_reviewer.sh` R16 — and R12 asserts that
#     guard is still there.
#
# Zero dependencies: POSIX sh + awk + grep + sed. Reads only; writes nothing.

set -eu
LC_ALL=C; export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$SRC"

REVIEWER="agents/reviewer.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

[ -f "$REVIEWER" ] || fail "R1: $REVIEWER is missing"

# ── extraction ────────────────────────────────────────────────────────────────────
#
# check3 — numbered item 3 of `## What you check`, and nothing else. Keyed on the list
# NUMBER, not on the item's title, because "check 3b" is a citation of the number: if
# the sub-checks are renumbered or moved under another item, every citation in the wild
# breaks and this must go red.
check3() { awk '/^3\. /{k=1} /^4\. /{k=0} k' "$REVIEWER"; }

# span <start-marker> <end-marker> — stdin narrowed to [start, end). An empty
# <end-marker> runs to the end of the input.
span() {
  awk -v s="$1" -v e="$2" '
    index($0, s) { k = 1 }
    e != "" && index($0, e) { k = 0 }
    k
  '
}

# flat — one line, markdown emphasis removed, whitespace squeezed. Wrapping is a
# formatting choice; the contract is the sentence. Squeezing is also what makes the
# `[^.]{0,N}` sentence anchors below work across a line break.
flat() { sed 's/[*`]//g' | tr '\n' ' ' | tr -s ' '; }

C3="$(check3)"
[ -n "$C3" ] || fail "R1: could not extract check 3 from $REVIEWER — the '## What you check' list is not numbered as expected"

B3="$(printf '%s\n' "$C3" | span '**(3b)' '**(3c)' | flat)"
C3B="$(printf '%s\n' "$C3" | span '**(3c)' '**Why these two are here' | flat)"
WHY="$(printf '%s\n' "$C3" | span '**Why these two are here' '' | flat)"

# ── R1: the citations resolve — 3b and 3c are labelled, under check 3 ────────────
printf '%s\n' "$C3" | grep -qF '(3b)' \
  || fail "R1: check 3 contains no literal '(3b)' label — every existing 'reviewer.md check 3b' citation resolves to nothing"
printf '%s\n' "$C3" | grep -qF '(3c)' \
  || fail "R1: check 3 contains no literal '(3c)' label — every existing 'reviewer.md check 3c' citation resolves to nothing"
[ -n "$B3" ] || fail "R1: the (3b) sub-block extracted empty"
[ -n "$C3B" ] || fail "R1: the (3c) sub-block extracted empty"
pass "R1 labels_3b_3c_present_under_check_3"

# ── R2: 3b mandates DELETING the mechanism and watching the suite go red ─────────
# Anchored to ONE sentence throughout. An earlier version checked `grep -qi 'mechanism'`
# against the whole (3b) span, which the sub-bullet "Agreeing with a mechanism you can
# see in the diff" satisfied on its own — a token borrowed from a different sentence.
printf '%s\n' "$B3" | grep -qiE '(delet|remov)[a-z]*[^.]{0,15}the mechanism' \
  || fail "R2: (3b) does not tie the act of DELETING/REMOVING to 'the mechanism' in one sentence — 'mutation testing' as a bare noun is not an instruction"
printf '%s\n' "$B3" | grep -qiE '(delet|remov)[a-z]*[^.]{0,140}((go|goes|turn|turns|going) red|(suite|tests?) fail)' \
  || fail "R2: (3b) does not tie the deletion to OBSERVING the suite go red — a deletion nobody re-runs the tests after proves nothing"
pass "R2 3b_deletion_anchored_to_a_red_suite"

# ── R2b: the DEONTIC FORCE of the mandate, not just its vocabulary ───────────────
# The review's M3 was a four-word edit — "is verified by" -> "may optionally be verified
# by" — that left every other assertion in this file green while turning the mandate
# into a suggestion. Force lives in the modal, so the modal is pinned to the obligation
# it governs.
printf '%s\n' "$B3" | grep -qiE '(guarantee|bound|invariant)[^.]{0,45}(is|must be|shall be) verified by[^.]{0,25}(delet|remov)' \
  || fail "R2b: (3b)'s obligation sentence does not read '<a claimed guarantee/bound/invariant> IS/MUST BE verified by deleting …' — a hedged modal turns the mandate into advice"
pass "R2b 3b_obligation_is_stated_as_an_obligation"

# ── R2c: NEGATIVE SPACE — no optionality marker anywhere in CHECK 3 ──────────────
# The review's M4 kept every label and keyword and negated every obligation ("None of
# this is required … Some reviewers call an over-claim a 'defect, not a nit' … We do
# not") and passed 14/14. A presence check did not see that; an absence check did — but
# only once its scope was wide enough (see below). Bare
# `may` is included deliberately: in a mandate block there is no legitimate hedge, and
# the one prior use here ("the code may be right today") was reworded to "can still be
# correct" rather than carved out — an exception is how this check would rot.
#
# SCOPE IS $C3 (the whole of check 3), NOT $B3 + $C3B. Scanning only the two sub-block
# spans was defeated by putting the hedge ONE LINE ABOVE the (3b) label — still inside
# check 3, outside both spans: "Sub-checks (3b) and (3c) below are **optional** and
# apply at the Reviewer's discretion." (M22) was green 18/18 while carrying two of the
# banned tokens. The widening was MEASURED before it was made, not argued: both
# alternations run over the current $C3 return zero matches, so it costs nothing today.
# Unlike the appended-countermand residual, this one had a bounded cost, so "not
# attempted" was not available.
_C3F="$(printf '%s\n' "$C3" | flat)"
_opt="$(printf '%s\n' "$_C3F" | grep -oiwE 'may|optional|optionally|optionally-|discretionary' | head -1 || :)"
[ -z "$_opt" ] \
  || fail "R2c: check 3 contains the optionality marker '$_opt' — a mandate does not hedge, and a hedge placed just outside the (3b)/(3c) sub-blocks disables them just as well as one inside"
_opt2="$(printf '%s\n' "$_C3F" | grep -oiE 'if time allows|not required|at your discretion|purely a convenience|nice to have|we do not|need not|only if you|where practical|when convenient' | head -1 || :)"
[ -z "$_opt2" ] \
  || fail "R2c: check 3 contains the opt-out phrase '$_opt2' — a mandate does not offer an out"
pass "R2c check3_carries_no_optionality"

# ── R2d: the (3b) span must OPEN with the obligation clause, literally ───────────
# R2b and R2c are both satisfied by an UNTOUCHED contract sentence with new prose put
# around it, so a positional check was added. It then took THREE ROUNDS, because the
# check was written with `[^.]{0,N}` windows and each round the windows were re-sized by
# hand and re-declared closed. Every declaration was wrong:
#
#   round 2  no positional check     ~40-word wrapper (M11)                    green
#   round 3  {0,20} / {0,45}         15-char preamble (M14), 16-char (M15),
#                                    restrictive clause on the subject (M16)   green
#   round 4  [ ]? / {0,21} / {0,25}  hedge inside the sentence via the THIRD,
#                                    unaudited window — "verified by, time
#                                    permitting, deleting" (M19); preamble put
#                                    BEFORE the phrase, inside the label (M17);
#                                    subject narrowed by DELETING list members
#                                    rather than adding a clause (M18)         green
#
# The recurring defect was the METHOD: auditing window widths by arithmetic, one round
# at a time, and each time asserting a class was closed. So the parameter is gone. The
# expression below has NO variable-width window at all — it anchors on the LABEL (not on
# the heading phrase, which M17 walked in front of), pins the subject list LITERALLY (the
# old {0,21} already hard-coded that list's byte length, so the literal costs nothing and
# is auditable BY READING instead of by counting), and requires EXACTLY ONE SPACE at each
# of the three joins. That removes the width that rounds 2-4 kept mis-auditing — and
# nothing more: M20 then beat this same regex without touching a window at all, by
# quoting the pinned sentence elsewhere in the block. The prefix anchor below is the
# answer to that one.
#
# WHAT THE REWORDS IN THE LOG DID, measured (no claim is made about rewords not tried):
# the eight vectors listed under "against R2d" in the header — including "A claimed" for
# "Any claimed" (M13), a benign-looking edit — each returned red. The intended repair
# when a red is legitimate is to EDIT THIS CHECK to the new wording in the same commit;
# the failure message says so, because a reader who sees only CI output would otherwise
# reach for the cheapest-looking repair, which is to relax it back into a window.
#
# THE PREFIX ANCHOR IS THE PRIMARY GATE, and it is a shell `case`, not a regex: no
# pattern language, no window, one literal string to read. It exists because the regex
# below is UNANCHORED WITHIN $B3, so a QUOTATION of the old wording elsewhere in the
# block supplies the match. M20 repealed the mandate in the operative bullet ("A careful
# reading of the diff is normally sufficient …") and kept the pinned sentence verbatim in
# a "Historical note … was retired" sub-bullet: green 18/18. Quoting a superseded rule
# with its label is an edit harness docs make routinely, including this one. Requiring
# the obligation to be the FIRST thing in the span makes "immediately after the label"
# literally true rather than aspirational. Measured: M20 reddens here (see the log). A
# prefix match is satisfied only by what the span STARTS with, so this is also why the
# failure message does not need a separate "delete any surviving copy of the old
# wording" clause — a copy that is not first is not the prefix.
#
# HOW FAR THE LITERAL REACHES, AND WHY IT WAS EXTENDED. It first stopped at "verified by
# delet", which left the rest of the operative clause held only by R2's `[^.]{0,140}`
# window — 59 characters of real text in a 140-character window, i.e. 81 free characters
# INSIDE the sentence the check called "verbatim". A discretionary carve-out fitted
# there: "deleting the mechanism that enforces it WHERE THE REVIEWER JUDGES THE RISK TO
# WARRANT IT and observing the suite go red" was green 18/18 (M23) — M19's twin, landing
# just after the old prefix boundary instead of just before it. The literal now runs
# through "…and observing the suite go red", which costs nothing today (that is the text)
# and removes the last window from the operative clause. What follows it — "— never by
# reading the code and agreeing with it." — is still held by R3's `[^.]{0,45}` and is
# NOT covered by this anchor; probe B1 in the log measures what fits there.
#
# NORMALISATION (advisory hardening, taken). `_head` strips leading whitespace INCLUDING
# TABS and tolerates a `-` or `+` list marker. The previous expansion `${B3%%[! ]*}`
# stripped spaces only, and its comment said "blanks", which was wrong twice over: POSIX
# blank includes tab, and tabs were not stripped. A tab-indented label line, or a marker
# reformatted to `*`/`+`, produced a FALSE RED (measured: X2, X3, X5). That matters
# because a false red on a repo-wide markdown reformat is precisely what pushes the next
# maintainer to relax the check. Note `flat()`'s `sed 's/[*`]//g'` already deletes a `*`
# marker outright, so only `-` and `+` survive to be stripped here. This normalises the
# LIST SYNTAX around the sentence; it introduces no window over the sentence itself.
_head="$(printf '%s' "$B3" | sed 's/^[[:space:]]*//; s/^[-+][[:space:]]*//')"
case "$_head" in
  "(3b) Mutate, don't read. Any claimed guarantee, bound or invariant is verified by deleting the mechanism that enforces it and observing the suite go red"*) : ;;
  *) fail "R2d: (3b) does not OPEN with the obligation clause. After the list marker, the span must BEGIN with, literally: \"(3b) Mutate, don't read. Any claimed guarantee, bound or invariant is verified by deleting the mechanism that enforces it and observing the suite go red\" — nothing before it, nothing inserted anywhere in it, and a copy of it further down the block does not count. ⚠️ IF YOU REACHED THIS BY LEGITIMATELY REWORDING THAT CLAUSE, EDIT THIS LITERAL AND THE R2d REGEX BELOW TO THE NEW WORDING, IN THE SAME COMMIT — do NOT relax either into a '[^.]{0,N}' window, and do not satisfy them by leaving the old wording quoted somewhere. Every window this check has ever had was used to slip a hedge past it ('Best practice: ', 'that is load-bearing', 'verified by, TIME PERMITTING, deleting', 'that enforces it WHERE THE REVIEWER JUDGES THE RISK TO WARRANT IT and observing'), and each re-widening was audited by hand and declared closed while still open." ;;
esac
# The regex is kept behind the anchor. As written it is unreachable — every input that
# fails it also fails the `case` above — but it is the layer that still enforces the
# sentence's internal structure if a future edit ever loosens the prefix (to tolerate a
# re-indent, say). Its alternations record which wordings were meant to be acceptable.
printf '%s\n' "$B3" | grep -qiE "\(3b\) Mutate, don't read\.[ ](any|every|each) claimed guarantee, bound or invariant[ ](is|must be|shall be) verified by[ ](delet|remov)" \
  || fail "R2d: (3b)'s obligation clause does not match the required structure. Required, single-spaced, with nothing inserted anywhere in it: '(3b) Mutate, don't read.' + 'ANY|EVERY|EACH claimed guarantee, bound or invariant' + 'IS|MUST BE verified by' + 'deleting|removing'. ⚠️ IF YOU REACHED THIS BY LEGITIMATELY REWORDING THAT SENTENCE, EDIT THIS REGEX AND THE `case` ANCHOR ABOVE TO THE NEW WORDING, IN THE SAME COMMIT — do NOT relax either into a '[^.]{0,N}' window. Every window this check has ever had was used to slip a hedge past it ('Best practice: ', 'that is load-bearing', 'verified by, TIME PERMITTING, deleting'), and each re-widening was audited by hand and declared closed while still open."
pass "R2d 3b_obligation_immediately_follows_the_label"

# ── R3: 3b forbids read-and-agree as verification ────────────────────────────────
printf '%s\n' "$B3" | grep -qiE '(never|not) by reading[^.]{0,45}agree' \
  || fail "R3: (3b) does not rule out verifying by reading the code and AGREEING with it, in one sentence — the whole point of the check"
pass "R3 3b_reading_is_not_verification"

# ── R4: 3b is explicit that CONSTANTS are mechanisms too ─────────────────────────
# The class that motivated the rule: a reserve or a batch size is a guarantee nobody
# thinks of as a "mechanism", so it ships unpinned. Naming the class alone is not
# enough — the block must show what mutating one looks like.
printf '%s\n' "$B3" | grep -qiE 'constants? count|constants? are|including constants|constants included' \
  || fail "R4: (3b) does not state that CONSTANTS count as mechanisms — the reserve/batch-size class is how unpinned bounds ship"
printf '%s\n' "$B3" | grep -qiE 'reserve|batch size|cap\b|threshold|timeout|limit' \
  || fail "R4: (3b) contains none of the recognised concrete constant examples (reserve / batch size / cap / threshold / timeout / limit) — naming the class without showing one leaves the reader to guess what mutating a constant means"
pass "R4 3b_constants_are_mechanisms"

# ── R5: 3b requires ISOLATION — one mutation at a time ───────────────────────────
printf '%s\n' "$B3" | grep -qiE 'in isolation|isolated' \
  || fail "R5: (3b) does not require the deletion to be made IN ISOLATION"
printf '%s\n' "$B3" | grep -qiE 'one (mutation )?at a time' \
  || fail "R5: (3b) does not require one mutation at a time"
printf '%s\n' "$B3" | grep -qiE '(names?|identif[a-z]*)[^.]{0,25}one cause|which one' \
  || fail "R5: (3b) does not say WHY isolation matters (a batched red result names no single cause)"
pass "R5 3b_one_mutation_at_a_time"

# ── R6: 3b states the consequence of a green suite after the deletion ────────────
printf '%s\n' "$B3" | grep -qiE 'stays green[^.]{0,70}(unpinned|not pinned)' \
  || fail "R6: (3b) does not tie a still-green suite to the verdict 'the guarantee is UNPINNED' in one sentence"
printf '%s\n' "$B3" | grep -qiE 'report (that|it) as a finding|is a finding' \
  || fail "R6: (3b) does not require an unpinned guarantee to be REPORTED — a diagnosis with no obligation attached is an observation"
pass "R6 3b_green_after_deletion_is_a_finding"

# ── R7: 3b carries the safe-revert rule (E99-F58), ANCHORED — M10 inversion reddens ─
# A mandate to mutate with no safe way back destroys uncommitted work; the two rules
# have to travel together. Round 1 checked the three ingredients independently and the
# review's M10 rewrote the bullet to RECOMMEND `git checkout -- <file>` ("a backup copy
# … or git stash push are both unnecessary ceremony; just use git checkout -- <file>,
# which is the fastest way back") — green, 14/14. Every assertion below now pins the
# VERDICT to the COMMAND, inside one sentence, in both directions: forbidden→checkout,
# sanctioned→mutbak/stash.
printf '%s\n' "$B3" | grep -qF 'git checkout -- <file>' \
  || fail "R7: (3b) does not name the forbidden revert 'git checkout -- <file>' literally"
printf '%s\n' "$B3" | grep -qiE 'forbidden[^.]{0,60}git checkout' \
  || fail "R7: (3b) does not mark 'git checkout -- <file>' FORBIDDEN in the same sentence as the command — naming it is not forbidding it, and the un-anchored form of this check passed on an inverted rule that recommended it"
printf '%s\n' "$B3" | grep -qiE 'never use it[^.]{0,25}git checkout' \
  || fail "R7: (3b) does not say 'never use it' in the same sentence as 'git checkout' — a 'never' elsewhere in the block is about something else"
printf '%s\n' "$B3" | grep -qF 'git restore <file>' \
  || fail "R7: (3b) does not name the 'git restore <file>' alias, which does identical damage"
printf '%s\n' "$B3" | grep -qiE 'sanctioned[^.]{0,90}backup copy[^.]{0,45}cp <file> <file>\.mutbak' \
  || fail "R7: (3b) does not present the backup copy as SANCTIONED and tie it to its mechanic (cp <file> <file>.mutbak) — a named-but-discouraged alternative satisfies a bare mention"
printf '%s\n' "$B3" | grep -qF 'mv <file>.mutbak <file>' \
  || fail "R7: (3b) does not give the backup-copy RESTORE command (mv <file>.mutbak <file>)"
printf '%s\n' "$B3" | grep -qiE 'git stash push[^.]{0,250}git stash list' \
  || fail "R7: (3b) does not tie 'git stash push' to the recoverable 'git stash list' entry that makes it safe"
printf '%s\n' "$B3" | grep -qiE 'commit[^.]{0,80}before the first mutation' \
  || fail "R7: (3b) does not require COMMITTING every real change before the first mutation"
printf '%s\n' "$B3" | grep -qiE 'git status --short[^.]{0,45}(must be )?clean' \
  || fail "R7: (3b) does not give the commit-first precondition a check (git status --short must be clean)"
printf '%s\n' "$B3" | grep -qiE 'diff, not a test run' \
  || fail "R7: (3b) does not require confirming the restore by DIFF rather than by a test run"
pass "R7 3b_safe_revert_anchored_in_both_directions"

# ── R7b: the condensation is declared, and its follow-up named (3c applied here) ─
# Only about a third of the E99-F58 discipline is present, in one of the two role files
# that need it. 3c makes leaving that implicit a defect, so the block must say so and
# cite the item that closes it.
printf '%s\n' "$B3" | grep -qiE 'condensation|condensed|partial' \
  || fail "R7b: (3b) does not declare that the safe-revert rule it carries is a CONDENSATION of E99-F58 — presenting a third of a rule as the rule is the 3c defect"
printf '%s\n' "$B3" | grep -qF 'agents/builder.md' \
  || fail "R7b: (3b) does not record that agents/builder.md carries NO mutation-revert rule at all, though Builders mutate routinely"
printf '%s\n' "$B3" | grep -qiE 'not yet enforced[^.]{0,40}E99-F102' \
  || fail "R7b: (3b) defers the rest of the discipline without naming the follow-up item (E99-F102) in the same sentence"
pass "R7b 3b_declares_its_own_gap_and_names_the_followup"

# ── R8: 3c — over-claiming prose is a DEFECT, not a nit, at real severity ────────
printf '%s\n' "$C3B" | grep -qiE 'defect,? not a nit' \
  || fail "R8: (3c) does not state that prose overstating a guarantee is a DEFECT, not a nit"
printf '%s\n' "$C3B" | grep -qiE '(required fix|blocking)[^.]{0,70}(same severity|severity of the missing)' \
  || fail "R8: (3c) does not tie the over-claim to the SEVERITY OF THE MISSING ENFORCEMENT in one sentence — 'defect' with no consequence attached is a nit by another name"
pass "R8 3c_overstated_prose_is_a_defect"

# ── R9: 3c gives the REASON — the next reader trusts it and stops looking ────────
# Without the reason the rule reads as pedantry about wording and gets waived.
printf '%s\n' "$C3B" | grep -qiE 'trusts? it[^.]{0,45}stops? looking' \
  || fail "R9: (3c) does not state, in one sentence, that the next reader TRUSTS the claim and therefore STOPS LOOKING — the reason an over-claim is worse than silence"
pass "R9 3c_states_why_an_overclaim_is_worse_than_silence"

# ── R10: 3c — deferred enforcement must say so and name its follow-up ────────────
printf '%s\n' "$C3B" | grep -qiE 'deferred[^.]{0,60}explicit' \
  || fail "R10: (3c) does not require DEFERRED enforcement to be declared EXPLICITLY, in one sentence"
printf '%s\n' "$C3B" | grep -qiE 'explicit[^.]{0,90}(name the follow-up|follow-up item|follow up item)' \
  || fail "R10: (3c) does not require the deferral to NAME the follow-up item that will land it"
pass "R10 3c_deferred_enforcement_names_its_followup"

# ── R11: the origin note is on the record, in the same section ───────────────────
# Load-bearing documentation, not decoration: it is the only place a future Reviewer
# learns that this rule has already failed once, in this file, by this mechanism.
printf '%s\n' "$WHY" | grep -qi 'mutation testing' \
  || fail "R11: check 3 does not record that this mandate was FOUND BY MUTATION TESTING"
printf '%s\n' "$WHY" | grep -qiE 'hidden|concealed|went unnoticed' \
  || fail "R11: the origin note does not record that the gap was HIDDEN"
printf '%s\n' "$WHY" | grep -qiE 'had (already )?been landed|claim(ed)? .*(landed|done|shipped)|asserting it' \
  || fail "R11: the origin note does not record that a note ASSERTED THE WORK HAD BEEN LANDED — the concealment mechanism is the lesson"
printf '%s\n' "$WHY" | grep -qiE '3b' \
  || fail "R11: the origin note does not tie the incident back to 3b (the check that would have caught it)"
pass "R11 origin_note_records_the_incident"

# ── R12: reachable from verification.test_command + the CROSS-SUITE existence guard ─
# Two halves, and only the second one survives this suite being renamed away:
#   (a) the config either names this suite or delegates to tools/run-tests.sh, which
#       DISCOVERS tests/test_*.sh. Asserting only one spelling would freeze a config
#       detail this suite has no stake in (same intent as test_agents_host.sh R28).
#   (b) tests/test_reviewer.sh R16 asserts THIS FILE EXISTS. That is the guard that goes
#       red when the suite is renamed out of the glob — the review's M5 renamed it and
#       the runner cheerfully reported "all 34 suites passed". A basename self-check
#       cannot catch that: it is only ever evaluated in the world where the answer is
#       already yes. This half checks that the external guard is still in place.
_tc="$(sed -n 's/^[[:space:]]*test_command:[[:space:]]*"\([^"]*\)".*$/\1/p' "$SRC/harness.config.yaml")"
[ -n "$_tc" ] || fail "R12: harness.config.yaml declares no verification.test_command"
printf '%s\n' "$_tc" | grep -qF 'tests/test_reviewer_mutation_mandate.sh' \
  || printf '%s\n' "$_tc" | grep -qF 'tools/run-tests.sh' \
  || fail "R12: this suite is not reachable from verification.test_command ('$_tc')"
[ -f "$SRC/tests/test_reviewer.sh" ] || fail "R12: tests/test_reviewer.sh is missing"
grep -qF 'tests/test_reviewer_mutation_mandate.sh' "$SRC/tests/test_reviewer.sh" \
  || fail "R12: tests/test_reviewer.sh no longer carries the cross-suite existence guard (R16) — without it, renaming this file out of the tests/test_*.sh glob makes the mandate silently stop being checked and the runner still reports success"
pass "R12 reachable_and_externally_guarded"

# ── R13: the mandate is recorded in the CHANGELOG ────────────────────────────────
# Anywhere in the file, never pinned to the current release: the entry is append-only
# history, so a later version must not be forced to re-mention it.
grep -qF '3b' CHANGELOG.md || fail "R13: CHANGELOG.md never records check 3b"
grep -qF '3c' CHANGELOG.md || fail "R13: CHANGELOG.md never records check 3c"
pass "R13 changelog_records_the_mandate"

# ── R14: this suite's own hygiene ────────────────────────────────────────────────
# Permanent-suite rules (same as tests/test_agents_host.sh R29): never diff against
# git, never freeze the VERSION string. The searched pattern is spelled with a
# character class, and the message says "git's diff subcommand" rather than the literal
# two-token sequence, so neither line matches itself — round 1's message did, and R14
# failed on its own diagnostic.
_self="$SRC/tests/test_reviewer_mutation_mandate.sh"
grep -q 'git[[:space:]][[:space:]]*diff' "$_self" \
  && fail "R14: this suite invokes git's diff subcommand — a permanent suite must never diff a file against git"
grep -qF "$(tr -d ' \n\r\t' < VERSION)" "$_self" \
  && fail "R14: this suite contains the current VERSION string — a permanent suite must not freeze it"
pass "R14 suite_hygiene"

echo "All reviewer mutation-mandate tests passed."
