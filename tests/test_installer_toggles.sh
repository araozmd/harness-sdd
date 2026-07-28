#!/bin/sh
# test_installer_toggles.sh — E20-F01: the installer's SECOND question,
# `execution.builder.backend`.
#
# Covers R1–R15 of specs/epics/E20-workflow-toggles/F01-builder-backend-prompt/.
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
  # The installer is INVOKED exactly once (inside hrun). The filters drop this check's own
  # pattern lines, the read-only source path used by the source-level checks, and message
  # strings — none of which run the installer.
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
pass "suite_wiring_and_hygiene: the suite is wired into verification.test_command and keeps its env discipline (R14)"
test_version_and_changelog
pass "version_and_changelog: VERSION is semver with a matching CHANGELOG entry carrying the feature marker (R15)"

echo "All installer-toggle tests passed."
