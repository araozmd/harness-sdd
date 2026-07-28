#!/bin/sh
# test_agents_host.sh — E19-F01: host detection + the explicit `--agents=host`
# resolution mode.
#
# Covers R1–R31 of specs/epics/E19-single-cli-default/F01-agents-host-resolution/.
#
# ENVIRONMENT DISCIPLINE (R29, and the reason this suite is a separate file):
# detection reads the AMBIENT environment, so a test that inherits the developer's shell
# tests nothing — it would pass on a laptop that happens to export CLAUDECODE and fail on
# one that does not, or worse, pass in CI for the wrong reason. Every installer invocation
# here therefore goes through `hrun`, the ONE place this suite names the installer, which
# runs it under `env -i` with nothing but PATH, a sandboxed HOME and a sandboxed
# CODEX_HOME (never the developer's real ~/.codex, whose /prompts dir the `codex`
# front-end writes to). No check freezes the exact VERSION string; no check diffs a
# DO-NOT-TOUCH file against `main`.
#
# Zero dependencies; self-cleaning temp dir.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-host)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# hrun <sandbox-dir> [VAR=VALUE …] -- <installer args…>
#
# The single gateway to the installer. Creates <sandbox-dir>/home and <sandbox-dir>/ch,
# then runs the installer under `env -i` with PATH + those two sandboxes + exactly the
# named variables. Arguments are rebuilt positionally (rotate-through-"$@") rather than
# accumulated into a string, so a value containing spaces — e.g.
# HARNESS_HOST_AGENT="claude gemini", which R10 requires — survives intact.
hrun() {
  _hr_dir="$1"; shift
  mkdir -p "$_hr_dir/home" "$_hr_dir/ch"
  _hr_i=0; _hr_total=$#
  while [ "$_hr_i" -lt "$_hr_total" ]; do
    if [ "$1" = "--" ]; then
      set -- "$@" sh "$SRC/harness-install.sh"
    else
      set -- "$@" "$1"
    fi
    shift
    _hr_i=$((_hr_i + 1))
  done
  env -i PATH="$PATH" HOME="$_hr_dir/home" CODEX_HOME="$_hr_dir/ch" "$@"
}

# sandbox <name> — a fresh per-case sandbox dir; prints its path.
sandbox() { mkdir -p "$T/$1"; printf '%s\n' "$T/$1"; }

# host_of <sandbox> <target> [VAR=VALUE …] — the `host=` value --print-agents reports.
#
# It DISTINGUISHES "ran and detected nothing" from "failed to run": every negative
# assertion in this suite is of the form "host= is empty", which a crashed installer would
# also satisfy. So a non-zero exit, or a run that never printed the `host=` contract line,
# yields a loud sentinel instead of the empty string — the assertion then fails with the
# sentinel in its message rather than passing vacuously. (Reviewer N1: a scratch harness
# pointing $SRC at a nonexistent dir once made the R6 case pass for the wrong reason.)
host_of() {
  _ho_x="$1"; _ho_t="$2"; shift 2
  if ! hrun "$_ho_x" "$@" -- --print-agents "$_ho_t" >"$_ho_x/host_of.out" 2>"$_ho_x/host_of.err"; then
    printf '%s\n' "__INSTALLER_EXITED_NONZERO__"
    return 0
  fi
  if ! grep -q '^host=' "$_ho_x/host_of.out"; then
    printf '%s\n' "__NO_HOST_LINE_ON_STDOUT__"
    return 0
  fi
  sed -n 's/^host=//p' "$_ho_x/host_of.out"
}

# The installer source, read once for the source-level checks.
INST="$SRC/harness-install.sh"

# marker_table — the body of the HOST_MARKERS table (rows only, no comments).
marker_table() {
  sed -n '/^HOST_MARKERS="$/,/^"$/p' "$INST" | sed '1d;$d'
}

# prov_entry <agent-key> — print JUST that key's entry from the PROVENANCE comment block:
# the `#   <key> …` line (the key at exactly three spaces of indent) plus its more deeply
# indented continuation lines, stopping at the next key's entry or at any section header.
#
# The per-key SCOPING is the whole point. A block-wide grep would let a row borrow another
# key's evidence — the mutation `gemini GEMINI_CLI` slipped through the old check precisely
# because `GEMINI_CLI` was mentioned (as a REJECTED candidate) inside the antigravity
# entry, and because `gemini` appears in the note saying gemini has *no* verified marker.
prov_entry() {
  awk -v key="$1" '
    /^# PROVENANCE/       { inblock = 1; next }
    /^HOST_MARKERS="/     { inblock = 0 }
    !inblock              { next }
    {
      # Anything that is not an indented comment body ends the current entry (this is what
      # keeps the REJECTED CANDIDATES section from being absorbed into the last entry).
      if ($0 !~ /^#   /) { cur = ""; next }
      body = $0
      sub(/^#[[:space:]]+/, "", body)
      # A new entry starts ONLY at exactly three spaces of indent, with a known agent key.
      if ($0 ~ /^#   [a-z]/) {
        w = body
        sub(/[[:space:]].*$/, "", w)
        if (w == "claude" || w == "gemini" || w == "opencode" || w == "antigravity" || w == "codex") cur = w
        else cur = ""
      }
      if (cur == key) print body
    }
  ' "$INST"
}

# comment_block_above <literal first characters of a definition line> — print the run of
# `#` comment lines immediately above that definition, and nothing else.
#
# The SCOPING is the point (same reason prov_entry scopes per key): a file-wide grep for a
# stale phrase either misses the block that matters or fires on unrelated prose elsewhere.
# Matching is by literal prefix, so no regex escaping of `()` is involved.
comment_block_above() {
  awk -v fn="$1" '
    index($0, fn) == 1 { printf "%s", buf; exit }
    /^#/               { buf = buf $0 "\n"; next }
                       { buf = "" }
  ' "$INST"
}

# ── R1, R3, R7 — a single present marker resolves to exactly one key ───────────
test_host_single_marker() {
  _x="$(sandbox single)"; _t="$_x/t"; mkdir -p "$_t"
  [ "$(host_of "$_x" "$_t" CLAUDECODE=1)" = "claude" ] \
    || fail "R1/R3/R7: CLAUDECODE=1 did not resolve the host to 'claude'"
  # CLAUDE_CODE_ENTRYPOINT is the same row's second marker — either one is enough (R1).
  [ "$(host_of "$_x" "$_t" CLAUDE_CODE_ENTRYPOINT=cli)" = "claude" ] \
    || fail "R1: the claude row's second marker did not resolve the host"
  # At most ONE key, never a list.
  [ "$(host_of "$_x" "$_t" CLAUDECODE=1 | wc -w | tr -d ' ')" = "1" ] \
    || fail "R1: detection printed more than one key"
  return 0
}

# ── R2 — a marker set to the EMPTY string is not present ──────────────────────
test_host_empty_marker_is_absent() {
  _x="$(sandbox empty)"; _t="$_x/t"; mkdir -p "$_t"
  _got="$(host_of "$_x" "$_t" CLAUDECODE=)"
  [ -z "$_got" ] || fail "R2: an empty CLAUDECODE counted as a present marker (got '$_got')"
  return 0
}

# ── R4 — no marker at all ⇒ undetected ────────────────────────────────────────
test_host_no_marker_undetected() {
  _x="$(sandbox nomarker)"; _t="$_x/t"; mkdir -p "$_t"
  _got="$(host_of "$_x" "$_t")"
  [ -z "$_got" ] || fail "R4: a marker-free environment resolved a host (got '$_got')"
  return 0
}

# ── R5 — two competing keys ⇒ undetected + a stderr diagnostic naming both ─────
test_host_ambiguous_is_undetected() {
  _x="$(sandbox ambiguous)"; _t="$_x/t"; mkdir -p "$_t"
  # Two SHIPPED rows' markers at once — the nesting case (one CLI shelling out to
  # another inherits the outer CLI's markers), which cannot be resolved from the
  # environment and is therefore a MISS, never a tie-break.
  _out="$(hrun "$_x" CLAUDECODE=1 OPENCODE=1 -- --print-agents "$_t" 2>"$_x/err.txt")"
  printf '%s\n' "$_out" | grep -qx 'host=' \
    || fail "R5: competing markers did not resolve to undetected (got: $_out)"
  grep -q 'claude' "$_x/err.txt" || fail "R5: the stderr diagnostic does not name 'claude'"
  grep -q 'opencode' "$_x/err.txt" || fail "R5: the stderr diagnostic does not name 'opencode'"
  # The diagnostic is on STDERR, never mixed into the machine-readable stdout.
  printf '%s\n' "$_out" | grep -q 'ambiguous' \
    && fail "R5: the ambiguity diagnostic leaked into stdout"
  return 0
}

# ── R6 — no ambient config/credential variable is ever a marker ────────────────
test_host_forbidden_markers() {
  _x="$(sandbox forbidden)"; _t="$_x/t"; mkdir -p "$_t"
  # CODEX_HOME is set on EVERY hrun invocation (it is the sandbox), so a CODEX_HOME
  # marker row would make every case in this file resolve `codex`. That is exactly the
  # trap R6 names: it would look correct in CI and be wrong on every real machine.
  for _v in CODEX_HOME GEMINI_API_KEY OPENCODE_API_KEY ANTHROPIC_API_KEY TERM_PROGRAM; do
    case "$_v" in
      CODEX_HOME) _got="$(host_of "$_x" "$_t")" ;;
      *)          _got="$(host_of "$_x" "$_t" "$_v=x")" ;;
    esac
    [ -z "$_got" ] || fail "R6: the ambient variable $_v acted as a marker (resolved '$_got')"
  done
  # Source-level: the forbidden names must not appear in the table body at all.
  _body="$(marker_table)"
  printf '%s\n' "$_body" | grep -q '_API_KEY' \
    && fail "R6: the HOST_MARKERS table contains an _API_KEY credential variable"
  printf '%s\n' "$_body" | grep -q 'CODEX_HOME' \
    && fail "R6: the HOST_MARKERS table contains CODEX_HOME"
  printf '%s\n' "$_body" | grep -qw 'HOME' \
    && fail "R6: the HOST_MARKERS table contains HOME"
  printf '%s\n' "$_body" | grep -q 'TERM_PROGRAM' \
    && fail "R6: the HOST_MARKERS table contains TERM_PROGRAM"
  return 0
}

# ── R8 — every shipped row records its empirical provenance, per VARIABLE ─────
# R8 is the guard that keeps a future contributor from pinning a marker nobody verified —
# the failure the spec calls out ("getting it wrong is how a Claude Code user gets a
# Codex-only install"). So this check inspects the row's VARIABLE NAMES, not just its key,
# and scopes the evidence to that key's own PROVENANCE entry. Two mutations it must catch:
# adding `gemini GEMINI_CLI` with no new provenance, and appending an invented variable to
# an existing row. (A key with NO row is undetectable — an accepted outcome, not a defect —
# so only the rows that DO ship are policed here.)
test_host_marker_rows_documented() {
  _prov="$(sed -n '/^# PROVENANCE/,/^HOST_MARKERS="$/p' "$INST")"
  [ -n "$_prov" ] || fail "R8: the HOST_MARKERS table carries no PROVENANCE comment block"
  marker_table > "$T/rows.txt"
  [ -s "$T/rows.txt" ] || fail "R8: the HOST_MARKERS table has no rows at all"
  # Redirected (not piped) so a `fail` inside the loop exits the suite instead of a subshell.
  while IFS= read -r _row; do
    [ -n "$_row" ] || continue
    _key="${_row%% *}"
    _vars="${_row#* }"
    grep -q "^AGENT_KEYS=.*$_key" "$INST" \
      || fail "R8: table row '$_key' is not an AGENT_KEYS member"
    [ "$_vars" != "$_row" ] || fail "R8: row '$_key' declares no marker variable"
    _entry="$(prov_entry "$_key")"
    [ -n "$_entry" ] \
      || fail "R8: row '$_key' has no PROVENANCE entry (expected a '#   $_key …' line)"
    # (a) the entry must name the CLI VERSION the markers were observed on.
    printf '%s\n' "$_entry" | grep -Eq '[0-9]+\.[0-9]+' \
      || fail "R8: the PROVENANCE entry for '$_key' records no CLI version — R8 requires the CLI and version it was observed on"
    # (b) EVERY variable on the row must be recorded in THAT key's entry. Borrowing
    #     another key's entry, or a rejected-candidate mention, does not count.
    for _v in $_vars; do
      printf '%s\n' "$_entry" | grep -qw "$_v" \
        || fail "R8: marker '$_v' on row '$_key' is not recorded in that key's PROVENANCE entry — an unverified marker must never ship"
    done
  done < "$T/rows.txt"
  return 0
}

# ── R9 — HARNESS_HOST_AGENT wins over the marker table ────────────────────────
test_host_env_declaration_wins() {
  _x="$(sandbox decl)"; _t="$_x/t"; mkdir -p "$_t"
  [ "$(host_of "$_x" "$_t" CLAUDECODE=1 HARNESS_HOST_AGENT=opencode)" = "opencode" ] \
    || fail "R9: HARNESS_HOST_AGENT did not win over a present CLAUDECODE marker"
  [ "$(host_of "$_x" "$_t" HARNESS_HOST_AGENT=gemini)" = "gemini" ] \
    || fail "R9: HARNESS_HOST_AGENT could not declare an undetectable front-end"
  return 0
}

# ── R10 — an invalid declaration warns, continues, never aborts ───────────────
test_host_env_declaration_invalid_warns() {
  _x="$(sandbox declbad)"; _t="$_x/t"; mkdir -p "$_t"
  for _bad in bogus host "claude gemini"; do
    hrun "$_x" HARNESS_HOST_AGENT="$_bad" CLAUDECODE=1 -- --print-agents "$_t" \
      >"$_x/out.txt" 2>"$_x/err.txt" || fail "R10: HARNESS_HOST_AGENT='$_bad' aborted the run"
    grep -qF "$_bad" "$_x/err.txt" \
      || fail "R10: the warning for HARNESS_HOST_AGENT='$_bad' does not name the value"
    # Falls through to the marker verdict, exactly as if the variable were unset.
    grep -qx 'host=claude' "$_x/out.txt" \
      || fail "R10: HARNESS_HOST_AGENT='$_bad' did not fall back to the marker verdict"
  done
  return 0
}

# ── R11, R23 — --print-agents: two lines, exit 0, writes nothing ──────────────
test_print_agents_contract() {
  _x="$(sandbox printcontract)"
  # (a) an empty target dir …
  _t="$_x/fresh"; mkdir -p "$_t"
  _before="$(find "$_t" | sort)"
  hrun "$_x" CLAUDECODE=1 -- --print-agents "$_t" >"$_x/a.out" 2>"$_x/a.err" \
    || fail "R23: --print-agents exited non-zero on a fresh dir"
  [ "$(wc -l <"$_x/a.out" | tr -d ' ')" = "2" ] \
    || fail "R23: --print-agents printed $(wc -l <"$_x/a.out") stdout lines, expected exactly 2"
  sed -n '1p' "$_x/a.out" | grep -qx 'host=claude' || fail "R23: line 1 is not host=<key>"
  # E19-F02 R1 CHANGED THIS EXPECTED VALUE, deliberately: on a target with no existing
  # install the baseline is now the detected host alone, and `baseline=` reports the
  # picker's pre-check set (R6). The old expectation here was all five — the very default
  # this feature replaces. The sorted MULTI-key rendering the line also has to prove is
  # preserved in (a2) below, on the same fresh dir with detection missing.
  sed -n '2p' "$_x/a.out" | grep -qx 'baseline=claude' \
    || fail "R23/F02 R1: line 2 is not the detected-host baseline ($(sed -n '2p' "$_x/a.out"))"
  [ "$(find "$_t" | sort)" = "$_before" ] \
    || fail "R11/R23: --print-agents created or modified a file in the target"
  # (a2) the same fresh dir, no marker ⇒ the sorted all-keys line.
  hrun "$_x" -- --print-agents "$_t" >"$_x/a2.out" 2>/dev/null \
    || fail "R23: --print-agents exited non-zero on an undetected fresh dir"
  sed -n '2p' "$_x/a2.out" | grep -qx 'baseline=antigravity claude codex gemini opencode' \
    || fail "R23: line 2 is not the sorted baseline ($(sed -n '2p' "$_x/a2.out"))"
  [ "$(find "$_t" | sort)" = "$_before" ] \
    || fail "R11/R23: --print-agents created or modified a file in the target"
  # (b) … and an INSTALLED target, on both TTY-less runs.
  _i="$_x/installed"; mkdir -p "$_i"
  hrun "$_x" -- --agents=claude "$_i" >/dev/null 2>&1 || fail "R23: setup install failed"
  _before="$(find "$_i" | sort)"
  hrun "$_x" -- --print-agents "$_i" >"$_x/b.out" 2>/dev/null \
    || fail "R23: --print-agents exited non-zero on an installed target"
  sed -n '1p' "$_x/b.out" | grep -qx 'host=' || fail "R23: undetected host is not the empty value"
  sed -n '2p' "$_x/b.out" | grep -qx 'baseline=claude' \
    || fail "R23: baseline= does not report the installed target's persisted selection"
  [ "$(find "$_i" | sort)" = "$_before" ] \
    || fail "R11/R23: --print-agents mutated an installed target"
  [ -z "$(find "$_x/ch" -newer "$_x/b.out" 2>/dev/null)" ] \
    || fail "R11: --print-agents touched the global Codex prompts dir"
  return 0
}

# ── R24 — --print-agents is single-target only ────────────────────────────────
test_print_agents_umbrella_rejected() {
  _x="$(sandbox printumb)"; _u="$_x/umb"; mkdir -p "$_u/child"
  hrun "$_x" -- --print-agents --umbrella "$_u" >"$_x/out" 2>"$_x/err" \
    && fail "R24: --print-agents --umbrella exited 0"
  grep -q 'print-agents' "$_x/err" || fail "R24: the usage message does not name --print-agents"
  [ -z "$(find "$_u" -name .harness -print 2>/dev/null)" ] \
    || fail "R24: --print-agents --umbrella wrote a .harness/ somewhere"
  return 0
}

# ── R12 — detected ⇒ that front-end's glue and nothing else ───────────────────
test_host_mode_stamps_detected_only() {
  _x="$(sandbox detected)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" CLAUDECODE=1 -- --agents=host "$_t" >/dev/null 2>&1 \
    || fail "R12: --agents=host with a detected host exited non-zero"
  [ -f "$_t/CLAUDE.md" ]      || fail "R12: detected claude did not write CLAUDE.md"
  [ -d "$_t/.claude/agents" ] || fail "R12: detected claude did not write .claude/agents"
  [ -f "$_t/AGENTS.md" ]      || fail "R12: AGENTS.md must always be written, never gated"
  [ -f "$_t/GEMINI.md" ]      && fail "R12: host mode stamped the unselected gemini entrypoint"
  [ -f "$_t/opencode.json" ]  && fail "R12: host mode stamped opencode.json"
  [ -d "$_t/.opencode" ]      && fail "R12: host mode stamped .opencode/"
  [ -d "$_t/.agents" ]        && fail "R12: host mode stamped the antigravity .agents/ tree"
  [ -d "$_x/ch/prompts" ]     && fail "R12: host mode stamped the GLOBAL codex prompts"
  [ "$(tr '\n' ' ' <"$_t/.harness/.agents")" = "claude " ] \
    || fail "R12: persisted selection is not exactly 'claude'"
  return 0
}

# ── R13 — undetected + no existing install ⇒ ALL (today's no-TTY default) ─────
test_host_undetected_fresh_is_all() {
  _x="$(sandbox freshall)"; _t="$_x/host"; _r="$_x/ref"; mkdir -p "$_t" "$_r"
  hrun "$_x" -- --agents=host "$_t" >/dev/null 2>&1 \
    || fail "R13: undetected --agents=host on a fresh target exited non-zero"
  # The reference: a no-override non-TTY run, i.e. exactly today's behavior.
  hrun "$_x" -- "$_r" >/dev/null 2>&1 || fail "R13: reference install failed"
  [ "$(command cat "$_t/.harness/.agents")" = "$(command cat "$_r/.harness/.agents")" ] \
    || fail "R13: undetected host on a fresh target did not resolve to the ALL default"
  for _f in CLAUDE.md GEMINI.md opencode.json AGENTS.md; do
    [ -f "$_t/$_f" ] || fail "R13: undetected host fresh install is missing $_f"
  done
  [ -d "$_t/.agents" ] || fail "R13: undetected host fresh install is missing .agents/"
  return 0
}

# ── R14 — undetected + existing install ⇒ persisted-else-ALL, NEVER widens ────
test_host_undetected_upgrade_keeps_selection() {
  _x="$(sandbox keepsel)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 || fail "R14: setup install failed"
  hrun "$_x" -- --agents=host "$_t" >/dev/null 2>&1 \
    || fail "R14: undetected --agents=host on an existing install exited non-zero"
  [ "$(tr '\n' ' ' <"$_t/.harness/.agents")" = "claude " ] \
    || fail "R14: an undetected host run WIDENED a claude-only install"
  [ -f "$_t/GEMINI.md" ]     && fail "R14: an undetected host run created GEMINI.md"
  [ -f "$_t/opencode.json" ] && fail "R14: an undetected host run created opencode.json"
  [ -d "$_t/.agents" ]       && fail "R14: an undetected host run created .agents/"
  # A legacy-shaped target (install present, no persisted selection) ⇒ ALL.
  _l="$_x/legacy"; mkdir -p "$_l"
  hrun "$_x" -- --agents=claude "$_l" >/dev/null 2>&1 || fail "R14: legacy setup install failed"
  rm -f "$_l/.harness/.agents"
  hrun "$_x" -- --agents=host "$_l" >/dev/null 2>&1 || fail "R14: legacy host run exited non-zero"
  [ "$(tr '\n' ' ' <"$_l/.harness/.agents")" = "antigravity claude codex gemini opencode " ] \
    || fail "R14: a legacy install with no persisted selection did not fall back to ALL"
  return 0
}

# ── R13/R14 — "existing install" is the VERSION STAMP, not a stray .agents ────
# Regression (Codex P2 on PR #70): a fresh target can carry metadata without being an
# install — copied, or half-restored — and keying the fallback off .harness/.agents alone
# treated that as an existing install and silently omitted the other front-ends.
test_host_undetected_orphan_agents_is_all() {
  _x="$(sandbox orphan)"; _t="$_x/t"; _r="$_x/ref"; mkdir -p "$_t/.harness" "$_r"
  printf 'claude\n' > "$_t/.harness/.agents"
  [ -f "$_t/.harness/.harness-version" ] && fail "R13: the orphan fixture must carry no version stamp"
  hrun "$_x" -- --agents=host "$_t" >/dev/null 2>&1 \
    || fail "R13: undetected --agents=host on orphan metadata exited non-zero"
  hrun "$_x" -- "$_r" >/dev/null 2>&1 || fail "R13: reference install failed"
  [ "$(command cat "$_t/.harness/.agents")" = "$(command cat "$_r/.harness/.agents")" ] \
    || fail "R13: an orphan .harness/.agents narrowed a target with no existing install ($(tr '\n' ' ' <"$_t/.harness/.agents"))"
  for _f in GEMINI.md opencode.json; do
    [ -f "$_t/$_f" ] || fail "R13: the orphan-metadata host install is missing $_f"
  done
  # …and the anti-widening property is untouched: WITH the stamp, the same shape is kept.
  _s="$_x/stamped"; mkdir -p "$_s"
  hrun "$_x" -- --agents=claude "$_s" >/dev/null 2>&1 || fail "R14: stamped setup install failed"
  [ -f "$_s/.harness/.harness-version" ] || fail "R14: the setup install left no version stamp"
  hrun "$_x" -- --agents=host "$_s" >/dev/null 2>&1 \
    || fail "R14: undetected --agents=host on a real existing install exited non-zero"
  [ "$(tr '\n' ' ' <"$_s/.harness/.agents")" = "claude " ] \
    || fail "R14: an undetected host run WIDENED a real existing install"
  [ -f "$_s/GEMINI.md" ] && fail "R14: an undetected host run created GEMINI.md on a real install"
  return 0
}

# ── R15 — honored via HARNESS_AGENTS too, and on an upgrade ───────────────────
test_host_mode_env_and_upgrade() {
  _x="$(sandbox envmode)"; _e="$_x/env"; _f="$_x/flag"; mkdir -p "$_e" "$_f"
  hrun "$_x" CLAUDECODE=1 HARNESS_AGENTS=host -- "$_e" >/dev/null 2>&1 \
    || fail "R15: HARNESS_AGENTS=host exited non-zero"
  hrun "$_x" CLAUDECODE=1 -- --agents=host "$_f" >/dev/null 2>&1 \
    || fail "R15: --agents=host exited non-zero"
  [ "$(command cat "$_e/.harness/.agents")" = "$(command cat "$_f/.harness/.agents")" ] \
    || fail "R15: HARNESS_AGENTS=host and --agents=host resolved differently"
  # A second host run over the existing install resolves the same way, no prompt.
  hrun "$_x" CLAUDECODE=1 -- --agents=host "$_f" >/dev/null 2>&1 \
    || fail "R15: a repeat --agents=host upgrade exited non-zero"
  [ "$(tr '\n' ' ' <"$_f/.harness/.agents")" = "claude " ] \
    || fail "R15: the repeat host upgrade changed the resolved set"
  return 0
}

# ── R16 — `host` mixed with any other token is rejected, nothing written ──────
test_host_mixed_token_rejected() {
  _x="$(sandbox mixed)"; _t="$_x/t"; mkdir -p "$_t"
  for _v in host,gemini gemini,host "host, claude"; do
    hrun "$_x" -- --agents="$_v" "$_t" >"$_x/out" 2>"$_x/err" \
      && fail "R16: --agents=$_v exited 0"
    grep -q "host" "$_x/err" || fail "R16: the rejection message for '$_v' does not mention host"
    [ -d "$_t/.harness" ] && fail "R16: a rejected mixed override still wrote to the target"
  done
  # Same rule through the environment.
  hrun "$_x" HARNESS_AGENTS=host,codex -- "$_t" >/dev/null 2>"$_x/err2" \
    && fail "R16: HARNESS_AGENTS=host,codex exited 0"
  grep -q "host" "$_x/err2" || fail "R16: the env-side rejection message does not mention host"
  return 0
}

# ── R17 — `host` is not a registry key / picker row ───────────────────────────
test_host_not_a_registry_key() {
  grep '^AGENT_KEYS=' "$INST" | grep -q 'host' \
    && fail "R17: AGENT_KEYS contains 'host' — it would become a selectable picker row"
  _x="$(sandbox registry)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" CLAUDECODE=1 -- --agents=host "$_t" >/dev/null 2>&1 || fail "R17: install failed"
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    case " claude gemini opencode antigravity codex " in
      *" $_line "*) : ;;
      *) fail "R17/R18: .harness/.agents holds the non-key token '$_line'" ;;
    esac
  done < "$_t/.harness/.agents"
  grep -qx 'host' "$_t/.harness/.agents" \
    && fail "R18: the token 'host' was persisted to .harness/.agents"
  return 0
}

# ── R19 — PRIOR_AGENTS computation is untouched ───────────────────────────────
test_prior_agents_unchanged() {
  grep -qF 'PRIOR_AGENTS="$(normalize_keys "$AGENT_KEYS" | grep -vx codex)"' "$INST" \
    || fail "R19: the PRIOR_AGENTS legacy baseline lost its 'grep -vx codex' exclusion"
  # Integration: a legacy-shaped upgrade selecting claude must reclaim NO global prompt.
  _x="$(sandbox prior)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude,codex "$_t" >/dev/null 2>&1 || fail "R19: setup install failed"
  _kept="$_x/ch/prompts/sdd-next.md"
  [ -f "$_kept" ] || fail "R19: setup did not stamp the global codex prompts"
  rm -f "$_t/.harness/.agents"   # legacy shape: install present, selection absent
  hrun "$_x" CLAUDECODE=1 -- --agents=host "$_t" >/dev/null 2>&1 \
    || fail "R19: legacy-shaped host upgrade exited non-zero"
  [ -f "$_kept" ] \
    || fail "R19: a legacy-baseline upgrade reclaimed a cross-target GLOBAL codex prompt"
  return 0
}

# ── R20 — a host run with no existing install touches no global prompt/ledger ─
test_host_fresh_removes_nothing() {
  _x="$(sandbox freshsafe)"; _t="$_x/t"; mkdir -p "$_t" "$_x/ch/prompts"
  _foreign="$_x/ch/prompts/someone-elses.md"
  printf 'not ours\n' > "$_foreign"
  _ledger="$_x/ch/prompts/.sdd-pr-loop.owners"
  printf '%s\n' "/some/other/target" > "$_ledger"
  _pr="$_x/ch/prompts/sdd-pr-loop.md"
  printf 'another target stamped this\n' > "$_pr"
  hrun "$_x" CLAUDECODE=1 -- --agents=host "$_t" >/dev/null 2>&1 \
    || fail "R20: fresh host install exited non-zero"
  [ -f "$_foreign" ] || fail "R20: a fresh host install deleted a foreign global prompt"
  [ "$(command cat "$_foreign")" = "not ours" ] \
    || fail "R20: a fresh host install modified a foreign global prompt"
  [ -f "$_ledger" ] || fail "R20: a fresh host install deleted the .sdd-pr-loop.owners ledger"
  grep -qx '/some/other/target' "$_ledger" \
    || fail "R20: a fresh host install dropped another target's ledger claim"
  [ -f "$_pr" ] || fail "R20: a fresh host install reclaimed a ledger-owned global prompt"
  # It also stamped no NEW codex glue (codex was not the detected host).
  [ -f "$_x/ch/prompts/sdd-next.md" ] \
    && fail "R20: a claude-only host install stamped the global codex prompts"
  return 0
}

# ── R21 — a host upgrade that drops codex obeys the pristine-compare rule ─────
test_host_upgrade_removal_respects_pristine() {
  _x="$(sandbox pristine)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude,codex "$_t" >/dev/null 2>&1 || fail "R21: setup install failed"
  _edited="$_x/ch/prompts/sdd-new.md"
  _clean="$_x/ch/prompts/sdd-next.md"
  [ -f "$_edited" ] && [ -f "$_clean" ] || fail "R21: setup did not stamp the global prompts"
  printf '\nhand-edited by the user\n' >> "$_edited"
  _warn="$(hrun "$_x" CLAUDECODE=1 -- --agents=host "$_t" 2>&1 >/dev/null)" \
    || fail "R21: the host upgrade exited non-zero"
  [ -f "$_clean" ] && fail "R21: a byte-pristine deselected global prompt was not reclaimed"
  [ -f "$_edited" ] || fail "R21: a hand-edited global prompt was destroyed"
  grep -qF 'hand-edited by the user' "$_edited" \
    || fail "R21: the user's edit was overwritten instead of preserved"
  printf '%s\n' "$_warn" | grep -q '⚠️' \
    || fail "R21: the preserved edit was not reported with a warning"
  return 0
}

# ── R22 — a run that never names `host` is byte-identically today's behavior ──
test_additive_no_host_unchanged() {
  _x="$(sandbox additive)"; _a="$_x/all"; _c="$_x/claudeonly"; mkdir -p "$_a" "$_c"
  # A present marker must NOT influence a run that did not ask for host resolution.
  hrun "$_x" CLAUDECODE=1 -- "$_a" >/dev/null 2>&1 || fail "R22: no-override run exited non-zero"
  [ "$(tr '\n' ' ' <"$_a/.harness/.agents")" = "antigravity claude codex gemini opencode " ] \
    || fail "R22: a no-override non-TTY run with CLAUDECODE set no longer stamps ALL"
  [ -f "$_a/GEMINI.md" ] && [ -f "$_a/opencode.json" ] && [ -d "$_a/.agents" ] \
    || fail "R22: a no-override non-TTY run stopped stamping every front-end"
  hrun "$_x" CLAUDECODE=1 -- --agents=claude "$_c" >/dev/null 2>&1 \
    || fail "R22: --agents=claude exited non-zero"
  [ "$(tr '\n' ' ' <"$_c/.harness/.agents")" = "claude " ] \
    || fail "R22: an explicit concrete override no longer resolves to exactly that set"
  # HARNESS_HOST_AGENT alone changes nothing either — it only feeds `host` resolution.
  _d="$_x/decl"; mkdir -p "$_d"
  hrun "$_x" HARNESS_HOST_AGENT=claude -- "$_d" >/dev/null 2>&1 \
    || fail "R22: HARNESS_HOST_AGENT-only run exited non-zero"
  [ "$(tr '\n' ' ' <"$_d/.harness/.agents")" = "antigravity claude codex gemini opencode " ] \
    || fail "R22: HARNESS_HOST_AGENT narrowed a run that never named 'host'"
  return 0
}

# ── R25 — exactly one report line, naming the key or the applied fallback ─────
test_host_reports_resolution() {
  _x="$(sandbox report)"; _t="$_x/t"; _u="$_x/u"; mkdir -p "$_t" "$_u"
  _o="$(hrun "$_x" CLAUDECODE=1 -- --agents=host "$_t" 2>&1)" || fail "R25: detected run failed"
  printf '%s\n' "$_o" | grep -q 'agents: host detected' \
    || fail "R25: a detected host run printed no resolution line"
  printf '%s\n' "$_o" | grep -q "claude" \
    || fail "R25: the detected resolution line does not name the key"
  [ "$(printf '%s\n' "$_o" | grep -c 'agents: host')" = "1" ] \
    || fail "R25: the host branch printed more than one report line"
  # Undetected, fresh ⇒ the ALL fallback …
  _o2="$(hrun "$_x" -- --agents=host "$_u" 2>&1)" || fail "R25: undetected fresh run failed"
  printf '%s\n' "$_o2" | grep -q 'host undetected' \
    || fail "R25: an undetected host run printed no resolution line"
  printf '%s\n' "$_o2" | grep -q 'all front-ends' \
    || fail "R25: the fresh undetected fallback is not named in the report line"
  # … and undetected on an existing install ⇒ the kept-selection fallback. The two
  # cases MUST be distinguishable in the text.
  _o3="$(hrun "$_x" -- --agents=host "$_t" 2>&1)" || fail "R25: undetected upgrade run failed"
  printf '%s\n' "$_o3" | grep -q "keeping this install's selection" \
    || fail "R25: the existing-install undetected fallback is not distinguishable in the text"
  return 0
}

# ── R26 — one shared helper behind baseline=, the picker and the fallback ─────
test_baseline_single_helper() {
  grep -q '^precheck_baseline() {' "$INST" || fail "R26: precheck_baseline is not defined"
  grep -q '^host_fallback_set() {' "$INST" || fail "R26: host_fallback_set is not defined"
  # The persisted-shape answer has one source, shared by the picker and the R14 arm.
  _calls="$(grep -c 'precheck_baseline "' "$INST" || :)"
  [ "$_calls" -ge 2 ] \
    || fail "R26: precheck_baseline has $_calls call sites, expected the 2 documented ones"
  grep -q 'precheck_baseline "$_t"' "$INST" \
    || fail "R26: resolve_agents does not compute the picker baseline through precheck_baseline"
  # The undetected-fallback answer has one source, shared by resolution and the diagnostic.
  grep -q 'host_fallback_set "$_t"' "$INST" \
    || fail "R26: resolve_agents does not resolve the undetected fallback through host_fallback_set"
  # E19-F02 R6 REPOINTED THIS: `baseline=` now reports precheck_baseline — the picker's
  # pre-check set — so the diagnostic advertises the new fresh-install default instead of
  # the old one. For every UNDETECTED target the two helpers return the identical set
  # (host_fallback_set defers to precheck_baseline on an existing install and both answer
  # ALL otherwise), so R26's preview-matches-install property is preserved, not traded
  # away; test_print_agents_matches_host_install below still proves it end to end.
  grep -q 'precheck_baseline "$TGT"' "$INST" \
    || fail "R26/F02 R6: --print-agents does not compute baseline= through precheck_baseline"
  # The old inline computation is gone — two sources could disagree.
  grep -q '_base="$(normalize_keys "$(cat "$_persisted")")"' "$INST" \
    && fail "R26: the inline interactive baseline computation still exists alongside the helper"
  return 0
}

# ── R26 — the advertised baseline IS what a real --agents=host run installs ────
# Regression (Codex P2 on PR #70, comment 3663900848): baseline= was computed from the
# persisted file alone, so a fresh target carrying an orphan .harness/.agents advertised
# `baseline=claude` while an actual undetected --agents=host run took the R13 branch and
# selected all five. A preview that disagrees with the install is worse than no preview.
# Each case previews and then installs the SAME target — --print-agents writes nothing.
test_print_agents_matches_host_install() {
  _x="$(sandbox previewmatch)"
  # (a) the orphan corner: metadata present, version stamp absent ⇒ R13, ALL.
  _t="$_x/orphan"; mkdir -p "$_t/.harness"
  printf 'claude\n' > "$_t/.harness/.agents"
  [ -f "$_t/.harness/.harness-version" ] && fail "R26: the orphan fixture must carry no version stamp"
  _adv="$(hrun "$_x" -- --print-agents "$_t" 2>/dev/null | sed -n 's/^baseline=//p')"
  [ -n "$_adv" ] || fail "R26: --print-agents printed no baseline= line for the orphan target"
  hrun "$_x" -- --agents=host "$_t" >/dev/null 2>&1 \
    || fail "R26: undetected --agents=host on the orphan target exited non-zero"
  _got="$(tr '\n' ' ' <"$_t/.harness/.agents" | sed 's/[[:space:]]*$//')"
  [ "$_adv" = "$_got" ] \
    || fail "R26: --print-agents advertised '$_adv' but the host install selected '$_got' (orphan .agents, no stamp)"
  # (b) and the same agreement on a REAL existing install, which must stay narrow.
  _s="$_x/stamped"; mkdir -p "$_s"
  hrun "$_x" -- --agents=claude "$_s" >/dev/null 2>&1 || fail "R26: stamped setup install failed"
  _adv2="$(hrun "$_x" -- --print-agents "$_s" 2>/dev/null | sed -n 's/^baseline=//p')"
  hrun "$_x" -- --agents=host "$_s" >/dev/null 2>&1 \
    || fail "R26: undetected --agents=host on the stamped target exited non-zero"
  _got2="$(tr '\n' ' ' <"$_s/.harness/.agents" | sed 's/[[:space:]]*$//')"
  [ "$_adv2" = "$_got2" ] \
    || fail "R26: --print-agents advertised '$_adv2' but the host install selected '$_got2' (existing install)"
  [ "$_adv2" = "claude" ] \
    || fail "R26: the preview for a claude-only install is not 'claude' (got '$_adv2')"
  return 0
}

# ── R27 — docs, header and manifest name the mode ─────────────────────────────
test_docs_document_host_mode() {
  _x="$(sandbox docs)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" CLAUDECODE=1 -- --agents=host "$_t" >/dev/null 2>&1 || fail "R27: install failed"
  # The docs must SHIP (the installed copy), not merely exist in the source tree.
  _mi="$_t/.harness/docs/INSTALL.md"
  for _s in '--agents=host' 'HARNESS_HOST_AGENT' '--print-agents' 'CLAUDECODE'; do
    grep -qF -e "$_s" "$_mi" || fail "R27: installed docs/INSTALL.md does not document $_s"
  done
  grep -qF 'no existing install' "$_mi" \
    || fail "R27: docs/INSTALL.md does not document the no-existing-install fallback"
  grep -qF 'persisted' "$_mi" \
    || fail "R27: docs/INSTALL.md does not document the existing-install fallback"
  grep -qF 'host' "$_t/.harness/manifest.txt" \
    || fail "R27: the generated manifest.txt AGENT SELECTION block does not name host"
  grep -qF -e '--agents=host' "$SRC/README.md" || fail "R27: README.md does not name --agents=host"
  sed -n '1,60p' "$INST" | grep -qF 'host' \
    || fail "R27: the harness-install.sh header comment does not name the host mode"
  return 0
}

# ── R28 — the suite exists and is wired into verification.test_command ────────
test_suite_wired_into_verification() {
  grep -qF 'tests/test_agents_host.sh' "$SRC/harness.config.yaml" \
    || fail "R28: this suite is not registered in verification.test_command"
  [ -f "$SRC/tests/test_agents_host.sh" ] || fail "R28: tests/test_agents_host.sh does not exist"
  grep -qF -e 'agents=host' "$SRC/tests/test_install.sh" \
    || fail "R28: tests/test_install.sh does not cover --agents=host end to end"
  return 0
}

# ── R29 — this suite's own hygiene ────────────────────────────────────────────
test_suite_hygiene() {
  _self="$SRC/tests/test_agents_host.sh"
  # (The pattern is spelled with a character class so this very line does not match it.)
  grep -q 'git[[:space:]][[:space:]]*diff' "$_self" \
    && fail "R29: this suite diffs a file against git — a permanent suite must never do that"
  grep -qF "$(command cat "$SRC/VERSION")" "$_self" \
    && fail "R29: this suite freezes the exact VERSION string"
  # The installer is INVOKED exactly once (inside hrun). The filters drop this check's own
  # pattern line, the read-only source path used by the source-level checks, and message
  # strings — none of which run the installer.
  _named="$(grep -n 'harness-install' "$_self" | grep -v 'grep ' | grep -v 'INST=' | grep -v 'fail "' | grep -c . || :)"
  [ "$_named" -le 1 ] \
    || fail "R29: the installer is invoked outside hrun ($_named sites) — env control is lost"
  grep -q 'env -i PATH=' "$_self" || fail "R29: hrun does not run the installer under env -i"
  grep -q 'CODEX_HOME="$_hr_dir/ch"' "$_self" \
    || fail "R29: hrun does not sandbox CODEX_HOME under the case's own temp dir"
  return 0
}

# ── R30 — no new dependency; an installed target still passes init.sh ─────────
test_init_still_green() {
  _x="$(sandbox initgreen)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" CLAUDECODE=1 -- --agents=host "$_t" >/dev/null 2>&1 || fail "R30: install failed"
  "$_t/.harness/init.sh" >"$_x/init.out" 2>"$_x/init.err" \
    || fail "R30: the installed init.sh exited non-zero: $(command cat "$_x/init.err")"
  # Detection uses only shell built-ins + the commands the installer already relies on.
  for _c in ps proc lsof curl wget python; do
    sed -n '/^detect_host() {/,/^}/p' "$INST" | grep -qw "$_c" \
      && fail "R30: detect_host reaches for the new dependency '$_c'"
  done
  return 0
}

# ── R31 — MINOR VERSION bump + a matching CHANGELOG entry ─────────────────────
test_version_and_changelog() {
  # Compared by PARSED COMPONENTS, never by freezing a literal — a frozen string is a
  # permanent-suite anti-pattern that breaks on the next bump.
  _v="$(command cat "$SRC/VERSION")"
  _maj="${_v%%.*}"; _rest="${_v#*.}"; _min="${_rest%%.*}"
  [ "$_maj" -eq 0 ] || fail "R31: unexpected MAJOR version $_maj"
  [ "$_min" -ge 40 ] || fail "R31: VERSION $_v is not the MINOR bump this feature requires"
  grep -qF "## [$_v]" "$SRC/CHANGELOG.md" || fail "R31: CHANGELOG.md has no entry for $_v"
  grep -qF 'host' "$SRC/CHANGELOG.md" || fail "R31: CHANGELOG.md does not mention the host mode"
  # E19-F02 R13 — one more MINOR step on top of the 0.40 E19-F01 shipped, still compared
  # by parsed components. The feature marker is looked for ANYWHERE in the file, not in
  # the current top section, so a later release cannot be forced to re-mention it.
  [ "$_min" -ge 41 ] \
    || fail "F02 R13: VERSION $_v is not a MINOR step beyond the 0.40 E19-F01 shipped"
  grep -qiE 'pre-check|precheck' "$SRC/CHANGELOG.md" \
    || fail "F02 R13: CHANGELOG.md carries no fresh-install pre-check baseline entry"
  return 0
}

# ══ E19-F02 — the fresh-install pre-check baseline ════════════════════════════════════
#
# WHY --print-agents IS THE INSTRUMENT: the thing under test is what the INTERACTIVE
# picker pre-checks, and a POSIX suite cannot portably hand the installer a TTY. E19-F01
# R26 / E19-F02 R6 make the picker's baseline and the `baseline=` diagnostic line the
# output of the SAME helper (precheck_baseline), so asserting `baseline=` is asserting the
# picker — and test_baseline_single_helper below is what keeps that equivalence honest.

# ALL — the five keys, sorted, as --print-agents renders them on one line. Derived from
# the installer's own AGENT_KEYS so a future sixth front-end cannot make these cases pass
# by leaving the expectation frozen at five names.
ALL_KEYS="$(sed -n 's/^AGENT_KEYS="\(.*\)"$/\1/p' "$INST" | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')"

# baseline_of <sandbox> <target> [VAR=VALUE …] — the `baseline=` value --print-agents
# reports, under hrun's env discipline.
#
# Like host_of, it distinguishes "ran and reported" from "failed to run": a crashed
# installer yields a loud sentinel rather than an empty string, so no assertion below can
# pass (or fail) vacuously.
baseline_of() {
  _bo_x="$1"; _bo_t="$2"; shift 2
  if ! hrun "$_bo_x" "$@" -- --print-agents "$_bo_t" >"$_bo_x/baseline_of.out" 2>"$_bo_x/baseline_of.err"; then
    printf '%s\n' "__INSTALLER_EXITED_NONZERO__"
    return 0
  fi
  if ! grep -q '^baseline=' "$_bo_x/baseline_of.out"; then
    printf '%s\n' "__NO_BASELINE_LINE_ON_STDOUT__"
    return 0
  fi
  sed -n 's/^baseline=//p' "$_bo_x/baseline_of.out"
}

# ── R4, R9 — a pre-E08 install (stamped, no persisted selection) ⇒ ALL ────────
# THE regression this feature must not cause. Such a target carries every front-end's glue
# and no .harness/.agents; if the fresh-install detection branch could reach it, a human
# pressing Enter on the pre-checked picker would DELETE four working front-ends. The
# "existing install" test is therefore the VERSION STAMP, not the presence of .agents.
test_baseline_legacy_upgrade_is_all() {
  _x="$(sandbox f2legacy)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude,gemini "$_t" >/dev/null 2>&1 || fail "R4: setup install failed"
  rm -f "$_t/.harness/.agents"
  [ -f "$_t/.harness/.harness-version" ] \
    || fail "R4: the pre-E08 fixture must still carry its version stamp"
  _got="$(baseline_of "$_x" "$_t" CLAUDECODE=1)"
  [ "$_got" = "$ALL_KEYS" ] \
    || fail "R4/R9: a pre-E08 upgrade's baseline was narrowed by detection (got '$_got', want '$ALL_KEYS')"
  return 0
}

# ── R1 — no existing install + detected ⇒ that key ALONE ─────────────────────
# The equality is EXACT on the whole line, which is what makes this the
# host-only-not-host-plus-claude check: `claude gemini`, `antigravity claude` or any other
# union that merely CONTAINS the detected key fails here. Two different hosts are asserted
# so a hardcoded `claude` cannot pass, and the declared-host path is included because a
# front-end with no verified marker must reach the same branch.
test_baseline_fresh_is_host_only() {
  _x="$(sandbox f2fresh)"; _t="$_x/t"; mkdir -p "$_t"
  _got="$(baseline_of "$_x" "$_t" CLAUDECODE=1)"
  [ "$_got" = "claude" ] \
    || fail "R1: a fresh install inside Claude Code does not pre-check 'claude' alone (got '$_got')"
  _got="$(baseline_of "$_x" "$_t" OPENCODE=1)"
  [ "$_got" = "opencode" ] \
    || fail "R1: a fresh install inside OpenCode does not pre-check 'opencode' alone (got '$_got')"
  _got="$(baseline_of "$_x" "$_t" HARNESS_HOST_AGENT=gemini)"
  [ "$_got" = "gemini" ] \
    || fail "R1: a declared host does not pre-check that key alone on a fresh target (got '$_got')"
  # The target is still untouched — a baseline is computed, never installed.
  [ -d "$_t/.harness" ] && fail "R1: computing the fresh baseline wrote to the target"
  return 0
}

# ── R2 — no existing install + undetected ⇒ ALL ──────────────────────────────
# The detection MISS keeps today's behavior byte-for-byte; it is the designed degradation
# for every front-end with no verified marker, not a gap.
test_baseline_fresh_undetected_is_all() {
  _x="$(sandbox f2freshall)"; _t="$_x/t"; mkdir -p "$_t"
  _got="$(baseline_of "$_x" "$_t")"
  [ "$_got" = "$ALL_KEYS" ] \
    || fail "R2: an undetected fresh target does not pre-check ALL (got '$_got', want '$ALL_KEYS')"
  # Ambiguity (two front-ends' markers at once) is a MISS, so it lands here too.
  _got="$(baseline_of "$_x" "$_t" CLAUDECODE=1 OPENCODE=1)"
  [ "$_got" = "$ALL_KEYS" ] \
    || fail "R2: competing markers on a fresh target did not fall back to ALL (got '$_got')"
  return 0
}

# ── R3 — existing install + persisted selection ⇒ that selection ─────────────
# Detection must not reach an upgrade at all: the marker here (claude) is deliberately NOT
# the persisted key (gemini), so a baseline that consulted detection would be visible.
test_baseline_upgrade_keeps_persisted() {
  _x="$(sandbox f2upg)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=gemini "$_t" >/dev/null 2>&1 || fail "R3: setup install failed"
  _got="$(baseline_of "$_x" "$_t" CLAUDECODE=1)"
  [ "$_got" = "gemini" ] \
    || fail "R3: an upgrade's baseline is not its persisted selection (got '$_got')"
  # …and it is the SAME with detection absent — the persisted set is the only input.
  _plain="$(baseline_of "$_x" "$_t")"
  [ "$_plain" = "$_got" ] \
    || fail "R3: an upgrade's baseline changed with the marker set ('$_plain' vs '$_got')"
  return 0
}

# ── R5 — no TTY + no override ⇒ ALL, exactly as before this feature ──────────
# CI back-compat is non-negotiable: a scripted run has no human to correct a wrong guess,
# so the narrowing axis is explicit-vs-implicit, and this path never consults the helper.
test_no_tty_default_unchanged() {
  _x="$(sandbox f2nottty)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" CLAUDECODE=1 -- "$_t" >/dev/null 2>&1 \
    || fail "R5: a no-override non-TTY install with a marker set exited non-zero"
  [ "$(tr '\n' ' ' <"$_t/.harness/.agents" | sed 's/[[:space:]]*$//')" = "$ALL_KEYS" ] \
    || fail "R5: a no-override non-TTY run no longer persists ALL ($(tr '\n' ' ' <"$_t/.harness/.agents"))"
  for _f in CLAUDE.md GEMINI.md opencode.json AGENTS.md; do
    [ -f "$_t/$_f" ] || fail "R5: the no-TTY default stopped stamping $_f"
  done
  [ -d "$_t/.agents" ]      || fail "R5: the no-TTY default stopped stamping the antigravity .agents/ tree"
  [ -d "$_x/ch/prompts" ]   || fail "R5: the no-TTY default stopped stamping the global codex prompts"
  # Source: that branch still assigns ALL directly and never reaches precheck_baseline.
  _tail="$(sed -n '/^resolve_agents() {/,/^}/p' "$INST" | sed -n '/^  else$/,/^}/p')"
  printf '%s\n' "$_tail" | grep -qF 'SELECTED="$(normalize_keys "$AGENT_KEYS")"' \
    || fail "R5: the no-TTY/no-override branch no longer assigns ALL directly"
  printf '%s\n' "$_tail" | grep -q 'precheck_baseline\|detect_host' \
    && fail "R5: the no-TTY/no-override branch now consults detection"
  return 0
}

# ── R8 — confirming the narrowed fresh baseline removes nothing ──────────────
# `--agents=host` is the non-interactive proxy for a human confirming the pre-check: it
# resolves to the same single key. The GLOBAL codex prompts dir is shared across every
# harness target, so the only acceptable outcome is that a narrowed fresh install is
# byte-inert there — including E18-F01's .sdd-pr-loop.owners cross-target ledger.
test_baseline_fresh_removes_nothing() {
  _x="$(sandbox f2freshsafe)"; _t="$_x/t"; mkdir -p "$_t" "$_x/ch/prompts"
  _foreign="$_x/ch/prompts/someone-elses.md"
  printf 'not ours\n' > "$_foreign"
  _ledger="$_x/ch/prompts/.sdd-pr-loop.owners"
  printf '%s\n' "/some/other/target" > "$_ledger"
  _pr="$_x/ch/prompts/sdd-pr-loop.md"
  printf 'another target stamped this\n' > "$_pr"
  cp -R "$_x/ch/prompts" "$_x/prompts.before"
  hrun "$_x" CLAUDECODE=1 -- --agents=host "$_t" >"$_x/out" 2>"$_x/err" \
    || fail "R8: the narrowed fresh install exited non-zero"
  # Byte-identical, file-for-file: nothing deleted, nothing rewritten, nothing added.
  diff -r "$_x/prompts.before" "$_x/ch/prompts" >"$_x/promptsdiff" 2>&1 \
    || fail "R8: the narrowed fresh install changed the shared codex prompts dir: $(command cat "$_x/promptsdiff")"
  grep -qx '/some/other/target' "$_ledger" \
    || fail "R8: another target's .sdd-pr-loop.owners claim was dropped"
  # And it removed no front-end glue in the target: the removal path never ran.
  printf '%s\n' "$(command cat "$_x/err")" | grep -qi 'removing' \
    && fail "R8: a fresh narrowed install reported a glue removal"
  [ -f "$_t/CLAUDE.md" ] || fail "R8: the narrowed install did not stamp the host's own glue"
  return 0
}

# ── R9 — an existing install's resolution is independent of every marker ─────
# NOTE on the shape of this check: a no-override non-TTY re-run resolves to ALL by R5, so
# "unchanged bytes" is NOT the invariant (that path widens a narrow install today, and
# this feature does not touch it). The invariant R9 states is MARKER-INDEPENDENCE, so two
# identical installs are re-run — one inside a detected host, one not — and compared to
# each other. A stamp-blind precheck_baseline, or a detection branch leaking into the
# no-override path, makes them differ.
test_existing_install_never_narrows() {
  _x="$(sandbox f2narrow)"; _m="$_x/marked"; _p="$_x/plain"; mkdir -p "$_m" "$_p"
  for _d in "$_m" "$_p"; do
    hrun "$_x" -- --agents=claude,gemini "$_d" >/dev/null 2>&1 || fail "R9: setup install failed"
  done
  hrun "$_x" CLAUDECODE=1 -- "$_m" >/dev/null 2>&1 || fail "R9: the marked re-run exited non-zero"
  hrun "$_x" -- "$_p" >/dev/null 2>&1               || fail "R9: the unmarked re-run exited non-zero"
  [ "$(command cat "$_m/.harness/.agents")" = "$(command cat "$_p/.harness/.agents")" ] \
    || fail "R9: a marker changed what a no-override re-run resolved ($(tr '\n' ' ' <"$_m/.harness/.agents") vs $(tr '\n' ' ' <"$_p/.harness/.agents"))"
  # Nothing was NARROWED away either: the previously selected glue is still there.
  [ -f "$_m/GEMINI.md" ] || fail "R9: a no-override re-run inside Claude Code deleted GEMINI.md"
  [ -f "$_m/CLAUDE.md" ] || fail "R9: a no-override re-run deleted CLAUDE.md"
  # The PRE-CHECK side of the same rule: the baseline offered for an existing install is
  # the same with and without a marker.
  _bm="$(baseline_of "$_x" "$_m" CLAUDECODE=1)"; _bp="$(baseline_of "$_x" "$_m")"
  [ "$_bm" = "$_bp" ] \
    || fail "R9: an existing install's baseline depends on a marker ('$_bm' vs '$_bp')"
  return 0
}

# ── R10 — docs/INSTALL.md + the installer header state the new default ───────
# Scoped to the section body, so a stray mention of a word elsewhere in a 400-line doc
# cannot satisfy the check, and phrased as SUBSTANCE (the three cases the default has),
# not as a keyword hunt.
test_docs_document_fresh_default() {
  _doc="$SRC/docs/INSTALL.md"
  _sec="$(awk '/^### The fresh-install default/{f=1;next} /^#{2,3} /{f=0} f' "$_doc")"
  [ -n "$_sec" ] \
    || fail "R10: docs/INSTALL.md has no '### The fresh-install default' section"
  printf '%s\n' "$_sec" | grep -qi 'interactive' \
    || fail "R10: the fresh-install default section does not say it applies to an interactive install"
  printf '%s\n' "$_sec" | grep -qi 'no existing install\|first install\|fresh install' \
    || fail "R10: the section does not scope the new default to a target with no existing install"
  printf '%s\n' "$_sec" | grep -qi 'pre-check' \
    || fail "R10: the section does not say the detected host is PRE-CHECKED (a default, not a restriction)"
  printf '%s\n' "$_sec" | grep -qi 'upgrade' \
    || fail "R10: the section does not state the upgrade exception"
  printf '%s\n' "$_sec" | grep -qF '.harness/.agents' \
    || fail "R10: the section does not name .harness/.agents as what an upgrade keeps"
  printf '%s\n' "$_sec" | grep -qi 'undetected' \
    || fail "R10: the section does not state that an undetected host still pre-checks everything"
  # The installer header no longer claims the old default.
  _hdr="$(sed -n '1,60p' "$INST")"
  printf '%s\n' "$_hdr" | grep -qF 'ALL on a fresh install' \
    && fail "R10: the harness-install.sh header still claims the interactive path pre-checks ALL on a fresh install"
  printf '%s\n' "$_hdr" | grep -qi 'pre-check' \
    || fail "R10: the harness-install.sh header no longer describes the interactive pre-check at all"
  # R10 is about the file's own description of the default, and the header is not the only
  # place that gives it. The two docblocks BELOW that describe the same decision are held
  # to the same standard, scoped to the block so unrelated prose can neither satisfy nor
  # break the check. (Deliberately NOT done: a file-wide ban on the phrase "ALL on a fresh
  # install". That sentence is TRUE of the no-TTY branch, so a file-wide ban would fire on
  # a correct future comment about it — brittle, for no extra catch.)
  #
  # (a) resolve_agents' resolution-order block is what a maintainer reads before editing
  #     the branch, so it must describe the CURRENT pre-check, not the one F02 replaced.
  #     Positive assertions: an accurate description cannot omit these.
  _ra="$(comment_block_above 'resolve_agents() {')"
  [ -n "$_ra" ] || fail "R10: no comment block was found above resolve_agents()"
  printf '%s\n' "$_ra" | grep -qi 'detected host\|detect_host' \
    || fail "R10: resolve_agents' resolution-order block does not mention the detected host — it still describes the pre-F02 pre-check"
  printf '%s\n' "$_ra" | grep -qi 'no existing install' \
    || fail "R10: resolve_agents' resolution-order block does not scope the new pre-check to a target with no existing install"
  printf '%s\n' "$_ra" | grep -qF 'precheck_baseline' \
    || fail "R10: resolve_agents' resolution-order block no longer names the helper the picker seeds from"
  # (b) host_fallback_set's docblock used to justify keeping `baseline=` off
  #     precheck_baseline and to claim two callers. Both became false in E19-F02, and the
  #     first read as a standing instruction to revert the feature. The caller claim is
  #     pinned to the REAL count, so a future feature that re-adds a caller trips this
  #     first and updates both together.
  _hfs_calls="$(grep -c '^[^#]*host_fallback_set "' "$INST" || :)"
  [ "$_hfs_calls" = "1" ] \
    || fail "R10: host_fallback_set has $_hfs_calls non-comment call sites, expected exactly 1 (resolve_agents' undetected host arm)"
  _hfs="$(comment_block_above 'host_fallback_set() {')"
  [ -n "$_hfs" ] || fail "R10: no comment block was found above host_fallback_set()"
  printf '%s\n' "$_hfs" | grep -qiE 'two callers|both call sites' \
    && fail "R10: the host_fallback_set docblock still claims two callers — --print-agents stopped calling it in E19-F02"
  printf '%s\n' "$_hfs" | grep -qiF 'not precheck_baseline' \
    && fail "R10: the host_fallback_set docblock still instructs a maintainer to keep baseline= off precheck_baseline — that is the change this feature exists to make"
  return 0
}

# ── R11 — docs/INSTALL.md documents the re-run re-toggle path ────────────────
# This fact shipped only inside a source header comment; it is the first question the new
# default provokes, so the doc must carry the command AND the fact that a re-run removes.
test_docs_document_retoggle_path() {
  _doc="$SRC/docs/INSTALL.md"
  _sec="$(awk '/^### Changing the selection later/{f=1;next} /^#{2,3} /{f=0} f' "$_doc")"
  [ -n "$_sec" ] \
    || fail "R11: docs/INSTALL.md has no '### Changing the selection later' section"
  printf '%s\n' "$_sec" | grep -qF './harness-install.sh' \
    || fail "R11: the re-toggle section carries no copy-pasteable installer command"
  printf '%s\n' "$_sec" | grep -qF '.harness/.agents' \
    || fail "R11: the re-toggle section does not name .harness/.agents as the pre-checked source"
  printf '%s\n' "$_sec" | grep -qi 'remove\|deselect' \
    || fail "R11: the re-toggle section does not say a re-run also applies REMOVALS"
  printf '%s\n' "$_sec" | grep -qi 'add' \
    || fail "R11: the re-toggle section does not say a re-run applies additions"
  # It must SHIP, not merely exist in the source tree (the installed copy is what a user
  # of the harness reads).
  _x="$(sandbox f2docs)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" CLAUDECODE=1 -- --agents=host "$_t" >/dev/null 2>&1 || fail "R11: install failed"
  grep -qF 'Changing the selection later' "$_t/.harness/docs/INSTALL.md" \
    || fail "R11: the installed docs/INSTALL.md does not carry the re-toggle section"
  return 0
}

test_host_single_marker
test_host_empty_marker_is_absent
test_host_no_marker_undetected
pass "detection: one present marker resolves one key; empty/absent markers do not (R1, R2, R3, R4, R7)"
test_host_ambiguous_is_undetected
pass "two competing front-end markers ⇒ undetected + a stderr diagnostic naming both (R5)"
test_host_forbidden_markers
pass "no ambient config/credential variable acts as a marker, in the table or at runtime (R6)"
test_host_marker_rows_documented
pass "every shipped marker VARIABLE is recorded, with a CLI version, in its own key's provenance entry (R8)"
test_host_env_declaration_wins
test_host_env_declaration_invalid_warns
pass "HARNESS_HOST_AGENT declares the host; an invalid value warns and continues (R9, R10)"
test_print_agents_contract
pass "--print-agents prints exactly two lines, writes nothing, exits 0 (R11, R23)"
test_print_agents_umbrella_rejected
pass "--print-agents --umbrella exits non-zero and writes nothing (R24)"
test_host_mode_stamps_detected_only
pass "--agents=host with a detected host stamps that front-end only (R12)"
test_host_undetected_fresh_is_all
pass "undetected host on a target with no existing install ⇒ ALL, as today (R13)"
test_host_undetected_upgrade_keeps_selection
pass "undetected host on an existing install keeps its selection, never widens (R14)"
test_host_undetected_orphan_agents_is_all
pass "an orphan .harness/.agents with no version stamp is not an install ⇒ ALL (R13, R14)"
test_host_mode_env_and_upgrade
pass "HARNESS_AGENTS=host matches --agents=host, and repeats cleanly on an upgrade (R15)"
test_host_mixed_token_rejected
pass "'host' mixed with any other token is rejected and writes nothing (R16)"
test_host_not_a_registry_key
pass "'host' is not an AGENT_KEYS member and is never persisted (R17, R18)"
test_prior_agents_unchanged
pass "PRIOR_AGENTS keeps its legacy codex exclusion; no cross-target prompt is reclaimed (R19, F02 R7)"
test_host_fresh_removes_nothing
pass "a fresh host install leaves foreign global prompts and the owners ledger untouched (R20)"
test_host_upgrade_removal_respects_pristine
pass "a host upgrade reclaims pristine global prompts and preserves a hand-edited one (R21)"
test_additive_no_host_unchanged
pass "a run that never names 'host' behaves exactly as before this feature (R22)"
test_host_reports_resolution
pass "the host branch prints one report line naming the key or the applied fallback (R25)"
test_baseline_single_helper
test_print_agents_matches_host_install
pass "baseline= and the undetected fallback share one helper, so the preview matches the install (R26)"
test_docs_document_host_mode
pass "INSTALL.md, README.md, the installer header and manifest.txt document the host mode (R27)"
test_suite_wired_into_verification
test_suite_hygiene
pass "the suite is wired into verification.test_command and keeps its env discipline (R28, R29, F02 R12)"
test_init_still_green
pass "no new dependency; an installed target still passes init.sh (R30)"
test_version_and_changelog
pass "VERSION carries the MINOR bump and CHANGELOG.md the matching entry (R31, F02 R13)"

# ── E19-F02 — the fresh-install pre-check baseline ────────────────────────────
# (F02 R6 is asserted inside test_baseline_single_helper, F02 R7 inside
#  test_prior_agents_unchanged and F02 R12 inside test_suite_hygiene — the F01 checks that
#  already own those source properties; extending them beats a second copy that could
#  disagree.)
[ -n "$ALL_KEYS" ] && [ "$(printf '%s\n' "$ALL_KEYS" | wc -w | tr -d ' ')" -ge 5 ] \
  || fail "F02: ALL_KEYS was not derived from AGENT_KEYS ('$ALL_KEYS') — the baseline cases would compare against nothing"
test_baseline_legacy_upgrade_is_all
pass "F02 baseline_legacy_upgrade_is_all: a pre-E08 upgrade pre-checks ALL, detection ignored (F02 R4, R9)"
test_baseline_fresh_is_host_only
pass "F02 baseline_fresh_is_host_only: a fresh install pre-checks the detected host ALONE (F02 R1)"
test_baseline_fresh_undetected_is_all
pass "F02 baseline_fresh_undetected_is_all: an undetected fresh install still pre-checks ALL (F02 R2)"
test_baseline_upgrade_keeps_persisted
pass "F02 baseline_upgrade_keeps_persisted: an upgrade pre-checks its persisted selection (F02 R3)"
test_no_tty_default_unchanged
pass "F02 no_tty_default_unchanged: no TTY + no override still stamps ALL (F02 R5)"
test_baseline_fresh_removes_nothing
pass "F02 baseline_fresh_removes_nothing: the narrowed fresh install is byte-inert in the shared codex prompts (F02 R8)"
test_existing_install_never_narrows
pass "F02 existing_install_never_narrows: an existing install's resolution ignores every marker (F02 R9)"
test_docs_document_fresh_default
pass "F02 docs_document_fresh_default: INSTALL.md and the installer header state the new default (F02 R10)"
test_docs_document_retoggle_path
pass "F02 docs_document_retoggle_path: INSTALL.md documents the re-run re-toggle path (F02 R11)"

echo "All agents-host tests passed."
