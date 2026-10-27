#!/bin/sh
# host-frontend.sh — print the front-end this session runs inside, or nothing. (E99-F182)
#
# The PRODUCER of the key `tools/builder-role.sh --frontend <key>` consumes (ADR-0011). The
# Orchestrator pipes this tool's output straight into that flag — it never types a key it
# believes is right, because a typed key is the guess the escalation rule exists to replace:
#
#     role="$(sh "$HARNESS_DIR/tools/builder-role.sh" "<complexity>" "<round>" … \
#               --frontend "$(sh "$HARNESS_DIR/tools/host-frontend.sh")")"
#
# Evidence, in precedence order — the same evidence and order harness-install.sh's
# `detect_host` trusts (E19-F01):
#   1. HARNESS_HOST_AGENT, when it is exactly ONE key that has a marker row below. Any other
#      non-empty value (an unknown token, several tokens, `host`, or a known front-end with no
#      marker row such as `antigravity`) warns once on stderr and is otherwise ignored.
#   2. The session markers: exactly one front-end with a NON-EMPTY marker ⇒ its key; none ⇒
#      nothing; two or more ⇒ nothing plus one `ambiguous` warning. Ambiguity is never a
#      tie-break — the table is not ordered by confidence.
# Printing nothing is normal operation: builder-role.sh then applies the all-front-ends rule
# (the arming file's first line), which is exactly the pre-ADR-0011 behaviour.
#
# THE SECOND-COPY RULE. The rows below are a byte-for-byte copy of `HOST_MARKERS` in
# harness-install.sh. The installer is not present in an installed target (`.harness/` ships
# `tools/`, not `harness-install.sh`), so this tool cannot call `detect_host`; the copy is
# PARITY-TESTED instead (tests/test_host_frontend.sh::marker_rows_parity — same keys, same
# variables, same order), the E36-F04 precedent. The rows' provenance — which CLI version each
# marker was observed on, and the rejected candidates — lives beside the installer's table
# and is not repeated here. Change a row THERE first, then copy it here; the parity test reds
# until both agree.
#
# Usage:
#   tools/host-frontend.sh            print the host key (or nothing), exit 0
#   tools/host-frontend.sh --help|-h  print this usage on stdout, exit 0
#   anything else                     usage on stderr, exit 4
#
# Contract: stdout carries at most one key and a newline; every diagnostic goes to stderr.
# Reads only the environment — never a file, never git, never the network — and writes
# nothing. Exits 0 on every detection outcome, including "cannot tell".

set -eu

usage() { echo "usage: host-frontend.sh   (no arguments — prints the host front-end key, or nothing)"; }

case "$#" in
  0) : ;;
  *)
    case "$1" in
      --help|-h) [ "$#" -eq 1 ] || { usage >&2; exit 4; }; usage; exit 0 ;;
      *) usage >&2; exit 4 ;;
    esac ;;
esac

HOST_MARKERS="
claude CLAUDECODE CLAUDE_CODE_ENTRYPOINT
codex CODEX_THREAD_ID
opencode OPENCODE OPENCODE_PID OPENCODE_SESSION_ID OPENCODE_TERMINAL
pi PI_CODING_AGENT
"

# marker_present <var-name> — true iff the NAMED variable is set and NON-EMPTY. The `${…:-}`
# guard is load-bearing under `set -u`, where a bare expansion of an unset marker aborts. The
# name comes only from the literal table above, never from input, so the eval is closed.
marker_present() {
  eval "_mp_val=\${$1:-}"
  [ -n "$_mp_val" ]
}

# The walk: every key with at least one present marker, one per line, sorted and unique.
_hits="$(
  printf '%s\n' "$HOST_MARKERS" | while IFS= read -r _row; do
    [ -n "$_row" ] || continue
    _key=""
    for _var in $_row; do
      if [ -z "$_key" ]; then _key="$_var"; continue; fi
      if marker_present "$_var"; then printf '%s\n' "$_key"; break; fi
    done
  done | sort -u
)"

_n=0
for _k in $_hits; do _n=$((_n + 1)); done
if [ "$_n" -eq 1 ]; then
  printf '%s\n' "$_hits"
elif [ "$_n" -gt 1 ]; then
  echo "⚠️  host detection ambiguous — session markers present for: $(printf '%s' "$_hits" | tr '\n' ' ')— no host key (builder-role.sh will use the all-front-ends rule)" >&2
fi
exit 0
