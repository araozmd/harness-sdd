#!/bin/sh
# test_stage_nfrs.sh — E36-F03: product stage and deferred-decision ADRs with triggers;
# sticky vs bolt-on NFRs (ADR-0009 decisions 1-3).
#
# Pins SHAPES and PROSE, not a lint (enforcement is E36-F04). Every prose contract is a
# WHOLE-FILE grep on the INSTALLED copy under $I — the installed body is a cp -R of the
# source, so the installed grep proves the shipped content. No heading slicer is used, so
# nothing here is fence-blind. R3 reads this repo's own specs/product.md (project-owned,
# never installed). R12 reads VERSION at runtime and freezes no literal.
#
# Co-occurrence anchors fold newlines (`tr '\n' ' '`) and bound the gap with `[^.]{0,N}`
# so the two tokens sit in one sentence. They prove co-occurrence, not polarity (see
# agents/builder.md) — read the diff for meaning.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-sn)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# One fresh install; sandboxed CODEX_HOME/HOME so nothing global is written.
mkdir -p "$T/tgt" "$T/ch" "$T/home"
CODEX_HOME="$T/ch" HOME="$T/home" sh "$ROOT/harness-install.sh" --agents=claude "$T/tgt" \
  >"$T/install.out" 2>"$T/install.err" \
  || fail "setup: fresh install exited non-zero: $(cat "$T/install.err")"
I="$T/tgt/.harness"

# fold <file> — the file on one line (newlines to spaces, runs of spaces squeezed, so a
# wrapped indented line reads as one sentence) for sentence-bounded anchors.
fold() { tr '\n' ' ' < "$1" | tr -s ' '; }

# frontmatter_stage_production <file> — 0 iff line 1 is `---` and the bare line
# `stage: production` sits before the block's closing `---` (the `$` anchor is the grammar:
# an inline comment on the value line fails it).
frontmatter_stage_production() {
  awk 'NR==1&&$0!="---"{exit 1} NR>1&&/^---$/{exit} /^stage: production$/{f=1} END{exit !f}' "$1"
}

# R3 — this repository declares its own stage.
R3_repo_product_stage() {
  frontmatter_stage_production "$ROOT/specs/product.md" \
    || fail "R3: specs/product.md does not open with a --- frontmatter block holding the bare line 'stage: production'"
  pass "this repo's specs/product.md declares 'stage: production' in its frontmatter (R3) [R3_repo_product_stage]"
}
R3_repo_product_stage

# lineno <file> <fixed-string> — first line number whose line STARTS with the string (0 if none).
lineno() {
  awk -v s="$2" 'index($0,s)==1{print NR; f=1; exit} END{if(!f) print 0}' "$1"
}

# R4 — the ADR template carries `deferred` and the mandatory-when-deferred Trigger: line.
R4_adr_template_deferred_trigger() {
  _a="$I/specs/_templates/adr.md"
  [ -f "$_a" ] || fail "R4: installed specs/_templates/adr.md missing"
  grep -qF -- '- **Status:** <proposed | accepted | deferred>' "$_a" \
    || fail "R4: ADR template Status line does not list 'proposed | accepted | deferred'"
  grep -qE '^- \*\*Trigger:\*\* ' "$_a" \
    || fail "R4: ADR template has no '- **Trigger:** ' header line"
  fold "$_a" | grep -qE 'Trigger:\*\*[^.]{0,120}mandatory when Status is deferred; omit otherwise' \
    || fail "R4: the Trigger: header line does not state it is mandatory when Status is deferred and omitted otherwise"
  _d="$(lineno "$_a" '- **Date:**')"; _t="$(lineno "$_a" '- **Trigger:**')"; _c="$(lineno "$_a" '## Context')"
  [ "$_d" -gt 0 ] && [ "$_t" -eq $((_d + 1)) ] && [ "$_c" -gt "$_t" ] \
    || fail "R4: the Trigger: line is not the header line directly after Date: (date=$_d trigger=$_t context=$_c)"
  grep -qiE 'one architecture decision per ADR' "$_a" \
    || fail "R4: the ADR template lost its 'One architecture decision per ADR' sentence"
  pass "ADR template lists deferred and carries a mandatory-when-deferred Trigger: header line (R4) [R4_adr_template_deferred_trigger]"
}
R4_adr_template_deferred_trigger

# R5 — the ADR template names the sticky list (never deferred) and the bolt-on examples.
R5_adr_template_sticky_boltons() {
  _a="$I/specs/_templates/adr.md"
  for _k in 'tenant isolation' 'auth boundary' 'secrets out of the repo' 'validation at the system edge'; do
    grep -qiF "$_k" "$_a" || fail "R5: ADR template guidance does not name the sticky NFR '$_k'"
  done
  grep -qF 'never deferred at any stage' "$_a" \
    || fail "R5: ADR template guidance does not say sticky NFRs are 'never deferred at any stage'"
  for _k in 'encryption at rest' 'WAF' 'rate limits' 'backups' 'caching'; do
    grep -qiF "$_k" "$_a" || fail "R5: ADR template guidance does not name the bolt-on example '$_k'"
  done
  fold "$_a" | grep -qE 'ADR-0009[^.]{0,40}extending[^.]{0,80}spec change' \
    || fail "R5: ADR template guidance does not say extending the sticky list is a change to ADR-0009 (a spec change)"
  _t="$(lineno "$_a" '- **Trigger:**')"; _g="$(lineno "$_a" '> ## Stage-aware NFRs (ADR-0009)')"; _c="$(lineno "$_a" '## Context')"
  [ "$_g" -gt "$_t" ] && [ "$_c" -gt "$_g" ] \
    || fail "R5: the '> ## Stage-aware NFRs (ADR-0009)' guidance block is not between the header list and ## Context (trigger=$_t guidance=$_g context=$_c)"
  pass "ADR template names the 4 sticky NFRs (never deferred at any stage), the 5 bolt-on examples and the spec-change rule (R5) [R5_adr_template_sticky_boltons]"
}
R5_adr_template_sticky_boltons

# R6 — the plan template carries `## Deferred` and every row cites an R-id or an ADR.
R6_plan_template_deferred() {
  _p="$I/specs/_templates/feature.plan.md"
  [ -f "$_p" ] || fail "R6: installed specs/_templates/feature.plan.md missing"
  grep -qE '^## Deferred' "$_p" || fail "R6: plan template has no '## Deferred' subsection"
  grep -qF '| Bolt-on | Deferred by | Trigger |' "$_p" \
    || fail "R6: plan template has no '| Bolt-on | Deferred by | Trigger |' table header"
  grep -qE '^\| .* \| ADR-NNNN \| .* \|$' "$_p" \
    || fail "R6: plan template's Deferred table has no placeholder row citing ADR-NNNN in its Deferred-by cell"
  grep -qF 'Deferred: none — <why>' "$_p" \
    || fail "R6: plan template does not name the 'Deferred: none — <why>' single-line alternative"
  grep -qF 'specs/product.md' "$_p" || fail "R6: plan template does not name the stage source specs/product.md"
  fold "$_p" | grep -qE 'production[^.]{0,40}absent|absent[^.]{0,40}production' \
    || fail "R6: plan template does not say the stage is production when absent"
  fold "$_p" | grep -qE 'R-id[^.]{0,80}ADR-NNNN[^.]{0,40}defers' \
    || fail "R6: plan template's header blockquote does not say every row cites the R-id it serves or the ADR-NNNN that defers it"
  _f="$(lineno "$_p" '## Files to change')"; _x="$(lineno "$_p" '## Deferred')"; _n="$(lineno "$_p" '## DO NOT TOUCH')"
  [ "$_f" -gt 0 ] && [ "$_x" -gt "$_f" ] && [ "$_n" -gt "$_x" ] \
    || fail "R6: '## Deferred' is not between '## Files to change' and '## DO NOT TOUCH' (files=$_f deferred=$_x dnt=$_n)"
  pass "plan template carries '## Deferred' (table or 'Deferred: none — <why>') and the row-citation blockquote (R6) [R6_plan_template_deferred]"
}
R6_plan_template_deferred

# R11 — SPEC-FORMAT states the citation grammar E36-F04 will lint. The section is bounded
# by LINE NUMBERS (its own heading .. the known next heading), not by a `^## ` slicer: its
# fenced `## Deferred` example would truncate a fence-blind slicer.
R11_spec_format_grammar_section() {
  _s_f="$I/docs/SPEC-FORMAT.md"
  [ -f "$_s_f" ] || fail "R11: installed docs/SPEC-FORMAT.md missing"
  _tk="$(lineno "$_s_f" '## Tasks — red/green pairs per requirement')"
  _s="$(lineno "$_s_f" '## Plan rows cite an R-id or an ADR')"
  _e="$(lineno "$_s_f" '## Architecture alignment')"
  [ "$_s" -gt 0 ] || fail "R11: docs/SPEC-FORMAT.md has no '## Plan rows cite an R-id or an ADR' section"
  [ "$_tk" -gt 0 ] && [ "$_s" -gt "$_tk" ] && [ "$_e" -gt "$_s" ] \
    || fail "R11: the grammar section is not after '## Tasks — red/green pairs per requirement' and before '## Architecture alignment' (tasks=$_tk section=$_s next=$_e)"
  sed -n "${_s},${_e}p" "$_s_f" > "$T/r11.sec"
  for _k in '^stage: (discovery|pilot|production)$' '- **Status:** deferred' '- **Trigger:**' \
            'R[0-9]+' 'ADR-[0-9]{4}' '## Data model' '## API / interface' '## Files to change' \
            '## Deferred' '| Bolt-on | Deferred by | Trigger |' 'Deferred: none — <why>' 'E36-F04'; do
    grep -qF -- "$_k" "$T/r11.sec" || fail "R11: the grammar section does not state '$_k'"
  done
  fold "$T/r11.sec" | grep -qE 'E36-F04[^.]{0,80}lint' \
    || fail "R11: the grammar section does not name E36-F04 as the lint that enforces it"
  # The `## Deferred` example heading sits INSIDE a fenced block (``` toggles).
  awk 'index($0,"```")==1{fz=!fz; next} index($0,"## Deferred")==1 && fz {ok=1} END{exit !ok}' "$T/r11.sec" \
    || fail "R11: the grammar section's '## Deferred' example is not inside a fenced code block"
  pass "SPEC-FORMAT carries the citation grammar section (stage regex, deferred header, row rule, ## Deferred forms, E36-F04) (R11) [R11_spec_format_grammar_section]"
}
R11_spec_format_grammar_section

# span <file> <start-heading> <end-heading> <out> — the lines from the line STARTING with
# <start-heading> up to the line starting with <end-heading>, by line number (fence-proof).
# Fails the row if either heading is missing or out of order.
span() {
  _sa="$(lineno "$1" "$2")"; _sb="$(lineno "$1" "$3")"
  [ "$_sa" -gt 0 ] && [ "$_sb" -gt "$_sa" ] || return 1
  sed -n "${_sa},${_sb}p" "$1" > "$4"
}

# R7 — the Architect reads the stage and defers bolt-ons by writing a deferred ADR.
R7_architect_stage_section() {
  _r="$I/agents/architect.md"
  [ -f "$_r" ] || fail "R7: installed agents/architect.md missing"
  grep -qF '## Stage and NFRs (ADR-0009)' "$_r" || fail "R7: agents/architect.md has no '## Stage and NFRs (ADR-0009)' section"
  _u="$(lineno "$_r" '### Umbrella / shared-contract specs')"; _x="$(lineno "$_r" '## Stage and NFRs (ADR-0009)')"
  [ "$_u" -gt 0 ] && [ "$_x" -gt "$_u" ] \
    || fail "R7: the Stage section is not after '### Umbrella / shared-contract specs' (umbrella=$_u stage=$_x)"
  span "$_r" '## Stage and NFRs (ADR-0009)' '## Principles' "$T/r7.sec" \
    || fail "R7: the Stage section does not sit directly before '## Principles'"
  for _k in "grep '^stage:'" 'specs/product.md' 'discovery' 'pilot' '- **Status:** deferred' '- **Trigger:**' \
            '## Deferred' 'never deferred at any stage' 'tenant isolation' 'auth boundary' \
            'secrets out of the repo' 'validation at the system edge' 'Deferred: none — stage is production'; do
    grep -qF -- "$_k" "$T/r7.sec" || fail "R7: the Architect's Stage section does not state '$_k'"
  done
  _f="$(fold "$T/r7.sec")"
  printf '%s\n' "$_f" | grep -qiE 'absent[^.]{0,60}production' || fail "R7: the Stage section does not say absent means production"
  printf '%s\n' "$_f" | grep -qiE 'bolt-on[^.]{0,80}without[^.]{0,40}R-id' || fail "R7: the Stage section does not say never add a bolt-on without an R-id"
  printf '%s\n' "$_f" | grep -qiE 'not an ADR delta' || fail "R7: the Stage section does not say a deferred ADR is not an ADR delta"
  printf '%s\n' "$_f" | grep -qiE 'one ADR kind' || fail "R7: the Stage section does not carve out the deferred ADR as the one ADR kind the Architect may author"
  grep -qF 'do **not** author an ADR delta' "$_r" || fail "R7: the existing 'do **not** author an ADR delta' sentence was lost"
  pass "Architect Stage section: read stage, absent=production, deferred ADR per excluded bolt-on, no bolt-on without an R-id, sticky never deferred, deferred-ADR carve-out (R7) [R7_architect_stage_section]"
}
R7_architect_stage_section

# R8 — the Planner reads the stage before architecture.md/ADRs and records excluded bolt-ons
# as deferred ADRs; it never writes specs/product.md.
R8_planner_stage_section() {
  _r="$I/agents/planner.md"
  [ -f "$_r" ] || fail "R8: installed agents/planner.md missing"
  grep -qF '## Stage (ADR-0009)' "$_r" || fail "R8: agents/planner.md has no '## Stage (ADR-0009)' section"
  _w="$(lineno "$_r" '## Write the architecture + ADRs')"; _x="$(lineno "$_r" '## Stage (ADR-0009)')"
  [ "$_w" -gt 0 ] && [ "$_x" -gt "$_w" ] \
    || fail "R8: the Stage section is not after '## Write the architecture + ADRs' (arch=$_w stage=$_x)"
  span "$_r" '## Stage (ADR-0009)' '## Repo topology output' "$T/r8.sec" \
    || fail "R8: the Stage section does not sit before '## Repo topology output'"
  grep -qF "grep '^stage:'" "$T/r8.sec" || fail "R8: the Planner's Stage section does not give the read command"
  _f="$(fold "$T/r8.sec")"
  printf '%s\n' "$_f" | grep -qiE 'before[^.]{0,80}architecture' || fail "R8: the Stage section does not say the stage is read before writing architecture.md and the ADRs"
  printf '%s\n' "$_f" | grep -qiE 'absent[^.]{0,60}production' || fail "R8: the Stage section does not say absent means production"
  printf '%s\n' "$_f" | grep -qiE 'deferred ADR[^.]{0,80}Trigger' || fail "R8: the Stage section does not record an excluded bolt-on as a deferred ADR with a Trigger:"
  printf '%s\n' "$_f" | grep -qiE 'not an accepted ADR[^.]{0,40}omission' || fail "R8: the Stage section does not say an excluded bolt-on is neither an accepted ADR nor an omission"
  printf '%s\n' "$_f" | grep -qiE 'never write[^.]{0,30}specs/product' || fail "R8: the Stage section does not say the Planner never writes specs/product.md"
  printf '%s\n' "$_f" | grep -qiE 'completion report[^.]{0,60}stage|stage[^.]{0,60}completion report' \
    || fail "R8: the Stage section does not say to name the stage in the completion report"
  pass "Planner Stage section: read before architecture/ADRs, absent=production, excluded bolt-on = deferred ADR with Trigger:, never writes product.md, names stage in report (R8) [R8_planner_stage_section]"
}
R8_planner_stage_section

# R9 — the Driller reads the stage with the design artifacts and records it in every brief.
R9_driller_stage_section() {
  _r="$I/agents/driller.md"
  [ -f "$_r" ] || fail "R9: installed agents/driller.md missing"
  grep -qF '## Stage (ADR-0009)' "$_r" || fail "R9: agents/driller.md has no '## Stage (ADR-0009)' section"
  _d="$(lineno "$_r" '## Read the draft epic + design artifacts as input')"; _x="$(lineno "$_r" '## Stage (ADR-0009)')"
  [ "$_d" -gt 0 ] && [ "$_x" -gt "$_d" ] \
    || fail "R9: the Stage section is not after '## Read the draft epic + design artifacts as input' (read=$_d stage=$_x)"
  span "$_r" '## Stage (ADR-0009)' '## Feature-size budget' "$T/r9.sec" \
    || fail "R9: the Stage section does not sit before '## Feature-size budget'"
  grep -qF "grep '^stage:'" "$T/r9.sec" || fail "R9: the Driller's Stage section does not give the read command"
  _f="$(fold "$T/r9.sec")"
  printf '%s\n' "$_f" | grep -qiE 'absent[^.]{0,60}production' || fail "R9: the Stage section does not say absent means production"
  printf '%s\n' "$_f" | grep -qE 'Stage: <value>[^.]{0,120}## Constraints[^.]{0,60}ADR-NNNN' \
    || fail "R9: the Stage section does not say to record 'Stage: <value>' in every brief's ## Constraints beside the ADR-NNNN ids"
  pass "Driller Stage section: read with the design artifacts, absent=production, Stage: <value> in every brief's ## Constraints (R9) [R9_driller_stage_section]"
}
R9_driller_stage_section

R9_brief_template_stage() {
  _b="$I/specs/_templates/inbox-brief.md"
  [ -f "$_b" ] || fail "R9: installed specs/_templates/inbox-brief.md missing"
  span "$_b" '## Constraints' '## Open questions' "$T/r9b.sec" \
    || fail "R9: inbox-brief template lost its '## Constraints' / '## Open questions' headings"
  grep -qE '^- Stage: <' "$T/r9b.sec" \
    || fail "R9: inbox-brief template has no '- Stage: <…>' placeholder line under ## Constraints"
  grep -qF '<Non-negotiables the Architect must honor.>' "$T/r9b.sec" \
    || fail "R9: inbox-brief template lost its existing ## Constraints placeholder sentence"
  pass "inbox-brief template carries a '- Stage:' placeholder under ## Constraints (R9) [R9_brief_template_stage]"
}
R9_brief_template_stage

# R10 — WORKFLOW documents the stage, the sticky/bolt-on table, the two forms and E36-F04.
R10_workflow_stage_section() {
  _w="$I/docs/WORKFLOW.md"
  [ -f "$_w" ] || fail "R10: installed docs/WORKFLOW.md missing"
  grep -qF '## Stage and NFRs (ADR-0009)' "$_w" || fail "R10: docs/WORKFLOW.md has no '## Stage and NFRs (ADR-0009)' section"
  _a="$(lineno "$_w" '## Architecture-aligned specs')"; _x="$(lineno "$_w" '## Stage and NFRs (ADR-0009)')"
  [ "$_a" -gt 0 ] && [ "$_x" -gt "$_a" ] \
    || fail "R10: the Stage section is not after '## Architecture-aligned specs' (arch=$_a stage=$_x)"
  span "$_w" '## Stage and NFRs (ADR-0009)' '## Doc-critic checkpoints' "$T/r10.sec" \
    || fail "R10: the Stage section does not sit before '## Doc-critic checkpoints'"
  grep -qxF '| Sticky (never deferred) | Bolt-on (deferred by an ADR with a trigger) |' "$T/r10.sec" \
    || fail "R10: the sticky/bolt-on table header is missing from the Stage section"
  for _row in '| tenant isolation | encryption at rest |' '| the auth boundary | WAF |' \
              '| secrets out of the repo | rate limits |' '| validation at the system edge | backups, caching |'; do
    grep -qxF -- "$_row" "$T/r10.sec" || fail "R10: the sticky/bolt-on table lacks the row '$_row'"
  done
  for _k in 'stage:' 'specs/product.md' '- **Status:** deferred' '- **Trigger:**' '## Deferred' 'Deferred: none — <why>'; do
    grep -qF -- "$_k" "$T/r10.sec" || fail "R10: the WORKFLOW Stage section does not state '$_k'"
  done
  _f="$(fold "$T/r10.sec")"
  printf '%s\n' "$_f" | grep -qiE 'absent[^.]{0,60}production' || fail "R10: the WORKFLOW Stage section does not say absent means production"
  printf '%s\n' "$_f" | grep -qE '[Ee]nforcement[^.]{0,160}E36-F04' || fail "R10: the WORKFLOW Stage section does not name E36-F04 as the enforcement"
  pass "WORKFLOW Stage section: stage field + default, sticky/bolt-on table, deferred-ADR and ## Deferred forms, enforcement is E36-F04 (R10) [R10_workflow_stage_section]"
}
R10_workflow_stage_section

# R12 — VERSION and the newest CHANGELOG heading agree (read at runtime, no frozen literal),
# and some release section's body names E36-F03 and the stage (a historical anchor that stays
# green when a later release is prepended above it).
R12_version_changelog_paired() {
  _v="$(cat "$ROOT/VERSION")"
  [ -n "$_v" ] || fail "R12: VERSION is empty"
  _h="$(grep -m1 '^## \[' "$ROOT/CHANGELOG.md" || true)"
  case "$_h" in "## [$_v]"*) ;; *) fail "R12: the newest CHANGELOG heading '$_h' does not match VERSION $_v" ;; esac
  awk '/^## \[/{if (e && s) found=1; e=0; s=0; next} /E36-F03/{e=1} /stage/{s=1} END{if (e && s) found=1; exit !found}' "$ROOT/CHANGELOG.md" \
    || fail "R12: no CHANGELOG release section names both E36-F03 and stage"
  pass "VERSION matches the newest CHANGELOG heading and a release section names E36-F03 and stage (R12) [R12_version_changelog_paired]"
}
R12_version_changelog_paired

echo "All stage/NFR tests passed."
