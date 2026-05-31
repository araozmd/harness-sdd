# init.project.sh — project-specific gate checks.
# Sourced by init.sh from the PROJECT ROOT (not .harness/), so paths and commands
# like `npm test` / `pytest` resolve against the repo. Seeded once; NEVER clobbered
# on upgrade — put your real checks here instead of editing init.sh. Inherits the
# `fail "msg"` (abort the gate) and `ok "msg"` helpers from init.sh.
#
# Examples:
#   command -v node >/dev/null 2>&1 || fail "node not installed"
#   npm test --silent             || fail "tests are failing — do not start work"
