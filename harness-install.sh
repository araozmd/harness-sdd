#!/bin/sh
# harness-install.sh — install or upgrade the agent harness into a target repo.
#
#   ./harness-install.sh [--agents=<csv>] <target-repo-path>
#   ./harness-install.sh --umbrella <umbrella-dir> [--shared-repo] [--recursive] [--dry-run|--list]
#
# Idempotent: run once to install, re-run to upgrade.
#
# Agent selection (E08-F01): the installer stamps a SELECTABLE set of coding-agent
# front-ends — claude (CLAUDE.md + .claude/), gemini (GEMINI.md), opencode
# (opencode.json + .opencode/command/), antigravity (.agents/, E07-F01). Resolution:
#   - --agents=<csv> or HARNESS_AGENTS=<csv> (comma-separated keys) → that set, no
#     prompt (the override always wins). An unknown key aborts non-zero.
#   - else an interactive TTY → a numbered toggle list (pre-checked from the saved
#     .harness/.agents set, or ALL on a fresh install).
#   - else (no TTY, no override) → ALL agents (preserves the historical behavior).
# The resolved set is persisted to .harness/.agents (a dot-file beside .harness-version;
# dot-prefixed to avoid colliding with the .harness/agents/ role-bodies dir) and re-prompted
# on every re-run, decoupled from VERSION/upgrade detection. A re-run that DESELECTS
# an agent deletes that agent's harness-owned, regenerated glue and warns (it never
# touches the shared AGENTS.md entrypoint or the .harness/ body; a hand-edited
# opencode.json is left in place with a warning).
#
#   - The harness BODY (agents, docs, store, tools, templates, init.sh, config, AGENTS.md)
#     is copied into <target>/.harness/ and OVERWRITTEN on every run.
#   - PROJECT-authored content (specs/product.md, state/tasks.json, specs/epics,
#     progress) is seeded once on a fresh install and NEVER clobbered on upgrade.
#   - Claude Code glue (.claude/) and the entrypoint pointer blocks in
#     CLAUDE.md / AGENTS.md / GEMINI.md are regenerated each run; existing prose in
#     those files is preserved (only the marked block is replaced).
#
# Umbrella mode (--umbrella, see docs/UMBRELLA.md): cascades a single install across
# an umbrella directory — writes the coordinator profile into the umbrella, discovers
# its immediate git children (depth 1), installs the normal child profile into each,
# and auto-populates umbrella.manifest.yaml. Single-target mode (no --umbrella) is
# unchanged. Pass --dry-run (alias --list) with --umbrella to preview exactly which
# coordinator + git children would be touched, writing nothing.
#
# Shared spec repository (--shared-repo, umbrella mode only, see docs/UMBRELLA.md):
# OPT-IN. After the cascade, make the umbrella ROOT its own git repo that tracks the
# shared .harness/ + umbrella docs and GIT-IGNORES the product child repos (each its own
# repo). `git init` runs ONLY if the umbrella root has no .git yet (an existing repo is
# never re-initialized); the umbrella-root .gitignore is append-seeded with the discovered
# child dirs (never clobbered). Without the flag, the umbrella stays a non-git parent dir
# exactly as before — the flag is the only thing that version-controls the root.
#
# POSIX sh, zero dependencies (matches init.sh's ethos).

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
VERSION="$(cat "$SRC/VERSION" 2>/dev/null || echo "0.0.0")"
MARK_BEGIN="<!-- harness:begin -->"
MARK_END="<!-- harness:end -->"

die()  { echo "❌ install: $1" >&2; exit 1; }
info() { echo "   $1"; }
ok()   { echo "✅ $1"; }

# ── config migration (append-only, value-preserving, idempotent, zero-dep) ────
# migrate_config <config-path>
#   Appends any MISSING default keys to a PRESERVED harness.config.yaml without
#   altering existing values or comments. Driven by an explicit table of guaranteed
#   defaults (extend the table to add future additive keys). For each missing key:
#     - if its section header exists, insert the indented key line after the header;
#     - if the header is absent, append the full header+key block at EOF.
#   Never rewrites an existing line. A second run finds every key present and writes
#   nothing (idempotent). POSIX sh + grep/awk only.
migrate_config() {
  _cfg="$1"
  [ -f "$_cfg" ] || return 0

  # Default table entries are processed below. Each entry knows its section header,
  # the (two-space-indented) key line to add, and the regex that detects the key.

  # --- verification.integration_command ---
  # Section-header match tolerates a trailing `# comment` (e.g. `verification: # ...`),
  # otherwise migration would append a SECOND `verification:` mapping at EOF.
  if ! grep -Eq '^[[:space:]]*integration_command:' "$_cfg"; then
    if grep -Eq '^verification:[[:space:]]*(#.*)?$' "$_cfg"; then
      _mc_insert_after "$_cfg" '^verification:[[:space:]]*(#.*)?$' \
        '  integration_command: ""   # umbrella integration gate (see docs/UMBRELLA.md)'
    else
      {
        printf '\n'
        printf 'verification:\n'
        printf '  integration_command: ""   # umbrella integration gate (see docs/UMBRELLA.md)\n'
      } >> "$_cfg"
    fi
  fi

  # --- umbrella.manifest ---
  # Scope the presence check to the top-level `umbrella:` section — an unrelated
  # nested `manifest:` (e.g. under `metadata:`) must not suppress the default.
  if ! _cfg_has_umbrella_manifest "$_cfg"; then
    if grep -Eq '^umbrella:[[:space:]]*(#.*)?$' "$_cfg"; then
      _mc_insert_after "$_cfg" '^umbrella:[[:space:]]*(#.*)?$' \
        '  manifest: ""   # path to umbrella.manifest.yaml; presence = umbrella mode'
    else
      {
        printf '\n'
        printf 'umbrella:\n'
        printf '  manifest: ""   # path to umbrella.manifest.yaml; presence = umbrella mode\n'
      } >> "$_cfg"
    fi
  fi

  # --- telemetry: block (E05-F02) ---
  # A preserved pre-telemetry config keeps working (absence of the block ⇒ enabled
  # with the default log), but a fresh install ships the discoverable `enabled`
  # kill-switch + `log:` knob, so add the whole block on upgrade for parity. Append-only
  # at EOF (it is a top-level block; no header to insert into when absent).
  if ! grep -Eq '^telemetry:[[:space:]]*(#.*)?$' "$_cfg"; then
    {
      printf '\n'
      printf '# Telemetry (E05-F02): local-only sub-agent + human-gate timing. See docs/UMBRELLA.md\n'
      printf '# is unrelated; see agents/orchestrator.md "## Telemetry". Absent block ⇒ enabled defaults.\n'
      printf 'telemetry:\n'
      printf '  enabled: true            # false ⇒ Orchestrator skips telemetry capture entirely\n'
      printf '  log: telemetry.jsonl     # resolved under HARNESS_DIR; gitignored/local-only\n'
    } >> "$_cfg"
  fi

  # --- store.on_write_command (post-write sync hook) ---
  # Insert under the top-level `store:` header (tolerating a trailing comment). Empty
  # default ⇒ no hook, i.e. today's behavior. Scope the presence check to NOT match a
  # same-named key elsewhere by requiring the two-space indent of a store child.
  if ! grep -Eq '^[[:space:]]+on_write_command:' "$_cfg"; then
    if grep -Eq '^store:[[:space:]]*(#.*)?$' "$_cfg"; then
      _mc_insert_after "$_cfg" '^store:[[:space:]]*(#.*)?$' \
        '  on_write_command: ""   # post-write sync hook; empty ⇒ none (see store/board-mirror.md)'
    else
      {
        printf '\n'
        printf 'store:\n'
        printf '  on_write_command: ""   # post-write sync hook; empty ⇒ none (see store/board-mirror.md)\n'
      } >> "$_cfg"
    fi
  fi

  # --- mirror.board block (optional board projection) ---
  # Top-level block; append at EOF when absent (no header to insert into). Empty provider
  # ⇒ tools/sync-board.mjs is a no-op, so a preserved config without this block behaves
  # exactly as before. See store/board-mirror.md.
  if ! grep -Eq '^mirror:[[:space:]]*(#.*)?$' "$_cfg"; then
    {
      printf '\n'
      printf '# Board mirror (optional, opt-in): one-way projection of tasks.json onto a project\n'
      printf '# board. INERT by default (empty provider). MIRROR, not a backend. See store/board-mirror.md.\n'
      printf 'mirror:\n'
      printf '  board:\n'
      printf '    provider: ""          # ""|none disables; github-projects implemented; jira|azure-boards stubs\n'
      printf '    owner: ""             # github-projects: org/user login\n'
      printf '    project_number: 0     # github-projects: Project number\n'
      printf '    repo: ""              # github-projects: owner/repo holding the issues\n'
      printf '    assignee: ""          # optional: gh login (or "@me") assigned once work starts; empty ⇒ skip\n'
      printf '    # status_map:         # optional: harness status -> board column name (omit ⇒ identity)\n'
      printf '    #   pending: "Todo"\n'
      printf '    #   done: "Done"\n'
    } >> "$_cfg"
  fi
}

# _cfg_has_umbrella_manifest <file> — true (exit 0) iff a `manifest:` key exists
# INSIDE the top-level `umbrella:` section (not anywhere else in the YAML).
_cfg_has_umbrella_manifest() {
  awk '
    /^umbrella:[[:space:]]*(#.*)?$/ { u=1; next }
    u && /^[^[:space:]#]/ { u=0 }
    u && /^[[:space:]]+manifest:/ { found=1 }
    END { exit found ? 0 : 1 }
  ' "$1"
}

# _cfg_umbrella_manifest_value <file> — print the umbrella.manifest value (unquoted,
# comment-stripped) from inside the top-level `umbrella:` section; empty if unset.
_cfg_umbrella_manifest_value() {
  awk '
    /^umbrella:[[:space:]]*(#.*)?$/ { u=1; next }
    u && /^[^[:space:]#]/ { u=0 }
    u && /^[[:space:]]+manifest:/ {
      sub(/^[[:space:]]+manifest:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "")
      gsub(/^"|"$|^'\''|'\''$/, ""); print; exit
    }
  ' "$1"
}

# _cfg_telemetry_log <file> — print the telemetry.log value (unquoted, comment-stripped)
# from inside the top-level `telemetry:` section; empty if unset. Same scoping as the
# python reader's _configured_log, so the installer ignores exactly what the writer uses.
_cfg_telemetry_log() {
  awk '
    /^telemetry:[[:space:]]*(#.*)?$/ { t=1; next }
    t && /^[^[:space:]#]/ { t=0 }
    t && /^[[:space:]]+log:/ {
      sub(/^[[:space:]]+log:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "")
      gsub(/^"|"$|^'\''|'\''$/, ""); print; exit
    }
  ' "$1"
}

# _mc_insert_after <file> <header-regex> <line>  — insert <line> immediately after the
# first line matching <header-regex>, leaving every other line byte-for-byte intact.
_mc_insert_after() {
  _f="$1"; _re="$2"; _line="$3"
  awk -v re="$_re" -v add="$_line" '
    { print }
    !done && $0 ~ re { print add; done=1 }
  ' "$_f" > "$_f.mctmp" && mv "$_f.mctmp" "$_f"
}

# ── agent registry (E08-F01) ──────────────────────────────────────────────────
# Declarative table of the selectable coding-agent front-ends the installer can
# stamp. Each agent is one row: a stable KEY, the existing stamp block it gates,
# and the harness-owned glue paths it OWNS for removal (R10). Adding a future
# agent is one new key here plus its gated stamp block + removal case.
#
# The selectable keys — the ONLY legal tokens for `--agents`/`HARNESS_AGENTS`,
# the `.harness/.agents` state file, and the toggle UI — are exactly:
AGENT_KEYS="claude gemini opencode antigravity codex"
# AGENTS.md (the shared portable entrypoint) is deliberately NOT a key: it is
# always written, never gated, never removed (see write_pointer AGENTS.md). It
# also doubles as Codex CLI's native entrypoint — Codex reads AGENTS.md from the
# repo root with no glue, so `codex` needs no entrypoint pointer of its own; its
# only stamped glue is the GLOBAL /sdd-* prompts (§5d).
#
# Harness-OWNED generated basenames (stems; all files are <stem>.md). These are the
# ONLY files a deselection may delete, so a selective re-run never removes a user's
# own agents/commands sharing the same dir (Codex r2 P1). Keep in sync with the
# emit_agent calls and the command-copy loops in install_one().
HARNESS_CLAUDE_SHIMS="orchestrator architect builder reviewer scout"
HARNESS_SDD_CMDS="sdd-next sdd-new sdd-plan sdd-drill sdd-fix"

# agent_known <key> — true (exit 0) iff <key> is a registered agent key (R7, R10).
agent_known() {
  for _k in $AGENT_KEYS; do [ "$_k" = "$1" ] && return 0; done
  return 1
}

# agent_selected <key> — true (exit 0) iff <key> is a line in $SELECTED (R3/R4).
agent_selected() {
  printf '%s\n' "$SELECTED" | grep -qx "$1"
}

# normalize_keys <space-or-newline-list> — print the given keys de-duplicated and
# sorted, one per line (the stable on-disk + comparison form for .harness/.agents).
normalize_keys() {
  printf '%s\n' "$1" | tr ' ' '\n' | grep -v '^$' | sort -u
}

# codex_prompts_dir — print the GLOBAL Codex prompts dir, or nothing if it cannot be
# resolved. Codex reads custom prompts from `$CODEX_HOME/prompts` (default `~/.codex`).
# Under `set -u` a bare `$HOME` expansion aborts the WHOLE install when neither var is
# set (minimal CI/container/systemd) — and since the no-TTY default selects codex, even
# a plain noninteractive install would hit it (Codex r1 P2). So resolve defensively:
# prefer CODEX_HOME, fall back to HOME, and emit EMPTY (never a bare `/.codex`) when
# neither is set so callers can warn-and-skip instead of crashing or writing to `/`.
codex_prompts_dir() {
  if [ -n "${CODEX_HOME:-}" ]; then
    printf '%s\n' "${CODEX_HOME}/prompts"
  elif [ -n "${HOME:-}" ]; then
    printf '%s\n' "${HOME}/.codex/prompts"
  fi
}

# validate_csv <csv> — split a comma-separated override on commas, trim each token,
# drop empties, de-duplicate, validate each against the registry; `die` non-zero
# naming the first unknown token (R7). On success, print the sorted keys (one per
# line). Makes no filesystem changes (caller has not touched the target yet).
validate_csv() {
  _out=""
  _ifs="$IFS"; IFS=','
  for _tok in $1; do
    IFS="$_ifs"
    # trim surrounding whitespace
    _tok="$(printf '%s' "$_tok" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$_tok" ] || continue
    agent_known "$_tok" || die "unknown agent key '$_tok' in --agents/HARNESS_AGENTS (known: $AGENT_KEYS)"
    _out="$_out $_tok"
    IFS=','
  done
  IFS="$_ifs"
  normalize_keys "$_out"
}

# toggle_select <baseline-newline-list> — pure-`read` numbered toggle UI (R1, R9).
# Only ever called on an interactive TTY. Prints the agent keys numbered with each
# key's pre-check state taken from <baseline>; the user types space/comma-separated
# numbers to toggle entries, then a blank line (or `done`) confirms. Prints the
# resolved sorted keys (one per line) on stdout; all prompts go to stderr so the
# captured stdout is purely the selection.
toggle_select() {
  _baseline="$1"
  # Build a positional list of keys and a parallel on/off state.
  _i=0
  for _k in $AGENT_KEYS; do
    _i=$((_i + 1))
    eval "_key_$_i=\$_k"
    if printf '%s\n' "$_baseline" | grep -qx "$_k"; then
      eval "_on_$_i=1"
    else
      eval "_on_$_i=0"
    fi
  done
  _n="$_i"
  echo "Select which agent front-ends to stamp (toggle by number, blank line to confirm):" >&2
  while :; do
    _i=0
    while [ "$_i" -lt "$_n" ]; do
      _i=$((_i + 1))
      eval "_k=\$_key_$_i; _s=\$_on_$_i"
      if [ "$_s" = 1 ]; then _mark="[x]"; else _mark="[ ]"; fi
      printf '  %d) %s %s\n' "$_i" "$_mark" "$_k" >&2
    done
    printf 'toggle #s (or Enter to confirm): ' >&2
    if ! read -r _line; then break; fi
    [ -n "$_line" ] || break
    case "$_line" in done|DONE|d) break ;; esac
    for _num in $(printf '%s' "$_line" | tr ',' ' '); do
      case "$_num" in
        *[!0-9]*) echo "  ignoring '$_num' (not a number)" >&2; continue ;;
      esac
      if [ "$_num" -ge 1 ] && [ "$_num" -le "$_n" ]; then
        eval "_cur=\$_on_$_num"
        if [ "$_cur" = 1 ]; then eval "_on_$_num=0"; else eval "_on_$_num=1"; fi
      else
        echo "  ignoring '$_num' (out of range 1-$_n)" >&2
      fi
    done
  done
  _sel=""
  _i=0
  while [ "$_i" -lt "$_n" ]; do
    _i=$((_i + 1))
    eval "_k=\$_key_$_i; _s=\$_on_$_i"
    [ "$_s" = 1 ] && _sel="$_sel $_k"
  done
  normalize_keys "$_sel"
}

# tui_capable — true (exit 0) iff we can drive a raw-mode cursor TUI: stdin is an
# interactive TTY AND `stty` can save + enter + restore raw mode. Probes by saving
# the current terminal settings and immediately restoring them; any failure (no
# stty, not a real tty, sandboxed) returns non-zero so the caller falls back to the
# numbered toggle_select. Emits nothing to stdout (probe output is discarded).
tui_capable() {
  [ -t 0 ] || return 1
  command -v stty >/dev/null 2>&1 || return 1
  _probe="$(stty -g 2>/dev/null)" || return 1
  [ -n "$_probe" ] || return 1
  # Confirm we can actually restore from a saved snapshot.
  stty "$_probe" 2>/dev/null || return 1
  return 0
}

# tui_select <baseline-newline-list> — raw-mode arrow-key + spacebar checkbox UI
# (the preferred interactive picker; falls back via resolve_agents to toggle_select
# when tui_capable is false). Renders the agent keys as a cursor-driven list:
#   ↑/↓ (or k/j) move a `>` cursor · Space toggles the highlighted [x]/[ ] · Enter
#   confirms · q/Esc confirms the current selection too.
# Pre-check state seeds from <baseline> exactly as toggle_select does. ALL UI goes to
# stderr; only the resolved sorted keys (one per line, via normalize_keys) hit stdout,
# so the captured SELECTED contract is unchanged. Raw mode is entered with `stty` and
# UNCONDITIONALLY restored: an EXIT trap restores on the normal return path, while a
# shared `_tui_abort` routine restores AND aborts the whole installer (kill -INT $$ +
# exit 130). Ctrl-C is terminal-independent: the INT/TERM trap catches it where the
# terminal generates SIGINT, and an explicit byte-3 (ETX) arm in the read loop catches
# it on `-isig` terminals / PTYs that deliver it as a raw byte — so Ctrl-C never leaves
# the terminal in raw mode NOR silently continues to write files on the next Enter.
tui_select() {
  _baseline="$1"
  # Positional key list + parallel on/off state (same seeding as toggle_select).
  _i=0
  for _k in $AGENT_KEYS; do
    _i=$((_i + 1))
    eval "_key_$_i=\$_k"
    if printf '%s\n' "$_baseline" | grep -qx "$_k"; then
      eval "_on_$_i=1"
    else
      eval "_on_$_i=0"
    fi
  done
  _n="$_i"
  _cursor=1

  # Save terminal settings and guarantee restoration on ANY exit path.
  _saved_stty="$(stty -g 2>/dev/null)"
  # Ctrl-C abort is delivered two ways depending on the terminal, and BOTH must end
  # in the exact same restore+abort sequence (Codex P2 #3405383752, #3405430430):
  #   • Signal path — terminals/PTYs that keep `isig` (interrupt special chars) on
  #     translate Ctrl-C into SIGINT. The INT/TERM trap below catches it.
  #   • Raw-byte path — terminals that already have `-isig`, or PTYs that deliver
  #     VINTR as raw byte 3 (ETX), send Ctrl-C straight into the read loop as a byte.
  #     The loop's `case 3)` arm handles it (see below). Without this arm the byte is
  #     unhandled and the picker spins in raw mode forever.
  # `_tui_abort` is the single shared restore+abort routine both paths call:
  #   restore the saved stty, show the cursor (stderr), clear traps so the re-raised
  #   signal hits the default disposition, then abort the WHOLE installer. tui_select
  #   runs inside a command-substitution subshell (SELECTED="$(tui_select …)"), so a
  #   bare `exit` would only end the subshell and let the parent continue on the next
  #   Enter; instead we `kill -INT "$$"` — in POSIX sh `$$` is the ORIGINAL (parent)
  #   shell's PID even inside a subshell, so this aborts the installer process itself
  #   (no top-level trap → default terminate). `exit 130` is the belt-and-suspenders
  #   fallback if the kill is somehow swallowed. EXIT (normal confirm) just restores
  #   the terminal and must NOT force a non-zero status, or the captured SELECTED
  #   contract would look like a failure.
  _tui_abort() {
    stty "$_saved_stty" 2>/dev/null
    printf '\033[?25h' >&2
    trap - EXIT INT TERM
    kill -INT "$$" 2>/dev/null
    exit 130
  }
  # shellcheck disable=SC2064
  trap "stty '$_saved_stty' 2>/dev/null; printf '\\033[?25h' >&2" EXIT
  trap '_tui_abort' INT TERM
  # Raw-ish mode: no echo, char-at-a-time (-icanon min 1). We intentionally do NOT
  # add `isig`: Ctrl-C is handled portably via the explicit byte-3 arm in the read
  # loop, which works even where `isig` is unavailable/off; the INT/TERM trap stays
  # as the secondary net for terminals that DO generate the signal.
  stty -echo -icanon min 1 time 0 2>/dev/null
  printf '\033[?25l' >&2  # hide cursor

  printf '%s\n' \
    "Select which agent front-ends to stamp:" \
    "  ↑/↓ (or k/j) move · Space toggles [x]/[ ] · Enter confirms" >&2

  _drawn=0
  _redraw() {
    # Move cursor up to overwrite the previous render (after the first draw).
    if [ "$_drawn" = 1 ]; then printf '\033[%dA' "$_n" >&2; fi
    _i=0
    while [ "$_i" -lt "$_n" ]; do
      _i=$((_i + 1))
      eval "_k=\$_key_$_i; _s=\$_on_$_i"
      if [ "$_s" = 1 ]; then _mark="[x]"; else _mark="[ ]"; fi
      if [ "$_i" = "$_cursor" ]; then _point=">"; else _point=" "; fi
      printf '\033[2K\r %s %s %s\n' "$_point" "$_mark" "$_k" >&2
    done
    _drawn=1
  }
  _redraw

  # Read one byte at a time; decode arrows (ESC [ A/B) and act on space/enter/etc.
  while :; do
    _c="$(dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')"
    # Empty read = EOF (e.g. Ctrl-D / byte 4 closing stdin). Don't spin in raw mode —
    # treat it as an abort so the terminal is restored and no install_one runs.
    [ -n "$_c" ] || _tui_abort
    case "$_c" in
      3|4)    # Ctrl-C (ETX) / Ctrl-D (EOT) raw byte → abort. Covers terminals/PTYs
              # that deliver the interrupt as a byte instead of SIGINT (`-isig`).
        _tui_abort ;;
      10|13)  # LF / CR → Enter, confirm
        break ;;
      32)     # Space → toggle highlighted row
        eval "_cur=\$_on_$_cursor"
        if [ "$_cur" = 1 ]; then eval "_on_$_cursor=0"; else eval "_on_$_cursor=1"; fi
        _redraw ;;
      107)    # 'k' → up
        if [ "$_cursor" -gt 1 ]; then _cursor=$((_cursor - 1)); _redraw; fi ;;
      106)    # 'j' → down
        if [ "$_cursor" -lt "$_n" ]; then _cursor=$((_cursor + 1)); _redraw; fi ;;
      113)    # 'q' → confirm current selection and quit
        break ;;
      27)     # ESC — could be a bare Esc (abort/confirm) or an arrow sequence ESC [ A/B.
        # The continuation bytes must be read NON-blocking: a bare Esc sends no further
        # bytes, so a blocking `min 1` read would hang and freeze the installer. Switch
        # to `min 0 time 1` (0.1s grace) for the sequence reads, then restore `min 1`.
        stty -echo -icanon min 0 time 1 2>/dev/null
        _c2="$(dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')"
        if [ "$_c2" = 91 ]; then
          _c3="$(dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')"
        else
          _c3=""
        fi
        stty -echo -icanon min 1 time 0 2>/dev/null
        if [ "$_c2" != 91 ]; then
          break   # bare Esc (or anything not starting a CSI) → confirm current selection
        fi
        case "$_c3" in
          65)  # 'A' → up arrow
            if [ "$_cursor" -gt 1 ]; then _cursor=$((_cursor - 1)); _redraw; fi ;;
          66)  # 'B' → down arrow
            if [ "$_cursor" -lt "$_n" ]; then _cursor=$((_cursor + 1)); _redraw; fi ;;
        esac ;;
    esac
  done

  # Restore terminal NOW and clear the trap (normal completion path).
  stty "$_saved_stty" 2>/dev/null
  printf '\033[?25h' >&2
  trap - EXIT INT TERM

  _sel=""
  _i=0
  while [ "$_i" -lt "$_n" ]; do
    _i=$((_i + 1))
    eval "_k=\$_key_$_i; _s=\$_on_$_i"
    [ "$_s" = 1 ] && _sel="$_sel $_k"
  done
  normalize_keys "$_sel"
}

# resolve_agents <target> — resolve the SELECTED agent set for this run (R1, R5,
# R6, R9, R11). Resolution order, first match wins, decoupled from VERSION/UPGRADE:
#   1. Override (R5/R7): a non-empty $AGENTS_OVERRIDE (from --agents/HARNESS_AGENTS)
#      → validate_csv, no prompt — wins over persisted + TTY.
#   2. Interactive (R1/R9): else if stdin is a TTY → pre-check baseline is the
#      persisted .harness/.agents if present (R9) else ALL (R1). On a raw-capable
#      TTY this runs the arrow-key + spacebar checkbox picker (tui_select); when
#      raw mode is unavailable it gracefully falls back to the numbered
#      toggle_select. Both resolve the identical SELECTED set from the same baseline.
#   3. No-TTY default (R6): else → ALL keys (back-compat: stamp everything).
# Sets the global SELECTED to a sorted, newline-separated key list.
resolve_agents() {
  _t="$1"
  _persisted="$_t/.harness/.agents"
  if [ -n "${AGENTS_OVERRIDE:-}" ]; then
    SELECTED="$(validate_csv "$AGENTS_OVERRIDE")"
    info "agents: explicit selection ($(printf '%s' "$SELECTED" | tr '\n' ' '))"
  elif [ -t 0 ]; then
    if [ -f "$_persisted" ]; then
      _base="$(normalize_keys "$(cat "$_persisted")")"
    else
      _base="$(normalize_keys "$AGENT_KEYS")"
    fi
    # Preferred interactive path: arrow-key + spacebar checkbox TUI when the
    # terminal supports raw mode; otherwise fall back to the numbered toggle list.
    if tui_capable; then
      SELECTED="$(tui_select "$_base")"
    else
      SELECTED="$(toggle_select "$_base")"
    fi
    info "agents: interactive selection ($(printf '%s' "$SELECTED" | tr '\n' ' '))"
  else
    SELECTED="$(normalize_keys "$AGENT_KEYS")"
  fi
}

# ── install_one <target> ──────────────────────────────────────────────────────
# Installs (or upgrades) the harness into <target>. Identical behavior to the
# historical single-target installer. Sets LAST_UPGRADE to 0 (fresh) or 1 (upgrade)
# so callers can branch. <target> must already be validated as a directory != SRC.
LAST_UPGRADE=0
install_one() {
  TARGET="$1"
  H="$TARGET/.harness"
  UPGRADE=0
  if [ -f "$H/.harness-version" ]; then UPGRADE=1; fi

  # ── agent selection (E08-F01) ───────────────────────────────────────────────
  # Capture the PRIOR persisted selection (for add/remove reconciliation, R12/R13)
  # BEFORE anything is written this run, then resolve the new SELECTED set. Note
  # this is decoupled from UPGRADE/VERSION — it runs every install_one (R11).
  PRIOR_AGENTS=""
  if [ -f "$H/.agents" ]; then
    PRIOR_AGENTS="$(normalize_keys "$(cat "$H/.agents")")"
  elif [ "$UPGRADE" = 1 ]; then
    # Legacy upgrade: a pre-E08 install stamped ALL front-ends but persisted no
    # selection. Treat an existing install with no .harness/.agents as the
    # all-agents baseline, so the first selective upgrade can actually remove the
    # now-deselected glue (e.g. GEMINI.md, opencode.json) instead of leaving it
    # stale. A fresh install (UPGRADE=0) keeps PRIOR_AGENTS empty — nothing to
    # remove. (Codex P2 #3400941300.)
    PRIOR_AGENTS="$(normalize_keys "$AGENT_KEYS")"
  fi
  resolve_agents "$TARGET"

  echo "── harness install v$VERSION → $TARGET ──"
  if [ "$UPGRADE" = 1 ]; then info "existing install (v$(cat "$H/.harness-version")) — upgrading"; fi
  mkdir -p "$H"

  # ── 1. harness body → .harness/  (verbatim, overwritten each run) ───────────
  copy() { # copy <relpath>   (file or directory) from SRC into .harness/
    _src="$SRC/$1"; _dst="$H/$1"
    if [ ! -e "$_src" ]; then die "source missing: $1"; fi
    mkdir -p "$(dirname "$_dst")"
    rm -rf "$_dst"
    cp -R "$_src" "$_dst"
  }
  copy AGENTS.md
  copy init.sh
  copy agents
  copy docs
  copy store
  copy tools
  copy specs/_templates
  copy specs/glossary.md
  copy umbrella.manifest.example.yaml
  copy umbrella.gitignore.example
  chmod +x "$H/init.sh" 2>/dev/null || true
  chmod +x "$H/tools/telemetry-report.py" 2>/dev/null || true
  chmod +x "$H/tools/sync-board.mjs" 2>/dev/null || true
  # NOTE: harness.config.yaml is intentionally NOT copied here — it is seeded once
  # below (project-owned), so upgrades never erase bootstrap-set verification commands.
  ok "harness body installed (.harness/)"

  # ── 2. project workspace → .harness/  (seed once, never clobber) ────────────
  mkdir -p "$H/specs/epics" "$H/progress" "$H/state"
  if [ ! -f "$H/specs/epics/.gitkeep" ]; then : > "$H/specs/epics/.gitkeep"; fi

  # harness.config.yaml is project-owned once seeded: bootstrap fills in the
  # verification commands (and store backend), so an upgrade must NOT clobber it.
  if [ ! -f "$H/harness.config.yaml" ]; then
    cp "$SRC/harness.config.yaml" "$H/harness.config.yaml"
    # the target is a DIFFERENT product — start its verification commands blank.
    sed -e 's|^\( *test_command:\).*|\1 ""        # set during bootstrap|' \
        -e 's|^\( *lint_command:\).*|\1 ""        # set during bootstrap|' \
        -e 's|^\( *typecheck_command:\).*|\1 ""   # set during bootstrap|' \
        "$H/harness.config.yaml" > "$H/harness.config.yaml.tmp" \
        && mv "$H/harness.config.yaml.tmp" "$H/harness.config.yaml"
    info "seeded harness.config.yaml (verification commands blank)"
  else
    info "harness.config.yaml preserved (bootstrap verification commands kept)"
    # Additive, value-preserving migration: append any missing default keys (e.g.
    # the F01 umbrella.manifest / verification.integration_command) to the preserved
    # config without altering existing values or comments.
    migrate_config "$H/harness.config.yaml"
  fi

  # init.project.sh is project-owned: init.sh (BODY, overwritten on upgrade) sources
  # it for project-specific gate checks, so they live HERE and survive upgrades.
  if [ ! -f "$H/init.project.sh" ]; then
    cat > "$H/init.project.sh" <<'EOF'
# init.project.sh — project-specific gate checks.
# Sourced by init.sh from the PROJECT ROOT (not .harness/), so paths and commands
# like `npm test` / `pytest` resolve against the repo. Seeded once; NEVER clobbered
# on upgrade — put your real checks here instead of editing init.sh. Inherits the
# `fail "msg"` (abort the gate) and `ok "msg"` helpers from init.sh.
#
# Examples:
#   command -v node >/dev/null 2>&1 || fail "node not installed"
#   npm test --silent             || fail "tests are failing — do not start work"
EOF
    info "seeded init.project.sh (no checks yet)"
  else
    info "init.project.sh preserved"
  fi

  if [ ! -f "$H/specs/product.md" ]; then
    cat > "$H/specs/product.md" <<'EOF'
---
status: draft
---

# <Product name> — Product Constitution

> Layer 0. The stable, high-level "what & why". Rewrite this for your product,
> then run /sdd-next to bootstrap (detect test/lint commands, draft epics).

## What this product is
TODO

## Who it is for
TODO

## Principles & hard constraints
TODO
EOF
    info "seeded specs/product.md (stub)"
  fi

  if [ ! -f "$H/state/tasks.json" ]; then
    cat > "$H/state/tasks.json" <<'EOF'
{
  "$schema": "../store/tasks.schema.json",
  "project": "TODO-rename-me",
  "epics": [
    {
      "id": "E00",
      "title": "Harness bootstrap",
      "status": "in-progress",
      "features": [
        {
          "id": "E00-F01",
          "title": "Bootstrap: adapt the harness to this project",
          "status": "pending",
          "sdd": true,
          "autonomous": false,
          "depends_on": [],
          "spec_path": "specs/epics/E00-bootstrap/F01-adapt/"
        }
      ]
    }
  ]
}
EOF
    info "seeded state/tasks.json (bootstrap task)"
  fi

  if [ ! -f "$H/progress/history.md" ]; then
    printf '# Project history\n\n> Append one line per completed feature (Reviewer verdict).\n' > "$H/progress/history.md"
  fi
  if [ ! -f "$H/progress/.gitkeep" ]; then : > "$H/progress/.gitkeep"; fi

  # Telemetry is local-only runtime data. In an installed consumer the harness body
  # under .harness/ is committed and shared, so a blanket parent ignore would over-
  # exclude it. Seed a TARGETED .harness/.gitignore that ignores the telemetry log, so
  # the committed harness body coexists with a local-only log. We ignore BOTH the default
  # `telemetry.jsonl` AND the configured `telemetry.log` if it was overridden to a
  # different RELATIVE path (resolved under .harness/, where this .gitignore lives) — so a
  # documented override like `custom/my.jsonl` is still kept out of VCS. An ABSOLUTE
  # override lives outside the repo and needs no ignore. NOTE: if you change telemetry.log
  # AFTER install without re-running the installer, add the new path here yourself.
  _tlog="$(_cfg_telemetry_log "$H/harness.config.yaml" 2>/dev/null)"
  _ignores='telemetry.jsonl'
  case "$_tlog" in
    ''|telemetry.jsonl|/*) : ;;                 # default, unset, or absolute → nothing extra
    *) _ignores="$_ignores
$_tlog" ;;                                       # relative override → also ignore it
  esac
  if [ ! -f "$H/.gitignore" ]; then
    { printf '# Local-only telemetry log (see .harness/agents/orchestrator.md "## Telemetry").\n'
      printf '%s\n' "$_ignores"; } > "$H/.gitignore"
    info "seeded .harness/.gitignore (ignores telemetry log)"
  else
    printf '%s\n' "$_ignores" | while IFS= read -r _pat; do
      [ -n "$_pat" ] || continue
      grep -qF "$_pat" "$H/.gitignore" || printf '%s\n' "$_pat" >> "$H/.gitignore"
    done
    info ".harness/.gitignore ensured (telemetry log ignored)"
  fi

  # Personal/runtime agent state must never be committed to a SHARED project (e.g. a
  # spec/umbrella repo a team clones). Claude Code writes per-developer config
  # (.claude/settings.local.json), a scheduler lock (.claude/scheduled_tasks.lock), and
  # browser-MCP scratch at the PROJECT ROOT — none of which belong in VCS, while the
  # harness-GENERATED .claude/agents and .claude/commands DO. Seed/extend the project-root
  # .gitignore with TARGETED, append-only ignores (never clobbering existing entries), so a
  # shared repo stays free of one developer's local state. Full model:
  # .harness/docs/CONFIG-LAYERING.md.
  _root_ignores='.claude/settings.local.json
.claude/scheduled_tasks.lock'
  if [ ! -f "$TARGET/.gitignore" ]; then
    { printf '# Personal/runtime agent state — never commit (see .harness/docs/CONFIG-LAYERING.md).\n'
      printf '%s\n' "$_root_ignores"
      printf '# Per-tool MCP scratch dirs your setup may create — add your own (example):\n'
      printf '#.playwright-mcp/\n'; } > "$TARGET/.gitignore"
    info "seeded project-root .gitignore (personal/runtime agent state)"
  else
    printf '%s\n' "$_root_ignores" | while IFS= read -r _pat; do
      [ -n "$_pat" ] || continue
      grep -qF "$_pat" "$TARGET/.gitignore" || printf '%s\n' "$_pat" >> "$TARGET/.gitignore"
    done
    info "project-root .gitignore ensured (personal/runtime agent state)"
  fi
  ok "project workspace ready (.harness/specs, state, progress)"

  # ── 3. version stamp + manifest ─────────────────────────────────────────────
  printf '%s\n' "$VERSION" > "$H/.harness-version"
  cat > "$H/manifest.txt" <<EOF
harness-sdd install manifest — v$VERSION
Generated by harness-install.sh. Do not edit by hand.

HARNESS-OWNED  (overwritten on every upgrade):
  .harness/AGENTS.md  .harness/init.sh
  .harness/agents/  .harness/docs/  .harness/store/  .harness/tools/  .harness/specs/_templates/
  .harness/specs/glossary.md  .harness/umbrella.manifest.example.yaml  .harness/umbrella.gitignore.example
  .claude/agents/*  .claude/commands/*   .opencode/command/*   (repo root, regenerated)
  .agents/rules/*  .agents/agents/*  .agents/workflows/*   (repo root, regenerated; Antigravity glue)
  CLAUDE.md / AGENTS.md / GEMINI.md  -> only the harness:begin..end block

PROJECT-OWNED  (seeded once, never clobbered on upgrade):
  .harness/harness.config.yaml   (verification commands + store backend)
  .harness/init.project.sh       (project-specific init.sh gate checks)
  .harness/specs/product.md  .harness/specs/epics/
  .harness/state/tasks.json  .harness/progress/
  umbrella.manifest.yaml         (umbrella mode only: coordinator manifest)

AGENT SELECTION  (E08-F01):
  .harness/.agents               harness-owned: the selected agent keys, one per line
                                 (claude|gemini|opencode|antigravity), overwritten each run.
  Choose with --agents=<csv> / HARNESS_AGENTS=<csv>, an interactive toggle list, or
  (no TTY, no override) ALL. Deselecting an agent on a re-run REMOVES its glue above
  (its pointer block / .claude|.opencode dir / generated opencode.json) and warns;
  the shared AGENTS.md entrypoint and the .harness/ body are never removed.
EOF

  # ── 4. entrypoint pointer blocks (idempotent marked region) ─────────────────
  write_pointer() { # write_pointer <relative-file>
    _f="$TARGET/$1"
    _block="$MARK_BEGIN
## Agent Harness (Spec-Driven Development)
This project uses a portable agent harness installed in \`.harness/\`.
Start every agent session as the **Orchestrator**:
1. Run \`.harness/init.sh\` — if it exits non-zero, STOP.
2. Read \`.harness/AGENTS.md\` (the harness source of truth) and resolve its
   relative paths against \`.harness/\` (config, agents/, specs/, state/, store/,
   docs/, progress/).
3. Product/source code lives at the repo root; harness bookkeeping lives in
   \`.harness/\`. In Claude Code, run \`/sdd-next\`.
$MARK_END"
    if [ -f "$_f" ] && grep -qF "$MARK_BEGIN" "$_f"; then
      # Replace the marked block IN PLACE: keep the prefix before the begin marker
      # and the suffix after the end marker, so user content on either side keeps
      # its original order (the markers contain no sed-special characters).
      {
        sed "/$MARK_BEGIN/,\$d" "$_f"   # prefix: everything before the begin marker
        printf '%s\n' "$_block"
        sed "1,/$MARK_END/d" "$_f"      # suffix: everything after the end marker
      } > "$_f.tmp"
      mv "$_f.tmp" "$_f"
    else
      if [ -f "$_f" ]; then printf '\n' >> "$_f"; fi
      printf '%s\n' "$_block" >> "$_f"
    fi
  }
  # remove_pointer <relative-file> — delete the marked harness:begin..end block from
  # <file> in place, preserving any user prose on either side (mirrors write_pointer's
  # marker-aware edit). If the file becomes empty/whitespace-only afterward (it was
  # harness-only), remove it. Never touches a file that has no harness block. (R13)
  remove_pointer() {
    _f="$TARGET/$1"
    [ -f "$_f" ] || return 0
    grep -qF "$MARK_BEGIN" "$_f" || return 0
    {
      sed "/$MARK_BEGIN/,\$d" "$_f"   # prefix: everything before the begin marker
      sed "1,/$MARK_END/d" "$_f"      # suffix: everything after the end marker
    } > "$_f.tmp"
    mv "$_f.tmp" "$_f"
    # Remove the file only if nothing but whitespace remains (it was harness-only).
    if ! grep -q '[^[:space:]]' "$_f"; then rm -f "$_f"; fi
    info "removed harness pointer block from $1"
  }
  # remove_owned <dir-rel> <agent-label> <stem...> — on deselection, delete ONLY the
  # named harness-generated files (<dir>/<stem>.md) inside <dir>, then rmdir <dir> if it
  # is now empty. A user's own files in the same dir are preserved (the dir survives,
  # non-empty). This keeps removal scoped to harness-owned glue so a selective re-run
  # never deletes unrelated project/user config. (R13; Codex r2 P1)
  remove_owned() {
    _rel="$1"; _dir="$TARGET/$1"; _label="$2"; shift 2
    [ -d "$_dir" ] || return 0
    _removed=''
    for _b in "$@"; do
      if [ -f "$_dir/$_b.md" ]; then rm -f "$_dir/$_b.md"; _removed="$_removed $_b.md"; fi
    done
    [ -n "$_removed" ] && echo "⚠️  removed deselected agent '$_label' glue:$_removed (in $_rel/)" >&2
    rmdir "$_dir" 2>/dev/null || { [ -n "$_removed" ] && echo "ℹ️  kept $_rel/ — contains non-harness files" >&2; }
  }
  # gen_opencode_json <dest> — write the canonical generated opencode.json to <dest>.
  # Single source of truth for both the stamp (§6) and the deselect byte-comparison,
  # so removal deletes ONLY a pristine generated file and never a user-edited one.
  gen_opencode_json() {
    cat > "$1" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": [".harness/AGENTS.md"],
  "agent": {
    "orchestrator": { "mode": "primary",  "description": "The Leader: routes the next task, delegates. Never writes code.", "prompt": "{file:./.harness/agents/orchestrator.md}" },
    "architect":    { "mode": "subagent", "description": "Spec Author: writes the 4-file spec (EARS).",                     "prompt": "{file:./.harness/agents/architect.md}" },
    "builder":      { "mode": "subagent", "description": "Implementer: writes code from an approved spec.",                 "prompt": "{file:./.harness/agents/builder.md}" },
    "reviewer":     { "mode": "subagent", "description": "Evaluator: verifies against the spec, runs tests.",               "prompt": "{file:./.harness/agents/reviewer.md}" },
    "scout":        { "mode": "subagent", "description": "Read-only recon; writes findings to progress/.",                  "prompt": "{file:./.harness/agents/scout.md}" }
  }
}
EOF
  }

  # ── Antigravity .agents/ glue generators — single source of truth ─────────────
  # These are hoisted out of §5c so BOTH the install stamp (§5c) and the deselect
  # byte-compare (§7) call the exact same emitters. The deselect path removes an
  # `.agents/` file ONLY when it is byte-identical to a freshly-generated stamp
  # (pristine), never delete-by-name — so a user's own `.agents/agents/builder.md`
  # (or any standard-named persona/workflow they authored) is preserved. Mirrors
  # the opencode.json `cmp -s` "pristine generated" vs "differs — left in place"
  # contract above. (Codex r2 P1 #3404240336.)

  # gen_ag_rule <dest> — write the canonical .agents/rules/harness.md entrypoint rule.
  gen_ag_rule() {
    cat > "$1" <<'EOF'
---
description: SDD harness entrypoint — boot as the Orchestrator against .harness/.
---

This workspace uses the portable **SDD agent harness** installed in `.harness/`.
Antigravity does not auto-load `AGENTS.md`, so this rule loads the harness for you.

- **Source of truth:** `.harness/AGENTS.md` — read it and resolve every relative
  path it mentions against `.harness/` (config, `agents/`, `specs/`, `state/`,
  `store/`, `docs/`, `progress/`).
- **Start every session as the Orchestrator:** `.harness/agents/orchestrator.md`.
- **Before any work:** run `.harness/init.sh`. If it exits non-zero, STOP.
- **Working model (R12):** Antigravity drives the harness through the
  `description`-gated `.agents/workflows/` slash commands and the `.agents/agents/`
  personas, with `.harness/progress/` files as the hand-off / isolation boundary —
  NOT a Task-tool-style isolated spawn, and NOT an asserted bare-file subagent
  registration (bare-file persona discovery is unconfirmed; the durable primitives
  are this rule + the `description`-gated workflows + the `.harness/progress/`
  hand-off). Hand off through `.harness/progress/`, never by forwarding chat history.

The role files in `.agents/agents/` and the workflows in `.agents/workflows/` are thin
pointers at the canonical `.harness/agents/*.md` roles — they do not duplicate them.
EOF
  }

  # gen_ag_persona <role> <description> <dest> — write one .agents/agents/<role>.md.
  gen_ag_persona() {
    _agp_role="$1"; _agp_desc="$2"; _agp_dest="$3"
    cat > "$_agp_dest" <<EOF
---
description: $_agp_desc
---

You are the **$_agp_role** for this project's agent harness (installed in \`.harness/\`).

Your full, canonical role definition is \`.harness/agents/$_agp_role.md\` — read it now and
follow it exactly. Resolve every relative path it mentions against \`.harness/\`
(e.g. \`harness.config.yaml\` -> \`.harness/harness.config.yaml\`, \`progress/\` ->
\`.harness/progress/\`). Run \`.harness/init.sh\` before any work and halt on its
non-zero exit. Hand off through \`.harness/progress/\` files, never by forwarding
chat history.
EOF
  }

  # ag_personas — emit the role→description mapping ONE place, reused by the §5c
  # install loop and the §7 deselect compare so they can never diverge. Each line is
  # `<role>\t<description>`; callers read it field-by-field.
  ag_personas() {
    cat <<'EOF'
orchestrator	The Leader. Reads state, runs init.sh, routes the next task, delegates to architect/builder/reviewer/scout. Never writes code.
architect	The Spec Author. Writes the 4-file spec in EARS. No production code.
builder	The Implementer. Writes code from an APPROVED spec, one task at a time.
reviewer	The Evaluator. Verifies against the spec, runs tests, approves or rejects.
scout	Read-only codebase reconnaissance. Writes findings to progress/.
EOF
  }

  # remove_if_pristine <rel-path> <ref-file> <agent-label> — delete <TARGET>/<rel-path>
  # ONLY when it is byte-identical to <ref-file> (a freshly-generated stamp). If it
  # differs (user-edited or foreign), LEAVE it in place with a notice — exactly
  # mirroring the opencode.json case. Echoes the removed relpath on stdout (so the
  # caller can summarize) and prints user-facing notices to stderr.
  remove_if_pristine() {
    _rip_rel="$1"; _rip_ref="$2"; _rip_label="$3"
    _rip_f="$TARGET/$_rip_rel"
    [ -f "$_rip_f" ] || return 0
    if cmp -s "$_rip_f" "$_rip_ref"; then
      rm -f "$_rip_f"
      printf '%s\n' "$_rip_rel"
    else
      echo "⚠️  $_rip_rel differs from the generated stamp (edited) — left in place (deselected '$_rip_label' not removed)" >&2
    fi
  }

  # AGENTS.md is the shared portable entrypoint — ALWAYS written, never gated (R2 note).
  # It is also Codex CLI's native repo entrypoint (Codex reads AGENTS.md with no glue),
  # so a `codex`-only install needs no dedicated pointer here — AGENTS.md already serves it.
  write_pointer AGENTS.md
  # Per-agent entrypoint pointers are gated on selection (R2/R3/R4).
  agent_selected claude && write_pointer CLAUDE.md
  # The GEMINI.md managed block reads as "act as the Orchestrator, run
  # .harness/init.sh, read .harness/AGENTS.md" — Antigravity natively loads
  # GEMINI.md-style rules, so this same pointer also serves Antigravity as the
  # in-repo entrypoint (E07-F01 R1/R12); the .agents/rules/harness.md rule (§5c) is
  # the Antigravity-specific hook layered on top. Written when EITHER gemini OR
  # antigravity is selected — both share GEMINI.md as their in-repo entrypoint.
  if agent_selected gemini || agent_selected antigravity; then write_pointer GEMINI.md; fi
  ok "entrypoint pointers written (AGENTS.md + selected agents)"

  # ── 5. Claude Code sub-agent shims + /sdd-next (regenerated each run) ────────
  # Gated on selection (R3/R4): the Claude glue is stamped only when `claude` is in
  # SELECTED. The OpenCode mirror in §5b copies from these files, so it is gated on
  # `opencode` independently and re-derives the command bodies if Claude is skipped.
  if agent_selected claude; then
  mkdir -p "$TARGET/.claude/agents" "$TARGET/.claude/commands"
  emit_agent() { # emit_agent <name> <tools> <description>
    cat > "$TARGET/.claude/agents/$1.md" <<EOF
---
name: $1
description: $3
tools: $2
---

You are the **$1** for this project's agent harness (installed in \`.harness/\`).

Your full, canonical role definition is \`.harness/agents/$1.md\` — read it now and
follow it exactly. Resolve every relative path it mentions against \`.harness/\`
(e.g. \`harness.config.yaml\` -> \`.harness/harness.config.yaml\`, \`progress/\` ->
\`.harness/progress/\`). Run \`.harness/init.sh\` before any work and halt on failure.
Hand off through \`.harness/progress/\` files, never by forwarding chat history.
EOF
  }
  emit_agent orchestrator "Read, Bash, Edit, Grep, Glob, Task" \
    "The Leader. Reads state, runs init.sh, routes the next task, delegates to architect/builder/reviewer/scout. Never writes code."
  emit_agent architect "Read, Write, Edit, Grep, Glob, Bash" \
    "The Spec Author. Writes the 4-file spec in EARS. No production code."
  emit_agent builder "Read, Write, Edit, Bash, Grep, Glob" \
    "The Implementer. Writes code from an APPROVED spec, one task at a time."
  emit_agent reviewer "Read, Bash, Grep, Glob, Edit" \
    "The Evaluator. Verifies against the spec, runs tests, approves or rejects."
  emit_agent scout "Read, Grep, Glob, Bash" \
    "Read-only codebase reconnaissance. Writes findings to progress/."
  ok "Claude Code sub-agent shims installed (.claude/agents/)"
  fi  # end: claude-gated sub-agent shims

  # ── slash-command bodies (generated once into a temp dir, then mirrored to the
  # selected front-ends' command dirs). Generating into a neutral CMDDIR lets the
  # OpenCode mirror (§5b) work even when `claude` is NOT selected (R3/R4). ─────────
  CMDDIR="$(mktemp -d 2>/dev/null || mktemp -d -t harness-cmd)"
  cat > "$CMDDIR/sdd-next.md" <<'EOF'
---
description: Run the Orchestrator loop on the next actionable task (init → route → delegate)
---

Act as the **Orchestrator** (`.harness/agents/orchestrator.md`), resolving all
relative paths against `.harness/`.

1. Run `.harness/init.sh`. If it exits non-zero, STOP and report.
2. Read `.harness/harness.config.yaml` and the TaskStore (per `.harness/store/local.md`).
3. Find the next actionable feature and route it by status per
   `.harness/docs/WORKFLOW.md`:
   - `pending` + sdd:true → spawn **architect**, then `spec-ready` and PAUSE (human gate).
   - `spec-ready` + autonomous:true → set `in-progress`, spawn **builder**, then `in-review`.
   - `in-progress` → spawn **builder** with the approved specs only, then `in-review`.
   - `in-review` → spawn **reviewer**; approve → `done`, reject → back to `in-progress`.
4. Append what happened to `.harness/progress/history.md`.

$ARGUMENTS may name a specific feature id (e.g. `E01-F01`); if given, operate on it.
EOF

  cat > "$CMDDIR/sdd-new.md" <<'EOF'
---
description: Seed a new idea into the TaskStore as Inception (interactive intake → pending entry + inbox brief)
---

Act as **Inception** (`.harness/agents/inception.md`). That role file is the durable
contract; this command carries the interactive front-end. Resolve all relative paths
against `.harness/`.

The free-text idea is in `$ARGUMENTS`. If it is empty, ask the human for it.

1. Run `.harness/init.sh`. If it exits non-zero, STOP and report — do not seed into a
   broken environment.
2. Read `.harness/harness.config.yaml` and the TaskStore (`.harness/state/tasks.json`,
   per `.harness/store/local.md`).
3. Run a short, **adaptive** Q&A with the human to clarify: the problem and who it is
   for, the success outcome, the scope/boundaries, and any constraints. Where the
   shape forks, offer **at most 3** options as **text-only** (markdown/ASCII) mockups
   — never images. Keep it short; ask only what you need to triage and brief.
4. **Triage** the idea to exactly one altitude, per `.harness/agents/inception.md`:
   (1) new task on an existing feature / (2) new feature under an existing
   epic / (3) new epic + `epic.md` + `F01`. The write step is **altitude-dependent** —
   fork here. For altitudes 2 and 3, **allocate** a next-sequential id; for altitude 1,
   do NOT allocate a new id (you reuse the existing feature's id).
5. **Write** — branch by altitude:
   - **Altitude 1 (new task on an existing feature):** do NOT allocate a new id and do
     NOT insert a new feature into `.harness/state/tasks.json`. Branch on the existing
     feature's status (the inbox brief is read by the Architect only while a feature
     is `pending`):
     - **If it is still `pending`:** **append** a task-level note (and any dependency)
       to the EXISTING feature's `.harness/progress/inbox/<existing-feature-id>.md`
       brief — creating that brief from the `.harness/specs/_templates/inbox-brief.md`
       template if the feature predates the inbox convention. Per
       `.harness/agents/inception.md`, do not invent a competing feature. Then skip to
       step 8 (steps 6–7 cover only the new-entry path).
     - **If it is already `spec-ready`, `in-progress`, `in-review`, or `done`:** do
       NOT append to the brief — it has already been consumed, so the note would be a
       silent no-op. STOP and tell the human the addition must go back through
       specification: either raise it with the Architect to re-spec / update that
       feature's spec & task list, or re-run `/sdd-new` to seed it as a NEW feature
       (altitude 2) that `depends_on` the existing one. Do not write a no-op note.
   - **Altitudes 2 & 3:** write the `pending` feature entry into
     `.harness/state/tasks.json` (and, for a new epic, the epic entry +
     `.harness/specs/epics/<slug>/epic.md` + first `F01`), then continue to steps 6–7.
6. **Re-validate** `.harness/state/tasks.json` against
   `.harness/store/tasks.schema.json` (altitudes 2 & 3, after the new entry). If it
   fails, report the failure and do NOT claim a successful seed.
7. **Write** the intent brief to `.harness/progress/inbox/<feature-id>.md` (frontmatter
   + sections), copying `.harness/specs/_templates/inbox-brief.md` as the template.
8. **Report** the `<feature-id>` (for altitude 1, the EXISTING feature's id), the
   relevant `.harness/state/tasks.json` entry, the
   `.harness/progress/inbox/<feature-id>.md` path, and tell the human to **run
   `/sdd-next`** next. Do NOT spawn the Architect and do NOT change any status —
   Inception seeds, never specs, and never moves a feature past `pending`.
EOF

  cat > "$CMDDIR/sdd-plan.md" <<'EOF'
---
description: Whole-project inception as Planner — produce vision + architecture + ADRs and seed a block of draft epics (interactive)
---

Act as **Planner** (`.harness/agents/planner.md`). That role file is the durable
contract; this command carries the interactive front-end. Resolve all relative paths
against `.harness/`.

The free-text whole-project idea is in `$ARGUMENTS`. If it is empty, ask the human for it.

1. Run `.harness/init.sh`. If it exits non-zero, STOP and report — do not plan into a
   broken environment.
2. Read `.harness/harness.config.yaml` and the TaskStore (`.harness/state/tasks.json`,
   per `.harness/store/local.md`).
3. **Re-run guard.** If `.harness/specs/vision.md` or `.harness/specs/architecture.md`
   already exists, a default run STOPS and reports that the project already has a plan —
   point the human at `/sdd-drill` (F03) to deepen existing epics, or at an explicit
   amend mode that **appends** (never overwrites or renumbers). Do not silently
   overwrite.
4. Run a short, **adaptive** Q&A with the human to clarify: the problem and who it is
   for, the outcomes, the non-goals, and the roadmap shape. Where the shape forks, offer
   **at most 3** options as **text-only** (markdown/ASCII) mockups — never images. Keep
   it short; ask only what you need to write the vision and sketch the roadmap.
5. **Write** `.harness/specs/vision.md` from `.harness/specs/_templates/vision.md`
   (north star: problem, users, outcomes, non-goals; it complements
   `.harness/specs/product.md`/`glossary.md`).
6. **Write** `.harness/specs/architecture.md` from
   `.harness/specs/_templates/architecture.md` (system shape + stable upfront
   decisions), and one ADR per decision at `.harness/specs/adr/NNNN-<title>.md` from
   `.harness/specs/_templates/adr.md` (4-digit, above the max existing ADR number);
   `architecture.md` references each ADR by its `ADR-NNNN` id. Stay at whole-system
   depth — defer per-epic deltas to `/sdd-drill` (F03).
7. **Seed** the roadmap: for each epic, write a `.harness/state/tasks.json` row with
   `status: "draft"` and `features: []` (ids as a next-sequential block strictly above
   the max existing `E##`, append-only, no reuse), and create
   `.harness/specs/epics/<id>-<slug>/epic.md` = title + one-paragraph business brief
   only (no `F01`, no feature spec).
8. **Re-validate** `.harness/state/tasks.json` against
   `.harness/store/tasks.schema.json`. If it fails, report the failure and do NOT claim
   a successful plan.
9. **Report** the artifacts written (`.harness/specs/vision.md`,
   `.harness/specs/architecture.md`, each `.harness/specs/adr/NNNN-*.md`), the seeded
   `draft` epics (ids + titles + `epic.md` paths), and tell the human to **run
   `/sdd-drill <epic-id>`** next. Do NOT spawn the Architect, do NOT write any feature
   spec, and do NOT advance any epic past `draft` — the Planner produces, never specs.
EOF

  cat > "$CMDDIR/sdd-drill.md" <<'EOF'
---
description: Per-epic drill-down as Driller — decompose one draft epic into features + ADR deltas, then one epic-level approval (interactive)
---

Act as **Driller** (`.harness/agents/driller.md`). That role file is the durable
contract; this command carries the interactive front-end. Resolve all relative paths
against `.harness/`.

The target `<epic-id>` is in `$ARGUMENTS`. The `<epic-id>` is **required** — if
`$ARGUMENTS` is **empty**, STOP and **ask** the human for the epic id rather than drilling
an arbitrary epic.

1. Run `.harness/init.sh`. If it exits non-zero, STOP and report — do not drill into a
   broken environment.
2. Read `.harness/harness.config.yaml` and the TaskStore (`.harness/state/tasks.json`, per
   `.harness/store/local.md`).
3. **Precondition guard.** Resolve `<epic-id>`. If it does not resolve to an existing epic,
   or the epic's status is **not** `draft` (`planned` / `in-progress` / `done` / legacy
   `pending`), a default run STOPS and reports why (missing / not-`draft`) — seed nothing,
   append no ADR, change no status. (Re-running on an already-`planned` epic is an explicit
   **amend** opt-in that appends features/ADRs above the current max without renumbering or
   re-flipping.)
4. Read the target `draft` epic (`.harness/specs/epics/<id>-<slug>/epic.md` + its
   `.harness/state/tasks.json` row) and F02's design artifacts (`.harness/specs/vision.md`,
   `.harness/specs/architecture.md`, `.harness/specs/adr/NNNN-*.md`) as inputs.
5. Run a short, **adaptive** Q&A with the human to settle the feature breakdown. Where the
   breakdown forks, offer **at most 3** options as **text-only** (markdown/ASCII) mockups —
   never images. Keep it short.
6. **Seed** the decomposition: write each new feature into the epic's `features` array
   (`status: "pending"`, `sdd: true`, one-line `title`, `spec_path`, intra-epic
   `depends_on`; ids as a next-sequential block strictly above the epic's max `F##`,
   append-only, no reuse); fill the `epic.md` feature table (one row per feature); and write
   a per-feature inbox brief at `.harness/progress/inbox/<E##>-F<NN>.md` from
   `.harness/specs/_templates/inbox-brief.md`, recording the `ADR-NNNN` ids each feature
   must honor.
7. **Append** any per-epic **ADR deltas** the decomposition forces at
   `.harness/specs/adr/NNNN-<title>.md` (4-digit, above the max existing ADR number, no
   reuse) — do NOT rewrite or renumber F02's existing ADRs. Stay at per-epic depth; defer
   feature-level design to the feature's own spec.
8. **Re-validate** `.harness/state/tasks.json` against `.harness/store/tasks.schema.json`. If
   it fails, report the failure and do NOT claim a successful drill.
9. Present the **single epic-level decision** (one decision, not per feature):
   - **approve** → flip the epic `draft → planned` and stamp `autonomous: true` on every
     seeded feature (all-or-nothing); or
   - **keep gated** → flip the epic `draft → planned`, leaving every seeded feature
     `autonomous: false` so each parks at the per-feature spec-approval gate.
   Re-validate again after the flip/stamp.
10. **Report** the seeded features (ids + titles + `spec_path`s), the inbox briefs + ADR
    ids, any ADR deltas, and the decision taken; tell the human to **run `/sdd-next`** to
    execute. Do NOT spawn the Architect, do NOT write any feature `.spec/.plan/.tasks/.tests`,
    and advance ONLY the target epic to `planned` — the Driller decomposes, never specs.
EOF

  cat > "$CMDDIR/sdd-fix.md" <<'EOF'
---
description: Lightweight fix lane as Fixer — seed an sdd:false fix under the reserved maintenance epic (brief only, no spec/drill) and hand it to the existing Builder → Reviewer loop (interactive)
---

Act as **Fixer** (`.harness/agents/fixer.md`). That role file is the durable contract;
this command carries the interactive front-end. Resolve all relative paths against
`.harness/`.

The free-text fix description is in `$ARGUMENTS`. If `$ARGUMENTS` is **empty**, STOP and
**ask** the human what to fix rather than seeding an empty fix.

1. Run `.harness/init.sh`. If it exits non-zero, STOP and report — do not seed into a
   broken environment.
2. Read `.harness/harness.config.yaml` and the TaskStore (`.harness/state/tasks.json`,
   per `.harness/store/local.md`).
3. Run a short, **adaptive** Q&A with the human to settle the fix's shape: what's broken,
   the intended fix, and how to verify. Where the shape forks, offer **at most 3** options
   as **text-only** (markdown/ASCII) mockups — never images. Keep it short.
4. **Maintenance epic (create-on-first-use / reuse-by-id).** Look up epic `E99` in
   `.harness/state/tasks.json`. If **absent**, create it with `id: "E99"`, slug
   `maintenance`, title `"Maintenance (hotfixes & minor fixes)"`, `status: "planned"`,
   `features: []`, and write `.harness/specs/epics/E99-maintenance/epic.md` (title +
   one-paragraph brief only — no feature spec). If **present**, reuse that same epic **by
   id `E99`** — never create a second maintenance epic and never renumber its existing fixes.
5. **Seed** one fix: append a feature to `E99`'s `features` array with `sdd: false`,
   `status: "pending"`, a one-line `title`, a `spec_path`
   (`specs/epics/E99-maintenance/F<NN>-<slug>/`, **directory not created**), and an `id`
   allocated next-sequential strictly **above** the epic's max `F##` (append-only, no
   reuse). Stamp it `autonomous: true` by **default**; if the human passes a `--gated`
   opt-out, stamp it `autonomous: false` instead (it then parks at the normal gate).
6. Write **exactly one** fix-oriented inbox brief at `.harness/progress/inbox/<id>.md`
   (problem + intended fix + how to verify) from
   `.harness/specs/_templates/inbox-brief.md`. Do **NOT** create any feature
   `.spec.md`/`.plan.md`/`.tasks.md`/`.tests.md`, do **NOT** create the `spec_path`
   directory, and do **NOT** spawn the Architect — brief-only, never a spec.
7. **Re-validate** `.harness/state/tasks.json` against `.harness/store/tasks.schema.json`
   after the epic create and after the fix append. If it fails, report the failure and do
   NOT claim a successful seed.
8. **Hand off in-session.** After seeding + re-validation, **hand the seeded fix off to
   the existing `sdd: false → Builder → Reviewer` loop in-session** — do not stop at
   seeding. Trigger the existing Orchestrator routing (`pending + sdd: false → Builder →
   Reviewer`, the same behaviour `/sdd-next` drives) on the just-seeded fix; **reuse** that
   routing, do not re-implement it. The Fixer writes no production code (the Builder does).
9. **Report** the maintenance-epic state (created/reused `E99`), the seeded fix (id +
   title + `spec_path` + `autonomous` value), the inbox brief, that no spec / `spec_path`
   directory / Architect was created or spawned, and that the fix was handed off to the
   existing `sdd: false` loop in-session.
EOF
  # Mirror the generated command bodies into the SELECTED front-ends. Claude Code
  # reads .claude/commands/ (gated on `claude`, R3/R4); OpenCode reads
  # .opencode/command/ (gated on `opencode`, R3/R4). Both copy from the same CMDDIR,
  # so OpenCode commands appear even when `claude` is deselected.
  if agent_selected claude; then
    mkdir -p "$TARGET/.claude/commands"
    for _c in $HARNESS_SDD_CMDS; do
      cp "$CMDDIR/$_c.md" "$TARGET/.claude/commands/$_c.md"
    done
    ok "Claude Code commands /sdd-next + /sdd-new + /sdd-plan + /sdd-drill + /sdd-fix installed (.claude/)"
  fi

  # ── 5b. OpenCode commands (regenerated each run, gated on `opencode`) ────────
  # With no `agent:` frontmatter the command runs under the primary agent, which is
  # the orchestrator in the opencode.json below.
  if agent_selected opencode; then
    mkdir -p "$TARGET/.opencode/command"
    for _c in $HARNESS_SDD_CMDS; do
      cp "$CMDDIR/$_c.md" "$TARGET/.opencode/command/$_c.md"
    done
    ok "OpenCode commands /sdd-next + /sdd-new + /sdd-plan + /sdd-drill + /sdd-fix installed (.opencode/)"
  fi

  # ── 5c. Antigravity glue (.agents/, regenerated each run, gated on `antigravity`) ─
  # Antigravity (a Gemini-based agentic IDE) natively reads workspace-local
  # <root>/.agents/{rules,agents,workflows}/*.md. We stamp a glue layer that POINTS at
  # the canonical roles in .harness/agents/*.md — it never forks a role body. Mirrors
  # the per-tool pattern: personas model the .claude/agents shims (R4/R5 — best-effort:
  # bare-file persona discovery is unconfirmed, so they are written but not relied on),
  # and the workflows are COPIED from the shared CMDDIR command bodies exactly like
  # OpenCode (§5b), so the three front-ends stay byte-identical (R9). Placed after §5b and
  # before the CMDDIR cleanup so the workflow bodies are still available. (E07-F01 R2,R4,R6.)
  if agent_selected antigravity; then
    mkdir -p "$TARGET/.agents/rules" "$TARGET/.agents/agents" "$TARGET/.agents/workflows"

    # Entrypoint rule (R2/R3): points the agent at the source of truth + entry role;
    # mandates init.sh first. No copied role body — references by .harness/ path only.
    # Body lives in gen_ag_rule (hoisted) so the §7 deselect compare can reproduce it.
    gen_ag_rule "$TARGET/.agents/rules/harness.md"

    # Personas (R4/R5 — best-effort): one per harness role, each with a `description` + a
    # body that DEFERS to the canonical .harness/agents/<role>.md, mandates init.sh-first +
    # halt-on-fail, and hands off via .harness/progress/. No copied role body. Bare-file
    # persona discovery is UNCONFIRMED, so these are written (cheap, possibly honored) but
    # the harness does not claim they register as subagents — the durable model is the rule
    # + the `description`-gated workflows (R12). Descriptions come from ag_personas (the
    # single role→description source, shared with the §7 deselect compare so they can never
    # diverge).
    ag_personas | while IFS='	' read -r _agr _agd; do
      [ -n "$_agr" ] || continue
      gen_ag_persona "$_agr" "$_agd" "$TARGET/.agents/agents/$_agr.md"
    done

    # Workflows (R6/R7/R8/R9): COPY the shared command bodies from CMDDIR (mirror, like
    # the OpenCode block — do not re-author). The bodies already begin with their own
    # `---\ndescription: …\n---` frontmatter, which satisfies Antigravity's slash-command
    # registration (R7), and they already act as their role resolved against
    # .harness/agents/*.md carrying $ARGUMENTS (R8). A `cp` keeps them byte-identical to
    # the Claude/OpenCode copies so the front-ends stay byte-identical.
    for _w in $HARNESS_SDD_CMDS; do
      cp "$CMDDIR/$_w.md" "$TARGET/.agents/workflows/$_w.md"
    done

    ok "Antigravity glue (rules + agents + workflows) installed (.agents/)"
  fi

  # ── 5d. Codex CLI prompts (GLOBAL, gated on `codex`) ─────────────────────────
  # Codex CLI has no project-local custom-command mechanism (no `.codex/commands/`
  # or workspace-local prompts dir it reads). Its ONLY custom-slash-command surface
  # is the GLOBAL prompts dir `${CODEX_HOME:-$HOME/.codex}/prompts/*.md`, where each
  # `<name>.md` registers as the slash command `/prompts:<name>` (Codex namespaces
  # prompt files under `/prompts:`, NOT top-level `/<name>`). So — unlike every other
  # front-end, whose glue
  # is workspace-local under $TARGET — the `codex` stamp writes OUTSIDE the target, to
  # a single machine-global dir. Consequences, by design (accepted at install time):
  #   • the prompts are shared by EVERY harness target on this machine (they overwrite
  #     each other), and are not scoped per-repo;
  #   • that is harmless because each body resolves its relative paths against `.harness/`
  #     of whatever repo Codex is launched in (Codex runs from the repo root and reads
  #     that repo's AGENTS.md), so ONE global copy correctly drives any target;
  #   • deselect removal (§7) only reclaims byte-pristine copies (a user edit survives),
  #     and honors $CODEX_HOME so it never touches an unrelated home.
  # Copies the same CMDDIR bodies as §5b/§5c, so all front-ends stay byte-identical.
  if agent_selected codex; then
    _cdx="$(codex_prompts_dir)"
    if [ -z "$_cdx" ]; then
      # Neither CODEX_HOME nor HOME set: skip Codex glue rather than abort the whole
      # install (other front-ends must still complete). (Codex r1 P2.)
      echo "⚠️  codex selected but neither CODEX_HOME nor HOME is set — skipping GLOBAL /prompts:sdd-* install" >&2
    else
      mkdir -p "$_cdx"
      for _c in $HARNESS_SDD_CMDS; do
        _dst="$_cdx/$_c.md"
        # This dir is a USER-owned global namespace, not a harness-owned workspace dir,
        # so a same-named file may be the user's OWN pre-existing global prompt. Never
        # silently destroy it: if an existing file differs from the harness body, back
        # the ORIGINAL up ONCE (don't clobber a prior backup on repeated upgrades) and
        # warn, then install. Absent or already-identical files are written directly.
        # (Codex r2 P2.)
        if [ -f "$_dst" ] && ! cmp -s "$_dst" "$CMDDIR/$_c.md"; then
          if [ ! -f "$_dst.pre-harness.bak" ]; then
            cp "$_dst" "$_dst.pre-harness.bak"
            echo "⚠️  existing global Codex prompt $_dst backed up to $_dst.pre-harness.bak before installing the harness copy" >&2
          fi
        fi
        cp "$CMDDIR/$_c.md" "$_dst"
      done
      # Codex surfaces a prompts-dir file `<name>.md` as the slash command
      # `/prompts:<name>` (NOT top-level `/<name>`) — advertise it that way.
      ok "Codex CLI prompts /prompts:sdd-next + /prompts:sdd-new + /prompts:sdd-plan + /prompts:sdd-drill + /prompts:sdd-fix installed (GLOBAL: $_cdx)"
    fi
  fi

  # NOTE: CMDDIR cleanup is intentionally DEFERRED to AFTER §7 — the antigravity
  # deselect compare byte-checks each `.agents/workflows/<name>.md` against the
  # source `$CMDDIR/<name>.md`, so the temp workflow bodies must stay available
  # through the reconciliation loop. CMDDIR is only a temp dir; cleaning it later
  # is harmless and still unconditional. (Codex r2 P1 #3404240336.)

  # ── 6. opencode.json (gated on `opencode`; create if absent; never clobber) ──
  if agent_selected opencode && [ ! -f "$TARGET/opencode.json" ]; then
    gen_opencode_json "$TARGET/opencode.json"
    ok "opencode.json created"
  elif agent_selected opencode; then
    info "opencode.json exists — left untouched (point it at .harness/ manually if you use OpenCode)"
  fi

  # ── 7. selection persistence + add/remove reconciliation (E08-F01) ───────────
  # Persist the resolved selection beside .harness-version as harness-owned metadata
  # (one sorted key per line, overwritten every run) (R8).
  printf '%s\n' "$SELECTED" > "$H/.agents"

  # Reconcile removals (R12 adds are handled by the gated stamps above): for any key
  # in the PRIOR persisted set but NOT in SELECTED, delete that agent's harness-owned,
  # regenerated glue and warn, naming each removed path. NEVER touch AGENTS.md or the
  # .harness/ body (R13). Scoped to the registry-owned paths only.
  if [ -n "$PRIOR_AGENTS" ]; then
    printf '%s\n' "$PRIOR_AGENTS" | while IFS= read -r _rk; do
      [ -n "$_rk" ] || continue
      agent_selected "$_rk" && continue   # still selected → keep
      case "$_rk" in
        claude)
          remove_pointer CLAUDE.md
          remove_owned .claude/agents   claude $HARNESS_CLAUDE_SHIMS
          remove_owned .claude/commands claude $HARNESS_SDD_CMDS
          rmdir "$TARGET/.claude" 2>/dev/null || true   # prune parent only if now empty
          ;;
        gemini)
          # GEMINI.md is SHARED: it is the in-repo entrypoint for gemini AND
          # antigravity (E07-F01 R1/R12). Remove it only when NEITHER owner remains
          # selected — otherwise deselecting gemini while antigravity stays selected
          # would wrongly strip Antigravity's entrypoint.
          if ! agent_selected antigravity; then
            remove_pointer GEMINI.md
            echo "⚠️  removed deselected agent 'gemini' glue: GEMINI.md harness block" >&2
          fi
          ;;
        opencode)
          remove_owned .opencode/command opencode $HARNESS_SDD_CMDS
          rmdir "$TARGET/.opencode" 2>/dev/null || true   # prune parent only if now empty
          # opencode.json: delete ONLY a file byte-identical to what the installer
          # generates (a pristine, untouched stamp). ANY user edit — even adding a
          # `model`/providers key to the generated file — makes it differ, so it is
          # left in place with a warning. This is precise where the old substring
          # heuristic was too broad and could delete edited config. (Codex r4 P2)
          if [ -f "$TARGET/opencode.json" ]; then
            _ref="$(mktemp 2>/dev/null || mktemp -t harness-oc)"
            gen_opencode_json "$_ref"
            if cmp -s "$TARGET/opencode.json" "$_ref"; then
              rm -f "$TARGET/opencode.json"
              echo "⚠️  removed deselected agent 'opencode' glue: opencode.json (pristine generated)" >&2
            else
              echo "⚠️  opencode.json differs from the generated stamp (edited) — left in place (deselected 'opencode' not removed)" >&2
            fi
            rm -f "$_ref"
          fi
          ;;
        antigravity)
          # E07-F01: the antigravity stamp (§5c) OWNS a scoped `.agents/` glue tree
          # (rules/harness.md, the role personas, the sdd-* workflows). Deselection
          # removes ONLY files byte-identical to a freshly-generated stamp (pristine)
          # — NOT delete-by-name — so a user's OWN `.agents/agents/builder.md` (or any
          # standard-named persona/workflow they authored) survives. This mirrors the
          # opencode.json `cmp -s` contract above and fixes the data-loss case where a
          # pre-this-version no-op antigravity install left `antigravity` persisted in
          # `.harness/.agents` while the user authored their own `.agents/` files.
          # (Codex r2 P1 #3404240336; r3 P1 #3400997183 stays honored — scoped, never
          # destructive of non-harness files.)
          _agtmp="$(mktemp 2>/dev/null || mktemp -t harness-ag)"
          # rule
          gen_ag_rule "$_agtmp"
          remove_if_pristine .agents/rules/harness.md "$_agtmp" antigravity
          # personas — compare each against its freshly-generated body (same source
          # role→description map as the install loop, so no divergence).
          ag_personas | while IFS='	' read -r _agr _agd; do
            [ -n "$_agr" ] || continue
            gen_ag_persona "$_agr" "$_agd" "$_agtmp"
            remove_if_pristine ".agents/agents/$_agr.md" "$_agtmp" antigravity
          done
          # workflows — the install path `cp`s these verbatim from $CMDDIR, so the
          # pristine reference is the still-present $CMDDIR/<name>.md source bytes.
          for _agw in $HARNESS_SDD_CMDS; do
            [ -f "$CMDDIR/$_agw.md" ] || continue
            remove_if_pristine ".agents/workflows/$_agw.md" "$CMDDIR/$_agw.md" antigravity
          done
          rm -f "$_agtmp"
          # Prune each now-empty `.agents/` subdir + the parent, only when empty
          # (never `rm -rf` — preserve any user files left in place above).
          rmdir "$TARGET/.agents/rules" 2>/dev/null || true
          rmdir "$TARGET/.agents/agents" 2>/dev/null || true
          rmdir "$TARGET/.agents/workflows" 2>/dev/null || true
          rmdir "$TARGET/.agents" 2>/dev/null || true   # prune parent only if now empty
          # GEMINI.md is SHARED with gemini (E07-F01 R1/R12). Antigravity owns it as
          # an in-repo entrypoint too, so remove it on antigravity deselection ONLY
          # when gemini is also not selected — mirroring the gemini case. (Without
          # this, deselecting an antigravity-only install would orphan GEMINI.md,
          # since the gemini branch never runs when gemini was never a prior agent.)
          if ! agent_selected gemini; then
            remove_pointer GEMINI.md
            echo "⚠️  removed deselected agent 'antigravity' glue: GEMINI.md harness block" >&2
          fi
          ;;
        codex)
          # §5d installs GLOBAL prompts to ${CODEX_HOME:-$HOME/.codex}/prompts. Reclaim
          # ONLY byte-pristine copies (cmp -s against the still-present $CMDDIR source),
          # so a user-edited /sdd-* prompt survives — mirroring the opencode.json /
          # antigravity pristine-only contract. Honors $CODEX_HOME. NOTE: these prompts
          # are machine-global and may be shared by another harness target that still
          # selects `codex`; a subsequent install there re-stamps them (bodies are
          # regenerated every run), so removal here is safe but announced as GLOBAL.
          _cdx="$(codex_prompts_dir)"
          if [ -n "$_cdx" ]; then
            _cdx_removed=""
            for _cdw in $HARNESS_SDD_CMDS; do
              [ -f "$CMDDIR/$_cdw.md" ] || continue
              if [ -f "$_cdx/$_cdw.md" ] && cmp -s "$_cdx/$_cdw.md" "$CMDDIR/$_cdw.md"; then
                rm -f "$_cdx/$_cdw.md"
                _cdx_removed="$_cdx_removed $_cdw.md"
              elif [ -f "$_cdx/$_cdw.md" ]; then
                echo "⚠️  $_cdx/$_cdw.md differs from the generated prompt (edited) — left in place (deselected 'codex' not fully removed)" >&2
              fi
            done
            [ -n "$_cdx_removed" ] && echo "⚠️  removed deselected agent 'codex' glue:$_cdx_removed (in $_cdx/ — GLOBAL, shared prompts)" >&2
            rmdir "$_cdx" 2>/dev/null || true   # prune only if now empty
          fi
          ;;
      esac
    done
  fi

  # CMDDIR cleanup (deferred from §5c): the antigravity deselect compare above needs
  # the temp workflow bodies. Unconditional — always runs regardless of selection.
  rm -rf "$CMDDIR"

  # ── done ────────────────────────────────────────────────────────────────────
  echo "──────────────────────────────────────────────────"
  if [ "$UPGRADE" = 1 ]; then
    ok "upgrade complete (v$VERSION)"
  else
    ok "install complete (v$VERSION)"
    echo
    echo "Next steps:"
    echo "  1. Edit .harness/specs/product.md for your product."
    echo "  2. Open the repo in Claude Code and run  /sdd-next  to bootstrap"
    echo "     (detect test/lint commands, draft your first epics)."
  fi

  LAST_UPGRADE="$UPGRADE"
}

# ── manifest auto-population (append-only upsert, never clobbers entries) ──────
# manifest_upsert <manifest-path> <repo-name>
#   Ensures the manifest has a top-level `repos:` header and a block for <repo-name>.
#   If the key already exists under repos:, the block is left untouched (a
#   bootstrap-filled test_command/delegate_cmd survives re-runs). New entries get a
#   relative path and TODO placeholders. Two-space repo keys match init.sh's grammar.
manifest_upsert() {
  _mf="$1"; _name="$2"
  if [ ! -f "$_mf" ]; then
    printf 'repos:\n' > "$_mf"
  elif ! grep -Eq '^repos:[[:space:]]*$' "$_mf"; then
    # File exists but has no top-level `repos:` header (empty or comments-only).
    # init.sh only recognizes repo entries AFTER a `repos:` line, so add it —
    # otherwise the appended child blocks below would be unreadable.
    printf 'repos:\n' >> "$_mf"
  fi
  # Already present UNDER repos:? — never clobber. Scope the check to the repos:
  # mapping so a same-named two-space key in an unrelated section (e.g. `metadata:`)
  # is not mistaken for the repo entry.
  if awk -v n="$_name" '
       /^repos:[[:space:]]*$/ { r=1; next }
       r && /^[^[:space:]#]/ { r=0 }
       r && $0 ~ ("^  " n ":[[:space:]]*$") { found=1 }
       END { exit found ? 0 : 1 }
     ' "$_mf"; then
    return 0
  fi
  # Build the entry as a single string with literal `\n` escapes — `awk -v` converts
  # them to newlines (a value with real newlines would error "newline in string").
  _blk='  '"$_name"':\n    path: ./'"$_name"'\n    init: ./init.sh         # TODO: confirm child init\n    test_command: ""        # TODO: set during bootstrap\n    delegate_cmd: ""        # TODO: wire executor'
  # Insert the entry INSIDE the repos: mapping — immediately before the next top-level
  # key after `repos:` (a column-0, non-comment, non-blank line), or at EOF when
  # repos: is the last section. Appending blindly at EOF would otherwise nest the entry
  # under a later top-level section (e.g. a trailing `metadata:`), which init.sh — and
  # therefore the coordinator — would not read.
  awk -v blk="$_blk" '
    /^repos:[[:space:]]*$/ { print; in_repos=1; next }
    in_repos && !inserted && /^[^[:space:]#]/ { print blk; inserted=1; in_repos=0 }
    { print }
    END { if (in_repos && !inserted) print blk }
  ' "$_mf" > "$_mf.uptmp" && mv "$_mf.uptmp" "$_mf"
}

# ── arg parsing ───────────────────────────────────────────────────────────────
UMBRELLA=""
RECURSIVE=0
DRY_RUN=0
SHARED_REPO=0
POSITIONAL=""
# Agent selection override (E08-F01): --agents=<csv> wins over HARNESS_AGENTS, which
# wins over the interactive prompt / no-TTY ALL default. Seed from the environment so
# `--agents` (parsed below) can supersede it; an empty value means "no override".
AGENTS_OVERRIDE="${HARNESS_AGENTS:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --agents=*)
      # Explicit override; an empty value (`--agents=`) is treated as "no override"
      # (fall through to the prompt / ALL default), matching HARNESS_AGENTS="".
      AGENTS_OVERRIDE="${1#--agents=}"
      shift
      ;;
    --agents)
      [ "$#" -ge 2 ] || die "usage: $0 --agents=<csv> (e.g. --agents=claude,opencode)"
      AGENTS_OVERRIDE="$2"
      shift 2
      ;;
    --umbrella)
      [ "$#" -ge 2 ] || die "usage: $0 --umbrella <umbrella-dir> [--shared-repo] [--recursive] [--dry-run]"
      UMBRELLA="$2"
      shift 2
      ;;
    --shared-repo)
      # Opt-in: version-control the umbrella root (git init + ignore product children).
      # Umbrella mode only; validated below. See docs/UMBRELLA.md "Shared spec repository".
      SHARED_REPO=1
      shift
      ;;
    --recursive)
      RECURSIVE=1
      shift
      ;;
    --dry-run|--list)
      # Preview the cascade: list the coordinator + every git child that WOULD be
      # installed (with skip reasons), writing nothing. Umbrella mode only.
      DRY_RUN=1
      shift
      ;;
    --)
      shift
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      if [ -z "$POSITIONAL" ]; then POSITIONAL="$1"; else die "unexpected argument: $1"; fi
      shift
      ;;
  esac
done

# ── single-target mode (no --umbrella): behave exactly as before ──────────────
if [ -z "$UMBRELLA" ]; then
  [ "$DRY_RUN" = 0 ] || die "--dry-run/--list is umbrella-mode only (use with --umbrella)"
  [ "$SHARED_REPO" = 0 ] || die "--shared-repo is umbrella-mode only (use with --umbrella)"
  if [ "${POSITIONAL}" = "" ]; then die "usage: $0 <target-repo-path>"; fi
  TGT="$POSITIONAL"
  if [ ! -d "$TGT" ]; then die "target '$TGT' is not a directory"; fi
  TGT="$(CDPATH= cd -- "$TGT" && pwd)"
  if [ "$TGT" = "$SRC" ]; then die "target must differ from the harness source ($SRC)"; fi
  install_one "$TGT"
  exit 0
fi

# ── umbrella mode (cascade) ───────────────────────────────────────────────────
if [ ! -d "$UMBRELLA" ]; then die "umbrella dir '$UMBRELLA' is not a directory"; fi
if [ -n "$POSITIONAL" ]; then die "do not pass a positional <target> with --umbrella"; fi
# Resolve PHYSICAL paths (pwd -P) so a symlinked umbrella that points at the harness
# source is caught here — otherwise the coordinator install would self-install into
# the source checkout (same footgun the child-loop guard already prevents).
UMB="$(CDPATH= cd -- "$UMBRELLA" && pwd -P)"
if [ "$UMB" = "$(CDPATH= cd -- "$SRC" && pwd -P)" ]; then die "umbrella dir must differ from the harness source ($SRC)"; fi

if [ "$DRY_RUN" = 1 ]; then
  echo "══ umbrella cascade (DRY RUN — nothing will be written) → $UMB ══"
else
  echo "══ umbrella cascade → $UMB ══"
fi

# (a) coordinator profile into the umbrella dir.
if [ "$DRY_RUN" = 1 ]; then
  echo "would install coordinator profile → $UMB/.harness/"
  echo "would set/keep umbrella.manifest → ../umbrella.manifest.yaml (ENGAGES umbrella mode)"
  echo "── discovering git children (depth 1) ──"
  found_any=0
  for child in "$UMB"/*/; do
    [ -d "$child" ] || continue
    name="$(basename "$child")"
    case "$name" in .*) continue ;; .harness) continue ;; esac
    [ -e "$child/.git" ] || continue
    child_abs="$(CDPATH= cd -- "$child" && pwd -P)"
    if [ "$child_abs" = "$(CDPATH= cd -- "$SRC" && pwd -P)" ]; then
      echo "  skip  $name  (it is the harness source)"; continue
    fi
    found_any=1
    if ! printf '%s' "$name" | grep -Eq '^[a-z0-9-]+$'; then
      echo "  skip  $name  (name must match ^[a-z0-9-]+\$)"; continue
    fi
    echo "  would install + add manifest entry:  $name"
  done
  [ "$found_any" = 1 ] || echo "  (no git children found under $UMB at depth 1)"
  if [ "$SHARED_REPO" = 1 ]; then
    echo "── --shared-repo: version-control the umbrella root ──"
    if [ -e "$UMB/.git" ]; then
      echo "  would KEEP existing git repo at $UMB (never re-inits)"
    else
      echo "  would run: git init $UMB"
    fi
    echo "  would append-seed $UMB/.gitignore to ignore the discovered child repos above"
  fi
  echo "── end dry run — re-run without --dry-run/--list to apply ──"
  exit 0
fi

install_one "$UMB"

# Ensure the coordinator config carries an integration_command key (migration on a
# preserved config already handles this; on a fresh seed the shipped config has it).
# Then point umbrella.manifest at umbrella.manifest.yaml when it is unset/blank.
COORD_CFG="$UMB/.harness/harness.config.yaml"
migrate_config "$COORD_CFG"
# The manifest lives at the umbrella ROOT, but init.sh resolves umbrella.manifest
# relative to the harness dir (.harness/), so the default value is ../umbrella.manifest.yaml.
# When umbrella.manifest is blank (any form: ``, `""`, `''`, each with an optional
# trailing comment — migrate_config emits exactly that), point it at the root manifest.
# This operates ONLY inside the top-level `umbrella:` section, so a nested `manifest:`
# elsewhere is never matched or rewritten. A real value is preserved (skip activation).
if [ -z "$(_cfg_umbrella_manifest_value "$COORD_CFG")" ]; then
  awk '
    /^umbrella:[[:space:]]*(#.*)?$/ { u=1; print; next }
    u && /^[^[:space:]#]/ { u=0 }
    u && !done && $0 ~ /^[[:space:]]+manifest:[[:space:]]*("")?[[:space:]]*(#.*)?$/ {
      sub(/manifest:.*/, "manifest: \"../umbrella.manifest.yaml\""); done=1; print; next
    }
    u && !done && $0 ~ /^[[:space:]]+manifest:[[:space:]]*('"''"')[[:space:]]*(#.*)?$/ {
      sub(/manifest:.*/, "manifest: \"../umbrella.manifest.yaml\""); done=1; print; next
    }
    { print }
  ' "$COORD_CFG" > "$COORD_CFG.umtmp" && mv "$COORD_CFG.umtmp" "$COORD_CFG"
  info "coordinator umbrella.manifest -> ../umbrella.manifest.yaml — UMBRELLA MODE ENGAGED (init.sh now runs the coordinator loop; unset this value to revert to single-repo)"
fi

# Locked design: the auto-populated manifest ALWAYS lives at the umbrella root
# (`<umbrella>/umbrella.manifest.yaml`, read by init.sh as ../umbrella.manifest.yaml).
# If a coordinator has been pointed at a CUSTOM non-root path, the cascade does not
# try to write there — child `path:` entries are relative to the manifest's own dir,
# so a non-root manifest would mis-resolve every child. Warn and use the root file.
MANIFEST="$UMB/umbrella.manifest.yaml"
_cfg_manifest="$(_cfg_umbrella_manifest_value "$COORD_CFG")"
case "$_cfg_manifest" in
  ""|../umbrella.manifest.yaml|./umbrella.manifest.yaml|umbrella.manifest.yaml) : ;;  # the supported root location
  *)
    echo "⚠️  coordinator umbrella.manifest is a custom path ('$_cfg_manifest') — the cascade only auto-populates the root '$UMB/umbrella.manifest.yaml'. Point umbrella.manifest there, or maintain the custom manifest by hand." ;;
esac

# (b) discover immediate git children + (c) populate the manifest.
echo "── discovering git children (depth 1) ──"
if [ "$RECURSIVE" = 1 ]; then
  info "--recursive: deeper scan is accepted but deferred; scanning depth 1 only"
fi
[ -f "$MANIFEST" ] || printf 'repos:\n' > "$MANIFEST"   # R11

found_any=0
INSTALLED_CHILDREN=""   # newline-separated names of children actually installed (for --shared-repo)
for child in "$UMB"/*/; do
  # the literal glob (no matches) yields the pattern itself — guard it.
  [ -d "$child" ] || continue
  name="$(basename "$child")"
  # R9: skip dotfile dirs and the umbrella's own .harness.
  case "$name" in
    .*) continue ;;
    .harness) continue ;;
  esac
  [ "$name" = ".harness" ] && continue
  # R8: git child iff `.git` exists as a directory OR a file.
  [ -e "$child/.git" ] || continue
  # Never install into the harness source itself — when the installer checkout is an
  # immediate child of the umbrella (e.g. `harness-sdd/harness-install.sh --umbrella ..`)
  # it would otherwise get .harness/, pointer blocks, and .claude/ glue written into it.
  # Compare PHYSICAL paths (pwd -P) so a symlinked child that resolves to the source
  # is caught too, not just a same-named real directory.
  child_abs="$(CDPATH= cd -- "$child" && pwd -P)"
  src_phys="$(CDPATH= cd -- "$SRC" && pwd -P)"
  if [ "$child_abs" = "$src_phys" ]; then
    echo "⚠️  skipping child '$name': it is the harness source ($SRC) — not installing into the harness itself"
    continue
  fi
  found_any=1
  # R13: directory name must satisfy the slice-id repo-key grammar.
  if ! printf '%s' "$name" | grep -Eq '^[a-z0-9-]+$'; then
    echo "⚠️  skipping child '$name': name must match ^[a-z0-9-]+\$ (slice-id repo-key grammar) — no install, no manifest entry"
    continue
  fi
  echo "── child: $name ──"
  install_one "$UMB/$name"   # R10
  manifest_upsert "$MANIFEST" "$name"   # R12, R14
  INSTALLED_CHILDREN="$INSTALLED_CHILDREN$name
"
done

if [ "$found_any" = 0 ]; then
  info "no git children found under $UMB (depth 1)"
fi

# (d) --shared-repo: make the umbrella ROOT its own git repo (a shared "spec repository")
# that tracks .harness/ + umbrella docs and git-ignores the product child repos. OPT-IN —
# this whole block is skipped without the flag, so the default stays a non-git parent dir.
if [ "$SHARED_REPO" = 1 ]; then
  echo "── --shared-repo: version-control the umbrella root ──"
  if [ -e "$UMB/.git" ]; then
    info "umbrella root already a git repo — leaving it as-is (never re-inits)"
  elif command -v git >/dev/null 2>&1; then
    ( cd "$UMB" && git init -q ) && info "git init $UMB (shared spec repository)"
  else
    echo "⚠️  git not found — skipped 'git init'. Install git and run 'git init' in $UMB yourself; the .gitignore below is still seeded."
  fi

  # The umbrella-root .gitignore already carries personal/runtime ignores (seeded by the
  # coordinator's install_one above). APPEND the product child repos so they are tracked
  # as their OWN repos, never as gitlinks/nested content in this shared spec repo. We ignore
  # ONLY the children we actually installed into (discovered git repos) — never a blanket
  # rule that could swallow tracked harness/doc content. Append-only + idempotent.
  IGN="$UMB/.gitignore"
  if [ -n "$INSTALLED_CHILDREN" ]; then
    grep -qF '# Product repos (each its own git repo) — tracked separately' "$IGN" 2>/dev/null \
      || printf '\n# Product repos (each its own git repo) — tracked separately, NOT in this shared spec repo.\n' >> "$IGN"
    printf '%s' "$INSTALLED_CHILDREN" | while IFS= read -r _c; do
      [ -n "$_c" ] || continue
      _pat="/$_c/"
      grep -qxF "$_pat" "$IGN" 2>/dev/null || printf '%s\n' "$_pat" >> "$IGN"
    done
    info "umbrella-root .gitignore ignores product child repos (append-only)"
  fi
  echo "   shared spec repo: $UMB tracks .harness/ + umbrella docs; product repos git-ignored."
fi

echo "══════════════════════════════════════════════════"
ok "umbrella cascade complete (v$VERSION)"
echo "   coordinator: $UMB/.harness   manifest: $MANIFEST"
