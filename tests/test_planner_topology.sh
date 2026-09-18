#!/bin/sh
# test_planner_topology.sh — E28-F02: the Planner's repo-topology output.
#
# Covers R1–R10 of
# specs/epics/E28-greenfield-to-umbrella/F02-planner-topology/E28-F02.spec.md:
#   R1  >1 deployable ⇒ exactly one repo-topology ADR, above-max 4-digit id, excluded
#       from the generic architecture-ADR pass so a greenfield run cannot emit two
#   R2  >1 deployable ⇒ draft at umbrella.manifest.draft.yaml, one repos: entry per
#       deployable with the required key set; keys are normalization-unique and a
#       collision is disambiguated deterministically (-2, -3, ...); on an amend the
#       draft is reconciled against the existing file so a surviving deployable keeps
#       its key (never renumbered), suffixes go only to newly added deployables, and a
#       removed deployable's key is never reused (+ fixture run)
#   R3  exactly one (or zero) deployable ⇒ writes neither artifact
#   R4  the draft is inert: no umbrella.manifest write, no umbrella.manifest.yaml,
#       no umbrella engagement (static + fixture run 1)
#   R5  draft header marks DRAFT/inert; path: is relative to the draft's own dir
#   R6  scaffold_cmd is optional and opaque (only E28-F03 runs it)
#   R7  the portable agents/planner.md carries the whole rule
#   R8  the emitted /sdd-plan body + both source-mode artifacts carry the same step
#   R9  umbrella.manifest.example.yaml + docs/UMBRELLA.md document scaffold_cmd
#   R10 the Planner is the single writer; /sdd-drill does not amend the draft and the
#       Driller STOPS and records a required /sdd-plan amend when a decomposition changes
#       the deployable set, PERSISTING the full resulting deployable set (logical key +
#       path) to a progress/ handoff and naming that file in its stop message (role +
#       emitted body + both source-mode command surfaces)
#   R11 an amend records a topology change append-only (dated `## Repo topology`
#       delta + a new ADR ALWAYS, including a collapse) as a COMPLETE replacement snapshot
#       (the latest delta names the full set; earlier deltas superseded), so add/remove/
#       rename are all expressible; the trigger reads that effective set and removes the
#       derived draft when it falls to <=1 deployable (committed ADRs kept); the draft is
#       the ONE carve-out from the amend's no-deletion rule; and the amend's doc-critic
#       checkpoint reviews ONLY the newly written material, ALLOWING fixes within the
#       appended `## Repo topology` delta while prohibiting changes OUTSIDE it — the
#       committed vision/architecture/existing ADRs (the greenfield branch keeps the
#       full plan-output checkpoint); the amend CONSUMES the Driller's persisted
#       `progress/<run>/topology-handoff.md` set when one exists, instead of guessing
#   R12 the derived umbrella.manifest.draft.yaml is excluded from the harness-owned path
#       set (source AND installed layouts), so an untracked draft does not fail the drift
#       guard, while a genuine harness-body edit still does
#
# House rules (see progress/lessons.md; all are load-bearing here):
#   * Every span is extracted STRUCTURALLY (a `## ` heading → the next `## `; the
#     `cat > "$CMDDIR/sdd-plan.md"` heredoc → its closing `EOF`) and guarded by
#     non-empty AND a line-count floor — never bounded on the line that happens to be
#     last today (a bare `[ -s ]` pins only the START anchor).
#   * Every negative and every attribution is paired with a positive control from the
#     SAME extraction, so a predicate that can match nothing cannot pass as a test.
#   * The scaffold_cmd attribution is bounded to the SENTENCE that names it, split on
#     sentence-ending punctuation FOLLOWED BY whitespace/end — never a bare `.`, which
#     would fragment the dotted tokens (`umbrella.manifest.draft.yaml`, `scaffold_cmd`).
#   * No literal VERSION is asserted here (the bump is pinned by test_codex_native.sh).
#   * The fixture is install-free: tools/next-task.mjs's --tasks/--config override.
#     All fixture `umbrella.manifest` values are ABSOLUTE paths — the selector resolves
#     the value against its OWN source root, not the --config file's directory (F8).

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

ROLE="$SRC/agents/planner.md"
INST="$SRC/harness-install.sh"
CMD="$SRC/.claude/commands/sdd-plan.md"
SKILL="$SRC/.agents/skills/sdd-plan/SKILL.md"
DRILLER="$SRC/agents/driller.md"
DRILL_CMD="$SRC/.claude/commands/sdd-drill.md"
DRILL_SKILL="$SRC/.agents/skills/sdd-drill/SKILL.md"
EX="$SRC/umbrella.manifest.example.yaml"
DOC="$SRC/docs/UMBRELLA.md"
DOC_CRITIC="$SRC/agents/doc-critic.md"
CFG="$SRC/harness.config.yaml"

# The ONE CommonMark fence rule (E99-F131); every markdown-heading slicer in this repo
# loads and calls it so a `#`-line inside a fenced block cannot be read as a heading.
FENCE_AWK="$(cat "$SRC/tests/lib/fence.awk")"

T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-planner-topology)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── extraction helpers ─────────────────────────────────────────────────────────

# extract_section <file> <heading-substring> — the `## ` section whose heading
# contains <heading-substring>, up to (not including) the next `## ` heading.
# fence_delim($0) comes from tests/lib/fence.awk (one shared copy): a `## ` line
# inside a fenced code block must not be read as a heading reset or a terminator.
extract_section() {
  awk -v h="$2" "$FENCE_AWK"'
    fence_delim($0) { if (k) print; next }
    !fence && /^## / { k = (index($0, h) > 0); next }
    k { print }
  ' "$1"
}

# extract_heredoc <file> <marker> — from the line containing <marker> to the next
# line that is exactly EOF.
extract_heredoc() {
  awk -v m="$2" '
    index($0, m) > 0 { k = 1; next }
    k && $0 == "EOF" { exit }
    k { print }
  ' "$1"
}

# guard <label> <span-file> <min-lines> — a stale/moved/renamed section or an empty
# extraction must red here, not pass the anchors vacuously.
guard() {
  [ -s "$2" ] || fail "$1: extracted span is empty — the section is stale, moved, or renamed"
  _g_n="$(wc -l < "$2" | tr -d ' ')"
  [ "$_g_n" -ge "$3" ] || fail "$1: extracted span has $_g_n line(s), want >= $3 — the section was truncated or moved"
}

# fold_to <span-file> <out-file> — one physical line with runs of spaces squeezed,
# so a pinned phrase is not defeated by a line wrap (a wrapped line's indentation
# would otherwise turn `per deployable` into `per    deployable`).
fold_to() { tr '\n' ' ' < "$1" | tr -s ' ' > "$2"; }

# sentences <folded-file> — one sentence per line, split on [.!?] followed by a
# space or end-of-input (never a bare `.`).
sentences() {
  awk '{
    line = $0
    gsub(/[.!?] /, "&\n", line)
    gsub(/[.!?]$/, "&\n", line)
    print line
  }' "$1"
}

# require_tokens <label> <file> <token>... — every token must be present.
require_tokens() {
  _rt_lbl="$1"; _rt_f="$2"; shift 2
  for _rt_tok in "$@"; do
    grep -qF -- "$_rt_tok" "$_rt_f" || fail "$_rt_lbl: missing pinned anchor '$_rt_tok' — the topology step is missing or diverged"
  done
}

# every_naming_sentence_carries <label> <folded-file> <needle> <token>... — extract
# the sentences naming <needle> (positive control: at least one) and require every
# one of them to carry each <token>. This is the bounded-attribution shape.
every_naming_sentence_carries() {
  _en_lbl="$1"; _en_fold="$2"; _en_needle="$3"; shift 3
  sentences "$_en_fold" > "$T/sentences.all"
  grep -F "$_en_needle" "$T/sentences.all" > "$T/sentences.hit" || true
  [ -s "$T/sentences.hit" ] \
    || fail "$_en_lbl: no sentence names '$_en_needle' — positive control failed, the rule is absent"
  while IFS= read -r _en_s; do
    for _en_tok in "$@"; do
      if ! printf '%s' "$_en_s" | grep -qF -- "$_en_tok"; then
        fail "$_en_lbl: the sentence naming '$_en_needle' does not carry '$_en_tok' — the attribution is not bounded to the rule (got: $_en_s)"
      fi
    done
  done < "$T/sentences.hit"
}

# no_naming_sentence_carries <label> <folded-file> <needle> <forbidden-token>... — the
# counterpart of every_naming_sentence_carries for a rule whose defect is a CONTRADICTORY
# clause rather than a missing one. Positive control: a sentence naming <needle> must exist;
# then none of them may carry any <forbidden-token>. Two uses: the path-base rule (in an
# installed target the draft lives in the harness dir, so a clause forbidding that base — or
# moving it to the project root — states the opposite of the required `../<child>` base while
# still leaving `path` + `own directory` in the sentence), and the amend contract (the
# effective-set removal sentence must not re-add the old `writes no new repo-topology ADR`
# disclaimer, which contradicts the always-append rule while `removes`/`reconciles` survive).
no_naming_sentence_carries() {
  _nn_lbl="$1"; _nn_fold="$2"; _nn_needle="$3"; shift 3
  sentences "$_nn_fold" > "$T/sentences.none"
  grep -F "$_nn_needle" "$T/sentences.none" > "$T/sentences.none-hit" || true
  [ -s "$T/sentences.none-hit" ] \
    || fail "$_nn_lbl: no sentence names '$_nn_needle' — positive control failed, the rule is absent"
  while IFS= read -r _nn_s; do
    for _nn_tok in "$@"; do
      if printf '%s' "$_nn_s" | grep -qF -- "$_nn_tok"; then
        fail "$_nn_lbl: the sentence naming '$_nn_needle' also carries '$_nn_tok' — it contradicts a rule this contract requires (got: $_nn_s)"
      fi
    done
  done < "$T/sentences.none-hit"
}

# ── extract every span once ────────────────────────────────────────────────────
ROLE_SPAN="$T/role.span"; ROLE_FOLD="$T/role.fold"
BODY_SPAN="$T/body.span"; BODY_FOLD="$T/body.fold"
CMD_FOLD="$T/cmd.fold"
SKILL_SPAN="$T/skill.span"; SKILL_FOLD="$T/skill.fold"
# The Driller surfaces (R10, Reviewer finding 4043416606): the Driller's clean context
# does not receive agents/planner.md, so the stop-and-hand-off rule must live on the role
# and on the /sdd-drill command body it is actually given.
DRILL_ROLE_SPAN="$T/drill-role.span"; DRILL_ROLE_FOLD="$T/drill-role.fold"
DRILL_BODY_SPAN="$T/drill-body.span"; DRILL_BODY_FOLD="$T/drill-body.fold"
DRILL_CMD_FOLD="$T/drill-cmd.fold"
DRILL_SKILL_SPAN="$T/drill-skill.span"; DRILL_SKILL_FOLD="$T/drill-skill.fold"
# The role's ordered `## What you do` list is the durable contract's step order — the
# topology guard must be listed BEFORE the seeding step, matching the executable body
# (finding 4043487843). PLAN_WHAT_* is the Planner's `## What you do`, where the explicit
# greenfield/amend branches live (finding 4043487846).
PLAN_WHAT_SPAN="$T/plan-what.span"; PLAN_WHAT_FOLD="$T/plan-what.fold"
DRILL_WHAT_SPAN="$T/drill-what.span"; DRILL_WHAT_FOLD="$T/drill-what.fold"
# The Planner's `## Doc-critic checkpoint` section (finding 4043799422): the AMEND
# checkpoint is scoped there, so it is extracted as its own span — the `## Repo
# topology output` span and `## What you do` do not carry it.
ROLE_CRITIC_SPAN="$T/role-critic.span"; ROLE_CRITIC_FOLD="$T/role-critic.fold"
# The Doc-critic role's own invocation contract (the caller may scope a subset).
DOC_CRITIC_SPAN="$T/doc-critic.span"; DOC_CRITIC_FOLD="$T/doc-critic.fold"

extract_section "$ROLE" "Repo topology output" > "$ROLE_SPAN"
extract_heredoc "$INST" 'cat > "$CMDDIR/sdd-plan.md" <<'"'"'EOF'"'"'' > "$BODY_SPAN"
extract_section "$SKILL" "Canonical workflow" > "$SKILL_SPAN"
extract_section "$DRILLER" "Topology changes" > "$DRILL_ROLE_SPAN"
extract_heredoc "$INST" 'cat > "$CMDDIR/sdd-drill.md" <<'"'"'EOF'"'"'' > "$DRILL_BODY_SPAN"
extract_section "$DRILL_SKILL" "Canonical workflow" > "$DRILL_SKILL_SPAN"
extract_section "$ROLE" "What you do" > "$PLAN_WHAT_SPAN"
extract_section "$DRILLER" "What you do" > "$DRILL_WHAT_SPAN"
extract_section "$ROLE" "Doc-critic checkpoint" > "$ROLE_CRITIC_SPAN"
extract_section "$DOC_CRITIC" "Invocation contract" > "$DOC_CRITIC_SPAN"

fold_to "$ROLE_SPAN"  "$ROLE_FOLD"
fold_to "$BODY_SPAN"  "$BODY_FOLD"
fold_to "$CMD"        "$CMD_FOLD"
fold_to "$SKILL_SPAN" "$SKILL_FOLD"
fold_to "$DRILL_ROLE_SPAN"  "$DRILL_ROLE_FOLD"
fold_to "$DRILL_BODY_SPAN"  "$DRILL_BODY_FOLD"
fold_to "$DRILL_CMD"        "$DRILL_CMD_FOLD"
fold_to "$DRILL_SKILL_SPAN" "$DRILL_SKILL_FOLD"
fold_to "$PLAN_WHAT_SPAN"   "$PLAN_WHAT_FOLD"
fold_to "$DRILL_WHAT_SPAN"  "$DRILL_WHAT_FOLD"
fold_to "$ROLE_CRITIC_SPAN" "$ROLE_CRITIC_FOLD"
fold_to "$DOC_CRITIC_SPAN"  "$DOC_CRITIC_FOLD"

# ── R1: the repo-topology ADR ──────────────────────────────────────────────────
# test_role_and_body_name_the_topology_adr
guard "R1" "$ROLE_SPAN" 8
require_tokens "R1 positive control" "$ROLE_FOLD" "more than one deployable" "repo-topology ADR"
require_tokens "R1" "$ROLE_FOLD" "specs/adr/" "ADR-" "above the max existing ADR number"
# The ADR's CONTENT obligation (Reviewer finding 4043709586): it is not merely "an ADR at
# a path" — it is a single decision that NAMES EACH REPOSITORY and explains WHY IT IS
# SEPARATE, which is exactly what the spec's R1 requires and what F03's promotion consumes
# (the artifact justifying the umbrella). Without it the umbrella's rationale is never
# recorded and the ADR degrades to a bare pointer. Bounded to the sentence naming `names
# each repository` (positive control), so the path/allocation sentence elsewhere cannot
# satisfy it; asserted on every surface the topology step lives on, so a hand-edit that
# drops the justification on the executable body alone reds (the R8 full-anchor-set
# lesson). On pre-change text no sentence names `names each repository`, so this REDs.
for _rj_pair in "R1 role ADR justification|$ROLE_FOLD" \
                "R1 emitted body ADR justification|$BODY_FOLD" \
                "R1 .claude/commands ADR justification|$CMD_FOLD" \
                "R1 .agents/skills ADR justification|$SKILL_FOLD"; do
  _rj_lbl="${_rj_pair%%|*}"; _rj_f="${_rj_pair#*|}"
  every_naming_sentence_carries "$_rj_lbl" "$_rj_f" "names each repository" \
    "repo-topology ADR" "why it is separate"
done
pass "R1 role + body + both source artifacts require the ADR to name each repository and why it is separate [test_role_and_body_name_the_topology_adr]"

# ── R1: the repo-topology decision is EXCLUDED from the generic ADR pass ───────
# (Reviewer finding 4043843860.) The generic architecture-ADR pass above requires one
# ADR per decision, topology included, while the topology step then writes its own
# `repo-topology ADR` — so a literal greenfield run can emit TWO topology ADRs despite
# the "exactly one" rule. The topology decision must be excluded from the generic pass,
# and the topology step must state that it fulfills that pass, so exactly one is
# produced. Bounded to the sentence naming `generic ADR pass` (positive control), which
# only the resolved wording carries; on pre-change text no sentence names it, so the
# assertion REDs. Asserted on every surface the step lives on (role, emitted body,
# `.claude/commands`, `.agents/skills`) so a hand-edit dropping the exclusion on the
# executable body alone reds.
for _ga_pair in "R1 role generic pass exclusion|$ROLE_FOLD" \
                 "R1 emitted body generic pass exclusion|$BODY_FOLD" \
                 "R1 .claude/commands generic pass exclusion|$CMD_FOLD" \
                 "R1 .agents/skills generic pass exclusion|$SKILL_FOLD"; do
  _ga_lbl="${_ga_pair%%|*}"; _ga_f="${_ga_pair#*|}"
  every_naming_sentence_carries "$_ga_lbl" "$_ga_f" "generic ADR pass" \
    "excluded" "exactly one" "repo-topology ADR"
done
# ...and the generic pass SENTENCE itself must carry the exclusion: a separate
# `generic ADR pass` sentence alone does not stop the pass from still claiming the
# topology decision. Bounded to the sentence naming `one ADR per decision`, on every
# surface that carries the generic pass (the role's `## What you do`, the emitted body,
# `.claude/commands`, `.agents/skills`). On pre-change text that sentence carries
# neither `repo-topology` nor `excluded`, so this REDs with the finding's exact defect.
for _gp_pair in "R1 role generic pass|$PLAN_WHAT_FOLD" \
                 "R1 emitted body generic pass|$BODY_FOLD" \
                 "R1 .claude/commands generic pass|$CMD_FOLD" \
                 "R1 .agents/skills generic pass|$SKILL_FOLD"; do
  _gp_lbl="${_gp_pair%%|*}"; _gp_f="${_gp_pair#*|}"
  every_naming_sentence_carries "$_gp_lbl" "$_gp_f" "one ADR per decision" \
    "repo-topology" "excluded"
done
pass "R1 the repo-topology decision is excluded from the generic architecture-ADR pass, so exactly one repo-topology ADR is produced [test_role_and_body_name_the_topology_adr]"

# ── R7: the portable contract carries the whole rule ───────────────────────────
# test_planner_role_portable_contract
guard "R7" "$ROLE_SPAN" 8
require_tokens "R7" "$ROLE_FOLD" \
  "umbrella.manifest.draft.yaml" "does not engage umbrella mode" \
  "single writer" "/sdd-drill" "amend"
pass "R7 agents/planner.md carries path, inert rule and single-writer rule [test_planner_role_portable_contract]"

# ── R2: the draft path and the key set, in role AND emitted body ───────────────
# test_role_and_body_name_the_draft_and_keys
guard "R2 role" "$ROLE_SPAN" 8
guard "R2 body" "$BODY_SPAN" 20
for _r2_pair in "R2 role|$ROLE_FOLD" "R2 body|$BODY_FOLD"; do
  _r2_lbl="${_r2_pair%%|*}"; _r2_f="${_r2_pair#*|}"
  require_tokens "$_r2_lbl" "$_r2_f" \
    "umbrella.manifest.draft.yaml" "path" "init" "test_command" "delegate_cmd" "scaffold_cmd"
  grep -qiE 'one[^.]{0,40}per deployable' "$_r2_f" \
    || fail "$_r2_lbl: the shape sentence does not state one entry per deployable — 'a manifest' without the per-deployable rule would pass"
done
# Coordinator grammar (Reviewer finding 4043038790): the coordinator's manifestRepos()
# accepts a key only through `[A-Za-z0-9_-]+`, but a slice id ends in `[a-z0-9-]+`
# (`store/tasks.schema.json`, tools/next-task.mjs's SLICE_RE), and slice.repo must equal
# that suffix. So an underscore/uppercase key is a manifest entry no schema-valid slice can
# reference; keying by a dotted directory (`api.v2`) is likewise a `malformed repos entry`.
# The contract must name a slice-grammar logical key and put the actual directory in
# `path`. Bounded to the sentence naming `logical name`, so the entry-field list elsewhere
# cannot satisfy it. Asserted on every surface the step lives on — a hand-edit that drops it
# on the executable body alone is the divergence ADR-0003's one-body rule forbids (same
# lesson as R8's full anchor set). The worked example `api-v2` is pinned too, so widening
# the grammar back to `[A-Za-z0-9_-]+` OR leaving the `api_v2` example reds.
for _r2k_pair in "R2 role key grammar|$ROLE_FOLD" "R2 emitted body key grammar|$BODY_FOLD" \
                 "R2 .claude/commands key grammar|$CMD_FOLD" "R2 .agents/skills key grammar|$SKILL_FOLD"; do
  _r2k_lbl="${_r2k_pair%%|*}"; _r2k_f="${_r2k_pair#*|}"
  every_naming_sentence_carries "$_r2k_lbl" "$_r2k_f" "logical name" \
    '[a-z0-9-]+' 'api-v2' 'directory' 'path'
done
# Collision-safe keys (Reviewer finding 4043129416), completed by finding 4043241872:
# two DISTINCT deployable names can normalize to the SAME key (`api.v2` and `api-v2` both
# yield `api-v2`), and the coordinator's manifestRepos() rejects duplicate repository
# keys — so the later entry would be unusable and the promotion/selector flow would drop a
# deployable. The contract must require UNIQUE keys after normalization with a stated
# deterministic disambiguation, and the allocator must probe the COMPLETE set of keys
# already assigned: the old first-incumbent rule re-collides when a LATER deployable's bare
# normalized name equals a suffix already handed out (`api`, `api!`, `api-2` previously
# allocated `api`, `api-2`, `api-2`). Bounded to the sentence naming `unique` (positive
# control) and asserted on every surface the key rule lives on: the grammar sentence does
# not name `unique`, so it cannot satisfy this. `-2`/`-3` + `order` is the deterministic
# rule while `manifestRepos` names the consequence; `-3` is pinned because the worked
# example `api-2-2` itself contains `-2`, so a `-2`-only check survives deleting the
# explicit sequence. The resolved example `api`, `api!`, `api-2` => `api`, `api-2`,
# `api-2-2` and the phrase `complete set`/`already assigned` are the full-set-probe anchors:
# the pre-change first-incumbent wording carries none of them, so each reds there. The `--`
# in the helpers keeps a leading-dash token from being read as a grep option.
for _r2u_pair in "R2 role unique keys|$ROLE_FOLD" "R2 emitted body unique keys|$BODY_FOLD" \
                 "R2 .claude/commands unique keys|$CMD_FOLD" "R2 .agents/skills unique keys|$SKILL_FOLD"; do
  _r2u_lbl="${_r2u_pair%%|*}"; _r2u_f="${_r2u_pair#*|}"
  every_naming_sentence_carries "$_r2u_lbl" "$_r2u_f" "unique" \
    'normalizing' 'collide' '-2' '-3' 'order' 'manifestRepos' \
    'complete set' 'already assigned' 'api!' 'api-2-2'
done
# Amend key stability (PR #202 finding 4043920075). The collision allocator above is
# defined for a fresh set; re-running it against the NEW set on an amend RENUMBERS a
# surviving deployable. With `api.v2` and `api-v2` initially keyed `api-v2` and `api-v2-2`,
# removing the first makes a from-scratch allocation give the survivor `api-v2` — but
# existing slices still reference `api-v2-2` (the amendment workflow updates neither their
# ids nor `slice.repo`), so the survivor becomes undispatchable, while a slice for the
# removed deployable can now resolve onto the survivor. The contract must RECONCILE against
# the existing draft: survivors keep their key, suffixes go only to newly added
# deployables, and a removed key is never handed to a different deployable. Bounded to the
# sentence naming `surviving` and the sentence naming `removed deployable's key` (positive
# controls), asserted on every surface the key rule lives on. On pre-change text neither
# needle names a sentence, so both controls RED — the exact defect the finding reports.
for _r2s_pair in "R2 role amend key stability|$ROLE_FOLD" \
                 "R2 emitted body amend key stability|$BODY_FOLD" \
                 "R2 .claude/commands amend key stability|$CMD_FOLD" \
                 "R2 .agents/skills amend key stability|$SKILL_FOLD"; do
  _r2s_lbl="${_r2s_pair%%|*}"; _r2s_f="${_r2s_pair#*|}"
  every_naming_sentence_carries "$_r2s_lbl survivor keeps its key" "$_r2s_f" "surviving" \
    "keeps" "never renumbered" "newly added" "suffix"
  every_naming_sentence_carries "$_r2s_lbl removed key not reused" "$_r2s_f" "removed deployable's key" \
    "never reused" "different deployable"
done
pass "R2 role + body preserve surviving keys across an amend (no renumbering, fresh suffixes only, removed keys not reused) [test_role_and_body_name_the_draft_and_keys]"
# Path-to-key assignments survive the draft's deletion (PR #202 finding 4044043016). The
# draft was the ONLY durable place the path->key assignments lived, yet a collapse to one
# deployable (or none) REMOVES it: the draft must go while every committed artifact stays
# append-only. After that single-deployable interval a later expansion reallocates the
# survivor's key from scratch and RENUMBERS it (`api-v2-2` -> `api-v2`), stranding every
# slice whose `repo` still names `api-v2-2` (the amendment workflow updates neither slice
# ids nor `slice.repo`). The repo-topology ADR is append-only and every set-changing amend
# appends one, so the assignment table must be recorded there and the survivor reconciled
# against THAT persisted table, not the deleted draft. Bounded to the sentence naming
# `path-to-key` (positive control), on every surface the key rule lives on. On pre-change
# text no sentence names `path-to-key`, so the positive control REDs.
for _r2p_pair in "R2 role durable key table|$ROLE_FOLD" \
                 "R2 emitted body durable key table|$BODY_FOLD" \
                 "R2 .claude/commands durable key table|$CMD_FOLD" \
                 "R2 .agents/skills durable key table|$SKILL_FOLD"; do
  _r2p_lbl="${_r2p_pair%%|*}"; _r2p_f="${_r2p_pair#*|}"
  every_naming_sentence_carries "$_r2p_lbl" "$_r2p_f" "path-to-key" \
    "repo-topology ADR" "append-only" "survive the draft"
done
pass "R2 path-to-key assignments are recorded in the append-only repo-topology ADR and survive the draft's deletion [test_role_and_body_name_the_draft_and_keys]"

# ── R3: exactly one deployable writes neither artifact ─────────────────────────
# test_single_deployable_writes_neither
guard "R3 role" "$ROLE_SPAN" 8
guard "R3 body" "$BODY_SPAN" 20
for _r3_pair in "R3 role|$ROLE_FOLD" "R3 body|$BODY_FOLD"; do
  _r3_lbl="${_r3_pair%%|*}"; _r3_f="${_r3_pair#*|}"
  require_tokens "$_r3_lbl positive control" "$_r3_f" "more than one deployable"
  require_tokens "$_r3_lbl" "$_r3_f" "exactly one deployable"
done
# The no-op sentence must name BOTH artifacts as not-written, not a bare "neither".
every_naming_sentence_carries "R3 role no-op" "$ROLE_FOLD" "exactly one deployable" \
  "repo-topology ADR" "umbrella.manifest.draft.yaml"
every_naming_sentence_carries "R3 body no-op" "$BODY_FOLD" "exactly one deployable" \
  "repo-topology ADR" "umbrella.manifest.draft.yaml"
pass "R3 exactly one deployable names both unwritten artifacts, still carries the trigger [test_single_deployable_writes_neither]"

# ── R4: the draft is inert; the shipped config default is "" ───────────────────
# test_draft_is_inert
guard "R4 role" "$ROLE_SPAN" 8
require_tokens "R4 role" "$ROLE_FOLD" "umbrella.manifest" "umbrella.manifest.yaml" "does not engage umbrella mode"
# `umbrella.manifest.yaml` is a NEGATIVE statement, not an absence: the sentence
# naming it must carry the prohibition, so "may write umbrella.manifest.yaml"
# (which the residual notes this contract cannot see as an absence) still reds.
every_naming_sentence_carries "R4 role prohibition" "$ROLE_FOLD" "umbrella.manifest.yaml" \
  "never write" "does not engage umbrella mode"
# A parsed read of the shipped umbrella: block — not a whole-file grep.
awk '/^umbrella:/{k=1;next} k && /^[^[:space:]#]/{exit} k{print}' "$CFG" > "$T/umbrella.block"
guard "R4 shipped config" "$T/umbrella.block" 1
_r4_manifest="$(grep -E '^[[:space:]]+manifest:' "$T/umbrella.block" || true)"
[ -n "$_r4_manifest" ] \
  || fail "R4: shipped harness.config.yaml umbrella block has no manifest: scalar — the switch shape changed"
if ! printf '%s\n' "$_r4_manifest" | grep -qE '^[[:space:]]+manifest:[[:space:]]*""[[:space:]]*$'; then
  fail "R4: shipped umbrella.manifest is not the empty string — a default install would engage umbrella mode"
fi
pass "R4 draft is inert in the role; shipped umbrella.manifest is \"\" [test_draft_is_inert]"

# ── R5: DRAFT/inert header and the path: base ──────────────────────────────────
# test_draft_header_and_path_base
guard "R5 role" "$ROLE_SPAN" 8
guard "R5 body" "$BODY_SPAN" 20
every_naming_sentence_carries "R5 role header" "$ROLE_FOLD" "DRAFT" "inert" "header"
every_naming_sentence_carries "R5 body header" "$BODY_FOLD" "DRAFT" "inert" "header"
every_naming_sentence_carries "R5 role path base" "$ROLE_FOLD" "own directory" "path"
every_naming_sentence_carries "R5 body path base" "$BODY_FOLD" "own directory" "path"
# ...and the base sentence must NOT also forbid it or re-base it to the project root: in an
# installed target the draft IS in the harness dir, so "never relative to the harness
# directory" contradicts the required `../<child>` sibling path. The positive pair check
# above stays green on the contradiction (both tokens survive), so this negative is what
# pins the correction on every surface the clause appears on.
no_naming_sentence_carries "R5 role path base" "$ROLE_FOLD" "own directory" "harness directory" "project root"
no_naming_sentence_carries "R5 body path base" "$BODY_FOLD" "own directory" "harness directory" "project root"
no_naming_sentence_carries "R5 .claude/commands" "$CMD_FOLD" "own directory" "harness directory" "project root"
no_naming_sentence_carries "R5 .agents/skills" "$SKILL_FOLD" "own directory" "harness directory" "project root"
pass "R5 DRAFT/inert header and path relative to the draft's own directory [test_draft_header_and_path_base]"

# ── R6: scaffold_cmd optional and opaque, attributed to F03 ────────────────────
# test_scaffold_cmd_optional_and_opaque
guard "R6 role" "$ROLE_SPAN" 8
guard "R6 body" "$BODY_SPAN" 20
require_tokens "R6 role" "$ROLE_FOLD" "scaffold_cmd" "optional" "opaque"
require_tokens "R6 body" "$BODY_FOLD" "scaffold_cmd" "optional" "opaque"
every_naming_sentence_carries "R6 role attribution" "$ROLE_FOLD" "scaffold_cmd" "opaque" "F03"
every_naming_sentence_carries "R6 body attribution" "$BODY_FOLD" "scaffold_cmd" "opaque" "F03"
pass "R6 scaffold_cmd is optional/opaque and only F03 runs it [test_scaffold_cmd_optional_and_opaque]"

# ── R8: the emitted body and both source-mode artifacts carry the same step ────
# test_command_body_matches_role_no_divergence
guard "R8 body" "$BODY_SPAN" 20
guard "R8 skill" "$SKILL_SPAN" 20
[ -f "$CMD" ] || fail "R8: $CMD is missing — the source-mode command was not reconciled"
# Positive control on the shared unit: a blanked/truncated SKILL cannot pass the
# anchors by being empty (the ADR-0003 header must still be there).
grep -qF '## Invocation adapter' "$SKILL" \
  || fail "R8: .agents/skills/sdd-plan/SKILL.md lost the shared-unit header '## Invocation adapter' — the unit was blanked or truncated"
for _r8_pair in "R8 emitted body|$BODY_FOLD" "R8 .claude/commands|$CMD_FOLD" "R8 .agents/skills|$SKILL_FOLD"; do
  _r8_lbl="${_r8_pair%%|*}"; _r8_f="${_r8_pair#*|}"
  # The FULL pinned-anchor set from the plan's content contract, not a convenient
  # subset: the ADR path/id/allocation anchors are asserted on every surface too, so
  # the executable body cannot diverge on where ADRs go while the role keeps them
  # (Reviewer Finding A / M2b, M24).
  require_tokens "$_r8_lbl" "$_r8_f" \
    "more than one deployable" "repo-topology ADR" "umbrella.manifest.draft.yaml" \
    "scaffold_cmd" "does not engage umbrella mode" \
    "specs/adr/" "ADR-" "above the max existing ADR number"
  # ...and those ADR anchors are pinned to the TOPOLOGY sentence (the one naming the
  # `more than one deployable` trigger), not merely anywhere in the span: the emitted
  # body also carries `specs/adr/` in the earlier generic architecture-ADR step, so a
  # whole-span token check leaves the topology step's own path / above-max allocation
  # rule renameable or deletable (Reviewer M2b, M24). Bounded here so the divergence
  # reds on every surface.
  every_naming_sentence_carries "$_r8_lbl ADR step" "$_r8_f" "more than one deployable" \
    "specs/adr/" "ADR-" "above the max existing ADR number"
done
# ADR-0003: one body, no per-host fork of the topology step. Anchored on the tokens
# anywhere in the span (a fork need not start at column 0); none of the three
# genuine spans carries `Codex:`/`OpenCode:` elsewhere, so this is not satisfied by
# the artifacts' ordinary host-neutral prose.
for _r8_f in "$BODY_SPAN" "$CMD" "$SKILL_SPAN"; do
  for _r8_host in "Codex:" "OpenCode:"; do
    if grep -qF "$_r8_host" "$_r8_f"; then
      fail "R8: $_r8_f introduces a host-specific fork ('$_r8_host') of the topology step — ADR-0003 requires one shared body"
    fi
  done
done
pass "R8 emitted body + both source-mode artifacts carry the same step, no fork [test_command_body_matches_role_no_divergence]"

# ── R8 (handoff): the post-plan report enumerates the draft on every surface ───
# The draft is a planning artifact, so the final handoff must name it — otherwise a
# user can commit every listed planning artifact while leaving the untracked draft
# behind (Reviewer finding 4042832630), and E28-F03 gets nothing to promote in
# another checkout. Bounded to the SENTENCE naming `artifacts written`, so the
# step-7 `umbrella.manifest.draft.yaml` token cannot satisfy it.
ROLE_REPORT_SPAN="$T/role-report.span"; ROLE_REPORT_FOLD="$T/role-report.fold"
extract_section "$ROLE" "Completion report" > "$ROLE_REPORT_SPAN"
guard "R8 handoff role" "$ROLE_REPORT_SPAN" 3
fold_to "$ROLE_REPORT_SPAN" "$ROLE_REPORT_FOLD"
for _r8h_pair in "R8 handoff role|$ROLE_REPORT_FOLD" "R8 handoff emitted body|$BODY_FOLD" \
                 "R8 handoff .claude/commands|$CMD_FOLD" "R8 handoff .agents/skills|$SKILL_FOLD"; do
  _r8h_lbl="${_r8h_pair%%|*}"; _r8h_f="${_r8h_pair#*|}"
  every_naming_sentence_carries "$_r8h_lbl" "$_r8h_f" "artifacts written" \
    "umbrella.manifest.draft.yaml"
done
pass "R8 post-plan report names the draft on the role, emitted body and both source artifacts [test_command_body_matches_role_no_divergence]"

# ── R9: example manifest + UMBRELLA.md Manifest reference ──────────────────────
# test_example_manifest_documents_scaffold_cmd
[ -f "$EX" ] || fail "R9: $EX is missing"
python3 - "$EX" <<'PY' || fail "R9: umbrella.manifest.example.yaml no longer parses path/init/test_command/delegate_cmd per repo"
import sys, re
lines = open(sys.argv[1]).read().splitlines()
repos = {}
cur = None
in_repos = False
for ln in lines:
    if re.match(r"^repos:\s*$", ln):
        in_repos = True
        continue
    if in_repos and re.match(r"^\S", ln):
        in_repos = False
    if not in_repos:
        continue
    m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", ln)
    if m:
        cur = m.group(1)
        repos[cur] = {}
        continue
    m = re.match(r"^    ([A-Za-z_]+):\s*(.+?)\s*$", ln)
    if m and cur:
        repos[cur][m.group(1)] = m.group(2)
assert repos, "no repos parsed"
for r, f in repos.items():
    for need in ("path", "init", "test_command", "delegate_cmd"):
        assert need in f, "repo %s missing required key %s" % (r, need)
assert any("scaffold_cmd" in f for f in repos.values()), "no entry carries the optional scaffold_cmd"
print("ok %d repos" % len(repos))
PY
# A comment LINE (not a key line) must name both scaffold_cmd and opaque.
if ! grep -E '^[[:space:]]*#' "$EX" | grep -F 'scaffold_cmd' | grep -qi 'opaque'; then
  fail "R9: no comment line in umbrella.manifest.example.yaml names scaffold_cmd and opaque"
fi
extract_section "$DOC" "Manifest reference" > "$T/doc.span"
guard "R9 UMBRELLA.md" "$T/doc.span" 3
require_tokens "R9 UMBRELLA.md" "$T/doc.span" "scaffold_cmd" "optional" "opaque"
pass "R9 example + docs document scaffold_cmd and keep the four required keys [test_example_manifest_documents_scaffold_cmd]"

# ── R10: the Planner is the single writer; the Driller does not amend ──────────
# test_drill_does_not_amend_draft
guard "R10 role" "$ROLE_SPAN" 8
require_tokens "R10 role" "$ROLE_FOLD" "single writer"
every_naming_sentence_carries "R10 role" "$ROLE_FOLD" "/sdd-drill" "never" "amend"
# R10's THIRD clause — "a topology change is a `/sdd-plan` amend" — is distinct from
# the /sdd-drill clause above: that clause's `amend` is a substring of `amends`, so
# deleting the whole re-plan clause would stay green without this line. The sentence
# naming `topology change` is required to carry `/sdd-plan`, not just `amend`.
every_naming_sentence_carries "R10 role re-plan" "$ROLE_FOLD" "topology change" "/sdd-plan" "amend" "append-only" "reconciles the draft"
# The Driller-side rule (Reviewer finding 4043416606). The Planner-side sentence above
# never reaches the Driller: its clean context is `agents/driller.md` plus the
# `/sdd-drill` command body, not `agents/planner.md`. On every surface the Driller rule
# lives on, the sentence naming the changed deployable set must carry the hand-off
# (`/sdd-plan` + `amend`, and `required` + `STOP` to prove it STOPS and records it); the
# sentence naming the draft must carry the Planner's single-writer authority and the
# Driller's `do not create or amend` prohibition (a positive prohibition, not an absence
# grep, so a Driller granted write authority would red); the sentence naming the topology
# decision must carry `do not make` (the Driller hands the decision to the Planner); and
# the sentence naming the ADR-delta authority must scope it to the non-topology decisions
# it keeps. Each surface is asserted independently, so a divergence on the emitted body
# reds while the role stays green (ADR-0003's one-body rule, the R8 lesson).
guard "R10 driller role" "$DRILL_ROLE_SPAN" 5
guard "R10 driller body" "$DRILL_BODY_SPAN" 20
guard "R10 driller skill" "$DRILL_SKILL_SPAN" 20
[ -f "$DRILL_CMD" ] || fail "R10: $DRILL_CMD is missing — the source-mode /sdd-drill command was not reconciled"
for _r10_pair in "R10 driller role|$DRILL_ROLE_FOLD" "R10 driller emitted body|$DRILL_BODY_FOLD" \
                 "R10 driller .claude/commands|$DRILL_CMD_FOLD" "R10 driller .agents/skills|$DRILL_SKILL_FOLD"; do
  _r10_lbl="${_r10_pair%%|*}"; _r10_f="${_r10_pair#*|}"
  every_naming_sentence_carries "$_r10_lbl hand-off" "$_r10_f" "deployable set changes" \
    "/sdd-plan" "amend" "required" "STOP"
  every_naming_sentence_carries "$_r10_lbl decision" "$_r10_f" "the topology decision" "do not make"
  every_naming_sentence_carries "$_r10_lbl draft authority" "$_r10_f" "umbrella.manifest.draft.yaml" \
    "Planner" "single writer" "do not create or amend"
  every_naming_sentence_carries "$_r10_lbl ADR-delta authority" "$_r10_f" "your ADR-delta authority" \
    "non-topology"
done
# PERSIST before the hand-off (PR #202 finding 4043983531). Stopping is not enough: the
# Planner's amend starts in a FRESH context and `specs/architecture.md` still names the old
# deployable set, so a literal amend cannot detect what the drill discovered and is told to
# leave the topology artifacts untouched. The Driller must therefore persist the full
# resulting deployable set (each deployable: logical key + `path` + why separate) to a
# durable handoff under `progress/` and NAME that file in its stop message, so the fresh
# amend can consume it. Bounded to the sentence naming `topology handoff` and the sentence
# naming `stop message` (each a positive control), so the surrounding no-write prose cannot
# satisfy either. On pre-change text neither needle names a sentence, so both RED.
for _r10p_pair in "R10 driller role|$DRILL_ROLE_FOLD" "R10 driller emitted body|$DRILL_BODY_FOLD" \
                  "R10 driller .claude/commands|$DRILL_CMD_FOLD" "R10 driller .agents/skills|$DRILL_SKILL_FOLD"; do
  _r10p_lbl="${_r10p_pair%%|*}"; _r10p_f="${_r10p_pair#*|}"
  every_naming_sentence_carries "$_r10p_lbl persist" "$_r10p_f" "topology handoff" \
    "progress/" "logical key" "path"
  every_naming_sentence_carries "$_r10p_lbl stop message" "$_r10p_f" "stop message" \
    "topology-handoff.md"
done
# ORDERING, not mere presence (finding 4043487843): the stop-and-hand-off check must run
# BEFORE any seeding/table/brief/ADR write, or the topology-dependent feature the durable
# contract says not to seed is already persisted when the Driller stops and a re-run after
# the plan amendment appends another decomposition instead of resuming cleanly. Asserted
# structurally by PHYSICAL LINE ORDER in the two ordered lists that actually drive the
# run — the executable /sdd-drill body and the role's `## What you do`. Positive control:
# both anchors must exist. On pre-change text the body's topology step sits AFTER the
# seeding step (so the comparison reds); the role's list has no topology guard at all (so
# its positive control reds).
_drill_order() {  # <span> <topology-pattern> <seed-pattern> <label>
  _do_t="$(grep -nF "$2" "$1" | head -n1 | cut -d: -f1 || true)"
  _do_s="$(grep -nF "$3" "$1" | head -n1 | cut -d: -f1 || true)"
  [ -n "$_do_t" ] \
    || fail "$4: no topology-check anchor — the stop-and-hand-off step is absent from the ordered list"
  [ -n "$_do_s" ] \
    || fail "$4: no seeding anchor — the ordering assertion has no second anchor"
  [ "$_do_t" -lt "$_do_s" ] \
    || fail "$4: the topology check (line $_do_t) does not precede the seeding step (line $_do_s) — a topology-dependent feature is persisted before the stop-and-hand-off"
}
_drill_order "$DRILL_BODY_SPAN" '**Topology changes' '**Seed** the decomposition' "R10 drill emitted body ordering"
_drill_order "$DRILL_CMD" '**Topology changes' '**Seed** the decomposition' "R10 drill .claude/commands ordering"
_drill_order "$DRILL_SKILL_SPAN" '**Topology changes' '**Seed** the decomposition' "R10 drill .agents/skills ordering"
_drill_order "$DRILL_WHAT_SPAN" '**Topology guard' '**Seed under the board lock**' "R10 drill role ordering"
pass "R10 Planner is single writer; the Driller stops and records a required /sdd-plan amend, and the topology check precedes any seeding write [test_drill_does_not_amend_draft]"

# ── R11: the amend path is append-only, latest-delta-wins, and removes the draft ─
# test_amend_is_append_only
# A topology change is a `/sdd-plan` amend (R10), but the amend contract is append-only
# and never rewrites the original `specs/architecture.md`. Without an appended
# `## Repo topology` delta plus a trigger that reads past the original section, the
# documented path re-reads the original one-deployable architecture and writes neither
# artifact (Reviewer finding 4042914412). The delta is a COMPLETE REPLACEMENT SNAPSHOT
# (Reviewer finding 4043241876): it names the full effective set and earlier deltas are
# superseded, so removal AND rename are expressible, not just add — a pure union (or a
# latest-wins-per-name reading) cannot express removal and keeps repositories that no
# longer exist. Every amend that changes the set ALWAYS appends the new repo-topology ADR,
# including a collapse to <=1 (Reviewer finding 4043241880), and when the effective set
# falls to one deployable (or none) the Planner additionally removes the derived draft
# while the committed ADRs are preserved. Each check is bounded to a sentence that only
# its rule carries, so the step-8 `append-only` remark and the no-op sentence's draft
# token cannot satisfy them.
guard "R11 role" "$ROLE_SPAN" 8
guard "R11 body" "$BODY_SPAN" 20
for _r11_pair in "R11 role|$ROLE_FOLD" "R11 emitted body|$BODY_FOLD" \
                 "R11 .claude/commands|$CMD_FOLD" "R11 .agents/skills|$SKILL_FOLD"; do
  _r11_lbl="${_r11_pair%%|*}"; _r11_f="${_r11_pair#*|}"
  # (1) The topology-change sentence itself is append-only and reconciles the draft.
  every_naming_sentence_carries "$_r11_lbl change" "$_r11_f" "topology change" \
    "/sdd-plan" "amend" "append-only" "reconciles the draft"
  # (2) The append-only mechanism: a dated `## Repo topology` delta + a new ADR.
  every_naming_sentence_carries "$_r11_lbl delta" "$_r11_f" "## Repo topology" \
    "append-only" "dated" "delta" "specs/architecture.md" "ADR"
  # (3) The amend delta is a COMPLETE REPLACEMENT SNAPSHOT, not a union with a
  # latest-per-deployable override: the latest delta names the **full** effective set and
  # earlier deltas are superseded, so removal AND rename are both expressible by naming the
  # resulting set (Reviewer finding 4043241876 — the union wording could not express
  # removal: original `{api, web}` + a delta naming `{api}` retained `web`).
  every_naming_sentence_carries "$_r11_lbl snapshot" "$_r11_f" "complete replacement snapshot" \
    "full" "superseded" "latest delta" "original"
  every_naming_sentence_carries "$_r11_lbl remove/rename" "$_r11_f" "rename" \
    "add" "remove" "naming" "removes" "frontend"
  # (4) The trigger reads the EFFECTIVE set; when it falls to one deployable (or none)
  # the derived draft is REMOVED and the committed repo-topology ADRs are preserved
  # (append-only, never deleted). The `one deployable` + `removes` + draft-token trio in
  # ONE sentence is the anchor: the draft token alone sits in the no-op sentence, and
  # `removes`/`one deployable` alone sit elsewhere in the span.
  every_naming_sentence_carries "$_r11_lbl effective set" "$_r11_f" "effective set" \
    "trigger" "one deployable" "removes" "umbrella.manifest.draft.yaml" "reconciles"
  # (5) The ADR-on-collapse rule and the draft-removal rule AGREE (Reviewer finding
  # 4043241880): a topology change that alters the deployable set ALWAYS appends a new
  # repo-topology ADR, including a collapse/removal that leaves one deployable (or none),
  # and the <=1 case ADDITIONALLY removes the derived draft (4). Bounded to the sentence
  # naming `collapse`, which only this rule carries; the pre-change text has no such
  # sentence, so the positive control fails there.
  every_naming_sentence_carries "$_r11_lbl collapse ADR" "$_r11_f" "collapse" \
    "always" "appends" "repo-topology ADR" "removal" "one deployable"
  # (6) The derived draft is the ONE carve-out from the amend's no-deletion rule
  # (finding 4043317444): the sentence naming `carve-out` must carry the draft path and
  # `derived`. The word `collapse` is deliberately absent from that sentence, so check (5)
  # — which extracts EVERY sentence naming `collapse` — stays green on it.
  every_naming_sentence_carries "$_r11_lbl carve-out" "$_r11_f" "carve-out" \
    "umbrella.manifest.draft.yaml" "derived"
  # ...and the resolved contract must not re-introduce the contradiction the old sentence
  # carried: neither the collapse sentence nor the effective-set removal sentence may
  # disclaim the required ADR (`writes no new repo-topology ADR`). Positive control first,
  # then the forbidden token.
  no_naming_sentence_carries "$_r11_lbl collapse no-ADR" "$_r11_f" "collapse" "writes no new"
  no_naming_sentence_carries "$_r11_lbl removal no-ADR" "$_r11_f" "effective set" "writes no new"
done
pass "R11 amended topology change is append-only, latest-delta-wins, and removes the draft at <=1 deployable [test_amend_is_append_only]"

# ── R11: /sdd-plan has explicit greenfield vs amend branches ────────────────────
# test_plan_branches_skip_greenfield_writes
# The old re-run guard merely "permitted an amend to continue" while steps 5-6 still
# unconditionally wrote vision.md/architecture.md from their templates, so the amend
# either overwrote committed planning artifacts or depended on the model ignoring earlier
# ordered steps (finding 4043487846). The two modes must be EXPLICIT branches on every
# surface, and the amend branch must SKIP the greenfield template writes. Bounded to the
# sentence naming `Amend branch` (positive control), so the greenfield sentence alone
# cannot satisfy the skip rule. The role's `## What you do` is the durable contract; the
# emitted body and its two source-mode artifacts are the executed surfaces.
guard "R11 plan branches role" "$PLAN_WHAT_SPAN" 5
for _rb_pair in "R11 plan branches role|$PLAN_WHAT_FOLD" "R11 plan branches emitted body|$BODY_FOLD" \
                "R11 plan branches .claude/commands|$CMD_FOLD" "R11 plan branches .agents/skills|$SKILL_FOLD"; do
  _rb_lbl="${_rb_pair%%|*}"; _rb_f="${_rb_pair#*|}"
  require_tokens "$_rb_lbl branch labels" "$_rb_f" "Greenfield branch" "Amend branch"
  every_naming_sentence_carries "$_rb_lbl amend skip" "$_rb_f" "Amend branch" \
    "SKIP" "greenfield" "never rewrites"
done
pass "R11 /sdd-plan has explicit greenfield vs amend branches; the amend branch skips the greenfield writes [test_plan_branches_skip_greenfield_writes]"

# ── R11: the amend branch GATES the topology writes on a detected set change ────
# (Reviewer finding 4043612841.) The pre-change amend branch told the Planner to
# append the dated topology delta and the new `repo-topology ADR` and reconcile or
# remove the derived draft on EVERY amend — including one that only adds roadmap epics
# or non-topology ADRs. That both manufactures a redundant topology decision and
# contradicts the amend contract, which conditions those operations on a CHANGED
# deployable set. The branch must state the condition explicitly (only a detected
# deployable-set change touches the topology artifacts) AND state the boundary the
# other way (a non-topology amend leaves them alone). Bounded per surface, so a branch
# that keeps the unconditional operations cannot pass: on pre-change text the needle
# `deployable-set change` is absent, so the positive control fails. The `non-topology
# ADR deltas` needle is deliberately distinct from the Driller's `non-topology
# decisions`, so this check cannot be satisfied by the Driller rule.
for _ag_pair in "R11 amend gate role|$PLAN_WHAT_FOLD" "R11 amend gate emitted body|$BODY_FOLD" \
                "R11 amend gate .claude/commands|$CMD_FOLD" "R11 amend gate .agents/skills|$SKILL_FOLD"; do
  _ag_lbl="${_ag_pair%%|*}"; _ag_f="${_ag_pair#*|}"
  every_naming_sentence_carries "$_ag_lbl condition" "$_ag_f" "deployable-set change" \
    "Only when" "topology delta" "repo-topology ADR" "reconcile"
  every_naming_sentence_carries "$_ag_lbl non-topology amend" "$_ag_f" "non-topology ADR deltas" \
    "must not touch the topology artifacts"
done
pass "R11 the amend branch gates the topology writes on a detected deployable-set change and leaves them alone for a non-topology amend [test_amend_is_append_only]"

# ── R11: a path-only relocation IS a topology change; reconcile entry metadata ──
# (PR #202 finding 4044043011.) The trigger classified the deployable SET, so RELOCATING
# an existing deployable to a new `path` without renaming it looked unchanged: the topology
# output step stayed off and the derived draft kept the STALE `path`. A relocation must be
# treated as a topology change (the entry metadata is reconciled) even though the set is
# the same. Bounded to the sentence naming `path-only relocation` (positive control), on
# every surface the step lives on. On pre-change text no sentence names `path-only
# relocation`, so the positive control REDs.
for _r11r_pair in "R11 role path-only relocation|$ROLE_FOLD" \
                  "R11 emitted body path-only relocation|$BODY_FOLD" \
                  "R11 .claude/commands path-only relocation|$CMD_FOLD" \
                  "R11 .agents/skills path-only relocation|$SKILL_FOLD"; do
  _r11r_lbl="${_r11r_pair%%|*}"; _r11r_f="${_r11r_pair#*|}"
  every_naming_sentence_carries "$_r11r_lbl" "$_r11r_f" "path-only relocation" \
    "topology change" "reconcile that entry's metadata" "stale"
done
pass "R11 a path-only relocation is a topology change that reconciles the entry metadata, so the draft keeps no stale path [test_amend_is_append_only]"

# ── R11: the amend CONSUMES the Driller's persisted topology handoff ───────────
# (PR #202 finding 4043983531, the Planner half.) The Driller persists the resulting
# deployable set to a progress handoff, but unless the amend tells the fresh Planner to
# consume it the file is inert and the amend still guesses — while it is instructed to
# leave the topology artifacts untouched. The Amend branch must name the handoff file and
# say it detects the change from that persisted set. Bounded to the sentence naming
# `topology handoff` (positive control), on the role's `## What you do` (where the Amend
# branch lives) and the emitted body / both source artifacts. On pre-change text no
# sentence names `topology handoff`, so the positive control fails.
for _ac_pair in "R11 amend consume role|$PLAN_WHAT_FOLD" "R11 amend consume emitted body|$BODY_FOLD" \
                "R11 amend consume .claude/commands|$CMD_FOLD" "R11 amend consume .agents/skills|$SKILL_FOLD"; do
  _ac_lbl="${_ac_pair%%|*}"; _ac_f="${_ac_pair#*|}"
  every_naming_sentence_carries "$_ac_lbl" "$_ac_f" "topology handoff" \
    "progress/" "consumes" "logical key" "path"
done
pass "R11 the amend branch consumes the Driller's persisted topology handoff (progress/ + logical key + path) instead of guessing [test_amend_is_append_only]"

# ── R11: the topology output step ITSELF is gated; the no-op rule is greenfield-scoped ─
# (Reviewer findings 4043709578 and 4043709584 — two refinements of the same condition.)
# (1) Step 7 was labeled "both branches" and wrote the ADR + draft unconditionally
#     whenever the architecture named >1 deployable — so a non-topology AMEND on a project
#     that ALREADY has >1 deployable manufactured a redundant topology ADR and rewrote the
#     draft. The step itself must be gated on an ACTUAL deployable-set change: greenfield's
#     set is new, and an amend acts only when it changed the set.
# (2) The no-artifact rule was unqualified ("exactly one deployable => write neither"),
#     which contradicted the collapse/consolidation-amend rule (a set-changing amend ALWAYS
#     appends the new repo-topology ADR, even when it collapses to one deployable). The two
#     directives must agree: the no-op rule is scoped to GREENFIELD runs, and the same
#     sentence states the consolidation amend still appends the ADR (and removes the draft).
# Bounded to a step-7-only needle (`topology output step`) and to the no-op sentence
# (`exactly one deployable`) respectively, on all four surfaces. On pre-change text no
# sentence names `topology output step`, and the no-op sentence carries neither
# `greenfield` nor `appends` — so each assertion REDs there.
for _tg_pair in "R11 role topology gate|$ROLE_FOLD" \
                "R11 emitted body topology gate|$BODY_FOLD" \
                "R11 .claude/commands topology gate|$CMD_FOLD" \
                "R11 .agents/skills topology gate|$SKILL_FOLD"; do
  _tg_lbl="${_tg_pair%%|*}"; _tg_f="${_tg_pair#*|}"
  every_naming_sentence_carries "$_tg_lbl" "$_tg_f" "topology output step" \
    "deployable-set change" "Only when"
done
for _gs_pair in "R11 role no-op greenfield|$ROLE_FOLD" \
                "R11 emitted body no-op greenfield|$BODY_FOLD" \
                "R11 .claude/commands no-op greenfield|$CMD_FOLD" \
                "R11 .agents/skills no-op greenfield|$SKILL_FOLD"; do
  _gs_lbl="${_gs_pair%%|*}"; _gs_f="${_gs_pair#*|}"
  every_naming_sentence_carries "$_gs_lbl" "$_gs_f" "exactly one deployable" \
    "greenfield" "appends" "repo-topology ADR"
done
pass "R11 the topology output step is gated on an actual set change and the no-artifact rule is greenfield-scoped while a consolidation amend still appends the ADR [test_amend_is_append_only]"

# ── R11: the amend doc-critic checkpoint reviews ONLY newly written material ────
# (Reviewer finding 4043799422.) The amend branch forbids rewriting vision.md,
# architecture.md and existing ADRs in STEPS 5-6, but step 9 still passed ALL of those
# committed artifacts to `target-type=plan-output` and told the Planner to apply the
# findings inline; `agents/doc-critic.md` requires fixes in every reviewed document, so an
# epic-only or topology amendment could rewrite the committed planning baseline
# INDIRECTLY through the checkpoint. The amend checkpoint must review ONLY the newly
# written material (new epics, the new repo-topology ADR, the appended `## Repo topology`
# delta) and must PROHIBIT fixes to committed artifacts; the greenfield branch keeps the
# full `plan-output` checkpoint. Each check is bounded to a naming sentence with its own
# positive control: on pre-change text no sentence names `newly written material` or
# `committed planning baseline`, so both positive controls fail (the RED check). The
# scope sentence must ALSO satisfy the existing R11 `## Repo topology` delta attribution
# above (it names the delta, `append-only`, `dated`, `specs/architecture.md` and `ADR`),
# which is why those tokens are carried here rather than a bare step reference.
guard "R11 doc-critic role" "$ROLE_CRITIC_SPAN" 5
for _dc_pair in "R11 doc-critic role|$ROLE_CRITIC_FOLD" \
                "R11 doc-critic emitted body|$BODY_FOLD" \
                "R11 doc-critic .claude/commands|$CMD_FOLD" \
                "R11 doc-critic .agents/skills|$SKILL_FOLD"; do
  _dc_lbl="${_dc_pair%%|*}"; _dc_f="${_dc_pair#*|}"
  # The amend checkpoint's scope sentence names only the new material. The scope
  # token is the PHRASE `only the newly written`, not the bare word `only`: the same
  # sentence also contains `append-only`, so a bare-`only` check is satisfied by
  # `append-only` and stays green when the exclusivity verb is deleted (M5, R13).
  every_naming_sentence_carries "$_dc_lbl scope" "$_dc_f" "newly written material" \
    "only the newly written" "repo-topology ADR" "delta" "epic.md"
  # ...and the prohibition sentence ALLOWS fixes WITHIN the appended section while
  # forbidding any change OUTSIDE it (Reviewer finding 4043843863). The checkpoint reviews
  # the appended `## Repo topology` delta, so a valid finding against the delta must be
  # fixable; the old "never applies a doc-critic fix to a committed specs/architecture.md"
  # wording forbade fixing the very section under review, so a valid delta finding had to
  # be ignored. The prohibition is now scoped to "no changes outside the appended
  # section". Bounded to the sentence naming `committed planning baseline` (positive
  # control); on pre-change text that sentence carries neither
  # `fix within the appended section only` nor `no changes outside the appended section`,
  # so each assertion REDs there.
  every_naming_sentence_carries "$_dc_lbl prohibition inside" "$_dc_f" "committed planning baseline" \
    "fix within the appended section only" "repo-topology ADR" "epic.md"
  every_naming_sentence_carries "$_dc_lbl prohibition outside" "$_dc_f" "committed planning baseline" \
    "no changes outside the appended section" "specs/vision.md" "specs/architecture.md" "existing ADR"
done
# The Doc-critic role's contract must state that a caller-scoped subset limits the fixes
# to that subset (the clarification that makes the checkpoint's own "apply fixes inline"
# clause harmless when the caller passes only the new material). Positive control: the
# sentence naming `review only that subset` must exist; on pre-change text it does not.
guard "R11 doc-critic contract" "$DOC_CRITIC_SPAN" 3
every_naming_sentence_carries "R11 doc-critic contract scope" "$DOC_CRITIC_FOLD" \
  "review only that subset" "newly written material" "propose fixes only there" "never"
pass "R11 the amend doc-critic checkpoint reviews only newly written material, allows fixes within the appended section and prohibits changes outside it [test_amend_is_append_only]"

# ── R12: the derived draft is project-owned, not harness drift ─────────────────
# test_draft_excluded_from_harness_owned
# The draft is DERIVED: docs/INSTALL.md commits the planning baseline only AFTER
# /sdd-drill, so between /sdd-plan and that commit it is untracked — yet tools/
# harness-owned-paths.sh claims the whole .harness/ tree as body, which hard-failed the
# mandatory drift gate on a file the Planner just wrote (P1 finding 4043317437). The fix
# is ONE :(exclude) line in the SHARED ownership definition (both init.sh's drift guard
# and the installer's cascade audit read it), so it must resolve in BOTH layouts — a
# source-layout-only fix would leave the installed target failing.
guard "R12" "$ROLE_SPAN" 8
sh "$SRC/tools/harness-owned-paths.sh" body "$SRC" \
  | grep -qxF ':(exclude)umbrella.manifest.draft.yaml' \
  || fail "R12: source-layout body pathspecs do not exclude umbrella.manifest.draft.yaml — the Planner's derived draft is claimed as harness body"
sh "$SRC/tools/harness-owned-paths.sh" body "$SRC/.harness" \
  | grep -qxF ':(exclude).harness/umbrella.manifest.draft.yaml' \
  || fail "R12: installed-layout body pathspecs do not exclude .harness/umbrella.manifest.draft.yaml — an untracked draft hard-fails init.sh's gate"

# Behavioral probe: run the EXACT query init.sh runs (`git status --porcelain -uall --
# <the body pathspecs>`) in a scratch repo. Writes only under $T. The positive control is
# in the SAME repo and differs only in WHICH file changed: without it an empty result
# would be satisfied by a pathspec set that checks nothing.
PROBE="$T/drift-probe"
mkdir -p "$PROBE/.harness/agents"
git -C "$PROBE" init -q .
git -C "$PROBE" config user.email "test@harness.local"
git -C "$PROBE" config user.name "harness test"
printf 'name = "planner body"\n' > "$PROBE/.harness/agents/planner.md"
git -C "$PROBE" add -A
git -C "$PROBE" commit -q -m "installed harness body"
[ -z "$(git -C "$PROBE" status --porcelain)" ] \
  || fail "R12 probe: fixture is dirty right after its commit — every assertion below would be about the wrong tree"
printf '# umbrella.manifest.draft.yaml — DRAFT, inert\nrepos: {}\n' \
  > "$PROBE/.harness/umbrella.manifest.draft.yaml"
# The body pathspecs, one per line. `set -f` around the unquoted expansion because the
# pathspec list is expanded by the shell, not quoted (no pathspec contains whitespace).
sh "$SRC/tools/harness-owned-paths.sh" body "$PROBE/.harness" > "$T/drift-probe.specs"
set -f
_probe_drift="$(git -C "$PROBE" status --porcelain -uall -- $(cat "$T/drift-probe.specs") || true)"
set +f
[ -z "$_probe_drift" ] \
  || fail "R12 probe: an untracked umbrella.manifest.draft.yaml is inside the checked set — init.sh would hard-fail on the Planner's own output: $_probe_drift"
# Positive control in the SAME repo: a genuine harness-body edit must still be reported.
printf '\n# unlanded edit\n' >> "$PROBE/.harness/agents/planner.md"
set -f
_probe_drift="$(git -C "$PROBE" status --porcelain -uall -- $(cat "$T/drift-probe.specs") || true)"
set +f
case "$_probe_drift" in
  *agents/planner.md*) : ;;
  *) fail "R12 control: a modified tracked harness-body file is NOT reported — the exclusion widened past the derived draft: $_probe_drift" ;;
esac
pass "R12 derived umbrella.manifest.draft.yaml is excluded from harness-owned paths (source + installed), with a real body edit still drifting [test_draft_excluded_from_harness_owned]"

# ── Fixture plan run (R2, R4, R9) — install-free, absolute manifest paths ──────
# test_fixture_plan_run_draft_shape_and_inertness
command -v node >/dev/null 2>&1 || fail "fixture plan run: node is required to run tools/next-task.mjs"

PLAN="$T/plan"
mkdir -p "$PLAN/specs" "$PLAN/state"

cat > "$PLAN/specs/architecture.md" <<'MD'
# Architecture (fixture)

Three deployables: `bff`, `web`, and `api.v2`, each its own repository.

## ADR index
- ADR-0001 — fixture
MD

cat > "$PLAN/umbrella.manifest.draft.yaml" <<'YAML'
# umbrella.manifest.draft.yaml — DRAFT, written by /sdd-plan.
# This file is inert: it is not a switch, and only E28-F03's promotion acts on it.
#
# Every `path:` is relative to THIS draft file's own directory (the child sibling).
repos:
  bff:
    path: ../bff
    init: ./init.sh
    test_command: "npm test"
    delegate_cmd: ""
    scaffold_cmd: ""
  web:
    path: ../web
    init: ./init.sh
    test_command: "npm test"
    delegate_cmd: ""
  api-v2:
    path: ../api.v2
    init: ./init.sh
    test_command: "pytest"
    delegate_cmd: ""
YAML

# A board with a slice naming one of the draft's repos: this makes run 1 vs run 2
# DISCRIMINATING (feature-kind vs slice-loop), so a manifest that silently fails to
# engage cannot pass run 2 by emitting the same output as run 1.
cat > "$PLAN/state/tasks.json" <<'JSON'
{"project":"fixture","epics":[{"id":"E1","title":"fixture","status":"planned","features":[
  {"id":"E1-F1","title":"fixture","status":"in-progress","sdd":true,"spec_path":"specs/f1/",
   "slices":[{"id":"E1-F1@bff","repo":"bff","status":"pending"}]}
]}]}
JSON

cat > "$PLAN/no-repos.yaml" <<'YAML'
metadata:
  name: not-a-manifest
YAML

write_cfg() {  # <file> <umbrella.manifest value>
  cat > "$1" <<EOF
workflow:
  require_spec_approval: true
  identity: ""
umbrella:
  manifest: "$2"
EOF
}

write_cfg "$PLAN/cfg-inert.yaml" ""
write_cfg "$PLAN/cfg-draft.yaml" "$PLAN/umbrella.manifest.draft.yaml"
write_cfg "$PLAN/cfg-no-repos.yaml" "$PLAN/no-repos.yaml"

RC=0
run_sel() {  # <config> <out-json>
  if node "$SRC/tools/next-task.mjs" --tasks "$PLAN/state/tasks.json" --config "$1" --json \
       > "$2" 2> "$PLAN/selector.err"; then
    RC=0
  else
    RC=$?
  fi
}

json_get() {  # <json-file> <python-expression over x>
  python3 - "$1" "$2" <<'PY'
import json, sys
x = json.load(open(sys.argv[1]))
print(eval(sys.argv[2], {"x": x}))
PY
}

# Shape — the suite's own parser (mirrors tests/test_umbrella.sh R5). Guard: >= 3
# repos, so a renamed/emptied repos: mapping reds rather than passing on zero.
python3 - "$PLAN/umbrella.manifest.draft.yaml" <<'PY' || fail "R2/R9 fixture: the draft's repos: shape is wrong"
import sys, re
lines = open(sys.argv[1]).read().splitlines()
repos = {}
cur = None
in_repos = False
for ln in lines:
    if re.match(r"^repos:\s*$", ln):
        in_repos = True
        continue
    if in_repos and re.match(r"^\S", ln):
        in_repos = False
    if not in_repos:
        continue
    m = re.match(r"^  ([a-z0-9-]+):\s*$", ln)
    if m:
        cur = m.group(1)
        repos[cur] = {}
        continue
    m = re.match(r"^    ([A-Za-z_]+):\s*(.+?)\s*$", ln)
    if m and cur:
        repos[cur][m.group(1)] = m.group(2)
assert len(repos) >= 3, "extracted %d repos, want >= 3" % len(repos)
assert set(repos) == {"bff", "web", "api-v2"}, sorted(repos)
for r, f in repos.items():
    for need in ("path", "init", "test_command", "delegate_cmd"):
        assert need in f, "repo %s missing %s" % (r, need)
    assert f["path"].startswith("../"), "repo %s path %r is not relative to the draft's own dir" % (r, f["path"])
# The coordinator grammar: the key is a slice-id-compatible logical name in [a-z0-9-]+, never
# the raw dotted directory; the actual directory lives in `path` (Reviewer finding
# 4043038790). The parser above is already restricted to [a-z0-9-]+, so an underscore or
# uppercase key line extracts < 3 repos and reds the count guard as well.
assert repos["api-v2"]["path"] == "../api.v2", \
    "the dotted directory must live in path, not the key (got key=api-v2 path=%r)" % repos["api-v2"]["path"]
print("ok %d repos" % len(repos))
PY
# The draft's header must mark it DRAFT and inert.
head -n 3 "$PLAN/umbrella.manifest.draft.yaml" | grep -qF 'DRAFT' \
  || fail "R5 fixture: the draft's header does not mark it DRAFT"
head -n 3 "$PLAN/umbrella.manifest.draft.yaml" | grep -qi 'inert' \
  || fail "R5 fixture: the draft's header does not state it is inert"

# Run 1 — config-default inertness (R4): draft present, key "" ⇒ single-repo.
run_sel "$PLAN/cfg-inert.yaml" "$PLAN/run1.json"
[ "$RC" -eq 0 ] || fail "R4 fixture run 1: selector exited $RC with umbrella.manifest \"\" — $(cat "$PLAN/selector.err")"
_r1_kind="$(json_get "$PLAN/run1.json" 'x["selected"]["kind"]' || true)"
[ "$_r1_kind" = "feature" ] \
  || fail "R4 fixture run 1: draft present with umbrella.manifest \"\" selected kind='$_r1_kind', want 'feature' — the file name is behaving as a switch"
if grep -qF 'manifest-error' "$PLAN/run1.json"; then
  fail "R4 fixture run 1: an inert draft produced manifest-error"
fi

# Run 2 — coordinator-grammar acceptance (R2/R9): point the key at the draft. The
# slice naming `bff` must now be selected through the umbrella path: this proves the
# draft really parsed AND the repo really matched (a relative path that silently
# resolves nowhere would leave run 2 looking exactly like run 1).
run_sel "$PLAN/cfg-draft.yaml" "$PLAN/run2.json"
[ "$RC" -eq 0 ] || fail "R2/R9 fixture run 2: selector exited $RC pointing at the draft — $(cat "$PLAN/selector.err")"
_r2_kind="$(json_get "$PLAN/run2.json" 'x["selected"]["kind"]' || true)"
_r2_slice="$(json_get "$PLAN/run2.json" 'x["selected"]["slice_id"]' || true)"
_r2_route="$(json_get "$PLAN/run2.json" 'x["selected"]["route"]' || true)"
[ "$_r2_kind" = "slice" ] && [ "$_r2_slice" = "E1-F1@bff" ] && [ "$_r2_route" = "slice-loop" ] \
  || fail "R2/R9 fixture run 2: draft did not engage (kind='$_r2_kind' slice='$_r2_slice' route='$_r2_route') — the artifact is not consumable under the coordinator's own parser"
if grep -qF 'manifest-error' "$PLAN/run2.json"; then
  fail "R2/R9 fixture run 2: pointing at the draft produced manifest-error"
fi

# Run 3 — positive control on the switch: an existing manifest lacking repos: must
# error, proving the config pointer is the switch and the fixture can engage it.
run_sel "$PLAN/cfg-no-repos.yaml" "$PLAN/run3.json"
[ "$RC" -ne 0 ] || fail "R4 fixture run 3 control: a manifest lacking repos: exited 0 — the switch is not the config pointer, so run 1 proves nothing"
_r3_code="$(json_get "$PLAN/run3.json" 'x["reason"]["code"]' || true)"
[ "$_r3_code" = "manifest-error" ] \
  || fail "R4 fixture run 3 control: reason code '$_r3_code', want 'manifest-error' — the fixture cannot engage the switch"

pass "fixture plan run: config-default inertness, draft acceptance, switch control (R2, R4, R9) [test_fixture_plan_run_draft_shape_and_inertness]"

echo "All planner topology tests passed."
