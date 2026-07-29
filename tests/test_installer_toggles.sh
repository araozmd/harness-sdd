#!/bin/sh
# test_installer_toggles.sh — the installer's follow-up questions:
#   E20-F01, the SECOND question — `execution.builder.backend`
#   E20-F02, the THIRD question  — `pr_loop.enabled`
#
# Covers R1–R15 of specs/epics/E20-workflow-toggles/F01-builder-backend-prompt/ and
# R1–R15 of specs/epics/E20-workflow-toggles/F02-pr-loop-prompt/. The two features share
# one seam and one set of environment rules, so they share one suite; every check below
# names the feature its R-ids belong to.
#
# WHY THIS IS A SEPARATE SUITE: tests/test_install.sh must stay out of this feature's
# diff (R14), and this feature's checks need their own environment discipline.
#
# HOW THE INTERACTIVE PATH IS TESTED. A POSIX suite cannot supply a pty, so the prompt
# cannot be typed into. Nothing meaningful hides behind that, in three layers:
#   1. The DECISION is a pure function and this suite calls it for real — the extracted
#      `builder_backend_answer` is sourced and its whole truth table exercised
#      (answer_mapping_unit). Every branch of the prompt's semantics is covered here.
#   2. The WRITE PATH is driven end to end by the override, which feeds the SAME resolver
#      and the SAME writer the prompt feeds — so the risky half (a value-preserving,
#      idempotent config write) is exercised on real files with real byte comparisons.
#   3. The GATING is asserted in the negative: a non-TTY run asks nothing and changes
#      nothing; an override suppresses the prompt.
# The residue is `read -r` and the menu printfs. A STRUCTURAL check (prompt_gating (c))
# keeps them residue: if decision logic migrates into builder_backend_prompt, where no
# suite can reach it, that check fails.
#
# ENVIRONMENT DISCIPLINE (R14). Every installer invocation goes through `hrun`, the ONE
# place this suite names the installer, which runs it under `env -i` with nothing but
# PATH, a sandboxed HOME and a sandboxed CODEX_HOME (never the developer's real ~/.codex,
# which the `codex` front-end writes global prompts into). No check freezes the exact
# VERSION string, compares against a hard-coded previous version, or diffs any file
# against `main` — all three are permanent-suite anti-patterns.
#
# Zero dependencies; self-cleaning temp dir.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-toggles)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# hrun <sandbox-dir> [VAR=VALUE …] -- <installer args…>
#
# The single gateway to the installer (pattern from tests/test_agents_host.sh). Creates
# <sandbox-dir>/home and <sandbox-dir>/ch, then runs the installer under `env -i` with
# PATH + those two sandboxes + exactly the named variables. Arguments are rebuilt
# positionally (rotate-through-"$@") rather than accumulated into a string, so a value
# containing spaces survives intact. Stdin is NOT redirected here: every caller that
# cares redirects it itself (`</dev/null`), and no test runner gives this suite a TTY —
# but see non_interactive_is_inert, which redirects explicitly rather than relying on it.
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

# cfg_backend <config> — read execution.builder.backend back INDEPENDENTLY.
#
# Deliberately NOT the installer's own _cfg_execution_builder_value: a reader that shares
# code with the writer can agree with it while both are wrong. This is the only place the
# suite parses the value, and it is a plain scoped awk.
cfg_backend() {
  awk '
    /^execution:[[:space:]]*(#.*)?$/ { e=1; next }
    e && /^[^[:space:]#]/ { e=0 }
    e && /^[[:space:]]+backend:/ {
      sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "")
      print; exit
    }
  ' "$1"
}

# cfg_pr_loop <config> — read pr_loop.enabled back INDEPENDENTLY (E20-F02).
#
# Deliberately NOT the installer's own _cfg_pr_loop_value, for the same reason cfg_backend
# is not _cfg_execution_builder_value: a reader that shares code with the writer can agree
# with it while both are wrong. Section-scoped, so a same-named `enabled:` under ANOTHER
# top-level section (the shipped config already has one under `telemetry:`) is never read.
cfg_pr_loop() {
  awk '
    /^pr_loop:[[:space:]]*(#.*)?$/ { p=1; next }
    p && /^[^[:space:]#]/ { p=0 }
    p && /^[[:space:]]+enabled:/ {
      sub(/^[[:space:]]*[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "")
      print; exit
    }
  ' "$1"
}

# prl_block <config> — the top-level `pr_loop:` block WITH its comment header, from the
# stable anchor to EOF. `pr_loop:` is the LAST block in the source config and migration can
# only append at EOF, so the same span captures both shapes — the span
# tests/test_pr_loop.sh's R17 already uses for the same convergence rule.
prl_block() { awk '/^# Codex PR review loop/,0' "$1"; }

# strip_prl <config> — remove the whole top-level `pr_loop:` block (comment header
# included), producing the shape of a config that predates it.
strip_prl() {
  awk '/^# Codex PR review loop/{exit} {print}' "$1" > "$1.strip" && mv "$1.strip" "$1"
}

# exec_block <config> — the top-level `execution:` block WITH its comment header, from the
# stable header anchor through the block's last key. Bounded at both ends on purpose: in a
# SEEDED config the block sits mid-file, in a MIGRATED one it runs to EOF, and the
# convergence check has to compare the same span in both.
exec_block() {
  awk '
    /^# Builder execution backend\./ { p=1 }
    p { print }
    p && /^[[:space:]]+delegate_cmd:/ { exit }
  ' "$1"
}

# The installer source, read once for the source-level checks.
INST="$SRC/harness-install.sh"

# fn_body <name> — the shell body of <name>, extracted by the documented sed range.
fn_body() { sed -n "/^$1() {\$/,/^}\$/p" "$INST"; }

# The stable, greppable markers this feature's contract is written in.
PROMPT_MARKER='Which builder backend'
REPORT_MARKER='builder backend:'
WARN_MARKER='delegate_cmd is empty'

# …and E20-F02's. PRL_REPORT_MARKER carries the colon deliberately: the §7b reclamation
# announcement says "pr_loop.enabled is not true" on STDERR, and the report line must be
# countable on STDOUT without colliding with it.
PRL_PROMPT_MARKER='Enable the Codex PR review loop'
PRL_REPORT_MARKER='pr_loop.enabled: '
PRL_ENV_WARN_MARKER='PER-RUN override'
PRL_RECLAIM_MARKER='pr_loop.enabled is not true'

# ── R2 — the answer→value mapping is a pure, extractable function ─────────────
# This is layer 1: the ONE place the prompt's semantics live, unit-tested for real.
test_answer_mapping_unit() {
  _x="$(sandbox answermap)"
  # The extraction is itself the R2 shape assertion: the opening line must be exactly
  # `builder_backend_answer() {` and the FIRST line that is exactly `}` must be the
  # function's own closer, or this range yields something that will not source.
  sed -n '/^builder_backend_answer() {$/,/^}$/p' "$INST" > "$_x/fn.sh"
  [ -s "$_x/fn.sh" ] \
    || fail "R2: the documented sed range extracted NOTHING — builder_backend_answer is missing or its opening line is not exactly 'builder_backend_answer() {'"
  grep -qx 'builder_backend_answer() {' "$_x/fn.sh" \
    || fail "R2: the extracted block does not start at the function definition"
  grep -qx '}' "$_x/fn.sh" \
    || fail "R2: the extracted block has no closing '}' line — the range is unterminated"
  # Sourceable STANDALONE: no helper, no global, no installer preamble.
  ( set -eu; . "$_x/fn.sh" ) \
    || fail "R2: the extracted definition is not sourceable on its own"
  . "$_x/fn.sh"
  command -v builder_backend_answer >/dev/null 2>&1 \
    || fail "R2: sourcing the extracted block defined no builder_backend_answer"

  # The full truth table. `"" delegate ⇒ delegate` is the load-bearing row: Enter follows
  # the CURRENT value, never a hard-coded default — it is what catches an implementation
  # where pressing Enter silently resets a delegating install to in-session.
  for _case in \
    '|in-session|in-session' \
    '|delegate|delegate' \
    '1|delegate|in-session' \
    '1|in-session|in-session' \
    'in-session|delegate|in-session' \
    '2|in-session|delegate' \
    '2|delegate|delegate' \
    'delegate|in-session|delegate' \
    'banana|delegate|delegate' \
    'banana|in-session|in-session' \
    '3|delegate|delegate' \
    ' |in-session|in-session'
  do
    _ans="${_case%%|*}"; _rest="${_case#*|}"
    _cur="${_rest%%|*}"; _want="${_rest#*|}"
    _got="$(builder_backend_answer "$_ans" "$_cur")"
    [ "$_got" = "$_want" ] \
      || fail "R2: builder_backend_answer '$_ans' '$_cur' printed '$_got', expected '$_want'"
  done

  # Side-effect-free: nothing on stderr, no file created, nothing but the value on stdout.
  mkdir -p "$_x/pure"
  _before="$(find "$_x/pure" | sort)"
  ( cd "$_x/pure" && builder_backend_answer 2 in-session ) >"$_x/pure.out" 2>"$_x/pure.err"
  [ -s "$_x/pure.err" ] \
    && fail "R2: builder_backend_answer wrote to stderr: $(command cat "$_x/pure.err")"
  [ "$(wc -l <"$_x/pure.out" | tr -d ' ')" = "1" ] \
    || fail "R2: builder_backend_answer printed $(wc -l <"$_x/pure.out") lines, expected exactly 1"
  [ "$(find "$_x/pure" | sort)" = "$_before" ] \
    || fail "R2: builder_backend_answer created a file — it must be side-effect-free"
  return 0
}

# ── R1 — the prompt is asked ONLY on an interactive TTY with no override ──────
test_prompt_gating() {
  _x="$(sandbox gating)"; _t="$_x/t"; mkdir -p "$_t"

  # (a) non-TTY, no override: nothing asked, exit 0.
  hrun "$_x" -- --agents=claude "$_t" >"$_x/a.out" 2>"$_x/a.err" </dev/null \
    || fail "R1: a non-TTY install exited non-zero"
  command cat "$_x/a.out" "$_x/a.err" | grep -qF "$PROMPT_MARKER" \
    && fail "R1: the follow-up prompt was asked on a NON-INTERACTIVE run"

  # (b) an override suppresses the prompt too.
  hrun "$_x" -- --agents=claude --builder-backend=delegate "$_t" >"$_x/b.out" 2>"$_x/b.err" </dev/null \
    || fail "R1: an override install exited non-zero"
  command cat "$_x/b.out" "$_x/b.err" | grep -qF "$PROMPT_MARKER" \
    && fail "R1: the follow-up prompt was asked despite an explicit override"

  # (c) source: the prompt is reachable only behind `[ -t 0 ]`, and only from the resolver.
  fn_body resolve_builder_backend > "$_x/resolver.sh"
  [ -s "$_x/resolver.sh" ] || fail "R1: resolve_builder_backend not found"
  grep -q '\[ -t 0 \]' "$_x/resolver.sh" \
    || fail "R1: resolve_builder_backend has no '[ -t 0 ]' interactive guard"
  _tty_ln="$(grep -n '\[ -t 0 \]' "$_x/resolver.sh" | head -n 1 | cut -d: -f1)"
  _ask_ln="$(grep -n 'builder_backend_prompt' "$_x/resolver.sh" | head -n 1 | cut -d: -f1)"
  [ -n "$_ask_ln" ] || fail "R1: resolve_builder_backend never calls builder_backend_prompt"
  [ "$_ask_ln" -gt "$_tty_ln" ] \
    || fail "R1: builder_backend_prompt is called BEFORE the '[ -t 0 ]' guard"
  # The prompt has exactly one caller in the whole installer, and it is that guarded one.
  _callers="$(grep -c '[^_]builder_backend_prompt "' "$INST" || :)"
  [ "$_callers" = "1" ] \
    || fail "R1: builder_backend_prompt is invoked from $_callers sites — the TTY guard is not the only door"

  # (c2) the resolver is asked AFTER the front-end picker, so both questions are back to
  #      back and neither reorders the other.
  _ra="$(grep -n '^  resolve_agents "\$TARGET"$' "$INST" | head -n 1 | cut -d: -f1)"
  _rb="$(grep -n '^  resolve_builder_backend "\$TARGET"$' "$INST" | head -n 1 | cut -d: -f1)"
  [ -n "$_ra" ] || fail "R1: install_one no longer calls resolve_agents \"\$TARGET\""
  [ -n "$_rb" ] || fail "R1: install_one does not call resolve_builder_backend \"\$TARGET\""
  [ "$_rb" -gt "$_ra" ] \
    || fail "R1: resolve_builder_backend is called BEFORE resolve_agents — the picker must come first"

  # (c3) STRUCTURAL: builder_backend_prompt is menu + read + one delegation, nothing else.
  # This is what keeps layer 1 authoritative — decision logic cannot hide where no suite
  # can reach it. Mutating the prompt to decide anything itself fails right here.
  fn_body builder_backend_prompt > "$_x/prompt.sh"
  [ -s "$_x/prompt.sh" ] || fail "R1: builder_backend_prompt not found"
  _body="$(sed '1d;$d' "$_x/prompt.sh")"
  printf '%s\n' "$_body" | grep -q 'read -r' \
    || fail "R1: builder_backend_prompt does not read a line"
  [ "$(printf '%s\n' "$_body" | grep -c 'read ')" = "1" ] \
    || fail "R1: builder_backend_prompt reads more than once — it must not loop or re-ask"
  [ "$(printf '%s\n' "$_body" | grep -c 'builder_backend_answer')" = "1" ] \
    || fail "R1: builder_backend_prompt does not delegate to builder_backend_answer exactly once"
  for _forbidden in 'case ' 'if ' 'elif ' 'while ' 'for ' '_cfg_' 'set_builder_backend' 'BUILDER_BACKEND' '>>' 'mv '; do
    printf '%s\n' "$_body" | grep -qF "$_forbidden" \
      && fail "R1: builder_backend_prompt contains '$_forbidden' — decision logic and side effects belong in builder_backend_answer / the resolver, where they are testable"
  done
  return 0
}

# ── R3 — the front-end picker is untouched ───────────────────────────────────
test_picker_unaffected() {
  _x="$(sandbox picker)"
  _a="$_x/with"; _b="$_x/without"; mkdir -p "$_a" "$_b"
  hrun "$_x" -- --agents=claude,gemini --builder-backend=delegate "$_a" >/dev/null 2>&1 </dev/null \
    || fail "R3: install with a backend override exited non-zero"
  hrun "$_x" -- --agents=claude,gemini "$_b" >/dev/null 2>&1 </dev/null \
    || fail "R3: install without a backend override exited non-zero"
  cmp -s "$_a/.harness/.agents" "$_b/.harness/.agents" \
    || fail "R3: the resolved front-end set DIFFERS with and without this feature's inputs"
  [ "$(tr '\n' ' ' <"$_a/.harness/.agents")" = "claude gemini " ] \
    || fail "R3: the front-end selection is not exactly claude+gemini ($(tr '\n' ' ' <"$_a/.harness/.agents"))"

  # Source: no backend vocabulary anywhere in the picker or its ladder.
  for _fn in tui_select toggle_select tui_capable normalize_keys validate_csv; do
    fn_body "$_fn" > "$_x/$_fn.sh"
    [ -s "$_x/$_fn.sh" ] || fail "R3: picker function $_fn is missing"
    grep -qiE 'backend|BUILDER_BACKEND' "$_x/$_fn.sh" \
      && fail "R3: $_fn gained builder-backend behavior — the picker must not change"
  done
  _keys="$(sed -n 's/^AGENT_KEYS="\(.*\)"$/\1/p' "$INST")"
  [ -n "$_keys" ] || fail "R3: AGENT_KEYS is no longer a single quoted line"
  [ "$(printf '%s\n' "$_keys" | wc -w | tr -d ' ')" = "5" ] \
    || fail "R3: AGENT_KEYS holds $(printf '%s\n' "$_keys" | wc -w) keys, expected the 5 front-ends ('$_keys')"
  for _k in claude gemini opencode antigravity codex; do
    printf '%s\n' "$_keys" | grep -qw "$_k" || fail "R3: AGENT_KEYS lost the front-end key '$_k'"
  done
  printf '%s\n' "$_keys" | grep -qiE 'backend|builder' \
    && fail "R3: an enum row was added to AGENT_KEYS — the backend is NOT a picker row"
  return 0
}

# ── R4 — flag/env override: no prompt, flag beats env, empty ⇒ no override ────
test_override_precedence() {
  _x="$(sandbox precedence)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R4: setup install exited non-zero"
  _c="$_t/.harness/harness.config.yaml"

  # (a) the environment variable alone resolves the value.
  hrun "$_x" HARNESS_BUILDER_BACKEND=delegate -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R4: HARNESS_BUILDER_BACKEND run exited non-zero"
  [ "$(cfg_backend "$_c")" = "delegate" ] \
    || fail "R4: HARNESS_BUILDER_BACKEND=delegate did not resolve (config reads '$(cfg_backend "$_c")')"

  # (b) the flag WINS over the environment variable.
  hrun "$_x" HARNESS_BUILDER_BACKEND=delegate -- --agents=claude --builder-backend=in-session "$_t" \
    >/dev/null 2>&1 </dev/null || fail "R4: flag-over-env run exited non-zero"
  [ "$(cfg_backend "$_c")" = "in-session" ] \
    || fail "R4: --builder-backend did not beat HARNESS_BUILDER_BACKEND (config reads '$(cfg_backend "$_c")')"

  # (c) an EMPTY value means "no override" — same contract as --agents=. On a non-TTY run
  #     that is a total no-op, byte for byte.
  cp "$_c" "$_x/before.yaml"
  hrun "$_x" -- --agents=claude --builder-backend= "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R4: --builder-backend= (empty) exited non-zero"
  [ "$(cfg_backend "$_c")" = "in-session" ] \
    || fail "R4: an empty override changed the value to '$(cfg_backend "$_c")'"
  cmp -s "$_x/before.yaml" "$_c" \
    || fail "R4: an empty override rewrote harness.config.yaml"
  # …and the same for an empty environment variable.
  hrun "$_x" HARNESS_BUILDER_BACKEND= -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R4: an empty HARNESS_BUILDER_BACKEND exited non-zero"
  cmp -s "$_x/before.yaml" "$_c" \
    || fail "R4: an empty HARNESS_BUILDER_BACKEND rewrote harness.config.yaml"

  # (d) the separated form --builder-backend <value> works too.
  hrun "$_x" -- --agents=claude --builder-backend delegate "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R4: the separated '--builder-backend <value>' form exited non-zero"
  [ "$(cfg_backend "$_c")" = "delegate" ] \
    || fail "R4: '--builder-backend delegate' did not resolve (config reads '$(cfg_backend "$_c")')"
  return 0
}

# ── R5 — an illegal override aborts non-zero BEFORE touching the target ──────
test_illegal_override_aborts() {
  _x="$(sandbox illegal)"

  _t="$_x/flag"; mkdir -p "$_t"
  _before="$(find "$_t" | sort)"
  if hrun "$_x" -- --agents=claude --builder-backend=turbo "$_t" >"$_x/f.out" 2>"$_x/f.err" </dev/null; then
    fail "R5: --builder-backend=turbo exited ZERO"
  fi
  grep -qF 'turbo' "$_x/f.err"      || fail "R5: the abort message does not name the offending value"
  grep -qF 'in-session' "$_x/f.err" || fail "R5: the abort message does not name the legal value in-session"
  grep -qF 'delegate' "$_x/f.err"   || fail "R5: the abort message does not name the legal value delegate"
  [ "$(find "$_t" | sort)" = "$_before" ] \
    || fail "R5: the illegal run created or modified something in the target"
  [ -d "$_t/.harness" ] && fail "R5: the illegal run created .harness/ in the target"

  _e="$_x/env"; mkdir -p "$_e"
  _before="$(find "$_e" | sort)"
  if hrun "$_x" HARNESS_BUILDER_BACKEND=turbo -- --agents=claude "$_e" >"$_x/e.out" 2>"$_x/e.err" </dev/null; then
    fail "R5: HARNESS_BUILDER_BACKEND=turbo exited ZERO"
  fi
  grep -qF 'turbo' "$_x/e.err" || fail "R5: the env abort message does not name the offending value"
  [ "$(find "$_e" | sort)" = "$_before" ] \
    || fail "R5: the illegal env run created or modified something in the target"
  return 0
}

# ── R6 — no TTY + no override ⇒ nothing asked, nothing changed ───────────────
# The CI back-compat guard, and the strongest single check in this suite.
test_non_interactive_is_inert() {
  _x="$(sandbox inert)"; _t="$_x/t"; mkdir -p "$_t"

  # (a) a fresh non-TTY install with no override seeds the default.
  hrun "$_x" -- --agents=claude "$_t" >"$_x/a.out" 2>"$_x/a.err" </dev/null \
    || fail "R6: fresh install exited non-zero"
  _c="$_t/.harness/harness.config.yaml"
  [ "$(cfg_backend "$_c")" = "in-session" ] \
    || fail "R6: a fresh non-TTY install did not seed in-session (reads '$(cfg_backend "$_c")')"

  # (b) hand-edit to `delegate` + a distinctive comment, then re-run with no override and
  #     no TTY: byte-identical. The setup uses an INSTALLED config, whose `execution:`
  #     block is already present, so R9's migration has nothing to append and cmp is a
  #     fair test of THIS feature's writer alone.
  awk '
    /^execution:[[:space:]]*(#.*)?$/ { e=1 }
    e && /^[[:space:]]+backend:[[:space:]]*in-session/ { print "    backend: delegate"; e=0; next }
    { print }
  ' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  printf '\n# DISTINCTIVE-HUMAN-NOTE-E20F01: do not lose me\n' >> "$_c"
  [ "$(cfg_backend "$_c")" = "delegate" ] || fail "R6: setup failed — hand-edit to delegate did not take"
  cp "$_c" "$_x/before.yaml"

  hrun "$_x" -- --agents=claude "$_t" >"$_x/b.out" 2>"$_x/b.err" </dev/null \
    || fail "R6: the no-override upgrade exited non-zero"
  cmp -s "$_x/before.yaml" "$_c" \
    || fail "R6: a non-TTY run with NO override changed harness.config.yaml: $(diff "$_x/before.yaml" "$_c" | head -n 6)"
  command cat "$_x/b.out" "$_x/b.err" | grep -qF "$PROMPT_MARKER" \
    && fail "R6: the follow-up prompt was asked on a non-TTY upgrade"
  grep -qF 'DISTINCTIVE-HUMAN-NOTE-E20F01' "$_c" \
    || fail "R6: the hand-added comment was lost"
  return 0
}

# ── R7 — only the one scalar is rewritten ───────────────────────────────────
test_write_preserves_everything_else() {
  _x="$(sandbox preserve)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R7: setup install exited non-zero"
  _c="$_t/.harness/harness.config.yaml"

  # Hand-edit: an unrelated value, an EOF note, and a trailing comment on the very line
  # the writer must touch.
  awk '
    /^[[:space:]]+identity:/ && !i { print "  identity: \"SENTINEL-E20F01\""; i=1; next }
    /^execution:[[:space:]]*(#.*)?$/ { e=1 }
    e && /^[[:space:]]+backend:[[:space:]]*in-session/ { print "    backend: in-session      # KEEP-THIS-TRAILING-COMMENT"; e=0; next }
    { print }
  ' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  printf '\n# HUMAN NOTE E20F01: this line must survive the write\n' >> "$_c"
  grep -qF 'SENTINEL-E20F01' "$_c"           || fail "R7: setup failed — sentinel not written"
  grep -qF 'KEEP-THIS-TRAILING-COMMENT' "$_c" || fail "R7: setup failed — trailing comment not written"
  cp "$_c" "$_x/before.yaml"

  hrun "$_x" -- --agents=claude --builder-backend=delegate "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R7: the writing run exited non-zero"

  [ "$(cfg_backend "$_c")" = "delegate" ] \
    || fail "R7: the value was not written (reads '$(cfg_backend "$_c")')"
  grep -qx '    backend: delegate      # KEEP-THIS-TRAILING-COMMENT' "$_c" \
    || fail "R7: the backend line lost its indentation or its trailing comment: '$(grep -n 'backend: delegate' "$_c" | head -n 1)'"
  grep -qF 'SENTINEL-E20F01' "$_c"  || fail "R7: an unrelated hand-edited value was lost"
  grep -qF 'HUMAN NOTE E20F01' "$_c" || fail "R7: the hand-added EOF comment was lost"

  # EXACTLY one line changed, in both directions.
  diff "$_x/before.yaml" "$_c" > "$_x/d.txt" || :
  _removed="$(grep -c '^< ' "$_x/d.txt" || :)"
  _added="$(grep -c '^> ' "$_x/d.txt" || :)"
  [ "$_removed" = "1" ] && [ "$_added" = "1" ] \
    || fail "R7: the write changed $_removed/$_added lines, expected exactly 1/1: $(command cat "$_x/d.txt")"
  return 0
}

# ── R8 — unchanged value ⇒ byte-identical; same value twice ⇒ idempotent ─────
test_write_is_idempotent() {
  _x="$(sandbox idem)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude --builder-backend=delegate "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R8: setup install exited non-zero"
  _c="$_t/.harness/harness.config.yaml"
  [ "$(cfg_backend "$_c")" = "delegate" ] || fail "R8: setup failed — value is not delegate"

  _i=1
  while [ "$_i" -le 2 ]; do
    cp "$_c" "$_x/pre-$_i.yaml"
    hrun "$_x" -- --agents=claude --builder-backend=delegate "$_t" >/dev/null 2>&1 </dev/null \
      || fail "R8: repeat run $_i exited non-zero"
    cmp -s "$_x/pre-$_i.yaml" "$_c" \
      || fail "R8: re-applying the SAME value rewrote the config (run $_i): $(diff "$_x/pre-$_i.yaml" "$_c" | head -n 6)"
    _i=$((_i + 1))
  done

  _i=1
  while [ "$_i" -le 2 ]; do
    cp "$_c" "$_x/noov-$_i.yaml"
    hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
      || fail "R8: no-override run $_i exited non-zero"
    cmp -s "$_x/noov-$_i.yaml" "$_c" \
      || fail "R8: a no-override non-TTY run rewrote the config (run $_i)"
    _i=$((_i + 1))
  done
  [ "$(cfg_backend "$_c")" = "delegate" ] \
    || fail "R8: the no-override runs silently reset the value to '$(cfg_backend "$_c")'"

  # The writer must be SKIPPED, not re-run with identical bytes. Byte comparison alone
  # cannot tell those apart — an "always rewrite" implementation would satisfy every cmp
  # above — so this asserts the file was not TOUCHED, via a reference marker created
  # immediately before the run. This is the check that makes "skip entirely" falsifiable.
  : > "$_x/marker"
  hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R8: the untouched-run exited non-zero"
  [ -n "$(find "$_c" -newer "$_x/marker" 2>/dev/null)" ] \
    && fail "R8: a no-override run TOUCHED harness.config.yaml — when the value already matches the writer must not run at all"
  : > "$_x/marker2"
  hrun "$_x" -- --agents=claude --builder-backend=delegate "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R8: the same-value override run exited non-zero"
  [ -n "$(find "$_c" -newer "$_x/marker2" 2>/dev/null)" ] \
    && fail "R8: re-applying the SAME value touched harness.config.yaml — the writer must be skipped"
  return 0
}

# ── R9 — migrate_config seeds a missing top-level `execution:` block ─────────
test_migration_seeds_execution_block() {
  _x="$(sandbox migrate)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R9: setup install exited non-zero"
  _c="$_t/.harness/harness.config.yaml"

  # Strip the whole top-level `execution:` block — INCLUDING its comment header, so the
  # fixture really is a config that predates the block rather than one carrying an orphan
  # header. (An orphan header would also give the convergence check below a second, bogus
  # anchor to latch onto.)
  awk '
    /^# Builder execution backend\./ { d=1 }
    d && /^[[:space:]]+delegate_cmd:/ { d=0; next }
    d { next }
    { print }
  ' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  grep -Eq '^execution:' "$_c" && fail "R9: setup failed — the execution: block was not stripped"
  grep -q '^# Builder execution backend\.' "$_c" \
    && fail "R9: setup failed — the block's comment header was left behind"
  cp "$_c" "$_x/stripped.yaml"

  hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R9: the migrating run exited non-zero"
  grep -Eq '^execution:[[:space:]]*(#.*)?$' "$_c" \
    || fail "R9: migrate_config did not append the execution: block"
  [ "$(cfg_backend "$_c")" = "in-session" ] \
    || fail "R9: the migrated block does not carry backend: in-session (reads '$(cfg_backend "$_c")')"
  grep -qE '^[[:space:]]+delegate_cmd:[[:space:]]*""' "$_c" \
    || fail "R9: the migrated block does not carry delegate_cmd: \"\""
  grep -qE '^[[:space:]]+builder:' "$_c" \
    || fail "R9: the migrated block has no builder: mapping"
  # Append-ONLY: every pre-existing line survives byte-for-byte as a prefix.
  _n="$(wc -l < "$_x/stripped.yaml")"
  head -n "$_n" "$_c" > "$_x/head.yaml"
  cmp -s "$_x/stripped.yaml" "$_x/head.yaml" \
    || fail "R9: the migration altered pre-existing config lines — it must be append-only"

  # A second run appends nothing.
  cp "$_c" "$_x/once.yaml"
  hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R9: the second migrating run exited non-zero"
  cmp -s "$_x/once.yaml" "$_c" \
    || fail "R9: a second run appended the execution: block again"
  [ "$(grep -cE '^execution:[[:space:]]*(#.*)?$' "$_c")" = "1" ] \
    || fail "R9: the config carries $(grep -cE '^execution:' "$_c") top-level execution: headers, expected exactly 1"

  # SEEDED == MIGRATED, byte for byte (the convergence rule migrate_config states for its
  # models: and pr_loop: entries, and which E18-F01 spent R17 on for pr_loop). A FRESH
  # install copies the source config verbatim and never migrates; an UPGRADE only migrates.
  # If the two blocks drifted apart, two installs of the same version would document the
  # same values with different comments — invisible until someone diffs them.
  #
  # The BLOCK is compared, not the whole file: the source block sits mid-file while
  # migration can only append at EOF, so positional convergence is impossible by
  # construction. Shape follows tests/test_pr_loop.sh's R17, bounded at both ends because
  # this block — unlike pr_loop's — is not the tail of the source config.
  _u2="$_x/seeded"; mkdir -p "$_u2"
  hrun "$_x" -- --agents=claude "$_u2" >/dev/null 2>&1 </dev/null \
    || fail "R9: the seeded-block install exited non-zero"
  exec_block "$_u2/.harness/harness.config.yaml" > "$_x/blk-seeded.txt"
  exec_block "$_c" > "$_x/blk-migrated.txt"
  [ -s "$_x/blk-seeded.txt" ] \
    || fail "R9: the SEEDED execution: block could not be captured — its comment header anchor is missing from the source harness.config.yaml"
  [ -s "$_x/blk-migrated.txt" ] \
    || fail "R9: the MIGRATED execution: block could not be captured — the migrate_config heredoc carries no matching comment header"
  cmp -s "$_x/blk-seeded.txt" "$_x/blk-migrated.txt" \
    || fail "R9: the migrated execution: block is NOT byte-identical to the seeded one — migrate_config's convergence rule is broken: $(diff "$_x/blk-seeded.txt" "$_x/blk-migrated.txt" | head -n 8)"
  # …and the block a FRESH install receives is the one that documents the new surface.
  # Fresh install is the majority path; shipping it the less discoverable text would
  # invert this feature's whole point.
  for _s in '--builder-backend' 'HARNESS_BUILDER_BACKEND' 'in-session' 'delegate_cmd'; do
    grep -qF -e "$_s" "$_x/blk-seeded.txt" \
      || fail "R9/R13: the execution: block a FRESH install seeds does not mention '$_s' — the config is the file a human actually edits"
  done

  # A config that ALREADY carries the block never gets a second one, even with a trailing
  # comment on the header (the shape every other migration entry tolerates).
  _u="$_x/u"; mkdir -p "$_u"
  hrun "$_x" -- --agents=claude "$_u" >/dev/null 2>&1 </dev/null \
    || fail "R9: untouched-target install exited non-zero"
  _uc="$_u/.harness/harness.config.yaml"
  sed 's/^execution:$/execution:   # my note/' "$_uc" > "$_uc.t" && mv "$_uc.t" "$_uc"
  hrun "$_x" -- --agents=claude "$_u" >/dev/null 2>&1 </dev/null \
    || fail "R9: commented-header run exited non-zero"
  [ "$(grep -cE '^execution:[[:space:]]*(#.*)?$' "$_uc")" = "1" ] \
    || fail "R9: a trailing comment on the execution: header caused a duplicate block"
  return 0
}

# ── R10 — a fresh install with no override seeds in-session ─────────────────
test_fresh_default_unchanged() {
  _x="$(sandbox fresh)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R10: fresh install exited non-zero"
  _c="$_t/.harness/harness.config.yaml"
  [ -f "$_c" ] || fail "R10: the fresh install seeded no harness.config.yaml"
  [ "$(cfg_backend "$_c")" = "in-session" ] \
    || fail "R10: a fresh install seeded backend '$(cfg_backend "$_c")', expected in-session"
  return 0
}

# ── R11 — delegate + empty delegate_cmd ⇒ written AND warned; else no warning ─
# BOTH directions are required: the negative is what makes the positive falsifiable.
test_delegate_without_cmd_warns() {
  _x="$(sandbox delegatewarn)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "R11: setup install exited non-zero"
  _c="$_t/.harness/harness.config.yaml"

  # (a) delegate_cmd is "" — the install SUCCEEDS, writes delegate, and warns.
  hrun "$_x" -- --agents=claude --builder-backend=delegate "$_t" >"$_x/a.out" 2>"$_x/a.err" </dev/null \
    || fail "R11: the delegate install ABORTED — it must warn and proceed"
  [ "$(cfg_backend "$_c")" = "delegate" ] \
    || fail "R11: the chosen value was not written (reads '$(cfg_backend "$_c")') — never silently downgrade"
  command cat "$_x/a.out" "$_x/a.err" > "$_x/a.all"
  grep -qF "$WARN_MARKER" "$_x/a.all" \
    || fail "R11: no warning was printed for delegate with an empty delegate_cmd"
  grep -F "$WARN_MARKER" "$_x/a.all" | grep -qF 'execution.builder.delegate_cmd' \
    || fail "R11: the warning does not name execution.builder.delegate_cmd"
  grep -F "$WARN_MARKER" "$_x/a.all" | grep -qF "$_c" \
    || fail "R11: the warning does not name the config's path"

  # (b) with a real delegate_cmd there is NO such warning.
  awk '
    /^execution:[[:space:]]*(#.*)?$/ { e=1 }
    e && /^[[:space:]]+delegate_cmd:/ { print "    delegate_cmd: \"/bin/true\""; e=0; next }
    { print }
  ' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  grep -qF '/bin/true' "$_c" || fail "R11: setup failed — delegate_cmd was not set"
  hrun "$_x" -- --agents=claude --builder-backend=delegate "$_t" >"$_x/b.out" 2>"$_x/b.err" </dev/null \
    || fail "R11: the delegate install with a real delegate_cmd exited non-zero"
  command cat "$_x/b.out" "$_x/b.err" > "$_x/b.all"
  grep -qF "$WARN_MARKER" "$_x/b.all" \
    && fail "R11: the warning fired even though delegate_cmd is set — it would be noise, not a signal"
  [ "$(cfg_backend "$_c")" = "delegate" ] || fail "R11: the value changed unexpectedly"
  return 0
}

# ── R12 — exactly one report line per target; --print-agents still two lines ──
test_reports_once() {
  _x="$(sandbox report)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude --builder-backend=delegate "$_t" >"$_x/a.out" 2>"$_x/a.err" </dev/null \
    || fail "R12: install exited non-zero"
  command cat "$_x/a.out" "$_x/a.err" > "$_x/a.all"
  _n="$(grep -cF "$REPORT_MARKER" "$_x/a.all" || :)"
  [ "$_n" = "1" ] \
    || fail "R12: a single-target install printed $_n report lines, expected exactly 1"
  grep -F "$REPORT_MARKER" "$_x/a.all" | grep -qF 'delegate' \
    || fail "R12: the report line does not name the resolved backend"
  grep -F "$REPORT_MARKER" "$_x/a.all" | grep -qF -e '--builder-backend' \
    || fail "R12: the report line does not say HOW the value resolved (override)"

  # A no-override re-run still reports exactly once, and says it is unchanged.
  hrun "$_x" -- --agents=claude "$_t" >"$_x/b.out" 2>"$_x/b.err" </dev/null \
    || fail "R12: the re-run exited non-zero"
  command cat "$_x/b.out" "$_x/b.err" > "$_x/b.all"
  [ "$(grep -cF "$REPORT_MARKER" "$_x/b.all" || :)" = "1" ] \
    || fail "R12: the no-override re-run did not report exactly once"

  # The E19 contract this feature must not break: --print-agents stdout is EXACTLY two
  # lines, so the report line must never land there.
  hrun "$_x" -- --print-agents "$_t" >"$_x/p.out" 2>/dev/null </dev/null \
    || fail "R12: --print-agents exited non-zero"
  [ "$(wc -l <"$_x/p.out" | tr -d ' ')" = "2" ] \
    || fail "R12: --print-agents printed $(wc -l <"$_x/p.out") stdout lines, expected exactly 2"
  grep -qF "$REPORT_MARKER" "$_x/p.out" \
    && fail "R12: the backend report line leaked into --print-agents stdout"
  return 0
}

# ── R13 — the docs and the installer's own text document the second question ──
test_docs_document_backend_prompt() {
  _doc="$SRC/docs/INSTALL.md"
  for _s in 'execution.builder.backend' '--builder-backend' 'HARNESS_BUILDER_BACKEND' \
            'in-session' 'delegate_cmd'; do
    grep -qF -e "$_s" "$_doc" || fail "R13: docs/INSTALL.md does not mention '$_s'"
  done
  grep -qiE 're-run|rerun|running the installer' "$_doc" \
    || fail "R13: docs/INSTALL.md does not say that re-running the installer changes the value"
  grep -qiE 'warn' "$_doc" \
    || fail "R13: docs/INSTALL.md does not document the warn-and-proceed delegate_cmd ruling"
  for _s in '--builder-backend' 'HARNESS_BUILDER_BACKEND' 'in-session' 'delegate'; do
    grep -qF -e "$_s" "$INST" || fail "R13: harness-install.sh's own text does not mention '$_s'"
  done
  # tests/test_drift_check.sh greps the installer case-insensitively for this word and
  # fails the WHOLE chain. Re-asserted here so this suite catches it first.
  grep -qi 'drift' "$INST" \
    && fail "R13: harness-install.sh contains the forbidden word (tests/test_drift_check.sh will fail the chain) — say 'diverge'"
  return 0
}

# ── R14 — suite wiring + permanent-suite hygiene ─────────────────────────────
test_suite_wiring_and_hygiene() {
  _self="$SRC/tests/test_installer_toggles.sh"
  grep -qF 'tests/test_installer_toggles.sh' "$SRC/harness.config.yaml" \
    || fail "R14: verification.test_command does not name tests/test_installer_toggles.sh"
  # (The pattern is spelled with a character class so this very line does not match it.)
  grep -q 'git[[:space:]][[:space:]]*diff' "$_self" \
    && fail "R14: this suite diffs a file against git — a permanent suite must never do that"
  grep -qF "$(command cat "$SRC/VERSION")" "$_self" \
    && fail "R14: this suite freezes the exact VERSION string"
  # The installer is INVOKED exactly once (inside hrun) — including every invocation the
  # E20-F02 checks added, which all go through the same gateway. The filters drop this
  # check's own pattern lines, the read-only source path used by the source-level checks,
  # and message strings — none of which run the installer.
  _named="$(grep -n 'harness-install' "$_self" | grep -v 'grep ' | grep -v 'INST=' | grep -v 'fail "' | grep -c . || :)"
  [ "$_named" -le 1 ] \
    || fail "R14: the installer is invoked outside hrun ($_named sites) — env control is lost"
  grep -q 'env -i PATH=' "$_self" || fail "R14: hrun does not run the installer under env -i"
  grep -q 'CODEX_HOME="$_hr_dir/ch"' "$_self" \
    || fail "R14: hrun does not sandbox CODEX_HOME under the case's own temp dir"
  return 0
}

# ── R15 — MINOR VERSION bump + a matching CHANGELOG entry ────────────────────
# Shape copied from tests/test_drift_check.sh's R19: parse, never freeze. The
# MINOR-vs-PATCH judgement is the Reviewer's, from the diff — a suite that pinned a floor
# would just be a slower way to write the literal down.
test_version_and_changelog() {
  _v="$(command cat "$SRC/VERSION")"
  printf '%s\n' "$_v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || fail "R15: VERSION '$_v' is not semver"
  grep -qF "## [$_v]" "$SRC/CHANGELOG.md" \
    || fail "R15: CHANGELOG.md has no '## [$_v]' heading"
  # The feature marker is looked for ANYWHERE in the file, not in the current top section,
  # so a later release is never forced to re-mention it.
  grep -qE 'builder-backend|execution\.builder\.backend' "$SRC/CHANGELOG.md" \
    || fail "R15: CHANGELOG.md carries no builder-backend marker anywhere"
  # …and E20-F02's marker, looked for the same way.
  grep -qE '\-\-pr-loop|pr_loop\.enabled' "$SRC/CHANGELOG.md" \
    || fail "F02 R15: CHANGELOG.md carries no pr_loop-prompt marker anywhere"
  return 0
}

# ══ E20-F02 — the THIRD question, `pr_loop.enabled` ══════════════════════════
# Same three layers as above: a pure extractable decision function exercised for real, a
# write path driven end to end through the `--pr-loop=` flag (the SAME resolver and the
# SAME writer the prompt feeds), and gating asserted in the negative.

# ── F02 R2 — the answer→value mapping is a pure, extractable function ─────────
test_pr_loop_answer_mapping_unit() {
  _x="$(sandbox prlanswer)"
  # The extraction is itself the R2 shape assertion.
  sed -n '/^pr_loop_answer() {$/,/^}$/p' "$INST" > "$_x/fn.sh"
  [ -s "$_x/fn.sh" ] \
    || fail "F02 R2: the documented sed range extracted NOTHING — pr_loop_answer is missing or its opening line is not exactly 'pr_loop_answer() {'"
  grep -qx 'pr_loop_answer() {' "$_x/fn.sh" \
    || fail "F02 R2: the extracted block does not start at the function definition"
  grep -qx '}' "$_x/fn.sh" \
    || fail "F02 R2: the extracted block has no closing '}' line — the range is unterminated"
  ( set -eu; . "$_x/fn.sh" ) \
    || fail "F02 R2: the extracted definition is not sourceable on its own"
  . "$_x/fn.sh"
  command -v pr_loop_answer >/dev/null 2>&1 \
    || fail "F02 R2: sourcing the extracted block defined no pr_loop_answer"

  # The full truth table. `"" true ⇒ true` is the load-bearing row: Enter follows the
  # CURRENT value, so it is what catches "Enter always means off" — an implementation that
  # silently disarmed a configured loop on every re-run.
  for _case in \
    '|false|false' \
    '|true|true' \
    '1|true|false' \
    '1|false|false' \
    'n|true|false' \
    'N|true|false' \
    'no|true|false' \
    'NO|true|false' \
    'No|true|false' \
    'false|true|false' \
    'FALSE|true|false' \
    'False|true|false' \
    '2|false|true' \
    '2|true|true' \
    'y|false|true' \
    'Y|false|true' \
    'yes|false|true' \
    'YES|false|true' \
    'Yes|false|true' \
    'true|false|true' \
    'TRUE|false|true' \
    'True|false|true' \
    'banana|true|true' \
    'banana|false|false' \
    '3|true|true' \
    ' |false|false'
  do
    _ans="${_case%%|*}"; _rest="${_case#*|}"
    _cur="${_rest%%|*}"; _want="${_rest#*|}"
    _got="$(pr_loop_answer "$_ans" "$_cur")"
    [ "$_got" = "$_want" ] \
      || fail "F02 R2: pr_loop_answer '$_ans' '$_cur' printed '$_got', expected '$_want'"
  done

  # THE E18-F01 R18b TRAP, asserted explicitly: only the literal `true` enables the gate,
  # so an implementation that echoed the raw answer through would write `Yes` — which reads
  # back as OFF, the exact opposite of what the human chose.
  _raw="$(pr_loop_answer Yes false)"
  [ "$_raw" = "true" ] \
    || fail "F02 R2: pr_loop_answer Yes false printed '$_raw' — the raw answer must be MAPPED to the literal 'true', never passed through"

  # Side-effect-free: nothing on stderr, no file created, exactly one line on stdout.
  mkdir -p "$_x/pure"
  _before="$(find "$_x/pure" | sort)"
  ( cd "$_x/pure" && pr_loop_answer 2 false ) >"$_x/pure.out" 2>"$_x/pure.err"
  [ -s "$_x/pure.err" ] \
    && fail "F02 R2: pr_loop_answer wrote to stderr: $(command cat "$_x/pure.err")"
  [ "$(wc -l <"$_x/pure.out" | tr -d ' ')" = "1" ] \
    || fail "F02 R2: pr_loop_answer printed $(wc -l <"$_x/pure.out") lines, expected exactly 1"
  [ "$(find "$_x/pure" | sort)" = "$_before" ] \
    || fail "F02 R2: pr_loop_answer created a file — it must be side-effect-free"
  return 0
}

# ── F02 R1 — the third prompt is TTY-only, override-suppressed, and thin ──────
test_pr_loop_prompt_gating() {
  _x="$(sandbox prlgating)"; _t="$_x/t"; mkdir -p "$_t"

  # (a) non-TTY, no override: nothing asked, exit 0.
  hrun "$_x" -- --agents=claude "$_t" >"$_x/a.out" 2>"$_x/a.err" </dev/null \
    || fail "F02 R1: a non-TTY install exited non-zero"
  command cat "$_x/a.out" "$_x/a.err" | grep -qF "$PRL_PROMPT_MARKER" \
    && fail "F02 R1: the third prompt was asked on a NON-INTERACTIVE run"

  # (b) an override suppresses the prompt too.
  hrun "$_x" -- --agents=claude --pr-loop=true "$_t" >"$_x/b.out" 2>"$_x/b.err" </dev/null \
    || fail "F02 R1: an override install exited non-zero"
  command cat "$_x/b.out" "$_x/b.err" | grep -qF "$PRL_PROMPT_MARKER" \
    && fail "F02 R1: the third prompt was asked despite an explicit override"

  # (c) source: the prompt is reachable only behind `[ -t 0 ]`, and only from the resolver.
  fn_body resolve_pr_loop > "$_x/resolver.sh"
  [ -s "$_x/resolver.sh" ] || fail "F02 R1: resolve_pr_loop not found"
  grep -q '\[ -t 0 \]' "$_x/resolver.sh" \
    || fail "F02 R1: resolve_pr_loop has no '[ -t 0 ]' interactive guard"
  _tty_ln="$(grep -n '\[ -t 0 \]' "$_x/resolver.sh" | head -n 1 | cut -d: -f1)"
  _ask_ln="$(grep -n 'pr_loop_prompt' "$_x/resolver.sh" | head -n 1 | cut -d: -f1)"
  [ -n "$_ask_ln" ] || fail "F02 R1: resolve_pr_loop never calls pr_loop_prompt"
  [ "$_ask_ln" -gt "$_tty_ln" ] \
    || fail "F02 R1: pr_loop_prompt is called BEFORE the '[ -t 0 ]' guard"
  _callers="$(grep -c '[^_]pr_loop_prompt "' "$INST" || :)"
  [ "$_callers" = "1" ] \
    || fail "F02 R1: pr_loop_prompt is invoked from $_callers sites — the TTY guard is not the only door"
  # The resolver must not consult the PER-RUN env override — that is E18-F01's knob and
  # persisting it would rewrite target configs underneath two other suites (spec OQ #2).
  grep -q 'HARNESS_PR_LOOP_ENABLED' "$_x/resolver.sh" \
    && fail "F02 R1/R5: resolve_pr_loop reads HARNESS_PR_LOOP_ENABLED — that variable is a PER-RUN override and must never feed the persisted value"

  # (c2) the third question is asked AFTER the second, so all three are back to back.
  _rb="$(grep -n '^  resolve_builder_backend "\$TARGET"$' "$INST" | head -n 1 | cut -d: -f1)"
  _rp="$(grep -n '^  resolve_pr_loop "\$TARGET"$' "$INST" | head -n 1 | cut -d: -f1)"
  [ -n "$_rb" ] || fail "F02 R1: install_one no longer calls resolve_builder_backend \"\$TARGET\""
  [ -n "$_rp" ] || fail "F02 R1: install_one does not call resolve_pr_loop \"\$TARGET\""
  [ "$_rp" -gt "$_rb" ] \
    || fail "F02 R1: resolve_pr_loop is called BEFORE resolve_builder_backend — the third question must follow the second"

  # (c3) the precondition is NAMED in the prompt text. This sentence is the whole
  # substitute for an install-time preflight (spec OQ #1), so it is asserted, not assumed.
  fn_body pr_loop_prompt > "$_x/prompt.sh"
  [ -s "$_x/prompt.sh" ] || fail "F02 R1: pr_loop_prompt not found"
  grep -qF 'Codex GitHub App' "$_x/prompt.sh" \
    || fail "F02 R1: the prompt text does not name the Codex GitHub App precondition"
  grep -qF 'gh' "$_x/prompt.sh" \
    || fail "F02 R1: the prompt text does not name \`gh\`"
  grep -qF 'true' "$_x/prompt.sh"  || fail "F02 R1: the prompt does not offer the legal value 'true'"
  grep -qF 'false' "$_x/prompt.sh" || fail "F02 R1: the prompt does not offer the legal value 'false'"
  # …and it names the CURRENT value as the Enter default, rather than a hard-coded one.
  grep -q 'Enter keeps \$_plp_cur' "$_x/prompt.sh" \
    || fail "F02 R1: the prompt does not offer the CURRENT effective value as the Enter default"

  # (c4) STRUCTURAL: pr_loop_prompt is menu + read + one delegation, nothing else. This is
  # what keeps layer 1 authoritative — decision logic cannot hide where no suite can reach.
  _body="$(sed '1d;$d' "$_x/prompt.sh")"
  printf '%s\n' "$_body" | grep -q 'read -r' \
    || fail "F02 R1: pr_loop_prompt does not read a line"
  [ "$(printf '%s\n' "$_body" | grep -c 'read ')" = "1" ] \
    || fail "F02 R1: pr_loop_prompt reads more than once — it must not loop or re-ask"
  [ "$(printf '%s\n' "$_body" | grep -c 'pr_loop_answer')" = "1" ] \
    || fail "F02 R1: pr_loop_prompt does not delegate to pr_loop_answer exactly once"
  for _forbidden in 'case ' 'if ' 'elif ' 'while ' 'for ' '_cfg_' 'set_pr_loop_enabled' \
                    'PR_LOOP' '>>' 'mv ' 'gh ' 'jq '; do
    printf '%s\n' "$_body" | grep -qF "$_forbidden" \
      && fail "F02 R1: pr_loop_prompt contains '$_forbidden' — decision logic, side effects and preflights belong in pr_loop_answer / the resolver, where they are testable"
  done
  return 0
}

# ── F02 R3 — E20-F01 and the picker gain no pr_loop behavior ─────────────────
test_f01_and_picker_unaffected() {
  _x="$(sandbox f01unaffected)"
  _a="$_x/with"; _b="$_x/without"; mkdir -p "$_a" "$_b"
  hrun "$_x" -- --agents=claude,gemini --pr-loop=true "$_a" >/dev/null 2>&1 </dev/null \
    || fail "F02 R3: install with a pr_loop override exited non-zero"
  hrun "$_x" -- --agents=claude,gemini "$_b" >/dev/null 2>&1 </dev/null \
    || fail "F02 R3: install without a pr_loop override exited non-zero"
  cmp -s "$_a/.harness/.agents" "$_b/.harness/.agents" \
    || fail "F02 R3: the resolved front-end set DIFFERS with and without this feature's inputs"
  [ "$(cfg_backend "$_a/.harness/harness.config.yaml")" = "in-session" ] \
    || fail "F02 R3: --pr-loop changed the resolved builder backend to '$(cfg_backend "$_a/.harness/harness.config.yaml")'"
  [ "$(cfg_backend "$_b/.harness/harness.config.yaml")" = "in-session" ] \
    || fail "F02 R3: the control target's builder backend is not in-session"
  # …and the converse: the F01 override does not move the pr_loop gate.
  _p="$_x/backend"; mkdir -p "$_p"
  hrun "$_x" -- --agents=claude --builder-backend=delegate "$_p" >/dev/null 2>&1 </dev/null \
    || fail "F02 R3: the backend-override install exited non-zero"
  [ "$(cfg_pr_loop "$_p/.harness/harness.config.yaml")" = "false" ] \
    || fail "F02 R3: --builder-backend moved pr_loop.enabled to '$(cfg_pr_loop "$_p/.harness/harness.config.yaml")'"

  # Source: no pr_loop vocabulary anywhere in the picker or its ladder.
  for _fn in tui_select toggle_select tui_capable normalize_keys validate_csv; do
    fn_body "$_fn" > "$_x/$_fn.sh"
    [ -s "$_x/$_fn.sh" ] || fail "F02 R3: picker function $_fn is missing"
    grep -qiE 'pr_loop|pr-loop|PR_LOOP' "$_x/$_fn.sh" \
      && fail "F02 R3: $_fn gained pr_loop behavior — the picker must not change"
  done
  _keys="$(sed -n 's/^AGENT_KEYS="\(.*\)"$/\1/p' "$INST")"
  [ "$(printf '%s\n' "$_keys" | wc -w | tr -d ' ')" = "5" ] \
    || fail "F02 R3: AGENT_KEYS holds $(printf '%s\n' "$_keys" | wc -w) keys, expected the 5 front-ends ('$_keys')"
  printf '%s\n' "$_keys" | grep -qiE 'pr_loop|pr-loop' \
    && fail "F02 R3: an enum row was added to AGENT_KEYS — the gate is NOT a picker row"

  # E20-F01's own R2 contract, re-asserted from here: a refactor of this shared area that
  # broke the merged feature's extractable mapping is caught by THIS feature's suite too.
  sed -n '/^builder_backend_answer() {$/,/^}$/p' "$INST" > "$_x/bb.sh"
  [ -s "$_x/bb.sh" ] || fail "F02 R3: builder_backend_answer is no longer sed-extractable"
  . "$_x/bb.sh"
  [ "$(builder_backend_answer 2 in-session)" = "delegate" ] \
    || fail "F02 R3: builder_backend_answer's mapping changed — E20-F01's contract broke"
  [ "$(builder_backend_answer '' delegate)" = "delegate" ] \
    || fail "F02 R3: builder_backend_answer no longer follows the current value on Enter"
  return 0
}

# ── F02 R4 — the --pr-loop override contract ─────────────────────────────────
test_pr_loop_override_contract() {
  _x="$(sandbox prlflag)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "F02 R4: setup install exited non-zero"
  _c="$_t/.harness/harness.config.yaml"

  hrun "$_x" -- --agents=claude --pr-loop=true "$_t" >/dev/null 2>&1 </dev/null \
    || fail "F02 R4: --pr-loop=true exited non-zero"
  [ "$(cfg_pr_loop "$_c")" = "true" ] \
    || fail "F02 R4: --pr-loop=true did not resolve (config reads '$(cfg_pr_loop "$_c")')"

  hrun "$_x" -- --agents=claude --pr-loop=false "$_t" >/dev/null 2>&1 </dev/null \
    || fail "F02 R4: --pr-loop=false exited non-zero"
  [ "$(cfg_pr_loop "$_c")" = "false" ] \
    || fail "F02 R4: --pr-loop=false did not resolve (config reads '$(cfg_pr_loop "$_c")')"

  # The two-token form works identically.
  hrun "$_x" -- --agents=claude --pr-loop true "$_t" >/dev/null 2>&1 </dev/null \
    || fail "F02 R4: the separated '--pr-loop <value>' form exited non-zero"
  [ "$(cfg_pr_loop "$_c")" = "true" ] \
    || fail "F02 R4: '--pr-loop true' did not resolve (config reads '$(cfg_pr_loop "$_c")')"

  # An EMPTY value means "no override" — on a non-TTY run that is a total no-op, byte for
  # byte. (Note the target is at `true` here, so a "empty means false" bug is visible.)
  cp "$_c" "$_x/before.yaml"
  hrun "$_x" -- --agents=claude --pr-loop= "$_t" >/dev/null 2>&1 </dev/null \
    || fail "F02 R4: --pr-loop= (empty) exited non-zero"
  [ "$(cfg_pr_loop "$_c")" = "true" ] \
    || fail "F02 R4: an empty override changed the value to '$(cfg_pr_loop "$_c")'"
  cmp -s "$_x/before.yaml" "$_c" \
    || fail "F02 R4: an empty override rewrote harness.config.yaml"

  # An illegal value aborts non-zero BEFORE anything is created in the target.
  _e="$_x/empty"; mkdir -p "$_e"
  _before="$(find "$_e" | sort)"
  if hrun "$_x" -- --agents=claude --pr-loop=maybe "$_e" >"$_x/i.out" 2>"$_x/i.err" </dev/null; then
    fail "F02 R4: --pr-loop=maybe exited ZERO"
  fi
  grep -qF 'maybe' "$_x/i.err" || fail "F02 R4: the abort message does not name the offending value"
  grep -qF 'true'  "$_x/i.err" || fail "F02 R4: the abort message does not name the legal value true"
  grep -qF 'false' "$_x/i.err" || fail "F02 R4: the abort message does not name the legal value false"
  [ "$(find "$_e" | sort)" = "$_before" ] \
    || fail "F02 R4: the illegal run created or modified something in the target"
  [ -d "$_e/.harness" ] && fail "F02 R4: the illegal run created .harness/ in the target"
  return 0
}

# ── F02 R5 — HARNESS_PR_LOOP_ENABLED stays PER-RUN, and says so once ─────────
# All three directions are required: the negatives are what make the positive falsifiable.
test_env_is_per_run_not_persisted() {
  _x="$(sandbox prlenv)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "F02 R5: setup install exited non-zero"
  _c="$_t/.harness/harness.config.yaml"
  [ "$(cfg_pr_loop "$_c")" = "false" ] || fail "F02 R5: setup failed — the gate is not false"
  cp "$_c" "$_x/before.yaml"

  # (a) env alone: the CONFIG is untouched, the RUN is still gated on (E18-F01 R20), and
  #     exactly one warning says so.
  hrun "$_x" HARNESS_PR_LOOP_ENABLED=true -- --agents=claude "$_t" \
    >"$_x/a.out" 2>"$_x/a.err" </dev/null || fail "F02 R5: the env-only run exited non-zero"
  cmp -s "$_x/before.yaml" "$_c" \
    || fail "F02 R5: HARNESS_PR_LOOP_ENABLED PERSISTED into the config — it is a per-run override: $(diff "$_x/before.yaml" "$_c" | head -n 6)"
  [ "$(cfg_pr_loop "$_c")" = "false" ] \
    || fail "F02 R5: the env override changed the stored value to '$(cfg_pr_loop "$_c")'"
  [ -f "$_t/.claude/commands/sdd-pr-loop.md" ] \
    || fail "F02 R5: the env override no longer gates the RUN — /sdd-pr-loop was not stamped (E18-F01 R20)"
  command cat "$_x/a.out" "$_x/a.err" > "$_x/a.all"
  _n="$(grep -cF "$PRL_ENV_WARN_MARKER" "$_x/a.all" || :)"
  [ "$_n" = "1" ] \
    || fail "F02 R5: the disagreeing env printed $_n '$PRL_ENV_WARN_MARKER' warnings, expected exactly 1"
  grep -F "$PRL_ENV_WARN_MARKER" "$_x/a.all" | grep -qF 'HARNESS_PR_LOOP_ENABLED' \
    || fail "F02 R5: the warning does not name the variable"
  grep -F "$PRL_ENV_WARN_MARKER" "$_x/a.all" | grep -qiE 'not persist' \
    || fail "F02 R5: the warning does not state that the value was not persisted"

  # (b) env AGREEING with the resolved value ⇒ no warning at all.
  hrun "$_x" HARNESS_PR_LOOP_ENABLED=true -- --agents=claude --pr-loop=true "$_t" \
    >"$_x/b.out" 2>"$_x/b.err" </dev/null || fail "F02 R5: the agreeing run exited non-zero"
  [ "$(cfg_pr_loop "$_c")" = "true" ] \
    || fail "F02 R5: --pr-loop=true did not persist alongside the env (reads '$(cfg_pr_loop "$_c")')"
  command cat "$_x/b.out" "$_x/b.err" | grep -qF "$PRL_ENV_WARN_MARKER" \
    && fail "F02 R5: a warning fired even though the env and the resolved value AGREE — it would be noise, not a signal"

  # (c) no env at all ⇒ no warning, whatever the flag says.
  hrun "$_x" -- --agents=claude --pr-loop=false "$_t" \
    >"$_x/c.out" 2>"$_x/c.err" </dev/null || fail "F02 R5: the no-env run exited non-zero"
  [ "$(cfg_pr_loop "$_c")" = "false" ] || fail "F02 R5: --pr-loop=false did not persist"
  command cat "$_x/c.out" "$_x/c.err" | grep -qF "$PRL_ENV_WARN_MARKER" \
    && fail "F02 R5: a warning fired with HARNESS_PR_LOOP_ENABLED unset"

  # (d) the reverse disagreement (env off, value on) warns too — one direction only would
  #     be a half-implemented rule.
  hrun "$_x" HARNESS_PR_LOOP_ENABLED=false -- --agents=claude --pr-loop=true "$_t" \
    >"$_x/d.out" 2>"$_x/d.err" </dev/null || fail "F02 R5: the reverse-disagreement run exited non-zero"
  [ "$(grep -cF "$PRL_ENV_WARN_MARKER" "$_x/d.err" || :)" = "1" ] \
    || fail "F02 R5: HARNESS_PR_LOOP_ENABLED=false against a resolved true printed no single warning"
  return 0
}

# ── F02 R6 — no TTY + no override ⇒ nothing asked, nothing changed ───────────
# The CI back-compat guard for this half of the suite.
test_pr_loop_non_interactive_is_inert() {
  _x="$(sandbox prlinert)"; _t="$_x/t"; mkdir -p "$_t"

  # (a) a fresh non-TTY install with no override seeds the opt-in default.
  hrun "$_x" -- --agents=claude "$_t" >"$_x/a.out" 2>"$_x/a.err" </dev/null \
    || fail "F02 R6: fresh install exited non-zero"
  _c="$_t/.harness/harness.config.yaml"
  [ "$(cfg_pr_loop "$_c")" = "false" ] \
    || fail "F02 R6: a fresh non-TTY install did not seed false (reads '$(cfg_pr_loop "$_c")')"

  # (b) hand-edit to `true` + a distinctive comment, then re-run with no override, no TTY
  #     and no HARNESS_* env: byte-identical. The setup uses an INSTALLED config, whose
  #     `pr_loop:` block is already present, so migration has nothing to append and cmp is
  #     a fair test of THIS feature's writer alone.
  awk '
    /^pr_loop:[[:space:]]*(#.*)?$/ { p=1 }
    p && /^[[:space:]]+enabled:/ { print "  enabled: true"; p=0; next }
    { print }
  ' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  printf '\n# DISTINCTIVE-HUMAN-NOTE-E20F02: do not lose me\n' >> "$_c"
  [ "$(cfg_pr_loop "$_c")" = "true" ] || fail "F02 R6: setup failed — hand-edit to true did not take"
  cp "$_c" "$_x/before.yaml"

  hrun "$_x" -- --agents=claude "$_t" >"$_x/b.out" 2>"$_x/b.err" </dev/null \
    || fail "F02 R6: the no-override upgrade exited non-zero"
  cmp -s "$_x/before.yaml" "$_c" \
    || fail "F02 R6: a non-TTY run with NO override changed harness.config.yaml: $(diff "$_x/before.yaml" "$_c" | head -n 6)"
  command cat "$_x/b.out" "$_x/b.err" | grep -qF "$PRL_PROMPT_MARKER" \
    && fail "F02 R6: the third prompt was asked on a non-TTY upgrade"
  grep -qF 'DISTINCTIVE-HUMAN-NOTE-E20F02' "$_c" \
    || fail "F02 R6: the hand-added comment was lost"
  [ "$(cfg_pr_loop "$_c")" = "true" ] \
    || fail "F02 R6: a no-override run silently reset a hand-enabled gate to '$(cfg_pr_loop "$_c")'"
  return 0
}

# ── F02 R7 — only the one scalar is rewritten (or the canonical line inserted) ─
test_pr_loop_write_is_surgical() {
  _x="$(sandbox prlsurgical)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "F02 R7: setup install exited non-zero"
  _c="$_t/.harness/harness.config.yaml"

  # Hand-edit: an unrelated value, a trailing comment on the very line the writer touches,
  # an EOF note, and a DECOY top-level section carrying its own `enabled:` key. The shipped
  # config already carries a second decoy — `telemetry.enabled` — which precedes the
  # pr_loop block, so both scope directions are covered.
  awk '
    /^[[:space:]]+identity:/ && !i { print "  identity: \"SENTINEL-E20F02\""; i=1; next }
    /^pr_loop:[[:space:]]*(#.*)?$/ { p=1; print; next }
    p && /^[[:space:]]+enabled:/ { print "  enabled: false      # KEEP-THIS-TRAILING-COMMENT-F02"; p=0; next }
    { print }
  ' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  printf '\ndecoy_e20f02:\n  enabled: false   # DECOY — a same-named key under ANOTHER section\n' >> "$_c"
  printf '\n# HUMAN NOTE E20F02: this line must survive the write\n' >> "$_c"
  grep -qF 'SENTINEL-E20F02' "$_c"                || fail "F02 R7: setup failed — sentinel not written"
  grep -qF 'KEEP-THIS-TRAILING-COMMENT-F02' "$_c" || fail "F02 R7: setup failed — trailing comment not written"
  [ "$(cfg_pr_loop "$_c")" = "false" ]            || fail "F02 R7: setup failed — the gate is not false"
  # The decoy really is a decoy: it reads `false` and telemetry's reads `true`, so a writer
  # that lost its section scope would visibly corrupt one of them.
  _tel_before="$(awk '/^telemetry:/{t=1;next} t&&/^[^[:space:]#]/{t=0} t&&/^[[:space:]]+enabled:/{sub(/^[^:]*:[[:space:]]*/,"");print;exit}' "$_c")"
  [ "$_tel_before" = "true" ] || fail "F02 R7: setup assumption broken — telemetry.enabled is not 'true'"
  cp "$_c" "$_x/before.yaml"

  hrun "$_x" -- --agents=claude --pr-loop=true "$_t" >/dev/null 2>&1 </dev/null \
    || fail "F02 R7: the writing run exited non-zero"

  [ "$(cfg_pr_loop "$_c")" = "true" ] \
    || fail "F02 R7: the value was not written (reads '$(cfg_pr_loop "$_c")')"
  grep -qx '  enabled: true      # KEEP-THIS-TRAILING-COMMENT-F02' "$_c" \
    || fail "F02 R7: the gate line lost its indentation or its trailing comment: '$(grep -n 'enabled: true' "$_c" | head -n 1)'"
  grep -qF 'SENTINEL-E20F02' "$_c"   || fail "F02 R7: an unrelated hand-edited value was lost"
  grep -qF 'HUMAN NOTE E20F02' "$_c" || fail "F02 R7: the hand-added EOF comment was lost"
  # The decoys are untouched — this is what the section scoping buys.
  grep -qF '  enabled: false   # DECOY' "$_c" \
    || fail "F02 R7: the decoy section's own enabled: key was rewritten — the writer lost its section scope"
  _tel_after="$(awk '/^telemetry:/{t=1;next} t&&/^[^[:space:]#]/{t=0} t&&/^[[:space:]]+enabled:/{sub(/^[^:]*:[[:space:]]*/,"");print;exit}' "$_c")"
  [ "$_tel_after" = "$_tel_before" ] \
    || fail "F02 R7: telemetry.enabled changed from '$_tel_before' to '$_tel_after' — the writer is not section-scoped"

  # EXACTLY one line changed, in both directions.
  diff "$_x/before.yaml" "$_c" > "$_x/d.txt" || :
  _removed="$(grep -c '^< ' "$_x/d.txt" || :)"
  _added="$(grep -c '^> ' "$_x/d.txt" || :)"
  [ "$_removed" = "1" ] && [ "$_added" = "1" ] \
    || fail "F02 R7: the write changed $_removed/$_added lines, expected exactly 1/1: $(command cat "$_x/d.txt")"

  # ── the MISSING-KEY shape (E18-F01 R18b builds exactly this config) ──────────
  # A `pr_loop:` section with no `enabled:` key at all. Resolving `true` must INSERT the
  # canonical line, not silently do nothing.
  _m="$_x/missing"; mkdir -p "$_m"
  hrun "$_x" -- --agents=claude "$_m" >/dev/null 2>&1 </dev/null \
    || fail "F02 R7: missing-key setup install exited non-zero"
  _mc="$_m/.harness/harness.config.yaml"
  awk '
    /^pr_loop:[[:space:]]*(#.*)?$/ { p=1; print; next }
    p && /^[^[:space:]#]/ { p=0 }
    p && /^[[:space:]]+enabled:/ { p=0; next }
    { print }
  ' "$_mc" > "$_mc.t" && mv "$_mc.t" "$_mc"
  [ -z "$(cfg_pr_loop "$_mc")" ] || fail "F02 R7: setup failed — the enabled: key was not removed"
  hrun "$_x" -- --agents=claude --pr-loop=true "$_m" >/dev/null 2>&1 </dev/null \
    || fail "F02 R7: the insert run exited non-zero"
  [ "$(cfg_pr_loop "$_mc")" = "true" ] \
    || fail "F02 R7: resolving true on a block with no enabled: key silently did nothing (reads '$(cfg_pr_loop "$_mc")')"
  # …directly under the section header…
  _hdr="$(grep -n '^pr_loop:' "$_mc" | head -n 1 | cut -d: -f1)"
  _ins="$(sed -n "$((_hdr + 1))p" "$_mc")"
  case "$_ins" in
    '  enabled: true'*) ;;
    *) fail "F02 R7: the inserted line is not directly under the pr_loop: header (found '$_ins')" ;;
  esac
  # …and BYTE-IDENTICAL to the line the normal replace path produces. This is the
  # authored-once proof: the inserted line and the seeded/migrated one come from the same
  # bytes, so they cannot diverge by hand-alignment (R10's rule, applied to the insert).
  _ref="$(grep -n '^pr_loop:' "$_c" | head -n 1 | cut -d: -f1)"
  _refline="$(awk -v s="$_ref" 'NR>s && /^[[:space:]]+enabled:/ {print; exit}' "$_t/.harness/harness.config.yaml")"
  # (the reference target carries a hand-added trailing comment, so compare the canonical
  #  form from a PRISTINE target instead)
  _p="$_x/pristine"; mkdir -p "$_p"
  hrun "$_x" -- --agents=claude --pr-loop=true "$_p" >/dev/null 2>&1 </dev/null \
    || fail "F02 R7: pristine reference install exited non-zero"
  _canon="$(awk '/^pr_loop:/{p=1;next} p&&/^[[:space:]]+enabled:/{print;exit}' "$_p/.harness/harness.config.yaml")"
  [ -n "$_canon" ] || fail "F02 R7: could not read the canonical gate line from a pristine target"
  [ "$_ins" = "$_canon" ] \
    || fail "F02 R7/R10: the INSERTED line differs from the canonical one a seeded target carries:
  inserted:  '$_ins'
  canonical: '$_canon'"
  # the other four keys survived the insertion
  for _k in auto_merge max_rounds blocking_severities merge_strategy; do
    grep -qE "^[[:space:]]+$_k:" "$_mc" || fail "F02 R7: the insertion lost the pr_loop.$_k key"
  done
  # …and the run stamped the glue, i.e. the inserted value took effect in that same run.
  [ -f "$_m/.claude/commands/sdd-pr-loop.md" ] \
    || fail "F02 R7: the inserted value did not take effect in the same run (no /sdd-pr-loop stamped)"
  return 0
}

# ── F02 R8 — unchanged value ⇒ byte-identical; same value twice ⇒ idempotent ──
test_pr_loop_write_is_idempotent() {
  _x="$(sandbox prlidem)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude --pr-loop=true "$_t" >/dev/null 2>&1 </dev/null \
    || fail "F02 R8: setup install exited non-zero"
  _c="$_t/.harness/harness.config.yaml"
  [ "$(cfg_pr_loop "$_c")" = "true" ] || fail "F02 R8: setup failed — the gate is not true"

  _i=1
  while [ "$_i" -le 2 ]; do
    cp "$_c" "$_x/pre-$_i.yaml"
    hrun "$_x" -- --agents=claude --pr-loop=true "$_t" >/dev/null 2>&1 </dev/null \
      || fail "F02 R8: repeat run $_i exited non-zero"
    cmp -s "$_x/pre-$_i.yaml" "$_c" \
      || fail "F02 R8: re-applying the SAME value rewrote the config (run $_i): $(diff "$_x/pre-$_i.yaml" "$_c" | head -n 6)"
    _i=$((_i + 1))
  done

  _i=1
  while [ "$_i" -le 2 ]; do
    cp "$_c" "$_x/noov-$_i.yaml"
    hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
      || fail "F02 R8: no-override run $_i exited non-zero"
    cmp -s "$_x/noov-$_i.yaml" "$_c" \
      || fail "F02 R8: a no-override non-TTY run rewrote the config (run $_i)"
    _i=$((_i + 1))
  done
  [ "$(cfg_pr_loop "$_c")" = "true" ] \
    || fail "F02 R8: the no-override runs silently reset the gate to '$(cfg_pr_loop "$_c")'"

  # The writer must be SKIPPED, not re-run with identical bytes. Byte comparison alone
  # cannot tell those apart — an "always rewrite" implementation would satisfy every cmp
  # above — so assert the file was not TOUCHED, against a marker created just before.
  : > "$_x/marker"
  hrun "$_x" -- --agents=claude "$_t" >/dev/null 2>&1 </dev/null \
    || fail "F02 R8: the untouched-run exited non-zero"
  [ -n "$(find "$_c" -newer "$_x/marker" 2>/dev/null)" ] \
    && fail "F02 R8: a no-override run TOUCHED harness.config.yaml — when the value already matches the writer must not run at all"
  : > "$_x/marker2"
  hrun "$_x" -- --agents=claude --pr-loop=true "$_t" >/dev/null 2>&1 </dev/null \
    || fail "F02 R8: the same-value override run exited non-zero"
  [ -n "$(find "$_c" -newer "$_x/marker2" 2>/dev/null)" ] \
    && fail "F02 R8: re-applying the SAME value touched harness.config.yaml — the writer must be skipped"
  return 0
}

# ── F02 R9 — seed_pr_loop_optin still forces false BEFORE the apply ──────────
test_fresh_seed_interaction() {
  _x="$(sandbox prlseed)"

  # (a) a fresh install with no override ends at false — even though the harness SOURCE
  #     repo carries `true`. Asserting the source value here states WHY this matters
  #     without freezing anything version-dependent.
  [ "$(cfg_pr_loop "$SRC/harness.config.yaml")" = "true" ] \
    || fail "F02 R9: this check assumes the harness source repo opts IN (its own pr_loop.enabled is '$(cfg_pr_loop "$SRC/harness.config.yaml")') — without that, a fresh install ending at false proves nothing about inheritance"
  _a="$_x/a"; mkdir -p "$_a"
  hrun "$_x" -- --agents=claude "$_a" >/dev/null 2>&1 </dev/null \
    || fail "F02 R9: the fresh install exited non-zero"
  [ "$(cfg_pr_loop "$_a/.harness/harness.config.yaml")" = "false" ] \
    || fail "F02 R9: a fresh install INHERITED the source repo's gate (reads '$(cfg_pr_loop "$_a/.harness/harness.config.yaml")') — E18-F01 R15 forbids that"
  [ -f "$_a/.claude/commands/sdd-pr-loop.md" ] \
    && fail "F02 R9: a fresh default install stamped /sdd-pr-loop"

  # (b) a fresh install with an explicit --pr-loop=true ends at true — the ONLY route.
  _b="$_x/b"; mkdir -p "$_b"
  hrun "$_x" -- --agents=claude --pr-loop=true "$_b" >/dev/null 2>&1 </dev/null \
    || fail "F02 R9: the explicit fresh install exited non-zero"
  [ "$(cfg_pr_loop "$_b/.harness/harness.config.yaml")" = "true" ] \
    || fail "F02 R9: an explicit --pr-loop=true on a FRESH install did not stick (reads '$(cfg_pr_loop "$_b/.harness/harness.config.yaml")')"
  [ -f "$_b/.claude/commands/sdd-pr-loop.md" ] \
    || fail "F02 R9: the explicit fresh install did not stamp /sdd-pr-loop"

  # (c) source: seed_pr_loop_optin is still CALLED on the fresh-seed branch, and the new
  #     writer runs AFTER it. That ordering is what makes "no answer ⇒ off" hold twice.
  _seed_ln="$(grep -n '^    seed_pr_loop_optin "\$H/harness.config.yaml"$' "$INST" | head -n 1 | cut -d: -f1)"
  [ -n "$_seed_ln" ] \
    || fail "F02 R9: install_one no longer calls seed_pr_loop_optin on the fresh-seed branch"
  _write_ln="$(grep -n '^    set_pr_loop_enabled "\$_prl_cfg" "\$PR_LOOP_CHOICE"$' "$INST" | head -n 1 | cut -d: -f1)"
  [ -n "$_write_ln" ] || fail "F02 R9: install_one does not call set_pr_loop_enabled"
  [ "$_write_ln" -gt "$_seed_ln" ] \
    || fail "F02 R9: the pr_loop writer runs BEFORE seed_pr_loop_optin — the seed would then clobber the resolved value"
  return 0
}

# ── F02 R10 — seeded and migrated blocks converge, AFTER the writer runs ─────
# E18-F01 R17 re-asserted under this feature's writer, for BOTH values.
test_seeded_migrated_block_converge() {
  _x="$(sandbox prlconverge)"
  for _v in true false; do
    _a="$_x/seeded-$_v"; _b="$_x/migrated-$_v"; mkdir -p "$_a" "$_b"

    # A: a fresh install that goes straight to the resolved value.
    hrun "$_x" -- --agents=claude --pr-loop="$_v" "$_a" >/dev/null 2>&1 </dev/null \
      || fail "F02 R10: the seeded install ($_v) exited non-zero"

    # B: a fresh install, the whole pr_loop block stripped (a config that predates it),
    #    then a run that both migrates the block back AND applies the resolved value.
    hrun "$_x" -- --agents=claude "$_b" >/dev/null 2>&1 </dev/null \
      || fail "F02 R10: the migrated setup install ($_v) exited non-zero"
    _bc="$_b/.harness/harness.config.yaml"
    strip_prl "$_bc"
    grep -q '^pr_loop:' "$_bc" && fail "F02 R10: setup failed — the pr_loop: block was not stripped"
    hrun "$_x" -- --agents=claude --pr-loop="$_v" "$_b" >/dev/null 2>&1 </dev/null \
      || fail "F02 R10: the migrating run ($_v) exited non-zero"
    grep -q '^pr_loop:' "$_bc" || fail "F02 R10: migrate_config did not re-append the pr_loop: block"

    prl_block "$_a/.harness/harness.config.yaml" > "$_x/blk-seeded-$_v.txt"
    prl_block "$_bc" > "$_x/blk-migrated-$_v.txt"
    [ -s "$_x/blk-seeded-$_v.txt" ] \
      || fail "F02 R10: the SEEDED pr_loop block could not be captured ($_v)"
    [ -s "$_x/blk-migrated-$_v.txt" ] \
      || fail "F02 R10: the MIGRATED pr_loop block could not be captured ($_v)"
    cmp -s "$_x/blk-seeded-$_v.txt" "$_x/blk-migrated-$_v.txt" \
      || fail "F02 R10: for the resolved value '$_v' the migrated pr_loop block is NOT byte-identical to the seeded one: $(diff "$_x/blk-seeded-$_v.txt" "$_x/blk-migrated-$_v.txt" | head -n 8)"
    # …and both really carry the resolved value (a convergence check on two identically
    #  WRONG blocks would otherwise pass).
    [ "$(cfg_pr_loop "$_a/.harness/harness.config.yaml")" = "$_v" ] \
      || fail "F02 R10: the seeded target does not read '$_v'"
    [ "$(cfg_pr_loop "$_bc")" = "$_v" ] \
      || fail "F02 R10: the migrated target does not read '$_v'"
  done

  # The block a FRESH install seeds is also the one that documents the new surface — the
  # fresh path is the majority path, and the config is the file a human actually edits.
  for _s in '--pr-loop' 'opt-in' 'Codex GitHub App' 'HARNESS_PR_LOOP_ENABLED'; do
    grep -qF -e "$_s" "$_x/blk-seeded-true.txt" \
      || fail "F02 R10/R13: the pr_loop block a FRESH install seeds does not mention '$_s'"
  done
  return 0
}

# ── F02 R11 — the flip is reconciled inside the SAME run ─────────────────────
test_same_run_stamp_and_reclaim() {
  _x="$(sandbox prlsamerun)"; _t="$_x/t"; mkdir -p "$_t"
  _prompts="$_x/ch/prompts"
  _skill="$_t/.agents/skills/sdd-pr-loop/SKILL.md"

  # (a) ON: Codex receives the project-local gated skill; no global prompt is created.
  hrun "$_x" -- --agents=claude,codex --pr-loop=true "$_t" >"$_x/a.out" 2>"$_x/a.err" </dev/null \
    || fail "F02 R11: the enabling install exited non-zero"
  for _f in "$_t/.claude/commands/sdd-pr-loop.md" "$_t/.claude/agents/pr-fixer.md" \
            "$_skill"; do
    [ -f "$_f" ] || fail "F02 R11: --pr-loop=true did not stamp $_f"
  done
  [ -d "$_prompts" ] && fail "F02 R11: enabling install created retired global prompts"
  cp "$_t/.claude/commands/sdd-pr-loop.md" "$_x/ref-cmd.md"
  cp "$_skill" "$_x/ref-skill.md"

  # (b) OFF, in ONE run: the same run that writes `false` also reclaims the glue and says
  #     so. No second install — this is the whole point of writing at §2c.
  hrun "$_x" -- --agents=claude,codex --pr-loop=false "$_t" >"$_x/b.out" 2>"$_x/b.err" </dev/null \
    || fail "F02 R11: the disabling install exited non-zero"
  [ "$(cfg_pr_loop "$_t/.harness/harness.config.yaml")" = "false" ] \
    || fail "F02 R11: --pr-loop=false did not persist"
  for _f in "$_t/.claude/commands/sdd-pr-loop.md" "$_t/.claude/agents/pr-fixer.md" \
            "$_skill"; do
    [ -f "$_f" ] && fail "F02 R11: the gate-off run left $_f behind"
  done
  grep -qF "$PRL_RECLAIM_MARKER" "$_x/b.err" \
    || fail "F02 R11: the gate-off run did not announce the reclamation"

  # (c) back ON: byte-identical glue returns.
  hrun "$_x" -- --agents=claude,codex --pr-loop=true "$_t" >/dev/null 2>&1 </dev/null \
    || fail "F02 R11: the re-enabling install exited non-zero"
  cmp -s "$_x/ref-cmd.md" "$_t/.claude/commands/sdd-pr-loop.md" \
    || fail "F02 R11: the restored /sdd-pr-loop command is not byte-identical to the original"
  cmp -s "$_x/ref-skill.md" "$_skill" \
    || fail "F02 R11: the restored Codex skill is not byte-identical to the original"

  # (d) Legacy migration still honors the ownership ledger in both directions.
  mkdir -p "$_prompts"
  cp "$_x/ref-cmd.md" "$_prompts/sdd-pr-loop.md"
  _ledger="$_prompts/.sdd-pr-loop.owners"
  _foreign="$_x/foreign"; mkdir -p "$_foreign/.harness"
  _foreign_phys="$( CDPATH= cd -- "$_foreign" && pwd -P )"
  printf '%s\n' "$_foreign_phys" > "$_ledger"
  hrun "$_x" -- --agents=claude,codex --pr-loop=false "$_t" >"$_x/d.out" 2>"$_x/d.err" </dev/null \
    || fail "F02 R11: the ledger-guarded gate-off run exited non-zero"
  [ -f "$_prompts/sdd-pr-loop.md" ] \
    || fail "F02 R11: legacy prompt was deleted while another live target still claimed it"
  grep -qxF "$_foreign_phys" "$_ledger" \
    || fail "F02 R11: the foreign owner's claim was dropped from the ledger"
  grep -qF 'live or unknown ownership' "$_x/d.err" \
    || fail "F02 R11: no warning was printed for the still-owned legacy prompt"
  : > "$_ledger"
  hrun "$_x" -- --agents=claude,codex --pr-loop=false "$_t" >"$_x/e.out" 2>"$_x/e.err" </dev/null \
    || fail "F02 R11: the unclaimed gate-off run exited non-zero"
  [ -f "$_prompts/sdd-pr-loop.md" ] \
    && fail "F02 R11: pristine legacy prompt was not reclaimed after ownership cleared"

  # (e) source: §5 generates the /sdd-pr-loop body into CMDDIR UNCONDITIONALLY (E18-F01
  #     R1). It is the pristine reference the reclamation in (b) byte-compares against, so
  #     gating it would make an already-stamped copy permanently unremovable. Asserted by
  #     locating the generation line and inspecting the slice that precedes it, not by eye:
  #     a guard around it must appear between the PREVIOUS command body and this one.
  _gen="$(grep -n 'cat > "\$CMDDIR/sdd-pr-loop.md"' "$INST" | head -n 1 | cut -d: -f1)"
  [ -n "$_gen" ] || fail "F02 R11: could not locate the /sdd-pr-loop CMDDIR generation line"
  _prev="$(grep -n 'cat > "\$CMDDIR/' "$INST" | cut -d: -f1 | awk -v g="$_gen" '$1 < g { l = $1 } END { print l }')"
  [ -n "$_prev" ] || fail "F02 R11: could not locate a preceding CMDDIR generation line to bound the slice"
  sed -n "${_prev},${_gen}p" "$INST" > "$_x/slice.txt"
  grep -q 'pr_loop_enabled' "$_x/slice.txt" \
    && fail "F02 R11: the /sdd-pr-loop CMDDIR generation is nested inside a pr_loop_enabled guard — E18-F01 R1 requires it UNCONDITIONALLY (it is the reclamation reference)"
  # …and it sits at the same nesting depth as its unguarded neighbour.
  _gen_ind="$(sed -n "${_gen}p" "$INST" | sed 's/[^ ].*//' | wc -c)"
  _prev_ind="$(sed -n "${_prev}p" "$INST" | sed 's/[^ ].*//' | wc -c)"
  [ "$_gen_ind" = "$_prev_ind" ] \
    || fail "F02 R11: the /sdd-pr-loop generation is indented differently from the neighbouring command body — it may have been wrapped in a guard"
  return 0
}

# ── F02 R12 — exactly one report line on STDOUT per target ───────────────────
test_pr_loop_reports_once() {
  _x="$(sandbox prlreport)"; _t="$_x/t"; mkdir -p "$_t"
  hrun "$_x" -- --agents=claude --pr-loop=true "$_t" >"$_x/a.out" 2>"$_x/a.err" </dev/null \
    || fail "F02 R12: install exited non-zero"
  # STDOUT ONLY — §7b's announcement lives on stderr and must never be counted here.
  _n="$(grep -cF "$PRL_REPORT_MARKER" "$_x/a.out" || :)"
  [ "$_n" = "1" ] \
    || fail "F02 R12: a single-target install printed $_n report lines on stdout, expected exactly 1"
  grep -F "$PRL_REPORT_MARKER" "$_x/a.out" | grep -qF 'true' \
    || fail "F02 R12: the report line does not name the resolved value"
  grep -F "$PRL_REPORT_MARKER" "$_x/a.out" | grep -qF -e '--pr-loop' \
    || fail "F02 R12: the report line does not say HOW the value resolved (override)"

  # A gate-off re-run reports exactly once too, and its stderr reclamation announcement
  # does not inflate the stdout count.
  hrun "$_x" -- --agents=claude --pr-loop=false "$_t" >"$_x/b.out" 2>"$_x/b.err" </dev/null \
    || fail "F02 R12: the gate-off re-run exited non-zero"
  [ "$(grep -cF "$PRL_REPORT_MARKER" "$_x/b.out" || :)" = "1" ] \
    || fail "F02 R12: the gate-off re-run did not report exactly once on stdout"
  grep -qF "$PRL_RECLAIM_MARKER" "$_x/b.err" \
    || fail "F02 R12: the reclamation announcement is missing — this check's stdout/stderr split proves nothing without it"
  grep -qF "$PRL_RECLAIM_MARKER" "$_x/b.out" \
    && fail "F02 R12: the reclamation announcement leaked onto stdout, where the report line is counted"

  # A no-override re-run still reports exactly once, and says it is unchanged.
  hrun "$_x" -- --agents=claude "$_t" >"$_x/c.out" 2>"$_x/c.err" </dev/null \
    || fail "F02 R12: the no-override re-run exited non-zero"
  [ "$(grep -cF "$PRL_REPORT_MARKER" "$_x/c.out" || :)" = "1" ] \
    || fail "F02 R12: the no-override re-run did not report exactly once"
  grep -F "$PRL_REPORT_MARKER" "$_x/c.out" | grep -qF 'unchanged' \
    || fail "F02 R12: the no-override report line does not say the value is unchanged"

  # The E19 contract: --print-agents stdout is EXACTLY two lines.
  hrun "$_x" -- --print-agents "$_t" >"$_x/p.out" 2>/dev/null </dev/null \
    || fail "F02 R12: --print-agents exited non-zero"
  [ "$(wc -l <"$_x/p.out" | tr -d ' ')" = "2" ] \
    || fail "F02 R12: --print-agents printed $(wc -l <"$_x/p.out") stdout lines, expected exactly 2"
  grep -qF "$PRL_REPORT_MARKER" "$_x/p.out" \
    && fail "F02 R12: the pr_loop report line leaked into --print-agents stdout"
  return 0
}

# ── F02 R13 — the docs and the installer's own text document the third question ─
test_docs_document_pr_loop_prompt() {
  _doc="$SRC/docs/INSTALL.md"
  for _s in 'pr_loop.enabled' '--pr-loop' 'HARNESS_PR_LOOP_ENABLED' 'Codex GitHub App'; do
    grep -qF -e "$_s" "$_doc" || fail "F02 R13: docs/INSTALL.md does not mention '$_s'"
  done
  grep -qE '`true`' "$_doc"  || fail "F02 R13: docs/INSTALL.md does not name the legal value true"
  grep -qE '`false`' "$_doc" || fail "F02 R13: docs/INSTALL.md does not name the legal value false"
  grep -qiE 'opt-in' "$_doc" || fail "F02 R13: docs/INSTALL.md does not document the opt-in default"
  grep -qiE 'per-run' "$_doc" \
    || fail "F02 R13: docs/INSTALL.md does not say HARNESS_PR_LOOP_ENABLED is per-run"
  grep -qiE 'never persisted|not persisted|no environment twin' "$_doc" \
    || fail "F02 R13: docs/INSTALL.md does not say HARNESS_PR_LOOP_ENABLED is not persisted"
  grep -qiE 'no install-time preflight|No install-time preflight|runs .*no.* check' "$_doc" \
    || fail "F02 R13: docs/INSTALL.md does not document the no-install-time-preflight ruling"
  grep -qiE 're-run|rerun|running the installer' "$_doc" \
    || fail "F02 R13: docs/INSTALL.md does not say that re-running the installer changes the value"
  # The installer's OWN text (header comment + summary) advertises the flag.
  for _s in '--pr-loop' 'pr_loop.enabled' 'HARNESS_PR_LOOP_ENABLED'; do
    grep -qF -e "$_s" "$INST" || fail "F02 R13: the installer's own text does not mention '$_s'"
  done
  # And the config block — the file a human actually edits — documents the prompt in the
  # SAME bytes in both copies (source + the migration heredoc). R10 asserts the
  # convergence behaviorally; this asserts the text is there at all.
  grep -qF -e '--pr-loop' "$SRC/harness.config.yaml" \
    || fail "F02 R13: the pr_loop: comment block in harness.config.yaml does not mention --pr-loop"
  return 0
}

# ── F02 R14 — enabling the loop runs NO install-time preflight ───────────────
# A BEHAVIORAL check, never a grep: the installer GENERATES the /sdd-pr-loop body from a
# heredoc, and that body legitimately contains dozens of `gh` and `jq` invocations — that
# is loop runtime, not install time. So stub both tools on PATH and prove neither is ever
# executed. (tests/test_pr_loop.sh guards the same boundary for init.sh with a grep,
# because init.sh has no generated body. This file does, so a grep would be a lie.)
test_no_install_time_preflight() {
  _x="$(sandbox prlpreflight)"; _t="$_x/t"; mkdir -p "$_t" "$_x/stub"
  for _tool in gh jq; do
    printf '#!/bin/sh\ntouch "%s/PREFLIGHT_RAN"\nexit 1\n' "$_x" > "$_x/stub/$_tool"
    chmod +x "$_x/stub/$_tool"
  done
  # A subshell, so the stubbed PATH reaches hrun's `env -i PATH="$PATH"`.
  ( PATH="$_x/stub:$PATH"; hrun "$_x" -- --agents=claude,codex --pr-loop=true "$_t" ) \
    >"$_x/a.out" 2>"$_x/a.err" </dev/null \
    || fail "F02 R14: enabling the loop with a FAILING gh/jq on PATH exited non-zero — the installer must not depend on them: $(command cat "$_x/a.err" | tail -n 3)"
  [ -f "$_x/PREFLIGHT_RAN" ] \
    && fail "F02 R14: the installer executed gh or jq at INSTALL time — it is POSIX sh with zero dependencies and the loop's preconditions are loop-RUNTIME only"
  [ "$(cfg_pr_loop "$_t/.harness/harness.config.yaml")" = "true" ] \
    || fail "F02 R14: the install did not enable the gate"
  [ -f "$_t/.claude/commands/sdd-pr-loop.md" ] \
    || fail "F02 R14: the install did not stamp the glue"
  # The stubs really were reachable — otherwise the sentinel's absence proves nothing.
  ( PATH="$_x/stub:$PATH"; command -v gh >/dev/null 2>&1 && gh --version >/dev/null 2>&1 ) || :
  [ -f "$_x/PREFLIGHT_RAN" ] \
    || fail "F02 R14: the gh stub was never reachable on PATH — this check could not have failed"
  return 0
}

# ── run ──────────────────────────────────────────────────────────────────────
test_answer_mapping_unit
pass "answer_mapping_unit: the answer→value mapping is pure, extractable and correct for every branch (R2)"
test_prompt_gating
pass "prompt_gating: the follow-up prompt is TTY-only, override-suppressed, asked after the picker, and holds no logic (R1)"
test_picker_unaffected
pass "picker_unaffected: the front-end picker and its ladder are untouched (R3)"
test_override_precedence
pass "override_precedence: flag beats env, both suppress the prompt, empty means no override (R4)"
test_illegal_override_aborts
pass "illegal_override_aborts: an illegal override exits non-zero before touching the target (R5)"
test_non_interactive_is_inert
pass "non_interactive_is_inert: no TTY + no override asks nothing and changes nothing (R6)"
test_write_preserves_everything_else
pass "write_preserves_everything_else: exactly one scalar is rewritten; comments and hand-edits survive (R7)"
test_write_is_idempotent
pass "write_is_idempotent: an unchanged value leaves the config byte-identical (R8)"
test_migration_seeds_execution_block
pass "migration_seeds_execution_block: a missing execution: block is appended once, append-only (R9)"
test_fresh_default_unchanged
pass "fresh_default_unchanged: a fresh install with no override seeds in-session (R10)"
test_delegate_without_cmd_warns
pass "delegate_without_cmd_warns: delegate with an empty delegate_cmd is written AND warned, never otherwise (R11)"
test_reports_once
pass "reports_once: exactly one report line per target; --print-agents stays at two stdout lines (R12)"
test_docs_document_backend_prompt
pass "docs_document_backend_prompt: INSTALL.md and the installer's own text document the second question (R13)"
test_suite_wiring_and_hygiene
pass "suite_wiring_and_hygiene / pr_loop_suite_hygiene: the suite is wired into verification.test_command and keeps its env discipline — including every invocation E20-F02 added (R14, F02 R14)"
test_version_and_changelog
pass "version_and_changelog: VERSION is semver with a matching CHANGELOG entry carrying the feature marker (R15)"

# ── E20-F02 — the third question ─────────────────────────────────────────────
test_pr_loop_answer_mapping_unit
pass "pr_loop_answer_mapping_unit: the answer→value mapping is pure, extractable and correct for every branch, and never passes the raw answer through (F02 R2)"
test_pr_loop_prompt_gating
pass "pr_loop_prompt_gating: the third prompt is TTY-only, override-suppressed, asked after the second, names its precondition, and holds no logic (F02 R1)"
test_f01_and_picker_unaffected
pass "f01_and_picker_unaffected: the picker and the E20-F01 backend prompt gain no pr_loop behavior (F02 R3)"
test_pr_loop_override_contract
pass "pr_loop_override_contract: both --pr-loop forms resolve, empty means no override, illegal aborts before touching the target (F02 R4)"
test_env_is_per_run_not_persisted
pass "env_is_per_run_not_persisted: HARNESS_PR_LOOP_ENABLED still gates the run, persists nothing, and warns exactly once when it disagrees (F02 R5)"
test_pr_loop_non_interactive_is_inert
pass "pr_loop_non_interactive_is_inert: no TTY + no override asks nothing and leaves the config byte-identical (F02 R6)"
test_pr_loop_write_is_surgical
pass "pr_loop_write_is_surgical: exactly one scalar is rewritten, decoy sections survive, and a missing enabled: key gets the canonical line (F02 R7)"
test_pr_loop_write_is_idempotent
pass "pr_loop_write_is_idempotent: an unchanged value never touches the config (F02 R8)"
test_fresh_seed_interaction
pass "fresh_seed_interaction: seed_pr_loop_optin still forces false before the apply, so a fresh install can only reach true explicitly (F02 R9)"
test_seeded_migrated_block_converge
pass "seeded_migrated_block_converge: seeded and migrated pr_loop blocks are byte-identical after the writer, for both values (F02 R10)"
test_same_run_stamp_and_reclaim
pass "same_run_stamp_and_reclaim: the flip stamps or reclaims in the SAME run, honors the owners ledger, and leaves CMDDIR generation unconditional (F02 R11)"
test_pr_loop_reports_once
pass "pr_loop_reports_once: exactly one stdout report line per target; --print-agents stays at two (F02 R12)"
test_docs_document_pr_loop_prompt
pass "docs_document_pr_loop_prompt: INSTALL.md, the installer's text and the config block document the third question (F02 R13)"
test_no_install_time_preflight
pass "no_install_time_preflight: enabling the loop executes neither gh nor jq at install time (F02 R14)"

echo "All installer-toggle tests passed."
