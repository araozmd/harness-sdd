#!/bin/sh
# test_mirror.sh — board mirror (tools/sync-board.mjs) + post-write hook + config
# migration. Behavioral assertions: the INERT DEFAULT path is a true no-op (never shells
# out to `gh`), recognized stubs no-op, a misconfigured real provider errors, and the
# config migration append-seeds the new keys idempotently. Per the harness test ethos we
# assert BEHAVIOR, never pin the exact VERSION. Node-running cases are skipped (still
# reported) when node is unavailable, so the suite stays green on a node-less box.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALLER="$ROOT/harness-install.sh"
TOOL="$ROOT/tools/sync-board.mjs"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harnessmirror)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

[ -f "$TOOL" ] || fail "tools/sync-board.mjs missing from the body"
pass "sync-board.mjs ships in the body [tool_present]"

# A fake .harness layout the tool resolves config + tasks against (HERE/../).
mk_harness() { # mk_harness <dir> <provider-block>
  _h="$1"; _prov="$2"
  mkdir -p "$_h/tools" "$_h/state"
  cp "$TOOL" "$_h/tools/sync-board.mjs"
  printf '{"epics":[{"id":"E01","title":"Demo","features":[{"id":"E01-F01","title":"X","status":"pending"}]}]}\n' > "$_h/state/tasks.json"
  printf 'store:\n  tasks: local\n%s\n' "$_prov" > "$_h/harness.config.yaml"
}

# A fake `gh` on PATH that records ANY invocation — proves the inert path never shells out.
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<EOF
#!/bin/sh
echo "called: \$*" >> "$T/gh-called"
exit 0
EOF
chmod +x "$T/bin/gh"

if command -v node >/dev/null 2>&1; then
  # 1) INERT DEFAULT — empty provider ⇒ exit 0, "disabled" notice, and NO gh call.
  H1="$T/h-default"; mk_harness "$H1" 'mirror:
  board:
    provider: ""'
  rm -f "$T/gh-called"
  OUT="$(PATH="$T/bin:$PATH" node "$H1/tools/sync-board.mjs" 2>&1)" || fail "inert default exited non-zero"
  printf '%s' "$OUT" | grep -qi "disabled" || { echo "$OUT"; fail "inert default did not report disabled"; }
  [ ! -f "$T/gh-called" ] || { cat "$T/gh-called"; fail "inert default shelled out to gh (must be a pure no-op)"; }
  pass "empty provider ⇒ no-op, never calls gh [inert_default_noop]"

  # 2) STUB providers — recognized, no-op exit 0, no gh call.
  for prov in jira azure-boards; do
    HS="$T/h-$prov"; mk_harness "$HS" "mirror:
  board:
    provider: \"$prov\""
    rm -f "$T/gh-called"
    OUT="$(PATH="$T/bin:$PATH" node "$HS/tools/sync-board.mjs" 2>&1)" || fail "$prov stub exited non-zero"
    printf '%s' "$OUT" | grep -qi "not implemented" || { echo "$OUT"; fail "$prov stub did not say not implemented"; }
    [ ! -f "$T/gh-called" ] || fail "$prov stub shelled out to gh"
  done
  pass "jira + azure-boards stubs no-op, never call gh [stub_providers_noop]"

  # 3) UNKNOWN provider ⇒ non-zero exit (clear error, no silent pass).
  HU="$T/h-unknown"; mk_harness "$HU" 'mirror:
  board:
    provider: "trello"'
  if PATH="$T/bin:$PATH" node "$HU/tools/sync-board.mjs" >/dev/null 2>&1; then
    fail "unknown provider should exit non-zero"
  fi
  pass "unknown provider rejected [unknown_provider_rejected]"

  # 4) github-projects MISCONFIGURED (no owner/project/repo) ⇒ non-zero, names the keys,
  #    and exits BEFORE touching gh (config is validated first).
  HM="$T/h-ghmiss"; mk_harness "$HM" 'mirror:
  board:
    provider: "github-projects"'
  rm -f "$T/gh-called"
  if PATH="$T/bin:$PATH" node "$HM/tools/sync-board.mjs" >"$T/ghmiss.out" 2>&1; then
    fail "github-projects with no config should exit non-zero"
  fi
  grep -qi "owner" "$T/ghmiss.out" || fail "misconfig error does not name the missing keys"
  [ ! -f "$T/gh-called" ] || fail "misconfig path shelled out to gh before validating config"
  pass "github-projects without config errors before calling gh [ghprojects_misconfig_errors]"

  # 5) github-projects FULLY configured ⇒ the YAML parser reads owner/project/repo and
  #    dispatches to gh with them (proves nested-key parsing — the riskiest custom code).
  #    The fake gh records args; real syncing needs live gh, so we only assert dispatch.
  HG="$T/h-ghok"; mk_harness "$HG" 'mirror:
  board:
    provider: "github-projects"
    owner: "acme-org"
    project_number: 7
    repo: "acme-org/specs"'
  rm -f "$T/gh-called"
  PATH="$T/bin:$PATH" node "$HG/tools/sync-board.mjs" >/dev/null 2>&1 || true
  [ -f "$T/gh-called" ] || fail "configured github-projects never dispatched to gh"
  grep -q 'project view 7' "$T/gh-called" || { cat "$T/gh-called"; fail "parser did not read project_number"; }
  grep -q 'acme-org' "$T/gh-called"       || { cat "$T/gh-called"; fail "parser did not read owner"; }
  pass "github-projects parses nested config + dispatches to gh [ghprojects_parses_config]"

  # 6) status_map ⇒ the nested-map reader maps statuses to CUSTOM board columns. A
  #    dispatching fake gh returns minimal project/field JSON; with --dry-run the tool
  #    reports the column names it WOULD set, which must be the mapped ones, not identity.
  mkdir -p "$T/bin2"
  cat > "$T/bin2/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "project view")       echo '{"id":"PID"}' ;;
  "project field-list") echo '{"fields":[{"id":"FS","name":"Status","options":[{"id":"o","name":"X"}]},{"id":"FE","name":"Epic","options":[]}]}' ;;
  "project item-list")  echo '{"items":[]}' ;;
  "issue list")         echo '[]' ;;
  *)                    echo '{}' ;;
esac
exit 0
EOF
  chmod +x "$T/bin2/gh"
  HSM="$T/h-statusmap"; mk_harness "$HSM" 'mirror:
  board:
    provider: "github-projects"
    owner: "acme-org"
    project_number: 7
    repo: "acme-org/specs"
    status_map:
      pending: "Todo"
      in-review: "In review"'
  OUT="$(PATH="$T/bin2:$PATH" node "$HSM/tools/sync-board.mjs" --dry-run 2>&1)" || { echo "$OUT"; fail "status_map dry-run errored"; }
  SLINE="$(printf '%s\n' "$OUT" | grep -i 'Status options' || true)"
  printf '%s' "$SLINE" | grep -q 'Todo'                  || { echo "$OUT"; fail "status_map did not map pending -> Todo"; }
  printf '%s' "$SLINE" | grep -q 'In review'             || { echo "$OUT"; fail "status_map did not map in-review -> In review"; }
  printf '%s' "$SLINE" | grep -Eq '(^|[^-])pending' && fail "identity 'pending' column leaked despite status_map override"
  pass "status_map remaps board columns via config, no file edit [status_map_overrides_columns]"

  # 7) assignee ⇒ status-gated assign/unassign + dynamic "@me" resolution. A dispatching
  #    fake gh resolves `gh api user` to a login and returns two pre-existing issues: one
  #    for an in-progress feature (unassigned → should assign) and one for a pending feature
  #    already assigned (not-started → should unassign). --dry-run reports both intents and
  #    the "@me -> login" resolution, without mutating anything.
  mkdir -p "$T/bin3"
  cat > "$T/bin3/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "api user")           echo 'resolveduser' ;;
  "project view")       echo '{"id":"PID"}' ;;
  "project field-list") echo '{"fields":[{"id":"FS","name":"Status","options":[{"id":"o","name":"in-progress"}]},{"id":"FE","name":"Epic","options":[{"id":"oe","name":"E01 — Demo"}]}]}' ;;
  "project item-list")  echo '{"items":[{"id":"IT1","content":{"number":42}},{"id":"IT2","content":{"number":43}}]}' ;;
  "issue list")         echo '[{"number":42,"title":"E01-F01 — X","url":"https://github.com/acme-org/specs/issues/42","state":"OPEN","assignees":[]},{"number":43,"title":"E01-F02 — Y","url":"https://github.com/acme-org/specs/issues/43","state":"OPEN","assignees":[{"login":"resolveduser"}]}]' ;;
  *)                    echo '{}' ;;
esac
exit 0
EOF
  chmod +x "$T/bin3/gh"
  HAS="$T/h-assignee"; mkdir -p "$HAS/tools" "$HAS/state"
  cp "$TOOL" "$HAS/tools/sync-board.mjs"
  printf '{"epics":[{"id":"E01","title":"Demo","features":[{"id":"E01-F01","title":"X","status":"in-progress"},{"id":"E01-F02","title":"Y","status":"pending"}]}]}\n' > "$HAS/state/tasks.json"
  printf 'store:\n  tasks: local\nmirror:\n  board:\n    provider: "github-projects"\n    owner: "acme-org"\n    project_number: 7\n    repo: "acme-org/specs"\n    assignee: "@me"\n' > "$HAS/harness.config.yaml"
  OUT="$(PATH="$T/bin3:$PATH" node "$HAS/tools/sync-board.mjs" --dry-run 2>&1)" || { echo "$OUT"; fail "assignee dry-run errored"; }
  printf '%s' "$OUT" | grep -q "@me' -> resolveduser"          || { echo "$OUT"; fail "'@me' was not resolved to the authed gh login"; }
  printf '%s' "$OUT" | grep -q 'would assign #42 -> resolveduser'   || { echo "$OUT"; fail "in-progress feature was not assigned"; }
  printf '%s' "$OUT" | grep -q 'would unassign #43 <- resolveduser' || { echo "$OUT"; fail "regressed/not-started feature was not unassigned"; }
  pass "assignee: @me resolves + status-gates assign/unassign [assignee_status_gated]"

  # 8) assignee UNSET ⇒ the mirror never touches assignees (back-compat: no assign/unassign
  #    log lines even though issues exist and statuses vary).
  HNA="$T/h-noassignee"; mkdir -p "$HNA/tools" "$HNA/state"
  cp "$TOOL" "$HNA/tools/sync-board.mjs"
  cp "$HAS/state/tasks.json" "$HNA/state/tasks.json"
  printf 'store:\n  tasks: local\nmirror:\n  board:\n    provider: "github-projects"\n    owner: "acme-org"\n    project_number: 7\n    repo: "acme-org/specs"\n' > "$HNA/harness.config.yaml"
  OUT="$(PATH="$T/bin3:$PATH" node "$HNA/tools/sync-board.mjs" --dry-run 2>&1)" || { echo "$OUT"; fail "no-assignee dry-run errored"; }
  printf '%s' "$OUT" | grep -Eqi 'assign' && { echo "$OUT"; fail "assignee unset but the mirror still touched assignees"; }
  pass "assignee unset ⇒ mirror never touches assignees [assignee_default_inert]"
else
  pass "node-running cases skipped (node unavailable) [inert_default_noop]"
fi

# ── config migration: a pre-mirror config gains the new keys, idempotently ──────
PRE="$T/pre"; mkdir -p "$PRE"
printf '# My Project\n' > "$PRE/CLAUDE.md"
sh "$INSTALLER" "$PRE" >/dev/null 2>&1 || fail "fresh install failed"
CFG="$PRE/.harness/harness.config.yaml"
grep -Eq '^[[:space:]]+on_write_command:' "$CFG" || fail "store.on_write_command not seeded on fresh install"
grep -Eq '^mirror:[[:space:]]*$' "$CFG"          || fail "mirror: block not seeded on fresh install"
grep -Eq '^[[:space:]]+provider:' "$CFG"         || fail "mirror.board.provider not seeded on fresh install"
[ -x "$PRE/.harness/tools/sync-board.mjs" ]      || fail "installed sync-board.mjs not executable"
pass "fresh install seeds on_write_command + mirror block, tool executable [fresh_seeds_keys]"

# Simulate a pre-0.12 config (no store hook, no mirror block) + a bootstrap value that must
# survive, then upgrade.
cat > "$CFG" <<'EOF'
store:
  tasks: local
verification:
  test_command: "pytest -q"   # keep me exactly
EOF
sh "$INSTALLER" "$PRE" >/dev/null 2>&1 || fail "upgrade over pre-0.12 config failed"
grep -Eq '^[[:space:]]+on_write_command:' "$CFG" || fail "on_write_command not appended on upgrade"
grep -Eq '^mirror:[[:space:]]*$' "$CFG"          || fail "mirror: block not appended on upgrade"
grep -qF 'test_command: "pytest -q"   # keep me exactly' "$CFG" || fail "upgrade altered an existing value/comment"
pass "upgrade append-seeds the keys, preserves existing values [upgrade_seeds_keys]"

# Idempotent: a complete config is left byte-for-byte identical on a second run.
cp "$CFG" "$T/after1"
sh "$INSTALLER" "$PRE" >/dev/null 2>&1 || fail "second upgrade failed"
cmp -s "$CFG" "$T/after1" || { diff "$T/after1" "$CFG" || true; fail "migration not idempotent (mirror/hook duplicated)"; }
pass "mirror/hook migration is idempotent on a complete config [migration_idempotent]"

echo "All mirror tests passed."
