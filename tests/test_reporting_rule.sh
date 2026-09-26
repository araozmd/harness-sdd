#!/bin/sh
# test_reporting_rule.sh — prompt-contract test contract for E32-F03 (the reporting rule +
# the /sdd-report command). Zero-dependency POSIX sh (+ awk/grep/sed/git/date), matching the
# house style of tests/test_feedback_config.sh / test_feedback_report.sh: a self-cleaning
# mktemp tree, fail/pass helpers, dash-clean. No LLM runs, no network — every check extracts
# the exact rule / role / command span and asserts pinned anchors INSIDE it, plus real
# installer runs into temp targets for the emitted front-end surfaces.
#
# R1-R11 map to E32-F03.tests.md. Every markdown heading slicer loads tests/lib/fence.awk
# and calls fence_delim($0) as its first rule (tests/lib/fence.awk is the ONE copy;
# tests/test_change_size.sh R9d enforces it).

set -eu
LC_ALL=C
export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL="$SRC/harness-install.sh"
REPORT_TOOL="$SRC/tools/harness-report.sh"

T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-reporting-rule)"
trap 'rm -rf "$T"' EXIT
# Sandbox Codex's GLOBAL prompts dir so no installer run touches the developer's real ~/.codex.
export CODEX_HOME="$T/codex-home"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── fence-aware markdown section slicer (tests/lib/fence.awk, E99-F131) ──────────────────
FENCE_AWK="$(cat "$SRC/tests/lib/fence.awk")"
_section() { # _section <heading-literal> <file>
  awk -v h="$1" "$FENCE_AWK"'
    fence_delim($0) { if (k) print; next }
    !fence && index($0,h)==1 { k=1; print; next }
    !fence && k && /^## / { exit }
    k { print }
  ' "$2"
}

# _between <file> <start-literal> <end-literal> — the lines from the first line containing
# <start-literal> through the line BEFORE the first line containing <end-literal>. No heading
# reset, so no fence call is needed here (the input is already a fenced section).
_between() {
  awk -v s="$2" -v e="$3" '
    index($0,s)==1 { k=1 }
    k && index($0,e)==1 { exit }
    k
  ' "$1"
}

# _floor <span> <bytes> <what> — a non-empty span plus a length floor, so a truncated or
# blank extraction cannot make the anchors below pass vacuously.
_floor() {
  _f_str="$1"; _f_n="$2"; _f_what="$3"
  [ -n "$_f_str" ] \
    || fail "$_f_what: the extracted span is EMPTY — the anchor is stale, so its assertions prove nothing"
  [ "${#_f_str}" -ge "$_f_n" ] \
    || fail "$_f_what: the extracted span is only ${#_f_str} bytes (floor $_f_n) — truncated, so the assertions below measure a prefix"
}

# _fold <file> — newlines folded to single spaces, so a two-token anchor can span a wrapped line.
_fold() { tr '\n' ' ' < "$1" | tr -s ' '; }

# ── the AGENTS.md rule section, extracted once ───────────────────────────────────────────
_RULE="$T/agents-rule.txt"
_section '## Reporting harness defects' "$SRC/AGENTS.md" > "$_RULE"
_floor "$(cat "$_RULE")" 200 "R1-R4: the AGENTS.md '## Reporting harness defects' section"

_triggers_span() { _between "$_RULE" 'Report exactly these four' 'A failure of the project'; }
_nontriggers_span() { _between "$_RULE" 'A failure of the project' '**When.**'; }
_when_span() { _between "$_RULE" '**When.**' '**Who.**'; }
_who_span() { _between "$_RULE" '**Who.**' 'ZZZ-never-matches-a-line'; }

# ── R1 ────────────────────────────────────────────────────────────────────────────────────
test_rule_triggers() {
  _span="$(_triggers_span)"
  _floor "$_span" 150 "R1: the trigger-list span"
  _t="$(printf '%s\n' "$_span" | tr '\n' ' ' | tr -s ' ')"
  for _tok in harness-malfunction contradictory-instruction workaround missing-capability; do
    printf '%s' "$_t" | grep -qF -- "$_tok" \
      || fail "R1: the trigger list does not name the F02 token '$_tok'"
  done
  printf '%s' "$_t" | grep -qF 'the only reportable conditions' \
    || fail "R1: the rule does not state these four are 'the only reportable conditions'"
  # One-clause semantic gloss per token (the tests.md fixture scenario per trigger).
  printf '%s' "$_t" | grep -qE 'harness-malfunction.{0,40}harness script' \
    || fail "R1: harness-malfunction has no one-clause gloss naming a harness script"
  printf '%s' "$_t" | grep -qE 'contradictory-instruction.{0,40}conflict' \
    || fail "R1: contradictory-instruction has no one-clause gloss naming a conflict"
  printf '%s' "$_t" | grep -qE 'workaround.{0,60}documented workflow' \
    || fail "R1: workaround has no one-clause gloss naming the documented workflow"
  printf '%s' "$_t" | grep -qE 'missing-capability.{0,60}no path' \
    || fail "R1: missing-capability has no one-clause gloss naming 'no path'"
  pass "R1 the rule names the four trigger tokens verbatim, glosses each, and calls them the only reportable conditions (R1) [test_rule_triggers]"
}

# ── R2 ────────────────────────────────────────────────────────────────────────────────────
test_rule_nontriggers() {
  _span="$(_nontriggers_span)"
  _floor "$_span" 120 "R2: the non-trigger span"
  _nt="$(printf '%s\n' "$_span" | tr '\n' ' ' | tr -s ' ')"
  printf '%s' "$_nt" | grep -qF "project's own code" \
    || fail "R2: the non-trigger span does not name the project's own code/tests"
  printf '%s' "$_nt" | grep -qF 'transient network or auth' \
    || fail "R2: the non-trigger span does not name a transient network/auth error"
  printf '%s' "$_nt" | grep -qF 'correctly caught' \
    || fail "R2: the non-trigger span does not name an agent mistake the harness correctly caught"
  printf '%s' "$_nt" | grep -qiE 'none of them produces a report|no report' \
    || fail "R2: the rule does not state that none of the non-triggers produces a report"
  # Positive controls on the SHAPE: the predicate is not dead (the file itself carries the
  # phrases, and each 'grep -qF' above found one), so the disjointness negatives below are
  # not vacuous.
  grep -qF "project's own code" "$SRC/AGENTS.md" \
    || fail "R2 control: 'project's own code' is absent from AGENTS.md, so the negative below is dead"
  grep -qF 'transient network or auth' "$SRC/AGENTS.md" \
    || fail "R2 control: the transient network/auth phrase is absent from AGENTS.md"
  grep -qF 'correctly caught' "$SRC/AGENTS.md" \
    || fail "R2 control: the 'correctly caught' phrase is absent from AGENTS.md"
  # Disjointness: a non-trigger phrase must not satisfy the R1 trigger span, and a trigger
  # token must not satisfy the R2 span (a rule that collapses the two lists reds here).
  if printf '%s' "$(_triggers_span)" | grep -qF "project's own code"; then
    fail "R2: a non-trigger phrase leaked into the R1 trigger span — the two lists are not disjoint"
  fi
  if printf '%s' "$(_nontriggers_span)" | grep -qF 'harness-malfunction'; then
    fail "R2: a trigger token leaked into the R2 non-trigger span — the two lists are not disjoint"
  fi
  pass "R2 the rule names the three non-trigger categories and states no report (R2) [test_rule_nontriggers]"
}

# ── R3 ────────────────────────────────────────────────────────────────────────────────────
test_rule_filing_moments() {
  _span="$(_when_span)"
  _floor "$_span" 60 "R3: the filing-moment span"
  _w="$(printf '%s\n' "$_span" | tr '\n' ' ' | tr -s ' ')"
  printf '%s' "$_w" | grep -qF 'task ends' \
    || fail "R3: the rule does not name the end-of-task filing moment"
  printf '%s' "$_w" | grep -qF 'stops early' \
    || fail "R3: the rule does not name the early-stop filing moment"
  printf '%s' "$_w" | grep -qF 'aborted, parked, or failed' \
    || fail "R3: the early stop is not scoped to aborted/parked/failed"
  printf '%s' "$_w" | grep -qiE 'never[^.]{0,30}mid-flow' \
    || fail "R3: the rule has no 'never ... mid-flow' polarity anchor"
  pass "R3 the rule states end-of-task and early-stop (aborted/parked/failed) filing, never mid-flow (R3) [test_rule_filing_moments]"
}

# ── R4 ────────────────────────────────────────────────────────────────────────────────────
test_rule_filer_and_notes() {
  _span="$(_who_span)"
  _floor "$_span" 200 "R4: the filer/notes span"
  _who="$(printf '%s\n' "$_span" | tr '\n' ' ' | tr -s ' ')"
  printf '%s' "$_who" | grep -qF 'session-owning top-level role' \
    || fail "R4: the rule does not name the session-owning top-level role as the filer"
  for _r in Orchestrator Fixer Inception Planner Driller; do
    printf '%s' "$_who" | grep -qF "$_r" || fail "R4: the filer clause does not name $_r"
  done
  printf '%s' "$_who" | grep -qF '/sdd-report' \
    || fail "R4: the filer clause does not name /sdd-report"
  printf '%s' "$_who" | grep -qF 'progress/feedback/notes.md' \
    || fail "R4: the sub-agent note path progress/feedback/notes.md is not named"
  # The ledger path must resolve to the SAME place the installed /sdd-report reads
  # (`.harness/progress/feedback/notes.md`), not the project root. Anchor the harness-root
  # clause to the concrete installed path in one bounded match, not two independent greps.
  printf '%s' "$_who" | grep -qE 'harness-root-relative.{0,120}\.harness/progress/feedback/notes\.md' \
    || fail "R4: the sub-agent note path is not resolved against the harness root (.harness/progress/feedback/notes.md in an installed target)"
  for _field in 'symptom:' 'command:' 'phase:'; do
    printf '%s' "$_who" | grep -qF "$_field" \
      || fail "R4: the note-entry format does not name '$_field'"
  done
  # The ledger directory does not exist in a pristine checkout or fresh target, so a bare
  # append would die with "Directory nonexistent" and the owning role would never see the
  # note. The rule must tell the sub-agent to create it first.
  printf '%s' "$_who" | grep -qF 'mkdir -p' \
    || fail "R4: the sub-agent note clause does not require mkdir -p before appending"
  printf '%s' "$_who" | grep -qiE 'never[^.]{0,40}invoke the reporter' \
    || fail "R4: the sub-agent prohibition ('never invoke the reporter') is missing"
  for _r in Architect Builder Reviewer Scout Doc-critic pr-fixer; do
    printf '%s' "$_who" | grep -qF "$_r" || fail "R4: the sub-agent list does not name $_r"
  done
  pass "R4 only the session-owning top-level role invokes the reporter; sub-agents append notes and never invoke it (R4) [test_rule_filer_and_notes]"
}

# ── R5 ────────────────────────────────────────────────────────────────────────────────────
TOP_ROLES="orchestrator fixer driller planner inception"
SUB_ROLES="architect builder reviewer scout doc-critic pr-fixer"

test_role_prompts_carry_rule() {
  for _r in $TOP_ROLES; do
    _f="$SRC/agents/$_r.md"
    [ -f "$_f" ] || fail "R5: agents/$_r.md is missing"
    _s="$(_section '## Reporting harness defects' "$_f")"
    _floor "$_s" 80 "R5: agents/$_r.md reporting section"
    _sf="$(printf '%s\n' "$_s" | tr '\n' ' ' | tr -s ' ')"
    printf '%s' "$_sf" | grep -qF '/sdd-report' \
      || fail "R5: agents/$_r.md (session-owning) does not carry the /sdd-report filing duty"
    printf '%s' "$_sf" | grep -qiE 'end of task|end-of-task' \
      || fail "R5: agents/$_r.md does not name the end-of-task filing moment"
    printf '%s' "$_sf" | grep -qi 'early stop' \
      || fail "R5: agents/$_r.md does not name the early-stop filing moment"
    printf '%s' "$_sf" | grep -qF 'HARNESS_FEEDBACK_SESSION_ID' \
      || fail "R5: agents/$_r.md does not carry the once-per-session token duty"
    # The note ledger the sub-agents write is harness-root-relative; the session owner
    # must read it where the installed /sdd-report does (`.harness/...`), not the root.
    printf '%s' "$_sf" | grep -qE 'harness-root-relative.{0,120}\.harness/progress/feedback/notes\.md' \
      || fail "R5: agents/$_r.md does not resolve the note ledger against the harness root (.harness/progress/feedback/notes.md in an installed target)"
  done
  for _r in $SUB_ROLES; do
    _f="$SRC/agents/$_r.md"
    [ -f "$_f" ] || fail "R5: agents/$_r.md is missing"
    _s="$(_section '## Reporting harness defects' "$_f")"
    _floor "$_s" 60 "R5: agents/$_r.md reporting section"
    _sf="$(printf '%s\n' "$_s" | tr '\n' ' ' | tr -s ' ')"
    printf '%s' "$_sf" | grep -qF 'progress/feedback/notes.md' \
      || fail "R5: agents/$_r.md (sub-agent) does not carry the note path"
    # A sub-agent writing the bare path in an installed target lands at the project root,
    # where the session owner (via /sdd-report) never looks. Anchor the harness-root
    # clause to the concrete installed path in ONE bounded match.
    printf '%s' "$_sf" | grep -qE 'harness-root-relative.{0,120}\.harness/progress/feedback/notes\.md' \
      || fail "R5: agents/$_r.md (sub-agent) does not resolve the note path against the harness root (.harness/progress/feedback/notes.md in an installed target)"
    printf '%s' "$_sf" | grep -qiE 'never[^.]{0,30}invoke the reporter' \
      || fail "R5: agents/$_r.md does not prohibit invoking the reporter"
    for _field in 'symptom:' 'command:' 'phase:'; do
      printf '%s' "$_sf" | grep -qF "$_field" \
        || fail "R5: agents/$_r.md note format does not name '$_field'"
    done
    # A pristine tree has no `progress/feedback/`: each sub-agent prompt must create it.
    printf '%s' "$_sf" | grep -qF 'mkdir -p' \
      || fail "R5: agents/$_r.md does not require mkdir -p before appending the note"
  done
  # builder-heavy delegates to builder.md: it must NOT carry a second copy of the rule.
  if _section '## Reporting harness defects' "$SRC/agents/builder-heavy.md" | grep -q .; then
    fail "R5: agents/builder-heavy.md carries a second copy of the rule — it delegates to builder.md"
  fi
  pass "R5 every session-owning role prompt carries the filing duty; every sub-agent prompt carries the note duty and the prohibition (R5) [test_role_prompts_carry_rule]"
}

# ── R6/R7 shared target install (each front end installed exactly once) ──────────────────
_ensure_target() { # _ensure_target <front-end>
  _et_fe="$1"; _et_tgt="$T/tgt-$_et_fe"
  if [ -f "$_et_tgt/.harness/.harness-version" ]; then printf '%s\n' "$_et_tgt"; return 0; fi
  [ ! -e "$_et_tgt" ] \
    || fail "R6/R7 setup: $_et_tgt already exists — the emitted-surface test must not inherit an artifact"
  mkdir -p "$_et_tgt"
  HARNESS_AGENTS="$_et_fe" CODEX_HOME="$T/codex-home" \
    sh "$INSTALL" --agents="$_et_fe" "$_et_tgt" >"$T/install-$_et_fe.log" 2>&1 \
    || { cat "$T/install-$_et_fe.log" >&2; fail "R6/R7: installer failed for front-end $_et_fe"; }
  printf '%s\n' "$_et_tgt"
}

# ── R6 ────────────────────────────────────────────────────────────────────────────────────
test_frontend_parity() {
  for _fe in claude codex opencode; do
    _tgt="$(_ensure_target "$_fe")"
    [ -f "$_tgt/.harness/AGENTS.md" ] || fail "R6: $_fe target has no .harness/AGENTS.md"
    # The ledger directory must exist in a fresh target: a sub-agent's first note append
    # would otherwise fail with "Directory nonexistent" before the owner can read it.
    [ -d "$_tgt/.harness/progress/feedback" ] \
      || fail "R6: $_fe target did not seed .harness/progress/feedback (E32-F03 note ledger)"
    cmp -s "$SRC/AGENTS.md" "$_tgt/.harness/AGENTS.md" \
      || fail "R6: $_fe's .harness/AGENTS.md is not the source AGENTS.md — the rule must install verbatim"
    _sec="$(_section '## Reporting harness defects' "$_tgt/.harness/AGENTS.md")"
    _floor "$_sec" 200 "R6: $_fe .harness/AGENTS.md rule section"
    printf '%s' "$_sec" | grep -qF 'harness-malfunction' \
      || fail "R6: $_fe .harness/AGENTS.md lacks the trigger token"
    [ -f "$_tgt/.harness/agents/orchestrator.md" ] \
      || fail "R6: $_fe target has no .harness/agents/orchestrator.md"
    if ! _section '## Reporting harness defects' "$_tgt/.harness/agents/orchestrator.md" | grep -qF '/sdd-report'; then
      fail "R6: $_fe .harness/agents/orchestrator.md does not carry the reporting rule"
    fi
    case "$_fe" in
      claude)
        grep -qF '.harness/agents/orchestrator.md' "$_tgt/.claude/agents/orchestrator.md" \
          || fail "R6: the Claude shim does not resolve .harness/agents/orchestrator.md" ;;
      codex)
        grep -qF '.harness/agents/orchestrator.md' "$_tgt/.codex/agents/orchestrator.toml" \
          || fail "R6: the Codex toml does not resolve .harness/agents/orchestrator.md" ;;
      opencode)
        grep -qF '{file:./.harness/agents/orchestrator.md}' "$_tgt/opencode.json" \
          || fail "R6: opencode.json agent.prompt does not resolve .harness/agents/orchestrator.md"
        grep -qF '.harness/AGENTS.md' "$_tgt/opencode.json" \
          || fail "R6: opencode.json instructions does not resolve .harness/AGENTS.md" ;;
    esac
  done
  pass "R6 each selected front end installs the rule into .harness/AGENTS.md + .harness/agents/* and resolves it through its own artifact (R6) [test_frontend_parity]"
}

# ── R7 ────────────────────────────────────────────────────────────────────────────────────
test_report_command_emitted() {
  _inst_cmds="$(sed -n 's/^HARNESS_SDD_CMDS="\(.*\)"$/\1/p' "$INSTALL")"
  [ -n "$_inst_cmds" ] || fail "R7: could not extract HARNESS_SDD_CMDS from harness-install.sh"
  case " $_inst_cmds " in *" sdd-report "*) ;; *) fail "R7: sdd-report is not in HARNESS_SDD_CMDS";; esac

  # Committed source glue, regenerated by --self (never hand-written).
  for _g in .claude/commands/sdd-report.md .opencode/command/sdd-report.md \
            .agents/skills/sdd-report/SKILL.md .agents/skills/sdd-report/agents/openai.yaml; do
    [ -s "$SRC/$_g" ] \
      || fail "R7: committed source glue $_g is missing or empty — run 'sh harness-install.sh --self' and commit it"
  done
  grep -qF ' .claude/commands/sdd-report.md' "$SRC/.claude/.glue-manifest" \
    || fail "R7: .claude/.glue-manifest does not list .claude/commands/sdd-report.md"
  grep -qF ' .agents/skills/sdd-report/SKILL.md' "$SRC/.claude/.glue-manifest" \
    || fail "R7: .claude/.glue-manifest does not list .agents/skills/sdd-report/SKILL.md"

  # Per-front-end emitted surface in a real install (fresh target, no inherited copy).
  _ct="$(_ensure_target claude)"
  [ -s "$_ct/.claude/commands/sdd-report.md" ] || fail "R7: claude /sdd-report was not emitted"
  _xt="$(_ensure_target codex)"
  [ -s "$_xt/.agents/skills/sdd-report/SKILL.md" ] \
    || fail "R7: codex shared sdd-report unit was not emitted"
  grep -qF 'allow_implicit_invocation: false' "$_xt/.agents/skills/sdd-report/agents/openai.yaml" \
    || fail "R7: the codex sdd-report policy companion is missing or wrong"
  _ot="$(_ensure_target opencode)"
  [ -s "$_ot/.opencode/command/sdd-report.md" ] || fail "R7: opencode /sdd-report was not emitted"
  [ -s "$_ot/.agents/skills/sdd-report/SKILL.md" ] \
    || fail "R7: the OpenCode claimant's shared sdd-report unit is missing"

  # --self regenerates the source glue in a PRISTINE copy: delete the artifacts first so a
  # copied fixture cannot satisfy the assertion (progress/lessons.md 2026-09-05).
  _sc="$T/selfcopy"; mkdir -p "$_sc"
  for _e in "$SRC"/* "$SRC"/.claude "$SRC"/.codex "$SRC"/.agents "$SRC"/.escalation-arming; do
    [ -e "$_e" ] || continue
    case "$(basename "$_e")" in .git|node_modules) continue ;; esac
    cp -R "$_e" "$_sc/" 2>/dev/null || true
  done
  rm -f "$_sc/.claude/.glue-manifest" \
        "$_sc/.claude/commands/sdd-report.md" "$_sc/.opencode/command/sdd-report.md"
  rm -rf "$_sc/.agents/skills/sdd-report"
  sh "$_sc/harness-install.sh" --self >"$T/self.log" 2>&1 \
    || { cat "$T/self.log" >&2; fail "R7: --self regeneration in a pristine copy failed"; }
  for _g in .claude/commands/sdd-report.md .opencode/command/sdd-report.md \
            .agents/skills/sdd-report/SKILL.md .agents/skills/sdd-report/agents/openai.yaml; do
    [ -s "$_sc/$_g" ] || fail "R7: --self did not regenerate $_g from the emitter"
  done
  grep -qF ' .claude/commands/sdd-report.md' "$_sc/.claude/.glue-manifest" \
    || fail "R7: --self's .glue-manifest does not list .claude/commands/sdd-report.md"
  pass "R7 /sdd-report is in HARNESS_SDD_CMDS and ships to every selected front end; --self regenerates the glue + manifest (R7) [test_report_command_emitted]"
}

# ── R8 ────────────────────────────────────────────────────────────────────────────────────
# The canonical body lives in the installer's `cat > "$CMDDIR/sdd-report.md"` heredoc; the
# committed glue is its --self rendering, so the emitter is the mutation-shaped surface.
_cmd_body() {
  awk '
    index($0,"cat > \"$CMDDIR/sdd-report.md\"") { k=1; next }
    k && $0=="EOF" { exit }
    k
  ' "$INSTALL"
}

# _step3_span <body-file> — the numbered step-3 (--file contract) span, up to step 4. The
# `--file` rule is read where it is written; extracting the step keeps a `--command` decoy
# elsewhere in the body from satisfying the anchors (agents/builder.md placement rule).
_step3_span() {
  awk '
    index($0,"3. **Pass at least one") { k=1 }
    k && index($0,"4. **Mint") { exit }
    k
  ' "$1"
}

test_report_command_body_contract() {
  _body="$T/sdd-report-body.md"
  _cmd_body > "$_body"
  _floor "$(cat "$_body")" 300 "R8: the canonical sdd-report command body"
  _bf="$(_fold "$_body")"
  # The actual invocation is the fenced shell block; every allow-listed flag must live THERE,
  # not merely somewhere in the prose (a body that names a flag but drops it from the call
  # never passes it).
  _invoc="$(awk '
    /^[[:space:]]*```sh[[:space:]]*$/ { k=1; next }
    k && /^[[:space:]]*```[[:space:]]*$/ { exit }
    k
  ' "$_body")"
  _floor "$_invoc" 120 "R8: the sdd-report invocation block"
  printf '%s' "$_invoc" | grep -qF 'tools/harness-report.sh' \
    || fail "R8: the invocation block does not call tools/harness-report.sh"
  for _flag in --trigger --symptom --file --command --exit-code --role --phase; do
    printf '%s' "$_invoc" | grep -qF -- "$_flag" \
      || fail "R8: the invocation block does not pass the allow-listed field $_flag"
  done
  # --phase is OPTIONAL but CONSTRAINED to F02's `_valid_phase` set: any other nonempty
  # value rejects the whole report to the local fallback. The invocation block must name
  # the set (not a bare placeholder) and say to omit the flag when none applies.
  for _ph in inception architect builder reviewer scout slice-dispatch handoff install; do
    printf '%s' "$_invoc" | grep -qF -- "$_ph" \
      || fail "R8: the invocation block does not name the F02-valid phase '$_ph'"
  done
  printf '%s' "$_invoc" | grep -qF -- 'omit when none applies' \
    || fail "R8: the invocation block does not say to omit --phase when no phase applies"
  if printf '%s' "$_invoc" | grep -qF -- '<phase>'; then
    fail "R8: the invocation block still passes the unconstrained --phase placeholder"
  fi
  printf '%s' "$_bf" | grep -qF 'rejects any other nonempty value' \
    || fail "R8: the body does not state that an out-of-set phase is rejected"
  # --exit-code is OPTIONAL too: a reportable event such as an instruction conflict or a
  # recurring workflow gap has no process exit status, so the invocation must say to omit
  # the flag rather than leave a placeholder for the caller to invent. A placeholder fails
  # F02's _valid_exit_code and silently downgrades the WHOLE report to a local-only
  # rejection. A revert to a bare, mandatory `--exit-code <n>` reds both anchors below.
  printf '%s' "$_invoc" | grep -qF -- 'omit the flag when no process exited' \
    || fail "R8: the invocation block presents --exit-code as mandatory; it must say to omit the flag when no process exited"
  if printf '%s' "$_invoc" | grep -qE -- '--exit-code[[:space:]]*<n>'; then
    fail "R8: the invocation block still presents the --exit-code <n> placeholder as the value to pass"
  fi
  printf '%s' "$_bf" | grep -qE 'exit-code.{0,40}is optional' \
    || fail "R8: the body does not state the --exit-code flag is optional"
  printf '%s' "$_bf" | grep -qE 'placeholder.{0,120}downgrades the whole report' \
    || fail "R8: the body does not state that a placeholder --exit-code downgrades the whole report to the local fallback"
  # --command is OPTIONAL too (mirroring --exit-code/--phase): a doc-conflict /
  # instruction-conflict / workflow-gap report has no failed harness command, and a
  # placeholder fails F02's `_valid_command` and silently downgrades the WHOLE report.
  # The invocation must tell the caller to omit the flag rather than present it as mandatory.
  printf '%s' "$_invoc" | grep -qF -- 'omit when no command applies' \
    || fail "R8: the invocation block presents --command as mandatory; it must say to omit the flag when none applies"
  printf '%s' "$_bf" | grep -qE 'command.{0,30}is optional' \
    || fail "R8: the body does not state the --command flag is optional"
  printf '%s' "$_bf" | grep -qE 'is optional.{0,200}no command applies.{0,120}doc-conflict' \
    || fail "R8: the optional --command clause does not name a no-command report case (doc-conflict)"
  printf '%s' "$_invoc" | grep -qF -- '--session-id' \
    || fail "R8: the invocation block does not pass --session-id"
  printf '%s' "$_invoc" | grep -qF 'HARNESS_FEEDBACK_SESSION_ID' \
    || fail "R8: the invocation block does not pass HARNESS_FEEDBACK_SESSION_ID"
  printf '%s' "$_invoc" | grep -qF 'date -u +%Y%m%dT%H%M%SZ' \
    || fail "R8: the invocation block names no grammar-safe date fallback for the session token"
  printf '%s' "$_invoc" | grep -qF -- '--notes-file' \
    || fail "R8: the invocation block does not pass --notes-file"
  # At least one harness-owned --file (F02 rejects otherwise).
  printf '%s' "$_bf" | grep -qiE 'at least one harness-owned' \
    || fail "R8: the body does not require at least one harness-owned --file"
  printf '%s' "$_bf" | grep -qF 'init.sh' \
    || fail "R8: the body does not pass a harness-owned --file (init.sh for the init path)"
  # The --file must be a CONCRETE tracked harness-body path, never an sdd-* command basename:
  # F02's `_prepare_listing` accepts only real harness-body paths, so `--file sdd-next` is
  # dropped and a sole-file report falls to the local-only copy (finding 4110441412).
  # Reverting step 3 to the old "or the named --command" suggestion reds all three anchors.
  _step3="$(_step3_span "$_body")"
  _floor "$_step3" 200 "R8: the sdd-report step-3 --file span"
  _s3="$(printf '%s\n' "$_step3" | tr '\n' ' ' | tr -s ' ')"
  printf '%s' "$_s3" | grep -qF 'harness-install.sh' \
    || fail "R8: step 3 names no concrete harness-owned body path (e.g. harness-install.sh) to pass as --file"
  printf '%s' "$_s3" | grep -qiE 'never[^.]{0,60}sdd-' \
    || fail "R8: step 3 does not forbid passing an sdd-* command basename as --file"
  if printf '%s' "$_s3" | grep -qF 'or the named `--command`'; then
    fail "R8: step 3 still suggests the named --command as --file — F02 drops that basename and the report falls local-only"
  fi
  _tok="$(date -u +%Y%m%dT%H%M%SZ)"
  printf '%s' "$_tok" | grep -qE '^[A-Za-z0-9._-]{1,64}$' \
    || fail "R8: the body's fallback expression produces a token F02 rejects (got '$_tok')"
  # Free-form text is local-only. Pin EACH negating clause by its own literal wording: a
  # bounded `never[^.]{0,40}sent to` anchor is maskable by the earlier "is never an upstream
  # field" (the negator need not be the one governing "sent to"). The clause itself must carry
  # the negation, so flipping "is never sent to" → "is sometimes sent to" reds.
  printf '%s' "$_bf" | grep -qi 'local-only' \
    || fail "R8: the body does not state the free-form summary is local-only"
  printf '%s' "$_bf" | grep -qF 'is never an upstream field' \
    || fail "R8: the body does not state free-form text is never an upstream field"
  printf '%s' "$_bf" | grep -qF 'is never sent to' \
    || fail "R8: the free-form-off-upstream polarity is not pinned to the negating clause itself (a different 'never' earlier in the sentence must not satisfy it)"
  # Symptom vocabulary: init.sh failure maps to init-failure.
  printf '%s' "$_bf" | grep -qiE 'init\.sh. failure maps to .init-failure' \
    || fail "R8: the body does not map an init.sh failure to init-failure"
  # None of F02's mechanisms are re-implemented.
  printf '%s' "$_bf" | grep -qiE 'never re-implement' \
    || fail "R8: the body does not forbid re-implementing F02's mechanisms"
  pass "R8 the command body calls the reporter with the allow-listed flags, requires a harness-owned --file, supplies a grammar-safe session token, keeps free-form local-only, and maps init.sh to init-failure (R8) [test_report_command_body_contract]"
}

# ── R8 (session token) — the token is minted ONCE per session and reused ──────────────────
# The command must not re-evaluate `date` on every call: reports more than a second apart
# would then carry different session ids, reset `.session-count` and bypass `max_per_session`.
# Extract the emitter's marked minting span, RUN it (the test harness appends the print that
# reports the variable the span fills), and pin: deterministic from the LATEST session-start
# marker, stable across calls, the exported value preferred, and the no-marker fallback
# grammar-safe.
_session_snippet() {
  _cmd_body | awk '
    /--- harness-session-id:begin ---/ { k=1; next }
    /--- harness-session-id:end ---/   { k=0 }
    k
  ' | sed 's/^   //'
  printf '%s\n' 'printf "%s" "$_hf_session"'
}

test_session_token_stable() {
  _snip="$T/session-id.sh"
  _session_snippet > "$_snip"
  _floor "$(cat "$_snip")" 120 "R8: the session-token minting span"
  grep -qF 'HARNESS_FEEDBACK_SESSION_ID' "$_snip" \
    || fail "R8: the token minting span does not read HARNESS_FEEDBACK_SESSION_ID"
  grep -qF 'session-start' "$_snip" \
    || fail "R8: the token minting span does not derive from the session-start marker"
  grep -qF 'date -u +%Y%m%dT%H%M%SZ' "$_snip" \
    || fail "R8: the token minting span names no grammar-safe fallback"

  # Latest marker wins, colons dropped, hyphens kept (spec: 2026-06-06T09:00:00Z →
  # 2026-06-06T090000Z). The middle record proves the extractor keys on `session-start`.
  _sfx="$T/session-id-fixture"; mkdir -p "$_sfx/.harness"
  {
    printf '%s\n' '{"schema_version":1,"type":"session-start","started_at":"2026-01-01T00:00:00Z"}'
    printf '%s\n' '{"schema_version":1,"type":"phase","phase":"builder"}'
    printf '%s\n' '{"schema_version":1,"type":"session-start","started_at":"2026-06-06T09:00:00Z"}'
  } > "$_sfx/.harness/telemetry.jsonl"

  _t1="$(cd "$_sfx" && HARNESS_FEEDBACK_SESSION_ID= sh "$_snip")"
  sleep 1
  _t2="$(cd "$_sfx" && HARNESS_FEEDBACK_SESSION_ID= sh "$_snip")"
  [ "$_t1" = "$_t2" ] \
    || fail "R8: the session token is not stable across calls ('$_t1' vs '$_t2') — F02's per-session cap ledger would reset"
  [ "$_t1" = "2026-06-06T090000Z" ] \
    || fail "R8: the session token is not the latest marker-derived token (got '$_t1')"
  printf '%s' "$_t1" | grep -qE '^[A-Za-z0-9._-]{1,64}$' \
    || fail "R8: the derived session token fails F02's grammar (got '$_t1')"

  # An exported token is preferred (the session owner's once-per-session mint wins).
  _t3="$(cd "$_sfx" && HARNESS_FEEDBACK_SESSION_ID=exported-session sh "$_snip")"
  [ "$_t3" = "exported-session" ] \
    || fail "R8: an exported HARNESS_FEEDBACK_SESSION_ID is not preferred (got '$_t3')"

  # No marker (the init.sh hard-stop path): the fallback is still grammar-safe.
  _nofx="$T/session-id-nomarker"; mkdir -p "$_nofx"
  _t4="$(cd "$_nofx" && HARNESS_FEEDBACK_SESSION_ID= sh "$_snip")"
  printf '%s' "$_t4" | grep -qE '^[A-Za-z0-9._-]{1,64}$' \
    || fail "R8: the no-marker fallback produces a token F02 rejects (got '$_t4')"

  # No marker + no export (telemetry disabled, or its best-effort write failed): the `date`
  # fallback must be minted ONCE and persisted, so every later call in the session reuses one
  # token. Recomputing `date` per call hands reports >1s apart different ids, resetting F02's
  # `.session-count` ledger and bypassing `max_per_session` (finding 4110441411).
  _pfx="$T/session-id-fallback"; mkdir -p "$_pfx/.harness"
  _p1="$(cd "$_pfx" && HARNESS_FEEDBACK_SESSION_ID= sh "$_snip")"
  sleep 1
  _p2="$(cd "$_pfx" && HARNESS_FEEDBACK_SESSION_ID= sh "$_snip")"
  [ "$_p1" = "$_p2" ] \
    || fail "R8: the no-marker date fallback is recomputed per call ('$_p1' vs '$_p2') — reports >1s apart get different ids and bypass F02's max_per_session"
  [ -f "$_pfx/.harness/progress/feedback/.session-id" ] \
    || fail "R8: the no-marker fallback was not persisted under the harness dir, so a later call cannot reuse it"
  [ "$_p1" = "$(cat "$_pfx/.harness/progress/feedback/.session-id")" ] \
    || fail "R8: the persisted fallback token does not match the token the block returned"
  printf '%s' "$_p1" | grep -qE '^[A-Za-z0-9._-]{1,64}$' \
    || fail "R8: the persisted fallback produces a token F02 rejects (got '$_p1')"

  # A corrupt or foreign persisted `.session-id` must NOT be returned verbatim. F02's
  # `_valid_session` rejects an out-of-grammar `--session-id` and drops the WHOLE report to a
  # local copy, so one bad line in `.session-id` would silently degrade EVERY later report in
  # the repo. The read-back re-validates against the grammar and re-mints (PR #227 round 5).
  _badfx="$T/session-id-corrupt"; mkdir -p "$_badfx/.harness/progress/feedback"
  for _bad in 'has space' 'has:colon' 'has/slash' "$(printf 'line1\nline2')"; do
    printf '%s\n' "$_bad" > "$_badfx/.harness/progress/feedback/.session-id"
    _tbad="$(cd "$_badfx" && HARNESS_FEEDBACK_SESSION_ID= sh "$_snip")"
    [ "$_tbad" != "$_bad" ] \
      || fail "R8: the corrupt persisted session id was returned verbatim — F02 rejects it and every later report degrades to a local copy"
    printf '%s' "$_tbad" | grep -qE '^[A-Za-z0-9._-]{1,64}$' \
      || fail "R8: a corrupt persisted session id was not re-minted to a grammar-valid token (got '$_tbad')"
    _persisted="$(cat "$_badfx/.harness/progress/feedback/.session-id")"
    printf '%s' "$_persisted" | grep -qE '^[A-Za-z0-9._-]{1,64}$' \
      || fail "R8: the corrupt persisted session id was not overwritten with the re-minted token, so a later call would reject it again"
  done
  # Over the 64-char cap: F02's grammar bounds length, so an over-long value is ignored too.
  _long65="$(awk 'BEGIN{for(i=0;i<65;i++)printf "a"}')"
  printf '%s\n' "$_long65" > "$_badfx/.harness/progress/feedback/.session-id"
  _tlong="$(cd "$_badfx" && HARNESS_FEEDBACK_SESSION_ID= sh "$_snip")"
  [ "$_tlong" != "$_long65" ] \
    || fail "R8: a 65-char persisted session id was returned verbatim — F02's ^[A-Za-z0-9._-]{1,64}$ caps length"
  printf '%s' "$_tlong" | grep -qE '^[A-Za-z0-9._-]{1,64}$' \
    || fail "R8: an over-length persisted session id was not re-minted to a grammar-valid token"
  pass "R8 a corrupt or over-length persisted session id is re-validated and re-minted on read-back, never returned verbatim (R8) [test_session_token_stable]"

  # A CONFIGURED telemetry.log (RELATIVE override) must be resolved the same way the
  # writer/reader resolve it: <harness dir>/<value>. A hard-coded default path misses the
  # marker, falls back to `date`, and re-mints the token on every call more than a second
  # apart — resetting F02's `.session-count` and bypassing `max_per_session`. A decoy at
  # the DEFAULT path with a DIFFERENT (older) marker makes the two routes distinguishable:
  # a default-path reader returns the decoy, a config-aware reader returns the custom one.
  _cfx="$T/session-id-custom"; mkdir -p "$_cfx/.harness/custom"
  printf '%s\n' 'telemetry:' '  log: custom/telemetry.jsonl' \
    > "$_cfx/.harness/harness.config.yaml"
  printf '%s\n' '{"schema_version":1,"type":"session-start","started_at":"2026-07-07T07:07:07Z"}' \
    > "$_cfx/.harness/custom/telemetry.jsonl"
  printf '%s\n' '{"schema_version":1,"type":"session-start","started_at":"2026-01-01T00:00:00Z"}' \
    > "$_cfx/.harness/telemetry.jsonl"
  _c1="$(cd "$_cfx" && HARNESS_FEEDBACK_SESSION_ID= sh "$_snip")"
  sleep 1
  _c2="$(cd "$_cfx" && HARNESS_FEEDBACK_SESSION_ID= sh "$_snip")"
  [ "$_c1" = "$_c2" ] \
    || fail "R8: the session token is not stable across calls under a configured telemetry.log ('$_c1' vs '$_c2') — F02's per-session cap ledger would reset"
  [ "$_c1" = "2026-07-07T070707Z" ] \
    || fail "R8: the configured relative telemetry.log is ignored (got '$_c1'); the token must come from the override, not the default path"

  # An ABSOLUTE override is used verbatim (never rejoined under the harness dir).
  _afx="$T/session-id-absolute"; _alog="$T/session-id-absolute-log/t.jsonl"
  mkdir -p "$_afx/.harness" "$T/session-id-absolute-log"
  printf 'telemetry:\n  log: %s\n' "$_alog" > "$_afx/.harness/harness.config.yaml"
  printf '%s\n' '{"schema_version":1,"type":"session-start","started_at":"2026-08-08T08:08:08Z"}' \
    > "$_alog"
  _a1="$(cd "$_afx" && HARNESS_FEEDBACK_SESSION_ID= sh "$_snip")"
  [ "$_a1" = "2026-08-08T080808Z" ] \
    || fail "R8: an absolute telemetry.log override is not honored (got '$_a1')"
  pass "R8 the session token is minted once and reused — latest session-start derived from the configured telemetry.log, exported value preferred, grammar-safe fallback (R8) [test_session_token_stable]"
}

# ── R9 ────────────────────────────────────────────────────────────────────────────────────
test_init_hard_stop_exception() {
  _span="$(_section '## Start every session' "$SRC/AGENTS.md")"
  _floor "$_span" 200 "R9: the '## Start every session' section"
  _sf="$(printf '%s\n' "$_span" | tr '\n' ' ' | tr -s ' ')"
  printf '%s' "$_sf" | grep -qi 'non-zero' \
    || fail "R9: the exception is not scoped to a non-zero init.sh exit"
  printf '%s' "$_sf" | grep -qi 'harness malfunction' \
    || fail "R9: the exception is not scoped to a harness malfunction"
  printf '%s' "$_sf" | grep -qF 'harness-malfunction' \
    || fail "R9: the exception does not name the harness-malfunction trigger"
  printf '%s' "$_sf" | grep -qiE 'reporter.{0,30}once' \
    || fail "R9: the exception does not limit the reporter call to exactly one"
  printf '%s' "$_sf" | grep -qi 'no repair' \
    || fail "R9: the exception does not state the call makes no repair"
  printf '%s' "$_sf" | grep -qi 'no board write' \
    || fail "R9: the exception does not state the call makes no board write"
  printf '%s' "$_sf" | grep -qi 'does not continue' \
    || fail "R9: the exception does not state the session does not continue"
  printf '%s' "$_sf" | grep -qiE 'never.{0,20}a way around the gate' \
    || fail "R9: the exception does not state reporting is never a way around the gate"
  pass "R9 AGENTS.md's init.sh STOP rule carries exactly one narrow reporting exception: one call, no repair, no board write, no continuation, never a way around the gate (R9) [test_init_hard_stop_exception]"
}

# ── R10 ───────────────────────────────────────────────────────────────────────────────────
test_tool_command_membership() {
  _tool_set="$(grep '^_shipped_sdd_cmds=' "$REPORT_TOOL" | sed 's/^[^"]*"//; s/"[^"]*$//')"
  [ -n "$_tool_set" ] || fail "R10: could not extract _shipped_sdd_cmds from tools/harness-report.sh"
  case " $_tool_set " in
    *" sdd-report "*) ;;
    *) fail "R10: sdd-report is not a member of the tool's _shipped_sdd_cmds" ;;
  esac
  _inst_set="$(sed -n 's/^HARNESS_SDD_CMDS="\(.*\)"$/\1/p' "$INSTALL")"
  [ -n "$_inst_set" ] || fail "R10: could not extract HARNESS_SDD_CMDS from harness-install.sh"
  case " $_inst_set " in
    *" sdd-report "*) ;;
    *) fail "R10: sdd-report is not a member of HARNESS_SDD_CMDS" ;;
  esac
  pass "R10 sdd-report is a member of both the tool's _shipped_sdd_cmds and the installer's HARNESS_SDD_CMDS (R10) [test_tool_command_membership]"
}

# ── R11 ───────────────────────────────────────────────────────────────────────────────────
test_release_sweep() {
  [ "$(cat "$SRC/VERSION")" = "0.87.0" ] \
    || fail "R11: VERSION is not 0.87.0 (got $(cat "$SRC/VERSION"))"

  _new="$T/cl-new.txt"
  _section '## [0.87.0]' "$SRC/CHANGELOG.md" > "$_new"
  [ -s "$_new" ] || fail "R11: no ## [0.87.0] CHANGELOG section"
  grep -qiE 'reporting (is )?live|reporting goes live' "$_new" \
    || fail "R11: the [0.87.0] CHANGELOG section does not name reporting going live"
  grep -qF 'E32-F03' "$_new" || fail "R11: the [0.87.0] CHANGELOG section does not name E32-F03"
  # Historical anchors and the deliberate non-semver fixture stay byte-intact.
  grep -qF '## [0.86.0]' "$SRC/CHANGELOG.md" || fail "R11: the historical ## [0.86.0] anchor is gone"
  grep -qF '## [0.85.0]' "$SRC/CHANGELOG.md" || fail "R11: the historical ## [0.85.0] anchor is gone"
  grep -qF '0.86.0-rc1' "$SRC/tests/test_feedback_report.sh" \
    || fail "R11: the deliberate 0.86.0-rc1 non-semver fixture is gone"

  _is="$T/install-feedback.txt"
  _section '## Harness feedback' "$SRC/docs/INSTALL.md" > "$_is"
  [ -s "$_is" ] || fail "R11: no '## Harness feedback' section in docs/INSTALL.md"
  if grep -qF 'Reporting stays inert' "$_is"; then
    fail "R11: docs/INSTALL.md still says reporting is inert"
  fi
  grep -qF 'E32-F02' "$_is" || fail "R11: INSTALL.md's feedback section dropped E32-F02"
  grep -qF 'E32-F03' "$_is" || fail "R11: INSTALL.md's feedback section dropped E32-F03"

  _rd="$T/readme-cli.txt"
  _section '## Supported CLIs' "$SRC/README.md" > "$_rd"
  [ -s "$_rd" ] || fail "R11: no '## Supported CLIs' section in README.md"
  grep -qF '/sdd-report' "$_rd" \
    || fail "R11: README's Supported-CLIs table does not name /sdd-report"
  grep -qF '$sdd-report' "$SRC/README.md" \
    || fail "R11: README's \$sdd-* sentence does not name \$sdd-report"

  # The stale-literal predicate is pinned to the exact comparison / pass-message SHAPE, not a
  # bare '0.86.0' grep. Positive control: the predicate must match a planted probe, or the
  # sweep below would be a dead predicate that greens on any input.
  _probe="$T/stale-probe.txt"
  printf '%s\n' '[ "$(cat "$SRC/VERSION")" = "0.86.0" ]' > "$_probe"
  printf '%s\n' "assert (src/'VERSION').read_text().strip()=='0.86.0'" >> "$_probe"
  printf '%s\n' 'VERSION is 0.86.0 and the changelog' >> "$_probe"
  grep -qE '= "0\.86\.0"|==.0\.86\.0.|VERSION is 0\.86\.0' "$_probe" \
    || fail "R11 control: the stale-literal predicate cannot match its own probe shape, so the sweep is a dead predicate"
  for _f in test_codex_native.sh test_feedback_config.sh test_feedback_report.sh; do
    if grep -qE '= "0\.86\.0"|==.0\.86\.0.|VERSION is (not )?0\.86\.0' "$SRC/tests/$_f"; then
      fail "R11: tests/$_f still pins the CURRENT VERSION 0.86.0 — sync the literal to 0.87.0 (the historical ## [0.85.0]/[0.86.0] anchors and the -rc1 fixture stay)"
    fi
  done
  pass "R11 VERSION=0.87.0, the CHANGELOG [0.87.0] entry names reporting live, INSTALL.md is no longer inert, README names /sdd-report, and the coupled literals are swept (R11) [test_release_sweep]"
}

# ── non-functional ────────────────────────────────────────────────────────────────────────
test_suite_is_executable() {
  [ -x "$SRC/tests/test_reporting_rule.sh" ] \
    || fail "non-functional: tests/test_reporting_rule.sh is not executable"
  pass "tests/test_reporting_rule.sh is executable (non-functional) [test_suite_is_executable]"
}

# ── run ───────────────────────────────────────────────────────────────────────────────────
test_rule_triggers
test_rule_nontriggers
test_rule_filing_moments
test_rule_filer_and_notes
test_role_prompts_carry_rule
test_frontend_parity
test_report_command_emitted
test_report_command_body_contract
test_session_token_stable
test_init_hard_stop_exception
test_tool_command_membership
test_release_sweep
test_suite_is_executable

echo "all reporting-rule tests passed"
