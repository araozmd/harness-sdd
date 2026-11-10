#!/bin/sh
# test_doc_critic.sh — contract assertions for the doc-critic advisory review pass.
# Static grep checks over the new role and the checkpoint wiring in the three
# generating-agent contracts. Zero dependencies; runs in the harness source tree.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ROLE="$SRC/agents/doc-critic.md"
PLANNER="$SRC/agents/planner.md"
DRILLER="$SRC/agents/driller.md"
ARCHITECT="$SRC/agents/architect.md"
WORKFLOW="$SRC/docs/WORKFLOW.md"
SCHEMA="$SRC/store/tasks.schema.json"
STATE="$SRC/state/tasks.json"
REVIEWER="$SRC/agents/reviewer.md"
TEMPLATE="$SRC/specs/_templates/feature.spec.md"
README="$SRC/README.md"
RATIONALE="$SRC/docs/RATIONALE.md"
FENCE_AWK="$(cat "$SRC/tests/lib/fence.awk")"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── R1: portable doc-critic role exists ───────────────────────────────────────
test_doc_critic_role_exists() {
  [ -f "$ROLE" ] || fail "R1: agents/doc-critic.md missing"
  grep -qE '^# Agent: Doc-critic' "$ROLE" || fail "R1: role header missing"
  pass "R1: portable doc-critic role exists"
}

# ── R2: role accepts target-type argument ─────────────────────────────────────
test_target_type_argument() {
  grep -qF 'target-type' "$ROLE" || fail "R2: target-type argument not mentioned"
  grep -qF '## Invocation contract' "$ROLE" || fail "R2: invocation contract section missing"
  pass "R2: role accepts target-type argument"
}

# ── R3: three target-type scopes are defined ──────────────────────────────────
test_target_type_scopes() {
  grep -qF 'plan-output' "$ROLE" || fail "R3: plan-output scope missing"
  grep -qF 'epic-decomposition' "$ROLE" || fail "R3: epic-decomposition scope missing"
  grep -qF 'feature-spec' "$ROLE" || fail "R3: feature-spec scope missing"
  pass "R3: three target-type scopes defined"
}

# ── R4: critic flags only real downstream problems ────────────────────────────
test_calibration() {
  grep -qF 'Completeness' "$ROLE" || fail "R4: completeness dimension missing"
  grep -qF 'Consistency' "$ROLE" || fail "R4: consistency dimension missing"
  grep -qF 'Clarity' "$ROLE" || fail "R4: clarity dimension missing"
  grep -qF 'Scope' "$ROLE" || fail "R4: scope dimension missing"
  grep -qF 'YAGNI' "$ROLE" || fail "R4: YAGNI dimension missing"
  grep -qF 'only issues that would cause real downstream problems' "$ROLE" \
    || fail "R4: calibration rule missing"
  pass "R4: critic calibrated to real downstream problems"
}

# ── R5: recommendations are advisory, inline-fix-then-proceed ─────────────────
test_advisory_inline_fix() {
  grep -qF 'advisory' "$ROLE" || fail "R5: advisory keyword missing"
  grep -qF 'inline' "$ROLE" || fail "R5: inline-fix keyword missing"
  grep -qF 'proceed' "$ROLE" || fail "R5: proceed keyword missing"
  grep -qF 'never block' "$ROLE" || fail "R5: never-block rule missing"
  pass "R5: advisory-only inline-fix-then-proceed stated"
}

# ── R6: best-effort proceed on error/timeout with progress note ───────────────
test_best_effort_failure() {
  grep -qF 'best-effort' "$ROLE" || fail "R6: best-effort keyword missing"
  grep -qF 'timeout' "$ROLE" || fail "R6: timeout keyword missing"
  grep -qF 'errors' "$ROLE" || fail "R6: errors keyword missing"
  grep -qF 'proceed' "$ROLE" || fail "R6: proceed-on-failure keyword missing"
  pass "R6: best-effort failure posture stated"
}

# ── R7: critic writes a progress note summarizing changes ─────────────────────
test_progress_note() {
  grep -qF 'progress/<run>/' "$ROLE" || fail "R7: progress/<run>/ output not required"
  grep -qF 'issues found' "$ROLE" || fail "R7: issues-found summary missing"
  grep -qF 'fix' "$ROLE" || fail "R7: fix summary missing"
  pass "R7: progress-note output required"
}

# ── R8: critic reviews documents only, not code ───────────────────────────────
test_no_code_review() {
  grep -qiF 'documents only' "$ROLE" || fail "R8: documents-only boundary missing"
  grep -qF 'production code' "$ROLE" || fail "R8: production-code exclusion missing"
  pass "R8: critic reviews documents only"
}

# ── R9: planner invokes critic after /sdd-plan ────────────────────────────────
test_planner_invokes_critic() {
  grep -qF 'Doc-critic' "$PLANNER" || fail "R9: planner does not name Doc-critic"
  grep -qF 'target-type=plan-output' "$PLANNER" || fail "R9: planner missing target-type=plan-output"
  grep -qF 'spawn' "$PLANNER" || fail "R9: planner missing spawn wording"
  pass "R9: planner invokes doc-critic after /sdd-plan"
}

# ── R10: planner checkpoint enforces drillable-minimum on epic.md ─────────────
test_drillable_minimum() {
  grep -qF 'Drillable-minimum checklist' "$PLANNER" || fail "R10: drillable-minimum checklist missing"
  grep -qF 'Business brief' "$PLANNER" || fail "R10: business brief element missing"
  grep -qF 'success criteria' "$PLANNER" || fail "R10: success-criteria element missing"
  grep -qF 'Technical considerations' "$PLANNER" || fail "R10: technical-considerations element missing"
  grep -qF 'Cross-epic dependencies' "$PLANNER" || fail "R10: cross-epic-dependencies element missing"
  grep -qF 'ADRs' "$PLANNER" || fail "R10: ADR-pointer element missing"
  pass "R10: planner enforces drillable-minimum on epic.md"
}

# ── R11: driller invokes critic after /sdd-drill ──────────────────────────────
test_driller_invokes_critic() {
  grep -qF 'Doc-critic' "$DRILLER" || fail "R11: driller does not name Doc-critic"
  grep -qF 'target-type=epic-decomposition' "$DRILLER" || fail "R11: driller missing target-type=epic-decomposition"
  grep -qF 'spawn' "$DRILLER" || fail "R11: driller missing spawn wording"
  pass "R11: driller invokes doc-critic after /sdd-drill"
}

# ── R12: architect invokes critic before spec-ready hand-off ──────────────────
test_architect_invokes_critic() {
  grep -qF 'Doc-critic' "$ARCHITECT" || fail "R12: architect does not name Doc-critic"
  grep -qF 'target-type=feature-spec' "$ARCHITECT" || fail "R12: architect missing target-type=feature-spec"
  grep -qF 'spawn' "$ARCHITECT" || fail "R12: architect missing spawn wording"
  pass "R12: architect invokes doc-critic before spec-ready hand-off"
}

# ── R15: VERSION bumped + CHANGELOG entry ─────────────────────────────────────
test_version_and_changelog() {
  [ -f "$SRC/VERSION" ] || fail "R15: VERSION file missing"
  _ver="$(cat "$SRC/VERSION")"
  case "$_ver" in
    *.*.*) : ;;
    *) fail "R15: VERSION '$_ver' is not SemVer-ish" ;;
  esac
  [ -f "$SRC/CHANGELOG.md" ] || fail "R15: CHANGELOG.md missing"
  grep -qF "[$_ver]" "$SRC/CHANGELOG.md" || fail "R15: CHANGELOG missing entry for $_ver"
  grep -qF 'doc-critic' "$SRC/CHANGELOG.md" || fail "R15: CHANGELOG does not mention doc-critic"
  pass "R15: VERSION ($_ver) bumped with CHANGELOG entry"
}

# ── R16: WORKFLOW.md documents checkpoints ────────────────────────────────────
test_workflow_docs() {
  grep -qF '## Doc-critic checkpoints' "$WORKFLOW" || fail "R16: Doc-critic checkpoints section missing"
  grep -qF '/sdd-plan' "$WORKFLOW" || fail "R16: /sdd-plan checkpoint not documented"
  grep -qF '/sdd-drill' "$WORKFLOW" || fail "R16: /sdd-drill checkpoint not documented"
  grep -qF 'spec-ready' "$WORKFLOW" || fail "R16: spec-ready checkpoint not documented"
  grep -qF 'advisory' "$WORKFLOW" || fail "R16: advisory nature not documented"
  grep -qF 'inline' "$WORKFLOW" || fail "R16: inline-fix nature not documented"
  grep -qF 'best-effort' "$WORKFLOW" || fail "R16: best-effort nature not documented"
  pass "R16: WORKFLOW.md documents doc-critic checkpoints"
}

# ── R17: no schema change ─────────────────────────────────────────────────────
test_no_schema_change() {
  # The critic adds no TaskStore fields or status values. A cheap, additive check:
  # no mention of critic in the schema, and the feature status enum remains the
  # canonical five values.
  grep -qiF 'critic' "$SCHEMA" && fail "R17: schema mentions critic (should be unchanged)"
  # The feature status enum is the one that follows the feature id pattern
  # "^E[0-9]+-F[0-9]+$". Capture that enum only.
  _feature_statuses="$(awk '
    /"pattern": "\^E\[0-9\]\+-F\[0-9\]\+\$"/ { in_feature=1 }
    in_feature && /"status": \{/ { in_status=1 }
    in_status && /"enum": \[/ {
      gsub(/.*\[|].*/, ""); print; in_status=0; in_feature=0
    }
  ' "$SCHEMA")"
  printf '%s' "$_feature_statuses" | tr -d ' \n"' | grep -qx 'pending,spec-ready,in-progress,in-review,done' \
    || fail "R17: feature status enum changed ('$_feature_statuses')"
  pass "R17: no schema change for doc-critic"
}

# ── R18: no new human gate ────────────────────────────────────────────────────
test_no_new_gate() {
  # The role itself must be advisory/non-blocking.
  grep -qE 'advisory[- ]only' "$ROLE" || fail "R18: advisory-only rule missing"
  grep -qF 'never block' "$ROLE" || fail "R18: never-block rule missing"
  # The workflow docs must not introduce a new status or gate.
  grep -qF '## Doc-critic checkpoints' "$WORKFLOW" || fail "R18: workflow section missing"
  # No new status values beyond the canonical feature set.
  _statuses="$(awk '
    /"pattern": "\^E\[0-9\]\+-F\[0-9\]\+\$"/ { in_feature=1 }
    in_feature && /"status": \{/ { in_status=1 }
    in_status && /"enum": \[/ {
      gsub(/.*\[|].*/, ""); print; in_status=0; in_feature=0
    }
  ' "$SCHEMA")"
  printf '%s' "$_statuses" | tr -d ' \n"' | grep -qx 'pending,spec-ready,in-progress,in-review,done' \
    || fail "R18: feature status enum changed ('$_statuses')"
  pass "R18: no new human gate or status value"
}

# ── portability: no CLI-specific instructions ─────────────────────────────────
test_portability() {
  grep -qF 'AGENTS.md-compatible' "$ROLE" || fail "portability: role not marked AGENTS.md-compatible"
  grep -qiF 'Claude Code' "$ROLE" && fail "portability: role contains Claude-specific wording"
  pass "portability: doc-critic role is CLI-agnostic"
}

# ── E37-F02 helpers ───────────────────────────────────────────────────────────
# slice <file> <heading-prefix>: the fence-aware text of a "## " section, heading to the next
# "## " heading (inclusive of the heading line). Fenced "## " lines never end or start a slice.
slice() {
  awk "$FENCE_AWK"'
    fence_delim($0) { if (keep) print; next }
    !fence && /^## / { keep = (index($0, h) == 1); if (keep) print; next }
    keep
  ' h="$2" "$1"
}
# folded: newlines to spaces, runs of spaces squeezed — anchors span wrapped lines.
folded() { tr '\n' ' ' | tr -s ' '; }
# sentences: count of sentence terminators ([.!?] then space or end) in folded text on stdin.
# A closed world for additive sentences: any added sentence carries a terminator, whatever its
# words. It cannot see an in-place edit or reorder of an existing sentence (same terminator
# count), so every clause is ALSO pinned by its own whole-sentence anchor.
sentences() { grep -oE '[.!?]( |$)' | wc -l | tr -d ' '; }
# lineno <file> <exact heading line>: first line number of an exact line, empty when absent.
lineno() { grep -nxF -- "$2" "$1" | head -n 1 | cut -d: -f1; }

# ── E37-F02:R1 — paraphrase-back section exists, is positioned, four-files-only ─
test_paraphrase_section() {
  _h='## Paraphrase-back comprehension (E37-F02)'
  [ "$(grep -cxF -- "$_h" "$ROLE" || true)" -eq 1 ] \
    || fail "E37-F02:R1: doc-critic must carry exactly one '$_h' heading"
  _rs="$(lineno "$ROLE" '## Review scope and calibration (what to flag)')"
  _ps="$(lineno "$ROLE" "$_h")"
  _pc="$(lineno "$ROLE" '## Plan-row citations and stage-aware NFRs (E36-F04)')"
  [ -n "$_rs" ] && [ -n "$_ps" ] && [ -n "$_pc" ] && [ "$_rs" -lt "$_ps" ] && [ "$_ps" -lt "$_pc" ] \
    || fail "E37-F02:R1: the section must sit after Review scope and before the E36-F04 section"
  _sec="$(slice "$ROLE" "$_h" | folded)"
  _need() {
    case "$_sec" in *"$1"*) : ;; *) fail "E37-F02:R1: $2" ;; esac
  }
  _need 'At `target-type=feature-spec`, before you evaluate the five dimensions, prove you understood the spec: your note opens with a `## Paraphrase` section written from the four spec files alone' \
    "opening sentence missing"
  _need 'Do not open the inbox brief under `progress/inbox/`, the epic'"'"'s `epic.md`, the architecture or any other file while you write it, and read no chat history: the Builder receives only these four files, in a clean context, and the paraphrase measures what they carry on their own.' \
    "four-files-only sentence missing"
  _need 'Quoting the spec'"'"'s sentences back is not a paraphrase.' "quoting-is-not-paraphrase sentence missing"
  _need 'what you know from elsewhere does not count, and a gap you can fill only from outside the document is a gap in the document' \
    "outside-knowledge sentence missing"
  _need 'Write `none` for a file whose every unit you could restate.' "none rule missing"
  _need 'The lints and every other check of this checkpoint run after the paraphrase is written.' \
    "paraphrase-before-lints sentence missing"
  # three parts, in order (offsets in the folded slice)
  _o1="$(printf '%s' "$_sec" | awk '{print index($0, "`### What this proposes`")}')"
  _o2="$(printf '%s' "$_sec" | awk '{print index($0, "`### How the existing system works, per this document`")}')"
  _o3="$(printf '%s' "$_sec" | awk '{print index($0, "`### Could not restate`")}')"
  [ "$_o1" -gt 0 ] && [ "$_o1" -lt "$_o2" ] && [ "$_o2" -lt "$_o3" ] \
    || fail "E37-F02:R1: the three parts must appear in order: proposes, existing system, could not restate"
  # negative: nothing lets the critic read the brief or chat
  if printf '%s' "$_sec" | grep -qiE '(may|can|should|free to)[^.]{0,60}(read|open|consult)[^.]{0,40}(inbox brief|progress/inbox|chat)'; then
    fail "E37-F02:R1: a sentence lets the critic read the inbox brief or chat for the paraphrase"
  fi
  # closed-world, two nets. (1) Token counts: every inbox/chat mention lies inside the single
  # pinned four-files-only sentence (2 x inbox, 1 x chat) — catches an added sentence or clause
  # that USES those words. (2) The sentence count below: catches an added sentence that avoids
  # them ("the intake brief", "the conversation", "the transcript"). Neither sees an in-place
  # rewording of, or a clause added to, an existing sentence; the anchors above see that only
  # over the span each one pins.
  [ "$(printf '%s' "$_sec" | grep -oi 'inbox' | wc -l | tr -d ' ')" -eq 2 ] \
    || fail "E37-F02:R1: an inbox mention lies outside the pinned four-files-only sentence"
  [ "$(printf '%s' "$_sec" | grep -oi 'chat' | wc -l | tr -d ' ')" -eq 1 ] \
    || fail "E37-F02:R1: a chat mention lies outside the pinned four-files-only sentence"
  # one list per file, each item naming the unit and what is missing
  _need '`### Could not restate` — one list per file (`.spec.md`, `.plan.md`, `.tasks.md`, `.tests.md`); each item names the unit you could not restate' \
    "one-list-per-file sentence missing"
  _need 'and one line on what is missing or contradictory.' "item-shape tail missing"
  # closed-world by sentence: the section holds exactly 16 sentences (a later feature editing a
  # NEIGHBOURING section cannot move this; the slice ends at the next "## " heading).
  [ "$(printf '%s' "$_sec" | sentences)" -eq 16 ] \
    || fail "E37-F02:R1: the paraphrase section must hold exactly its 16 sentences (an added or removed sentence changes the count)"
  grep -qiF 'Claude Code' "$ROLE" && fail "E37-F02:R1: role contains CLI-specific wording"
  pass "E37-F02:R1: paraphrase-back section present, positioned, four-files-only"
}

# ── E37-F02:R2 — could-not-restate is a blocking finding, bounded by one re-audit ─
test_could_not_restate_blocking() {
  _sec="$(slice "$ROLE" '## Paraphrase-back comprehension (E37-F02)' | folded)"
  _need() { case "$_sec" in *"$1"*) : ;; *) fail "E37-F02:R2: $2" ;; esac; }
  _need 'Each `### Could not restate` item is a **blocking finding** with the stable id `could-not-restate`, repeated in your findings as `could-not-restate <file> <unit> — <what is missing>`.' \
    "blocking-finding sentence with id and shape missing"
  _need 'Blocking means the Architect must fix the unit or record it under `## Accepted trade-offs` in the `.spec.md` before hand-off, bounded by one re-audit' \
    "fix-or-record sentence missing"
  _need 'you still never block the Architect, there is no new status and no new human gate, and every finding outside this list stays advisory as before' \
    "never-block / no-new-status sentence missing"
  _need 'write the paraphrase again from the revised files and list only what you still cannot restate' \
    "re-audit sentence missing"
  _need 'A unit counts only when its own meaning is missing from the four files, not when it cites a file, test, lesson or check you cannot open: a cross-reference whose purpose the unit states is restated.' \
    "calibration sentence missing"
  _need 'A unit you can restate but think wrong is an ordinary finding under the five dimensions, not a `could-not-restate`.' \
    "restate-but-wrong sentence missing"
  _need 'This section applies at `target-type=feature-spec` only; the `plan-output` and `epic-decomposition` checkpoints are unchanged.' \
    "feature-spec-only sentence missing"
  _out="$(slice "$ROLE" '## Output summary' | folded)"
  case "$_out" in
    *'At `target-type=feature-spec` the note opens with the `## Paraphrase` section (E37-F02) before the list below.'*) : ;;
    *) fail "E37-F02:R2: ## Output summary must say the feature-spec note opens with the ## Paraphrase section" ;;
  esac
  case "$_out" in
    *'progress/<run>/doc-critic-<checkpoint>.md'*) : ;;
    *) fail "E37-F02:R2: ## Output summary lost the progress note path" ;;
  esac
  grep -qiE 'advisory[- ]only' "$ROLE" || fail "E37-F02:R2: advisory-only anchor lost"
  grep -qF 'never block' "$ROLE" || fail "E37-F02:R2: never-block anchor lost"
  grep -qiF 'best-effort' "$ROLE" || fail "E37-F02:R2: best-effort anchor lost"
  pass "E37-F02:R2: could-not-restate is blocking-for-hand-off, advisory critic, one re-audit"
}

# ── E37-F02:R3 — Architect: paraphrase first, ONE re-audit, then record ───────
test_architect_paraphrase_step() {
  _sec="$(slice "$ARCHITECT" '## Doc-critic checkpoint before' | folded)"
  _need() { case "$_sec" in *"$1"*) : ;; *) fail "E37-F02:R3: $2" ;; esac; }
  _need 'spawn the **Doc-critic** (`agents/doc-critic.md`) as a sub-agent with `target-type=feature-spec`' \
    "existing spawn sentence lost"
  _need '**Paraphrase first, one re-audit, then record (E37-F02).**' "bold lead-in missing"
  _need 'pass it nothing else: not the inbox brief, not this conversation' "nothing-else rule missing"
  _need 'Read the paraphrase before the findings:' "read-the-paraphrase-before-the-findings clause missing or reordered"
  _need 'where the cold reader restated something other than what you meant, the document, not the reader, is wrong' \
    "document-not-reader sentence missing"
  _need 'Each `could-not-restate` finding is blocking for your hand-off: fix the unit it names, then spawn the critic once more on the revised files — at most **one** re-audit per feature.' \
    "one-re-audit sentence missing"
  _need 'Every `could-not-restate` still listed after the re-audit — including one your fixes introduced — or that you choose not to fix, is recorded in the `.spec.md` under `## Accepted trade-offs` as `- <unit> — <what the cold reader could not restate> — accepted because <why>` before you hand off' \
    "record-leftovers sentence missing"
  _need 'a leftover that is neither fixed nor recorded is not a finished checkpoint' "unfinished-checkpoint rule missing"
  _need 'The Reviewer reads that section and treats a recorded trade-off as a decision, not a defect' \
    "Reviewer sentence missing"
  _need 'When the first pass lists no `could-not-restate`, there is no re-audit' "no-re-audit-when-none sentence missing"
  _need 'When the critic errors or times out there is no list to act on: proceed best-effort and record the skip as the paragraph above says.' \
    "best-effort sentence missing"
  if printf '%s' "$_sec" | grep -qiE '(two|three|several|further|unlimited|as many|second|another|again|repeat)[^.]{0,12}re-audit'; then
    fail "E37-F02:R3: the checkpoint permits more than one re-audit"
  fi
  # closed-world, three nets. (1) Token counts: the four pinned sentences carry every
  # re-audit mention and the single "spawn the critic" — catches an added sentence that USES
  # those words. (2) The sentence count below: catches an added sentence that avoids them ("run
  # the critic again", "spawn the Doc-critic again", "you may pass it the inbox brief"). Neither
  # sees an in-place rewording of, or a clause added to, an existing sentence; the anchors above
  # see that only over the span each one pins. (3) The vocabulary regex
  # above is a third, narrower net (its word list only).
  [ "$(printf '%s' "$_sec" | grep -oi 're-audit' | wc -l | tr -d ' ')" -eq 4 ] \
    || fail "E37-F02:R3: a re-audit mention lies outside the four pinned sentences (the bound is one)"
  [ "$(printf '%s' "$_sec" | grep -oi 'spawn the critic' | wc -l | tr -d ' ')" -eq 1 ] \
    || fail "E37-F02:R3: the checkpoint spawns the critic more than the one pinned time"
  # The count spans the whole R12 section (its pre-existing first paragraph has 4 sentences, the
  # E37-F02 paragraph 7), so a NEW paragraph inside the section is caught too; editing the R12
  # paragraph is a same-section edit and updates this number. Neighbouring sections cannot move it.
  [ "$(printf '%s' "$_sec" | sentences)" -eq 11 ] \
    || fail "E37-F02:R3: the checkpoint section must hold exactly its 11 sentences (an added sentence may permit a further re-audit or pass the critic more)"
  pass "E37-F02:R3: architect checkpoint is paraphrase first, one re-audit, then record"
}

# ── E37-F02:R4 — Reviewer reads ## Accepted trade-offs; a recorded one is not a defect ─
test_reviewer_reads_trade_offs() {
  _h='## Accepted trade-offs (E37-F02)'
  [ "$(grep -cxF -- "$_h" "$REVIEWER" || true)" -eq 1 ] \
    || fail "E37-F02:R4: reviewer must carry exactly one '$_h' heading"
  _wy="$(lineno "$REVIEWER" '## What you check')"
  _at="$(lineno "$REVIEWER" "$_h")"
  _ac="$(lineno "$REVIEWER" '## ADR-citation check (architecture-aligned specs)')"
  [ -n "$_wy" ] && [ -n "$_at" ] && [ -n "$_ac" ] && [ "$_wy" -lt "$_at" ] && [ "$_at" -lt "$_ac" ] \
    || fail "E37-F02:R4: the section must sit after '## What you check' and before '## ADR-citation check'"
  _sec="$(slice "$REVIEWER" "$_h" | folded)"
  _need() { case "$_sec" in *"$1"*) : ;; *) fail "E37-F02:R4: $2" ;; esac; }
  _need 'When the `.spec.md` under review carries a `## Accepted trade-offs` section' "trigger clause missing"
  _need 'read it before you judge the spec'"'"'s prose' "read-before-judging clause missing"
  _need 'A recorded trade-off is a decision recorded by the Architect and visible at the human gate, not a defect: do not reject or flag the named unit for the comprehension gap it records, and do not ask the Builder to resolve it.' \
    "decision-not-defect sentence missing"
  _need 'The record waives only that, and every other check is unchanged — the unit'"'"'s `R-id` still needs a passing test (check 2), the three spec lints still decide on their exit codes (checks 7, 8 and 9), an over-claiming sentence is still a defect (3c), and a contradiction with a collaborator file is still check 5'"'"'s reject.' \
    "waives-only-that sentence missing"
  _need 'An entry that names no unit or gives no reason is itself a flag ("record the unit and the why"), not a reject.' \
    "malformed-entry sentence missing"
  _need 'A spec without the section has no trade-offs to read; nothing here fires.' "absent-section sentence missing"
  # closed-world by sentence: exactly 5 sentences (an added "flag it anyway" reds)
  [ "$(printf '%s' "$_sec" | sentences)" -eq 5 ] \
    || fail "E37-F02:R4: the Accepted trade-offs section must hold exactly its 5 sentences"
  # item 9 of '## What you check' is unchanged and names no trade-off
  _i9="$(awk "$FENCE_AWK"'
    fence_delim($0) { if (keep) print; next }
    !fence && keep && (/^## / || /^[0-9]+\. /) { keep = 0 }
    !fence && /^9\. / { keep = 1 }
    keep
  ' "$REVIEWER" | folded)"
  case "$_i9" in *'Checks 2, 7 and 8 are unchanged.'*) : ;; *) fail "E37-F02:R4: item 9 lost its closing sentence" ;; esac
  if printf '%s' "$_i9" | grep -qiF 'trade-off'; then
    fail "E37-F02:R4: item 9 must name no trade-off (the rule is its own section)"
  fi
  pass "E37-F02:R4: reviewer section present, positioned, waives only the comprehension gap"
}

# ── E37-F02:R5 — feature spec template carries the optional ## Accepted trade-offs ─
test_template_trade_offs_section() {
  _h='## Accepted trade-offs'
  [ "$(grep -cxF -- "$_h" "$TEMPLATE" || true)" -eq 1 ] \
    || fail "E37-F02:R5: template must carry exactly one '$_h' heading"
  _os="$(lineno "$TEMPLATE" '## Out of scope')"
  _tt="$(lineno "$TEMPLATE" "$_h")"
  _oq="$(lineno "$TEMPLATE" '## Open questions')"
  [ -n "$_os" ] && [ -n "$_tt" ] && [ -n "$_oq" ] && [ "$_os" -lt "$_tt" ] && [ "$_tt" -lt "$_oq" ] \
    || fail "E37-F02:R5: the section must sit between '## Out of scope' and '## Open questions'"
  _sl="$(slice "$TEMPLATE" "$_h")"
  _sec="$(printf '%s\n' "$_sl" | folded)"
  _note="$(printf '%s\n' "$_sl" | sed 's/^> //' | folded)"
  case "$_note" in
    *"What the Doc-critic's cold reader could not restate from the four files after the Architect's one re-audit, recorded here so the decision is durable and the Reviewer treats it as a decision, not a defect."*) : ;;
    *) fail "E37-F02:R5: the note sentence (one re-audit, decision not a defect) is missing or altered" ;;
  esac
  [ "$(printf '%s' "$_note" | grep -oi 're-audit' | wc -l | tr -d ' ')" -eq 1 ] \
    || fail "E37-F02:R5: the template note mentions re-audit outside its pinned sentence"
  case "$_sec" in *'Optional (E37-F02).'*) : ;; *) fail "E37-F02:R5: optional marker missing" ;; esac
  case "$_sec" in *'Omit the section when there is nothing to record.'*) : ;; *) fail "E37-F02:R5: omit sentence missing" ;; esac
  # closed-world by sentence: exactly 3 sentences (the placeholder line has none)
  [ "$(printf '%s' "$_note" | sentences)" -eq 3 ] \
    || fail "E37-F02:R5: the template section must hold exactly its 3 sentences"
  printf '%s\n' "$_sl" | grep -qxF -- '- <unit: R-id, plan row, T<n> or section> — <what the cold reader could not restate> — accepted because <why>' \
    || fail "E37-F02:R5: placeholder entry missing"
  _bm="$(lineno "$TEMPLATE" '## Business rules')"
  _aa="$(lineno "$TEMPLATE" '## Architecture alignment')"
  _ac="$(lineno "$TEMPLATE" '## Acceptance criteria (EARS)')"
  [ -n "$_bm" ] && [ -n "$_aa" ] && [ -n "$_ac" ] && [ "$_bm" -lt "$_aa" ] && [ "$_aa" -lt "$_ac" ] \
    || fail "E37-F02:R5: '## Architecture alignment' must stay between Business rules and Acceptance criteria"
  python3 "$SRC/tools/tasks-pair-check.py" "$SRC/specs/_templates/feature.tasks.md" --spec "$TEMPLATE" >/dev/null \
    || fail "E37-F02:R5: the templates no longer lint clean under tasks-pair-check"
  pass "E37-F02:R5: template carries the optional Accepted trade-offs section"
}

# ── E37-F02:R6 — WORKFLOW paragraph and README sentence ────────────────────────
test_workflow_paraphrase_paragraph() {
  _sec="$(slice "$WORKFLOW" '## Doc-critic checkpoints' | folded)"
  _need() { case "$_sec" in *"$1"*) : ;; *) fail "E37-F02:R6: WORKFLOW $2" ;; esac; }
  _need 'At the `feature-spec` checkpoint the critic'"'"'s note opens with a `## Paraphrase` (E37-F02)' "paragraph opener missing"
  _need 'restated from the four spec files alone — the inbox brief and the chat are withheld on purpose, because the Builder never sees them either — followed by a per-file `### Could not restate` list.' \
    "four-files-only / withheld-on-purpose clause missing"
  _need 'Each `could-not-restate` item is blocking for the Architect'"'"'s hand-off: fix it, or after at most one re-audit record it in the `.spec.md` under `## Accepted trade-offs`.' \
    "fix-or-record sentence missing"
  _need 'The critic itself stays advisory — no new status, no new gate — and the Reviewer reads `## Accepted trade-offs` and treats a recorded trade-off as a decision, not a defect.' \
    "advisory / Reviewer sentence missing"
  _need 'the Architect runs `tools/readiness-check.py <feature-dir>` before hand-off and it must exit 0' \
    "the E37-F01 paragraph was lost"
  _l1="$(grep -nF -- '(E37-F01): the Architect runs `tools/readiness-check.py' "$WORKFLOW" | head -n 1 | cut -d: -f1)"
  _l2="$(grep -nF -- "At the \`feature-spec\` checkpoint the critic's note opens with" "$WORKFLOW" | head -n 1 | cut -d: -f1)"
  [ -n "$_l1" ] && [ -n "$_l2" ] && [ "$_l1" -lt "$_l2" ] \
    || fail "E37-F02:R6: the paraphrase paragraph must come after the E37-F01 paragraph"
  # closed-world by sentence, scoped to the E37-F02 PARAGRAPH only (opener line to the next blank
  # line): the section is shared with E37-F01 and later features, so a section-wide count would
  # trip on their edits. A new separate paragraph in the section is not counted (accepted limit).
  _par="$(slice "$WORKFLOW" '## Doc-critic checkpoints' | awk -v s="At the \`feature-spec\` checkpoint the critic's note opens with" '
    index($0, s) == 1 { k = 1 }
    k && /^[[:space:]]*$/ { exit }
    k
  ' | folded)"
  [ "$(printf '%s' "$_par" | sentences)" -eq 3 ] \
    || fail "E37-F02:R6: WORKFLOW E37-F02 paragraph must hold exactly its 3 sentences"
  pass "E37-F02:R6: WORKFLOW carries the paraphrase paragraph, E37-F01 paragraph kept"
}

test_readme_paraphrase_sentence() {
  _sec="$(slice "$README" '## How it works' | folded)"
  case "$_sec" in
    *'Before the Builder sees a spec, the Doc-critic also paraphrases it back from the four files alone — what it proposes and how the existing system works, per the document — and anything the cold reader could not restate is fixed or recorded in the spec as an accepted trade-off (E37-F02).'*) : ;;
    *) fail "E37-F02:R6: README ## How it works lacks the paraphrase sentence" ;;
  esac
  case "$_sec" in
    *'the Reviewer rejects on exit 1.'*) : ;;
    *) fail "E37-F02:R6: README lost the three-lints sentence" ;;
  esac
  _r1="$(grep -nF -- 'the Reviewer rejects on exit 1.' "$README" | head -n 1 | cut -d: -f1)"
  _r2="$(grep -nF -- 'Before the Builder sees a spec' "$README" | head -n 1 | cut -d: -f1)"
  [ -n "$_r1" ] && [ -n "$_r2" ] && [ "$_r1" -lt "$_r2" ] \
    || fail "E37-F02:R6: the paraphrase sentence must come after the three-lints paragraph"
  pass "E37-F02:R6: README carries the paraphrase sentence"
}

# ── E37-F02:R8 — ledger row C12, VERSION/CHANGELOG pairing ─────────────────────
test_ledger_row_c12() {
  _row="$(grep -E '^\| C12 — Doc-critic paraphrase-back comprehension \| Capability compensation \|' "$RATIONALE" | head -n 1 || true)"
  [ -n "$_row" ] || fail "E37-F02:R8: docs/RATIONALE.md lacks the C12 capability-compensation row"
  printf '%s' "$_row" | grep -qE 'Ablation when a model generation ships[^|]*controlled runs[^|]*Keep only while its absence reproduces a spec defect reaching review' \
    || fail "E37-F02:R8: the C12 evidence cell lacks the ablation threshold and retention rule"
  _c11="$(grep -n '^| C11 ' "$RATIONALE" | head -n 1 | cut -d: -f1)"
  _c12="$(grep -n '^| C12 ' "$RATIONALE" | head -n 1 | cut -d: -f1)"
  [ -n "$_c11" ] && [ -n "$_c12" ] && [ "$_c12" -eq $((_c11 + 1)) ] \
    || fail "E37-F02:R8: the C12 row must sit directly after C11"
  _v="$(cat "$SRC/VERSION")"
  _top="$(grep -m 1 '^## \[' "$SRC/CHANGELOG.md" || true)"
  case "$_top" in
    "## [$_v]"*) : ;;
    *) fail "E37-F02:R8: newest CHANGELOG heading '$_top' does not match VERSION $_v" ;;
  esac
  awk '
    /^## \[/ { if (hit_f && hit_p) found = 1; hit_f = 0; hit_p = 0; next }
    /E37-F02/ { hit_f = 1 }
    /Paraphrase/ { hit_p = 1 }
    END { if (hit_f && hit_p) found = 1; exit(found ? 0 : 1) }
  ' "$SRC/CHANGELOG.md" || fail "E37-F02:R8: no CHANGELOG section names both E37-F02 and Paraphrase"
  pass "E37-F02:R8: C12 ledger row and CHANGELOG/VERSION pairing"
}

# ── run all tests ─────────────────────────────────────────────────────────────
test_doc_critic_role_exists
test_target_type_argument
test_target_type_scopes
test_calibration
test_advisory_inline_fix
test_best_effort_failure
test_progress_note
test_no_code_review
test_planner_invokes_critic
test_drillable_minimum
test_driller_invokes_critic
test_architect_invokes_critic
test_version_and_changelog
test_workflow_docs
test_no_schema_change
test_no_new_gate
test_portability
test_paraphrase_section
test_could_not_restate_blocking
test_architect_paraphrase_step
test_reviewer_reads_trade_offs
test_template_trade_offs_section
test_workflow_paraphrase_paragraph
test_readme_paraphrase_sentence
test_ledger_row_c12

echo "All doc-critic contract tests passed."
