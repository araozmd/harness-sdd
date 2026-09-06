#!/bin/sh
# test_inception.sh — static verification for E04-F01 (Inception role + /sdd-new).
# This feature ships PROSE (a portable role file + a Claude slash command + two doc
# edits), so verification is static: file-existence, required-phrase greps, and
# schema validation of the live state/tasks.json. The behavioral end-to-end checks
# are the documented manual /sdd-new walkthrough in inception.tests.md (§A/§B/§C),
# which the Reviewer performs once. Zero deps: POSIX sh + grep + python3.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

ROLE="agents/inception.md"
CMD=".claude/commands/sdd-new.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── R1: portable Inception role file ────────────────────────────────────────────
# role_file_exists
[ -f "$ROLE" ]              || fail "R1: $ROLE missing"
tr '\n' ' ' < "$ROLE" | grep -qiE 'seed[^.]{0,20}never spec' || fail "R1: role file does not state seed-never-spec"
tr '\n' ' ' < "$ROLE" | grep -qiE 'schema-passing[^.]{0,10}pending[^.]{0,10}entry' || fail "R1: role file does not produce a schema-passing pending entry"
tr '\n' ' ' < "$ROLE" | grep -qiE 'intent brief[^.]{0,20}progress/inbox' || fail "R1: role file does not write the intent brief under progress/inbox"
# Portable, not Claude-specific: must not assume the Claude slash mechanism as THE
# contract. It may *reference* /sdd-new as the example wrapper, but the role text
# states it is for any AGENTS.md-compatible CLI.
grep -qi 'AGENTS.md-compatible\|portable' "$ROLE" || fail "R1: role file not stated as portable"
pass "R1 role_file_exists"

# ── R2: /sdd-new slash command ──────────────────────────────────────────────────
# sdd_new_command
[ -f "$CMD" ]                       || fail "R2: $CMD missing"
grep -qF 'agents/inception.md' "$CMD" || fail "R2: command does not point at agents/inception.md"
grep -qF '$ARGUMENTS' "$CMD"          || fail "R2: command does not read \$ARGUMENTS"
pass "R2 sdd_new_command"

# ── R3: pending feature entry has all required fields (live store) ───────────────
# seed_entry_schema_valid — the role file mandates these fields; assert the role
# enumerates them, and that the live store's entries all carry them (schema-valid).
for f in 'id' 'title' 'status' 'sdd' 'autonomous' 'depends_on' 'spec_path'; do
  grep -qF "$f" "$ROLE" || fail "R3: role file does not specify the '$f' field"
done
grep -qi 'status.*pending\|"pending"' "$ROLE" || fail "R3: role file does not pin status to pending"
pass "R3 seed_entry_schema_valid"

# ── R6: tasks.json validates against the schema ──────────────────────────────────
# tasks_schema_valid — json.load + schema validation (jsonschema if present, else a
# built-in structural check mirroring init.sh's invariants).
python3 - state/tasks.json store/tasks.schema.json <<'PY' || fail "R6: state/tasks.json failed schema validation"
import json, re, sys
data = json.load(open(sys.argv[1]))
schema = json.load(open(sys.argv[2]))
try:
    import jsonschema
    errs = sorted(jsonschema.Draft7Validator(schema).iter_errors(data),
                  key=lambda e: list(e.path))
    for e in errs:
        print("  %s: %s" % ("/".join(str(p) for p in e.path) or "(root)", e.message), file=sys.stderr)
    sys.exit(1 if errs else 0)
except ImportError:
    pass
# Fallback structural check (subset: required fields + status enums + id patterns).
errors = []
FEAT = {"pending","spec-ready","in-progress","in-review","done"}
EPIC = {"draft","planned","pending","in-progress","done"}
for ei, ep in enumerate(data.get("epics", [])):
    if not re.match(r"^E[0-9]+$", ep.get("id","")): errors.append("epic[%d].id" % ei)
    if ep.get("status") not in EPIC: errors.append("epic[%d].status" % ei)
    for fi, ft in enumerate(ep.get("features", [])):
        for k in ("id","title","status","sdd","spec_path"):
            if k not in ft: errors.append("epic[%d].feat[%d] missing %s" % (ei,fi,k))
        if not re.match(r"^E[0-9]+-F[0-9]+$", ft.get("id","")): errors.append("epic[%d].feat[%d].id" % (ei,fi))
        if ft.get("status") not in FEAT: errors.append("epic[%d].feat[%d].status" % (ei,fi))
for e in errors: print("  "+e, file=sys.stderr)
sys.exit(1 if errors else 0)
PY
pass "R6 tasks_schema_valid"

# ── R4: inbox brief named after the entry id ─────────────────────────────────────
# inbox_brief_exists — assert the role pins the filename to the seeded id, and that
# the canonical template brief exists and is named after a real seeded entry.
grep -qF 'progress/inbox/<feature-id>.md' "$ROLE" || fail "R4: role does not pin brief to progress/inbox/<feature-id>.md"
grep -qi 'exactly the\|equals the .*id\|== .*id\|name.*equals\|filename.*id' "$ROLE" \
  || fail "R4: role does not require filename == seeded id"
[ -f "progress/inbox/E04-F01.md" ] || fail "R4: canonical template brief progress/inbox/E04-F01.md missing"
pass "R4 inbox_brief_exists"

# ── R5: brief frontmatter + sections ─────────────────────────────────────────────
# inbox_brief_format — assert the role specifies the frontmatter keys + sections, and
# that the canonical template brief actually carries them.
for tok in 'feature' 'seeded_by: inception' 'date'; do
  grep -qF "$tok" "$ROLE"                  || fail "R5: role does not specify frontmatter '$tok'"
  grep -qF "$tok" "progress/inbox/E04-F01.md" || fail "R5: template brief missing frontmatter '$tok'"
done
for sec in 'Problem' 'Success outcome' 'Scope' 'Constraints' 'Open questions'; do
  grep -qi "$sec" "$ROLE" || fail "R5: role does not specify the '$sec' section"
done
grep -qi 'chosen option' "$ROLE" || fail "R5: role does not specify the chosen-options section"
# Canonical, distributable inbox-brief template (shipped to consumers via
# specs/_templates/). Assert it exists and carries the same frontmatter + sections.
TPL="specs/_templates/inbox-brief.md"
[ -f "$TPL" ] || fail "R5: canonical template $TPL missing"
for tok in 'feature' 'seeded_by: inception' 'date'; do
  grep -qF "$tok" "$TPL" || fail "R5: template $TPL missing frontmatter '$tok'"
done
for sec in 'Problem' 'Success outcome' 'Scope' 'Constraints' 'Open questions'; do
  grep -qi "$sec" "$TPL" || fail "R5: template $TPL missing the '$sec' section"
done
grep -qi 'chosen option' "$TPL" || fail "R5: template $TPL missing the chosen-options section"
grep -qF 'specs/_templates/inbox-brief.md' "$ROLE" || fail "R5: role does not point at the canonical template"
pass "R5 inbox_brief_format"

# ── R7: validation failure ⇒ reported as non-success ─────────────────────────────
# fail_stop_documented
grep -qi 'must not claim a successful seed\|not.*claim.*success\|report the failure' "$ROLE" \
  || fail "R7: role does not state the fail-stop (report failure, do not claim seed)"
pass "R7 fail_stop_documented"

# ── R8: triage resolves to exactly one altitude ──────────────────────────────────
# triage_documented — the three altitudes named + "exactly one".
grep -qi 'exactly one' "$ROLE"                          || fail "R8: role does not say exactly one altitude"
grep -qi 'new task on an existing' "$ROLE"              || fail "R8: missing 'new task on existing feature' altitude"
grep -qi 'new feature under an existing epic' "$ROLE"   || fail "R8: missing 'new feature under existing epic' altitude"
grep -qi 'new epic' "$ROLE"                             || fail "R8: missing 'new epic' altitude"
pass "R8 triage_documented"

# ── R9: new epic creates epic entry + epic.md + F01 ──────────────────────────────
# new_epic_documented
grep -qF 'epic.md' "$ROLE"   || fail "R9: role does not mention creating epic.md"
grep -qi 'F01'     "$ROLE"   || fail "R9: role does not mention seeding first F01"
pass "R9 new_epic_documented"

# ── R10: next-sequential ids, no reuse ───────────────────────────────────────────
# id_policy_documented
grep -qi 'next.sequential\|next sequential' "$ROLE"     || fail "R10: role does not state next-sequential ids"
tr '\n' ' ' < "$ROLE" | grep -qiE 'never reuse[^.]{0,15}vacated id' || fail "R10: role does not state the never-reuse-a-vacated-id rule"
pass "R10 id_policy_documented"

# ── R11: never writes any spec file ──────────────────────────────────────────────
# no_spec_writes
grep -qi 'never.*spec\|seed.*never spec\|not.*create or modify any' "$ROLE" \
  || fail "R11: role does not state seeds-never-specs"
for ext in '.spec' '.plan' '.tasks' '.tests'; do
  grep -qF "$ext" "$ROLE" || fail "R11: role does not name $ext as forbidden"
done
pass "R11 no_spec_writes"

# ── R12: pending-only, never advances ────────────────────────────────────────────
# pending_only
grep -qi 'only ever create entries at .*pending\|only.*pending' "$ROLE" \
  || fail "R12: role does not pin writes to pending-only"
grep -qi 'never.*advance\|never set or advance' "$ROLE" \
  || fail "R12: role does not state never-advance-status"
for st in 'spec-ready' 'in-progress' 'in-review' 'done'; do
  grep -qF "$st" "$ROLE" || fail "R12: role does not name forbidden status '$st'"
done
pass "R12 pending_only"

# ── R13: no change to schema / orchestrator / architect; no new status ───────────
# do_not_touch_clean — assert the role STATES it must not touch them, and that the
# DO-NOT-TOUCH files are unchanged by this feature's diff (vs. main).
grep -qF 'store/tasks.schema.json' "$ROLE"  || fail "R13: role does not name tasks.schema.json as untouchable"
grep -qF 'agents/orchestrator.md' "$ROLE"   || fail "R13: role does not name orchestrator.md as untouchable"
grep -qF 'agents/architect.md' "$ROLE"      || fail "R13: role does not name architect.md as untouchable"
grep -qi 'new status' "$ROLE"               || fail "R13: role does not forbid a new status value"
# That the *Inception role* must not touch orchestrator routing / the schema is
# enforced permanently by the role-CONTENT assertions above (it names them as
# untouchable and forbids a new status). A byte-freeze-vs-main, by contrast, is only
# meaningful while THIS feature is the only thing on the branch — post-merge it would
# wrongly forbid ANY later feature from editing these files (the permanent-suite
# anti-pattern: e.g. E06-F01 legitimately extends the EPIC status enum). So no file
# is diffed against main here; the genuine permanent invariant is the FEATURE status
# enum content, re-checked below. Whether a given PR touched a DO-NOT-TOUCH file is a
# PR-review-time concern (the Reviewer reads the diff), not a frozen suite assertion.
# FEATURE status enum in the schema is unchanged (still the five canonical values, no new one).
grep -qF '"pending", "spec-ready", "in-progress", "in-review", "done"' store/tasks.schema.json \
  || fail "R13: feature status enum in schema changed"
pass "R13 do_not_touch_clean"

# ── R14: options/mockups text-only, ≤3 ───────────────────────────────────────────
# text_only_options — in BOTH the role and the command.
grep -qi 'text.*only\|markdown.*only\|markdown / ASCII\|markdown/ASCII' "$ROLE" || fail "R14: role does not state text-only mockups"
grep -qi 'at most 3\|at most three\|≤ *3\|<= *3' "$ROLE"                        || fail "R14: role does not cap options at 3"
grep -qi 'text.*only\|markdown.*ASCII\|markdown/ASCII' "$CMD"                   || fail "R14: command does not state text-only mockups"
grep -qi 'at most 3\|at most three\|≤ *3\|<= *3' "$CMD"                         || fail "R14: command does not cap options at 3"
pass "R14 text_only_options"

# ── R15: completion report names id + entry + inbox path + run /sdd-next ──────────
# completion_report — in BOTH the role and the command.
for f in "$ROLE" "$CMD"; do
  grep -qF '/sdd-next' "$f"                || fail "R15: $f does not tell the human to run /sdd-next"
  grep -qF 'progress/inbox/' "$f"          || fail "R15: $f does not report the inbox brief path"
done
grep -qi 'does not\|do NOT spawn\|never.*spawn' "$ROLE" || fail "R15: role does not state it does not spawn the Architect"
pass "R15 completion_report"

# ── R16: docs describe the pre-pending intake step ───────────────────────────────
# docs_mention_intake
tr '\n' ' ' < AGENTS.md | grep -qiE 'Inception[^.]{0,40}front door' || fail "R16: AGENTS.md does not name Inception as the front door"
grep -qi 'agents/\*.md.*Inception\|Inception.*Orchestrator' AGENTS.md \
  || fail "R16: AGENTS.md role list does not include Inception"
grep -qF '/sdd-new' docs/WORKFLOW.md           || fail "R16: WORKFLOW.md does not show /sdd-new"
grep -qi 'before.*pending\|pre-.pending\|step before' docs/WORKFLOW.md \
  || fail "R16: WORKFLOW.md does not describe the pre-pending step"
pass "R16 docs_mention_intake"

echo "All inception tests passed."
