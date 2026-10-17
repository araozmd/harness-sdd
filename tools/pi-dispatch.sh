#!/bin/sh
# pi-dispatch.sh — run ONE harness role as a separate `pi -p` process (E35-F02, ADR-0007
# option C). The always-available fallback when the community `pi-subagents` package (the
# `subagent` tool, option B) is not loaded.
#
# usage: pi-dispatch.sh <role> <task-file>
#
# The allowlist (`tools:`), the optional `model:` / `thinking:` and the prompt body all
# come from the generated role file `.pi/agents/<role>.md` — the SINGLE source shared with
# the `pi-subagents` path, so B and C cannot drift. The task file's contents ride in one
# argv element behind a fixed preamble, so the message never starts with `-` or `@`.
#
# Exit codes (checked in this order, so a bad role file with no `pi` on PATH exits 3):
#   2    bad usage: wrong argument count, role outside [a-z][a-z0-9-]*, or a task file that
#        is absent, non-regular or unreadable
#   3    unusable role file: absent, a symlink, the wrong node type, under a symlinked or
#        non-directory `.pi` / `.pi/agents`, or `tools:` / `model:` / `thinking:` invalid
#        (E35-F03: also a repeated `model:`/`thinking:` line, a `model:` over 256 bytes or
#        beginning with `-`, or a `model:` ending in `:<level>` beside a `thinking:` line)
#   127  no `pi` on PATH
#   else pi's own exit status (stdout is passed through unchanged)
# Every diagnostic goes to stderr, prefixed `pi-dispatch: `; stdout carries only pi's.
#
# Writes nothing in the repository: its only write is one mktemp file, removed on every
# exit path. Never reads or writes `~/.pi/agent`.
set -eu

fail() { # fail <exit-code> <message>
  echo "pi-dispatch: $2" >&2
  exit "$1"
}

[ "$#" -eq 2 ] || fail 2 "usage: pi-dispatch.sh <role> <task-file>"
role="$1"
task="$2"
# Whole-string validation: a glob class also matches an embedded newline (a line-based
# grep would not), so `a\nb` is rejected here.
case "$role" in
  ''|[!a-z]*|*[!a-z0-9-]*) fail 2 "invalid role name '$role' (expected [a-z][a-z0-9-]*)" ;;
esac
[ -f "$task" ] && [ -r "$task" ] || fail 2 "task file '$task' is not a readable regular file"
# Resolve before any cd.
case "$task" in /*) ;; *) task="$PWD/$task" ;; esac

# Project root: the parent of `.harness/` when installed, else the repository root
# (the harness-report.sh idiom).
H="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
case "$H" in */.harness) PROJ="${H%/*}" ;; *) PROJ="$H" ;; esac

# Role file. Same node-type rule as the installer's `pi_node_unsafe` (a tools/ script cannot
# source the installer): a component is unusable when it is a symlink (live or dangling) or
# exists as the wrong node type. A non-directory `.pi` or `.pi/agents` needs no check of its own:
# the leaf below cannot exist beneath it, so it fails the leaf test. A symlinked directory DOES
# need one — the leaf would resolve through it.
for _d in "$PROJ/.pi" "$PROJ/.pi/agents"; do
  if [ -L "$_d" ]; then fail 3 "$_d is a symlink"; fi
done
R="$PROJ/.pi/agents/$role.md"
if [ -L "$R" ] || [ ! -f "$R" ]; then
  fail 3 "role file .pi/agents/$role.md is absent, a symlink or not a regular file"
fi

# Frontmatter: line 1 is `---`, closed by the next line that is exactly `---`.
[ "$(sed -n '1p' "$R")" = '---' ] || fail 3 "$R has no frontmatter"
close="$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$R")"
[ -n "$close" ] || fail 3 "$R frontmatter is not closed"
fm="$(sed -n "2,$((close - 1))p" "$R")"

# fm_get <key> — first `key:` line's value (empty and "absent" are told apart by fm_has).
fm_has() { printf '%s\n' "$fm" | grep -q "^$1:"; }
fm_get() { printf '%s\n' "$fm" | sed -n "s/^$1:[[:space:]]*//p" | sed -n '1p'; }

tools="$(fm_get tools | tr -d ' ')"
[ -n "$tools" ] || fail 3 "$R has a missing or empty tools: value"
case "$tools" in
  *[!A-Za-z0-9_:,.*/+-]*) fail 3 "$R tools: value has characters outside the allowed set" ;;
esac

model=""
if fm_has model; then
  model="$(fm_get model)"
  case "$model" in
    ''|*[!A-Za-z0-9._:/@-]*) fail 3 "$R model: value is empty or has characters outside the allowed set" ;;
  esac
fi
thinking=""
if fm_has thinking; then
  thinking="$(fm_get thinking)"
  case "$thinking" in
    off|minimal|low|medium|high|xhigh|max) ;;
    *) fail 3 "$R thinking: value '$thinking' is not one of off|minimal|low|medium|high|xhigh|max" ;;
  esac
fi

# E35-F03 R6 — B/C agreement and argv safety. pi-subagents is last-wins on a repeated key
# (tools: included — a second tools: line would grant different permissions per path)
# and `fm_get` is first-wins, so a repeated key is drift; an overlong or `-`-leading model
# is not a model id; a `:<level>` model suffix beside a `thinking:` line runs at one level
# here (`--thinking` wins) and another through pi-subagents (suffix wins). The charset
# bracket above is textually the installer's `pi_pin_verdict` one (pinned by test_pi_agents.sh).
for _k in tools model thinking; do
  _n="$(printf '%s\n' "$fm" | grep -c "^$_k:" || true)"
  [ "$_n" -le 1 ] || fail 3 "$R has $_n $_k: lines (expected at most one)"
done
if [ -n "$model" ]; then
  [ "${#model}" -le 256 ] || fail 3 "$R model: value is longer than 256 bytes"
  case "$model" in
    -*) fail 3 "$R model: value begins with '-'" ;;
  esac
  if [ -n "$thinking" ]; then
    case "${model##*:}" in
      off|minimal|low|medium|high|xhigh|max)
        case "$model" in
          *:*) fail 3 "$R model: ends in a :<thinking> suffix while thinking: is also set" ;;
        esac ;;
    esac
  fi
fi

command -v pi >/dev/null 2>&1 || fail 127 "pi is not on PATH"

# Body = everything after the closing `---`, handed over as a FILE (an existing path is
# unambiguous for --append-system-prompt).
_tmp="$(mktemp 2>/dev/null || mktemp -t pi-dispatch)"
trap 'rm -f "$_tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sed -n "$((close + 1)),\$p" "$R" > "$_tmp"

# Run from the project root. The task path was made absolute above, so it is still readable here.
cd "$PROJ"
msg="$(printf 'You are the harness %s role (dispatched by pi-dispatch.sh). Your task follows.\n\n%s' "$role" "$(cat "$task")")"

set -- -p -a --no-session --no-skills
if [ -n "$model" ]; then set -- "$@" --model "$model"; fi
if [ -n "$thinking" ]; then set -- "$@" --thinking "$thinking"; fi
set -- "$@" --tools "$tools" --append-system-prompt "$_tmp" "$msg"

# No `exec`: the trap must still remove the temp file. `|| rc=$?` is the set -e-safe capture.
rc=0
pi "$@" || rc=$?
exit "$rc"
