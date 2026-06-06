#!/bin/sh
# test_telemetry.sh — R-id traceability suite for E05-F02 (sub-agent & human-gate
# telemetry with rollup reports). This feature ships PROSE (Orchestrator role edits +
# an AGENTS.md pointer + config) + ONE python3-stdlib report script. Verification is a
# mix of: (a) BEHAVIORAL assertions against tools/telemetry-report.py driven by fixture
# JSONL written to a temp --log (never the real <HARNESS_DIR>/telemetry.jsonl), and
# (b) STATIC greps that the capture contract is present in agents/orchestrator.md and
# the storage/portability seams are wired. Zero deps: POSIX sh + grep + python3.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

ORCH="agents/orchestrator.md"
REPORT="tools/telemetry-report.py"
CONFIG="harness.config.yaml"
INSTALLER="harness-install.sh"

T="$(mktemp -d 2>/dev/null || mktemp -d -t harnesstel)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# A deterministic fixture log: a session-start marker, stale pre-marker records, a
# fresh marker, then a round-1 builder (reject) / round-2 reviewer (done) pair across
# the same week, one slice-dispatch phase, a populated-cost line, a malformed line, and
# a gate open/close pair (human) plus an autonomous gate close.
FIX="$T/fixture.jsonl"
{
  printf '%s\n' '{"schema_version":1,"type":"session-start","started_at":"2026-01-01T00:00:00Z"}'
  printf '%s\n' '{"schema_version":1,"type":"phase","feature":"E00-F00","phase":"architect","round":1,"start":"2026-01-01T01:00:00Z","end":"2026-01-01T01:30:00Z","duration_s":1800,"outcome":"done","slice":null,"cost":null}'
  printf '%s\n' '{"schema_version":1,"type":"session-start","started_at":"2026-06-06T09:00:00Z"}'
  printf '%s\n' '{"schema_version":1,"type":"phase","feature":"E05-F02","phase":"architect","round":1,"start":"2026-06-06T09:10:00Z","end":"2026-06-06T09:40:00Z","duration_s":1800,"outcome":"done","slice":null,"cost":null}'
  printf '%s\n' '{"schema_version":1,"type":"phase","feature":"E05-F02","phase":"builder","round":1,"start":"2026-06-06T10:00:00Z","end":"2026-06-06T10:10:00Z","duration_s":600,"outcome":"reject","slice":null,"cost":null}'
  printf '%s\n' '{"schema_version":1,"type":"phase","feature":"E05-F02","phase":"reviewer","round":2,"start":"2026-06-06T11:00:00Z","end":"2026-06-06T11:05:00Z","duration_s":300,"outcome":"done","slice":null,"cost":{"tokens_in":10,"tokens_out":20,"usd":0.5}}'
  printf '%s\n' '{"schema_version":1,"type":"phase","feature":"E05-F02","phase":"scout","round":1,"start":"2026-06-06T09:05:00Z","end":"2026-06-06T09:07:00Z","duration_s":120,"outcome":"done","slice":null,"cost":null}'
  printf '%s\n' '{"schema_version":1,"type":"phase","feature":"E05-F02","phase":"inception","round":1,"start":"2026-06-06T09:01:00Z","end":"2026-06-06T09:02:00Z","duration_s":60,"outcome":"done","slice":null,"cost":null}'
  printf '%s\n' '{"schema_version":1,"type":"phase","feature":"E05-F02","phase":"slice-dispatch","round":1,"start":"2026-06-06T09:50:00Z","end":"2026-06-06T09:55:00Z","duration_s":300,"outcome":"done","slice":"E05-F02@viernes-api","cost":null}'
  printf '%s\n' 'this is a malformed line, not json {{{'
  printf '%s\n' '{"schema_version":1,"type":"gate","feature":"E05-F02","event":"spec_ready","spec_ready_at":"2026-06-06T10:00:00Z","autonomous":false}'
  printf '%s\n' '{"schema_version":1,"type":"gate","feature":"E05-F02","event":"in_progress","in_progress_at":"2026-06-06T15:30:00Z","human_latency_s":19800,"autonomous":false}'
  printf '%s\n' '{"schema_version":1,"type":"gate","feature":"E05-F03","event":"in_progress","in_progress_at":"2026-06-06T12:00:00Z","human_latency_s":2,"autonomous":true}'
} > "$FIX"

# ── R13: zero-dep report script exists, runs under python3, stdlib only ──────────
[ -f "$REPORT" ] || fail "R13: $REPORT missing"
command -v python3 >/dev/null 2>&1 || fail "R13: python3 not available to run the report"
python3 "$REPORT" --help >/dev/null 2>&1 || fail "R13: report --help failed"
# No third-party imports: every `import X` / `from X import` must be a stdlib module.
_bad="$(grep -E '^[[:space:]]*(import|from)[[:space:]]+' "$REPORT" \
  | grep -Ev '\b(argparse|json|os|re|statistics|sys|datetime)\b' || true)"
[ -z "$_bad" ] || fail "R13: non-stdlib import found: $_bad"
pass "R13 report_script_exists"

# ── R1: one phase record appended per finished phase → report counts them ────────
# 6 valid phase records (architect, builder, reviewer, scout, inception, slice-dispatch)
# after the latest marker; the session view's phase rows sum to 6.
_n="$(python3 "$REPORT" session --log "$FIX" | grep -E '^\| (architect|builder|reviewer|scout|inception|slice-dispatch) \|' | wc -l | tr -d ' ')"
[ "$_n" = "6" ] || fail "R1: expected 6 per-phase rows, got $_n"
pass "R1 report_counts_phase_records"

# ── R2: phase record has all required fields (schema doc + fixture) ──────────────
for fld in '"type":"phase"' '"feature"' '"phase"' '"start"' '"end"' '"duration_s"' '"outcome"' '"round"'; do
  grep -qF "$fld" "$FIX" || fail "R2: fixture missing field $fld"
done
grep -qiE 'feature id, phase/role, start timestamp, end timestamp|feature.*phase.*start.*end.*duration' "$ORCH" \
  || grep -qF '"duration_s"' "$ORCH" || fail "R2: orchestrator does not document phase record fields"
pass "R2 phase_schema_fields"

# ── R3: timestamps ISO-8601 UTC; orchestrator prose mentions date -u ─────────────
grep -qE '"start":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' "$FIX" \
  || fail "R3: fixture start is not ISO-8601 UTC"
grep -qF 'date -u' "$ORCH" || fail "R3: orchestrator prose does not mention date -u"
pass "R3 iso8601_utc_timestamps"

# ── R4: duration_s = end − start, non-negative; summed time matches; negatives ignored
# Session total autonomous time = 1800+600+300+120+60+300 = 3180s.
python3 "$REPORT" session --log "$FIX" | grep -qF 'Total autonomous agent time: 3180s' \
  || fail "R4: summed duration mismatch (expected 3180s)"
# A negative-duration phase must be ignored by the reader (not counted): a 100s valid
# phase plus a negative one must total exactly 100s, not -3500s.
NEG="$T/neg.jsonl"
printf '%s\n' \
  '{"schema_version":1,"type":"session-start","started_at":"2026-06-06T09:00:00Z"}' \
  '{"schema_version":1,"type":"phase","feature":"X","phase":"scout","round":1,"start":"2026-06-06T09:10:00Z","end":"2026-06-06T09:11:40Z","duration_s":100,"outcome":"done","slice":null,"cost":null}' \
  '{"schema_version":1,"type":"phase","feature":"X","phase":"builder","round":1,"start":"2026-06-06T10:00:00Z","end":"2026-06-06T09:00:00Z","duration_s":-3600,"outcome":"done","slice":null,"cost":null}' \
  > "$NEG"
python3 "$REPORT" session --log "$NEG" | grep -qF 'Total autonomous agent time: 100s' \
  || fail "R4: negative duration not ignored (total != 100s)"
pass "R4 duration_derivation"

# ── R5: phase ∈ enumerated roles, bucketed in the breakdown ──────────────────────
_out="$(python3 "$REPORT" session --log "$FIX")"
for ph in architect builder reviewer scout inception slice-dispatch; do
  printf '%s\n' "$_out" | grep -qE "^\| $ph \|" || fail "R5: phase $ph not in breakdown"
done
pass "R5 phase_enum"

# ── R6: round increments on review bounce (prose + fixture round 1/2) ────────────
grep -qiE 'in-review.*in-progress|in-progress.*in-review' "$ORCH" || fail "R6: no bounce wording"
grep -qi 'round' "$ORCH" || fail "R6: orchestrator does not mention round"
grep -qiE 'increment|\+1|increasing' "$ORCH" || fail "R6: orchestrator does not state round increments"
python3 "$REPORT" session --log "$FIX" | grep -qF 'Build/review rounds: 2' \
  || fail "R6: session round count != 2"
pass "R6 round_counter"

# ── R7: slice-dispatch record carries slice id (prose + fixture) ─────────────────
grep -qi 'slice-dispatch' "$ORCH" || fail "R7: orchestrator umbrella prose missing slice-dispatch record"
grep -qF '"slice":"E05-F02@viernes-api"' "$FIX" || fail "R7: fixture slice id missing"
python3 "$REPORT" session --log "$FIX" | grep -qE '^\| slice-dispatch \|' \
  || fail "R7: slice-dispatch not bucketed in breakdown"
pass "R7 slice_dispatch_record"

# ── R8: spec_ready open record stamped (prose + fixture parsed) ──────────────────
grep -qF 'spec_ready_at' "$ORCH" || fail "R8: orchestrator does not stamp spec_ready_at"
grep -qF '"event":"spec_ready"' "$FIX" || fail "R8: fixture gate-open record missing"
pass "R8 gate_open_record"

# ── R9: in_progress close + human_latency_s (fixture 10:00..15:30 = 19800s) ──────
python3 "$REPORT" session --log "$FIX" | grep -qE 'Human-gate latency.*mean 19800s' \
  || fail "R9: mean human latency != 19800s"
grep -qF 'human_latency_s' "$ORCH" || fail "R9: orchestrator does not document human_latency_s"
pass "R9 gate_latency"

# ── R10: autonomous distinguishable / excluded from human-latency stats ──────────
# The autonomous close (2s) must NOT pull the human mean below 19800; it is reported
# separately as an excluded autonomous transition.
_out="$(python3 "$REPORT" session --log "$FIX")"
printf '%s\n' "$_out" | grep -qE 'Human-gate latency \(n=1\).*mean 19800s' \
  || fail "R10: autonomous latency leaked into human stats"
printf '%s\n' "$_out" | grep -qiE 'autonomous.*excluded.*: 1' \
  || fail "R10: autonomous transition not reported/excluded"
grep -qi 'autonomous' "$ORCH" || fail "R10: orchestrator does not mention autonomous gate distinction"
pass "R10 autonomous_excluded"

# ── R11: unwritable/garbage path never blocks; prose says best-effort/never-block ─
grep -qiE 'best-effort|best effort' "$ORCH" || fail "R11: orchestrator missing best-effort wording"
grep -qiE 'never block|never-block|not? block|non-blocking' "$ORCH" || fail "R11: orchestrator missing never-block wording"
python3 "$REPORT" session --log "$T/this/path/does/not/exist.jsonl" >/dev/null 2>&1 \
  || fail "R11: report against a non-existent path did not exit 0"
pass "R11 best_effort_prose"

# ── R11 (storage): source .gitignore ignores the telemetry log path ──────────────
grep -qE '^/telemetry\.jsonl$' .gitignore || fail "R11: source .gitignore does not ignore /telemetry.jsonl"
if command -v git >/dev/null 2>&1 && [ -d .git ]; then
  git check-ignore -q telemetry.jsonl || fail "R11: git does not ignore telemetry.jsonl"
fi
pass "R11 source_gitignore_ignores_log"

# ── R11 (installer): seeds telemetry.jsonl into a .harness/.gitignore ────────────
grep -qF '.harness/.gitignore' "$INSTALLER" 2>/dev/null \
  || grep -qF '$H/.gitignore' "$INSTALLER" || fail "R11: installer does not seed a .harness/.gitignore"
grep -qF 'telemetry.jsonl' "$INSTALLER" || fail "R11: installer does not write telemetry.jsonl into the ignore"
# seed-once / never-clobber: the installer must guard with a presence/grep check.
grep -qE 'if \[ ! -f "\$H/\.gitignore" \]|grep -qF .telemetry\.jsonl. "\$H/\.gitignore"' "$INSTALLER" \
  || fail "R11: installer .harness/.gitignore seed is not guarded (seed-once)"
pass "R11 installer_seeds_harness_gitignore"

# ── R11 (installer): a RELATIVE telemetry.log override is also gitignored ─────────
# Regression for PR #12 Codex r3: a documented override like `custom/my.jsonl` resolves
# under .harness/ but the default ignore only covers `telemetry.jsonl`. The installer
# must ignore the configured override too (on its next run).
_CT="$T/consumer"; mkdir -p "$_CT"; ( cd "$_CT" && git init -q )
sh "$ROOT/$INSTALLER" "$_CT" >/dev/null 2>&1 || fail "R11: install into consumer failed"
# override telemetry.log to a relative subdir path, then re-run the installer
python3 - "$_CT/.harness/harness.config.yaml" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'(\n[ \t]+log:[ \t]*)telemetry\.jsonl', r'\1custom/my.jsonl', s, count=1)
open(p,"w").write(s)
PY
sh "$ROOT/$INSTALLER" "$_CT" >/dev/null 2>&1 || fail "R11: re-install into consumer failed"
grep -qF 'custom/my.jsonl' "$_CT/.harness/.gitignore" \
  || fail "R11: relative telemetry.log override not added to .harness/.gitignore"
# and prove git actually ignores it
mkdir -p "$_CT/.harness/custom" && : > "$_CT/.harness/custom/my.jsonl"
( cd "$_CT" && git check-ignore -q .harness/custom/my.jsonl ) \
  || fail "R11: overridden telemetry log path is not git-ignored"
pass "R11 installer_ignores_telemetry_log_override"

# ── R12: absent log auto-handled, not an error ───────────────────────────────────
python3 "$REPORT" --log "$T/absent.jsonl" >"$T/o12" 2>&1 || fail "R12: absent log exited non-zero"
grep -qiF 'no telemetry yet' "$T/o12" || fail "R12: absent log did not print the notice"
pass "R12 absent_log_noop"

# ── R14: all six granularities supported (each exits 0 + emits a table) ──────────
for g in daily weekly monthly quarterly semester annual; do
  python3 "$REPORT" "$g" --log "$FIX" >"$T/o14" 2>&1 || fail "R14: granularity $g exited non-zero"
  grep -qE '^\| phase \| count \| total duration \|' "$T/o14" || fail "R14: $g emitted no table"
done
pass "R14 granularities"

# ── R15: no-arg default summary (all granularities, no traceback) ────────────────
python3 "$REPORT" --log "$FIX" >"$T/o15" 2>&1 || fail "R15: default summary exited non-zero"
grep -qi 'all granularities' "$T/o15" || fail "R15: default summary header missing"
grep -qi 'Traceback' "$T/o15" && fail "R15: default summary printed a traceback"
for g in daily weekly monthly quarterly semester annual; do
  grep -qiF "$g rollup" "$T/o15" || fail "R15: default summary missing $g rollup"
done
pass "R15 default_summary"

# ── R16: per-period metrics present (total time, breakdown, count, mean+median) ──
python3 "$REPORT" weekly --log "$FIX" >"$T/o16" 2>&1 || fail "R16: weekly exited non-zero"
grep -qiF 'Total autonomous agent time' "$T/o16" || fail "R16: missing total autonomous time"
grep -qiF 'Phase count' "$T/o16" || fail "R16: missing phase count"
grep -qE '^\| (builder|reviewer) \|' "$T/o16" || fail "R16: missing per-phase breakdown"
grep -qiE 'mean .* median' "$T/o16" || fail "R16: missing mean+median latency"
pass "R16 report_metrics"

# ── R17: empty log → exit 0 + notice ─────────────────────────────────────────────
: > "$T/empty.jsonl"
python3 "$REPORT" --log "$T/empty.jsonl" >"$T/o17" 2>&1 || fail "R17: empty log exited non-zero"
grep -qiF 'no telemetry yet' "$T/o17" || fail "R17: empty log did not print the notice"
pass "R17 empty_log_notice"

# ── R18: malformed line skipped, not aborted (fixture has a garbage line) ─────────
# The fixture's garbage line is present but the report still aggregates the good lines.
grep -qF 'malformed line, not json' "$FIX" || fail "R18: fixture lost its garbage line"
python3 "$REPORT" weekly --log "$FIX" >/dev/null 2>&1 || fail "R18: malformed line aborted the report"
python3 "$REPORT" session --log "$FIX" | grep -qF 'Total autonomous agent time: 3180s' \
  || fail "R18: malformed line corrupted aggregation"
pass "R18 malformed_line_skipped"

# ── R19: append-only JSONL; one JSON object per line; prose says never rewrite ───
# Every non-blank fixture line that is JSON parses to a single object (round-trips).
python3 - "$FIX" <<'PY' || fail "R19: a JSON line is not a single object"
import json, sys
ok = 0
for ln in open(sys.argv[1]):
    ln = ln.strip()
    if not ln:
        continue
    try:
        obj = json.loads(ln)
    except ValueError:
        continue
    assert isinstance(obj, dict), "line is not a single JSON object"
    ok += 1
assert ok > 0
PY
grep -qiE 'append-only|append only' "$ORCH" || fail "R19: orchestrator missing append-only wording"
grep -qiE 'never rewrite|never reorder|rewrites or reorders|not rewrite or reorder' "$ORCH" || fail "R19: orchestrator missing no-rewrite wording"
pass "R19 jsonl_append_only"

# ── R20: reserved cost extension tolerated (populated + null both parse; ignored) ─
grep -qF '"cost":null' "$FIX" || fail "R20: fixture missing a null-cost line"
grep -qF '"cost":{"tokens_in"' "$FIX" || fail "R20: fixture missing a populated-cost line"
# The report must NOT surface any token/USD/cost figure for the populated-cost line.
_out="$(python3 "$REPORT" session --log "$FIX")"
printf '%s\n' "$_out" | grep -qiE 'token|usd|cost' && fail "R20: report surfaced a cost figure"
grep -qiE 'reserved|null today|cost.*null|null.*cost' "$ORCH" || fail "R20: orchestrator does not mark cost reserved/null"
pass "R20 cost_extension"

# ── R21: type + schema_version discriminator; report routes by type ──────────────
grep -qF '"type":"phase"' "$FIX" || fail "R21: no phase type"
grep -qF '"type":"gate"' "$FIX" || fail "R21: no gate type"
grep -qF '"schema_version":1' "$FIX" || fail "R21: no schema_version"
grep -qiE 'type.*discriminator|discriminator|schema_version' "$ORCH" || fail "R21: orchestrator does not document the discriminator"
pass "R21 record_discriminator"

# ── R22: end-of-session summary printed on wrap (prose) ──────────────────────────
grep -qiE 'end-of-session summary|end of session summary' "$ORCH" || fail "R22: no end-of-session summary heading"
grep -qiE 'wrap|hand back|hands back' "$ORCH" || fail "R22: does not tie summary to wrap/hand-back"
pass "R22 session_summary_prose"

# ── R23: summary is text/markdown table, no image ────────────────────────────────
python3 "$REPORT" session --log "$FIX" | grep -qE '^\|.*\|' || fail "R23: session view is not a markdown table"
grep -qiE 'text/markdown table|markdown table only|text-only|never an image|no image' "$ORCH" \
  || fail "R23: orchestrator does not state text-only / no-image"
pass "R23 session_summary_text_only"

# ── R24: summary = per-phase durations + round count + gate latency, NO tokens/USD
_out="$(python3 "$REPORT" session --log "$FIX")"
printf '%s\n' "$_out" | grep -qF 'Build/review rounds:' || fail "R24: session view missing round count"
printf '%s\n' "$_out" | grep -qiF 'Human-gate latency' || fail "R24: session view missing latency"
printf '%s\n' "$_out" | grep -qE '^\| builder \|' || fail "R24: session view missing per-phase durations"
printf '%s\n' "$_out" | grep -qiE 'token|usd|\$[0-9]' && fail "R24: session view surfaced token/USD"
pass "R24 session_metrics"

# ── R25: instruction portable, no Claude-only dep ────────────────────────────────
grep -qF 'python3 tools/telemetry-report.py session' "$ORCH" \
  || fail "R25: orchestrator does not invoke the portable session report"
# The end-of-session summary instruction must not depend on a Claude-only feature.
# Extract the "### End-of-session summary" block; any line that names a Claude-Code-only
# feature (Task tool / .claude/ / slash command) must do so only in a NEGATION ("no",
# "not", "without", "never", "depends on no …") — a positive dependency directive fails.
_blk="$(awk '/^### End-of-session summary/{f=1} f{print} /^## [^#]/{if(f && !/End-of-session/)exit}' "$ORCH")"
grep -qiE 'depends on no Claude|portable|no Claude-Code-specific' <<EOF || fail "R25: block does not assert portability"
$_blk
EOF
# Any reference to a Claude-only feature must be inside a negation line; strip negation
# lines first, then a leftover positive reference is a real dependency.
_pos="$(printf '%s\n' "$_blk" \
  | grep -iE 'Task tool|\.claude/|slash command' \
  | grep -ivE '\bno\b|\bnot\b|without|never|depends on no' || true)"
[ -z "$_pos" ] || fail "R25: end-of-session instruction has a positive Claude-only dependency: $_pos"
pass "R25 session_summary_portable"

# ── R25: AGENTS.md pointer present ───────────────────────────────────────────────
grep -qiE 'end-of-session.*summary|session.*telemetry summary' AGENTS.md \
  || fail "R25: AGENTS.md missing the end-of-session-summary pointer"
grep -qF 'agents/orchestrator.md' AGENTS.md || fail "R25: AGENTS.md pointer does not reference agents/orchestrator.md"
pass "R25 agents_md_summary_pointer"

# ── R26: session view reproduces the summary numbers (hand-computed) ─────────────
# Post-marker phases: architect 1800 + builder 600 + reviewer 300 + scout 120 +
# inception 60 + slice-dispatch 300 = 3180s; rounds=2; human latency mean=19800.
_out="$(python3 "$REPORT" session --log "$FIX")"
printf '%s\n' "$_out" | grep -qF 'Total autonomous agent time: 3180s' || fail "R26: total time mismatch"
printf '%s\n' "$_out" | grep -qF 'Build/review rounds: 2' || fail "R26: round count mismatch"
printf '%s\n' "$_out" | grep -qE 'Human-gate latency.*mean 19800s' || fail "R26: latency mismatch"
pass "R26 session_view_reproducible"

# ── R27: session-start marker scopes the session (pre-marker records excluded) ───
# The pre-marker architect span (E00-F00, also 1800s) must NOT be counted: if it were,
# the architect row would be 2 and total would be 4980s, not 3180s.
_out="$(python3 "$REPORT" session --log "$FIX")"
printf '%s\n' "$_out" | grep -qF 'Total autonomous agent time: 3180s' \
  || fail "R27: pre-marker records leaked into the session scope"
printf '%s\n' "$_out" | grep -qE '^\| architect \| 1 \|' \
  || fail "R27: pre-marker architect span not excluded (architect count != 1)"
grep -qF 'session-start' "$ORCH" || fail "R27: orchestrator does not append a session-start marker"
grep -qiE 'most recent|latest' "$ORCH" || fail "R27: orchestrator does not scope to the most-recent marker"
pass "R27 session_marker_scope"

# ── R26/R22: reader honors a CONFIGURED telemetry.log (reader/writer agreement) ──
# Regression for PR #12 Codex r1: the end-of-session summary must read the SAME path
# the writer uses, including a non-default `telemetry.log` override — otherwise the
# wrap-up shows "no telemetry yet" even though the session was captured. Build a temp
# harness layout with a custom log path and confirm the bare `session` run (no --log)
# reads it.
_TH="$(mktemp -d)"
mkdir -p "$_TH/tools" "$_TH/custom"
cp "$REPORT" "$_TH/tools/telemetry-report.py"
printf 'telemetry:\n  enabled: true\n  log: custom/my.jsonl\n' > "$_TH/harness.config.yaml"
printf '%s\n' \
  '{"type":"session-start","started_at":"2026-06-06T10:00:00Z","schema_version":1}' \
  '{"type":"phase","phase":"builder","start":"2026-06-06T10:00:00Z","duration_s":300,"round":1,"cost":null,"schema_version":1}' \
  > "$_TH/custom/my.jsonl"
_cfgout="$(python3 "$_TH/tools/telemetry-report.py" session)"   # NO --log on purpose
printf '%s\n' "$_cfgout" | grep -qF 'Total autonomous agent time: 300s' \
  || fail "R26: reader ignored configured telemetry.log override (got: $(printf '%s' "$_cfgout" | head -1))"
# SINGLE-QUOTED value must parse identically to the installer's awk (PR #12 Codex r4)
printf "telemetry:\n  enabled: true\n  log: 'custom/my.jsonl'\n" > "$_TH/harness.config.yaml"
_sqout="$(python3 "$_TH/tools/telemetry-report.py" session)"
printf '%s\n' "$_sqout" | grep -qF 'Total autonomous agent time: 300s' \
  || fail "R26: reader does not strip single-quoted telemetry.log (got: $(printf '%s' "$_sqout" | head -1))"
rm -rf "$_TH"
pass "R26 reader_honors_configured_log"

# ── Config + CI wiring sanity ────────────────────────────────────────────────────
grep -qE '^telemetry:' "$CONFIG" || fail "config: telemetry block missing"
grep -qE '^[[:space:]]*enabled:' "$CONFIG" || fail "config: telemetry.enabled missing (kill-switch)"
grep -qE '^[[:space:]]*log:[[:space:]]*telemetry\.jsonl' "$CONFIG" || fail "config: telemetry.log default missing"
grep -qF 'tests/test_telemetry.sh' "$CONFIG" || fail "config: test suite not wired into verification.test_command"
pass "config_and_ci_wired"

echo "All telemetry tests passed."
