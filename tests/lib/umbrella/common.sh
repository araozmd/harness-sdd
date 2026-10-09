set -eu
# E25-F01: non-Claude front-ends are parked by default on FRESH targets, so a bare
# installer run now stamps claude only. This suite's fixtures predate the flip and
# assert artifacts across the full matrix; pin the pre-flip selection explicitly
# (an explicit --agents in any call still wins over this env seed).
export HARNESS_AGENTS="claude,codex,opencode"

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCHEMA="$SRC/store/tasks.schema.json"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-umbrella)"
AU=""
umbrella_cleanup() {
  # Audit fixtures can contain deliberately read-only trees.
  if [ -n "$AU" ]; then
    chmod -R u+w "$AU" 2>/dev/null || :
    rm -rf "$AU"
  fi
  rm -rf "$T"
}
trap umbrella_cleanup EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

have_py() { command -v python3 >/dev/null 2>&1; }
