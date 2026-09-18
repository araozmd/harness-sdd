#!/bin/sh
# test_planner_topology.sh — E28-F02: the Planner's repo-topology output.
#
# Covers R1–R10 of
# specs/epics/E28-greenfield-to-umbrella/F02-planner-topology/E28-F02.spec.md:
#   R1  >1 deployable ⇒ exactly one repo-topology ADR, above-max 4-digit id
#   R2  >1 deployable ⇒ draft at umbrella.manifest.draft.yaml, one repos: entry per
#       deployable with the required key set; keys are normalization-unique and a
#       collision is disambiguated deterministically (-2, -3, ...) (+ fixture run)
#   R3  exactly one (or zero) deployable ⇒ writes neither artifact
#   R4  the draft is inert: no umbrella.manifest write, no umbrella.manifest.yaml,
#       no umbrella engagement (static + fixture run 1)
#   R5  draft header marks DRAFT/inert; path: is relative to the draft's own dir
#   R6  scaffold_cmd is optional and opaque (only E28-F03 runs it)
#   R7  the portable agents/planner.md carries the whole rule
#   R8  the emitted /sdd-plan body + both source-mode artifacts carry the same step
#   R9  umbrella.manifest.example.yaml + docs/UMBRELLA.md document scaffold_cmd
#   R10 the Planner is the single writer; /sdd-drill does not amend the draft
#   R11 an amend records a topology change append-only (dated `## Repo topology`
#       delta + new ADR) with the latest delta authoritative per deployable, so a
#       rename/remove drops the obsolete name; the trigger reads that effective set and
#       removes the derived draft when it falls to <=1 deployable (committed ADRs kept)
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
EX="$SRC/umbrella.manifest.example.yaml"
DOC="$SRC/docs/UMBRELLA.md"
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
# then none of them may carry any <forbidden-token>. The path-base rule needs this because
# in an installed target the draft lives in the harness dir, so a clause forbidding that base
# (or moving it to the project root) states the opposite of the required `../<child>` base
# while still leaving `path` + `own directory` in the sentence (which the positive check
# above alone cannot see).
no_naming_sentence_carries() {
  _nn_lbl="$1"; _nn_fold="$2"; _nn_needle="$3"; shift 3
  sentences "$_nn_fold" > "$T/sentences.none"
  grep -F "$_nn_needle" "$T/sentences.none" > "$T/sentences.none-hit" || true
  [ -s "$T/sentences.none-hit" ] \
    || fail "$_nn_lbl: no sentence names '$_nn_needle' — positive control failed, the rule is absent"
  while IFS= read -r _nn_s; do
    for _nn_tok in "$@"; do
      if printf '%s' "$_nn_s" | grep -qF -- "$_nn_tok"; then
        fail "$_nn_lbl: the sentence naming '$_nn_needle' also carries '$_nn_tok' — the path base is contradictory (got: $_nn_s)"
      fi
    done
  done < "$T/sentences.none-hit"
}

# ── extract every span once ────────────────────────────────────────────────────
ROLE_SPAN="$T/role.span"; ROLE_FOLD="$T/role.fold"
BODY_SPAN="$T/body.span"; BODY_FOLD="$T/body.fold"
CMD_FOLD="$T/cmd.fold"
SKILL_SPAN="$T/skill.span"; SKILL_FOLD="$T/skill.fold"

extract_section "$ROLE" "Repo topology output" > "$ROLE_SPAN"
extract_heredoc "$INST" 'cat > "$CMDDIR/sdd-plan.md" <<'"'"'EOF'"'"'' > "$BODY_SPAN"
extract_section "$SKILL" "Canonical workflow" > "$SKILL_SPAN"

fold_to "$ROLE_SPAN"  "$ROLE_FOLD"
fold_to "$BODY_SPAN"  "$BODY_FOLD"
fold_to "$CMD"        "$CMD_FOLD"
fold_to "$SKILL_SPAN" "$SKILL_FOLD"

# ── R1: the repo-topology ADR ──────────────────────────────────────────────────
# test_role_and_body_name_the_topology_adr
guard "R1" "$ROLE_SPAN" 8
require_tokens "R1 positive control" "$ROLE_FOLD" "more than one deployable" "repo-topology ADR"
require_tokens "R1" "$ROLE_FOLD" "specs/adr/" "ADR-" "above the max existing ADR number"
pass "R1 role names one repo-topology ADR, specs/adr/ + ADR- and above-max allocation [test_role_and_body_name_the_topology_adr]"

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
# Collision-safe keys (Reviewer finding 4043129416): two DISTINCT deployable names can
# normalize to the SAME key (`api.v2` and `api-v2` both yield `api-v2`), and the
# coordinator's manifestRepos() rejects duplicate repository keys — so the later entry
# would be unusable and the promotion/selector flow would drop a deployable. The contract
# must require UNIQUE keys after normalization with a stated deterministic disambiguation
# order (`-2`, `-3`, …). Bounded to the sentence naming `unique` (positive control) and
# asserted on every surface the key rule lives on: the grammar sentence does not name
# `unique`, so it cannot satisfy this, and `-2`/`-3` + `order` in one sentence is the
# anchor for the deterministic rule while `manifestRepos` names the consequence. `-3` is
# pinned alongside `-2` because the worked example `api-v2-2` itself contains `-2`: a
# mutant that deletes the explicit `-2`, `-3`, … sequence but keeps the example would
# survive a `-2`-only check (found in this round's campaign), while `-3` is reachable
# only through the stated sequence. The `--` in the helpers keeps a leading-dash token
# from being read as a grep option.
for _r2u_pair in "R2 role unique keys|$ROLE_FOLD" "R2 emitted body unique keys|$BODY_FOLD" \
                 "R2 .claude/commands unique keys|$CMD_FOLD" "R2 .agents/skills unique keys|$SKILL_FOLD"; do
  _r2u_lbl="${_r2u_pair%%|*}"; _r2u_f="${_r2u_pair#*|}"
  every_naming_sentence_carries "$_r2u_lbl" "$_r2u_f" "unique" \
    'normalizing' 'collide' '-2' '-3' 'order' 'manifestRepos'
done
pass "R2 role + body name the draft and its per-deployable, collision-safe key set [test_role_and_body_name_the_draft_and_keys]"

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
[ -f "$DRILLER" ] || fail "R10: $DRILLER is missing"
# Positive control FIRST (the Planner-side rule above), then the absence check.
if grep -qF 'umbrella.manifest.draft.yaml' "$DRILLER"; then
  fail "R10: agents/driller.md names umbrella.manifest.draft.yaml — the Driller must not touch the draft (the Planner is its single writer)"
fi
pass "R10 Planner is single writer; driller.md does not amend the draft [test_drill_does_not_amend_draft]"

# ── R11: the amend path is append-only, latest-delta-wins, and removes the draft ─
# test_amend_is_append_only
# A topology change is a `/sdd-plan` amend (R10), but the amend contract is append-only
# and never rewrites the original `specs/architecture.md`. Without an appended
# `## Repo topology` delta plus a trigger that reads past the original section, the
# documented path re-reads the original one-deployable architecture and writes neither
# artifact (Reviewer finding 4042914412). A PURE union is the mirror defect (Reviewer
# finding 4043129426): it preserves a deployable that a later delta renamed or removed,
# so the `>1` trigger stays true and the draft keeps repositories that no longer exist.
# The delta is therefore authoritative for the deployables it names (latest delta wins
# per deployable), and when the effective set falls to one deployable (or none) the
# derived draft is removed while the committed ADRs are preserved. Each check is bounded
# to a sentence that only its rule carries, so the step-8 `append-only` remark and the
# no-op sentence's draft token cannot satisfy them.
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
  # (3) The amend delta is AUTHORITATIVE: effective set = union of the original and the
  # appended deltas with the latest delta winning PER DEPLOYABLE — not a pure union,
  # which would preserve a renamed/removed deployable (Reviewer finding 4043129426).
  every_naming_sentence_carries "$_r11_lbl latest delta" "$_r11_f" "latest delta" \
    "authoritative" "union" "original" "appended" "per deployable"
  # (4) The trigger reads the EFFECTIVE set; when it falls to one deployable (or none)
  # the derived draft is REMOVED and the committed repo-topology ADRs are preserved
  # (append-only, never deleted). The `one deployable` + `removes` + draft-token trio in
  # ONE sentence is the anchor: the draft token alone sits in the no-op sentence, and
  # `removes`/`one deployable` alone sit elsewhere in the span.
  every_naming_sentence_carries "$_r11_lbl effective set" "$_r11_f" "effective set" \
    "trigger" "one deployable" "removes" "umbrella.manifest.draft.yaml" "reconciles"
done
pass "R11 amended topology change is append-only, latest-delta-wins, and removes the draft at <=1 deployable [test_amend_is_append_only]"

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
