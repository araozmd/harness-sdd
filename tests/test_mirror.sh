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
# Sandbox Codex's GLOBAL prompts dir (§5d) so ALL-default installs below never touch
# the developer's real ~/.codex. (See test_install.sh for the same guard.)
export CODEX_HOME="$T/codex-home"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

[ -f "$TOOL" ] || fail "tools/sync-board.mjs missing from the body"
pass "sync-board.mjs ships in the body [tool_present]"

# ── docs pin (R6 / R13) — behavior test on the governing phrases, not verbatim prose ──
DOCS="$ROOT/store/board-mirror.md"
[ -f "$DOCS" ] || fail "store/board-mirror.md missing"
grep -qi 'Projects v2'            "$DOCS" || fail "docs do not pin Projects v2 [projects_v2_pinned_in_docs]"
grep -qi 'Classic'                "$DOCS" || fail "docs do not state Classic Projects are unsupported"
pass "docs pin the supported surface as Projects v2 (Classic unsupported) [projects_v2_pinned_in_docs]"
grep -qi '2.31.0' "$DOCS" || fail "docs do not name the minimum gh version (2.31.0)"
grep -qi 'project'                "$DOCS" || fail "docs do not name the required project scope"
grep -qi 'repo'                   "$DOCS" || fail "docs do not name the required repo scope"
grep -qi 'no[- ]*mcp\|never[[:space:]]*mcp\|not[[:space:]]*mcp' "$DOCS" \
  || grep -qi 'gh` CLI ONLY'      "$DOCS" || fail "docs do not reaffirm the gh-only / no-MCP transport"
grep -qi 'one-way'                "$DOCS" || fail "docs do not reaffirm the one-way invariant"
pass "docs pin gh transport contract: min gh version + scopes + gh-only/no-MCP + one-way [docs_pin_gh_transport_contract]"

# ── VERSION shape (R14) — SemVer shape + a matching CHANGELOG entry. Behavior/shape only:
# NEVER pin the exact string and NEVER diff the working tree against HEAD/main.
VER="$(tr -d '[:space:]' < "$ROOT/VERSION")"
echo "$VER" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "VERSION is not valid SemVer MAJOR.MINOR.PATCH [version_bumped_minor]"
grep -qF "## [$VER]" "$ROOT/CHANGELOG.md" || fail "CHANGELOG.md has no entry matching the current VERSION [version_bumped_minor]"
pass "VERSION is valid SemVer with a matching CHANGELOG entry [version_bumped_minor]"

# A fake .harness layout the tool resolves config + tasks against (HERE/../).
mk_harness() { # mk_harness <dir> <provider-block>
  _h="$1"; _prov="$2"
  mkdir -p "$_h/tools" "$_h/state"
  cp "$TOOL" "$_h/tools/sync-board.mjs"
  printf '{"epics":[{"id":"E01","title":"Demo","features":[{"id":"E01-F01","title":"X","status":"pending"}]}]}\n' > "$_h/state/tasks.json"
  printf 'store:\n  tasks: local\n%s\n' "$_prov" > "$_h/harness.config.yaml"
}

# A fake `gh` on PATH that records ANY invocation — proves the inert path never shells out.
# It also answers the strengthened preflight (R7): `gh --version` reports a recent version
# and `gh auth status` reports the required `project` + `repo` scopes, so the happy-path
# dispatch cases below get PAST the preflight. Preflight-failure is exercised separately
# with dedicated shims (::preflight_gh_capability_fails_closed).
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<EOF
#!/bin/sh
echo "called: \$*" >> "$T/gh-called"
case "\$1 \$2" in
  "--version ") echo "gh version 2.62.0 (2024-11-27)" ;;
  "auth status") echo "Token scopes: 'project', 'read:org', 'repo'" ;;
esac
exit 0
EOF
chmod +x "$T/bin/gh"

# The dispatching fake-gh shims below (bin2/bin3/bin4) each answer the R7 preflight
# (`--version` + `auth status`) inline so they reach the reconcile dispatch they assert on.

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

  # 2) STUB providers — recognized, no-op exit 0, no gh call. (jira is IMPLEMENTED as of
  #    E12-F01 and exercised in the dedicated jira block below; azure-boards stays a stub.)
  for prov in azure-boards; do
    HS="$T/h-$prov"; mk_harness "$HS" "mirror:
  board:
    provider: \"$prov\""
    rm -f "$T/gh-called"
    OUT="$(PATH="$T/bin:$PATH" node "$HS/tools/sync-board.mjs" 2>&1)" || fail "$prov stub exited non-zero"
    printf '%s' "$OUT" | grep -qi "not implemented" || { echo "$OUT"; fail "$prov stub did not say not implemented"; }
    [ ! -f "$T/gh-called" ] || fail "$prov stub shelled out to gh"
  done
  pass "azure-boards stub no-ops, never calls gh [stub_providers_noop]"

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
  "--version ")         echo "gh version 2.62.0 (2024-11-27)"; exit 0 ;;
  "auth status")        echo "Token scopes: 'project', 'read:org', 'repo'"; exit 0 ;;
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
  #    fake gh resolves `gh api user` to a login and returns two pre-existing issues, each
  #    already assigned to a DIFFERENT user. The mirror owns the field and RECONCILES to the
  #    exact desired set: the in-progress feature (assigned 'carol') should reconcile to the
  #    resolved login — add resolveduser AND remove carol; the pending feature (assigned
  #    'alice') should clear to none. --dry-run reports all three intents and the
  #    "@me -> login" resolution, without mutating anything.
  mkdir -p "$T/bin3"
  cat > "$T/bin3/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "--version ")         echo "gh version 2.62.0 (2024-11-27)"; exit 0 ;;
  "auth status")        echo "Token scopes: 'project', 'read:org', 'repo'"; exit 0 ;;
  "api user")           echo 'resolveduser' ;;
  "project view")       echo '{"id":"PID"}' ;;
  "project field-list") echo '{"fields":[{"id":"FS","name":"Status","options":[{"id":"o","name":"in-progress"}]},{"id":"FE","name":"Epic","options":[{"id":"oe","name":"E01 — Demo"}]}]}' ;;
  "project item-list")  echo '{"items":[{"id":"IT1","content":{"number":42}},{"id":"IT2","content":{"number":43}}]}' ;;
  "issue list")         echo '[{"number":42,"title":"E01-F01 — X","url":"https://github.com/acme-org/specs/issues/42","state":"OPEN","assignees":[{"login":"carol"}]},{"number":43,"title":"E01-F02 — Y","url":"https://github.com/acme-org/specs/issues/43","state":"OPEN","assignees":[{"login":"alice"}]}]' ;;
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
  printf '%s' "$OUT" | grep -q 'would assign #42 -> resolveduser'   || { echo "$OUT"; fail "in-progress feature was not assigned the resolved login"; }
  printf '%s' "$OUT" | grep -q 'would unassign #42 <- carol'        || { echo "$OUT"; fail "started item did not reconcile off a foreign assignee"; }
  printf '%s' "$OUT" | grep -q 'would unassign #43 <- alice'        || { echo "$OUT"; fail "not-started feature did not clear a teammate's stale assignee"; }
  pass "assignee: @me resolves + reconciles started/not-started to the exact set [assignee_status_gated]"

  # 8) assignee UNSET ⇒ the mirror never touches assignees (back-compat: no assign/unassign
  #    log lines even though issues exist and statuses vary).
  HNA="$T/h-noassignee"; mkdir -p "$HNA/tools" "$HNA/state"
  cp "$TOOL" "$HNA/tools/sync-board.mjs"
  cp "$HAS/state/tasks.json" "$HNA/state/tasks.json"
  printf 'store:\n  tasks: local\nmirror:\n  board:\n    provider: "github-projects"\n    owner: "acme-org"\n    project_number: 7\n    repo: "acme-org/specs"\n' > "$HNA/harness.config.yaml"
  OUT="$(PATH="$T/bin3:$PATH" node "$HNA/tools/sync-board.mjs" --dry-run 2>&1)" || { echo "$OUT"; fail "no-assignee dry-run errored"; }
  printf '%s' "$OUT" | grep -Eqi 'assign' && { echo "$OUT"; fail "assignee unset but the mirror still touched assignees"; }
  pass "assignee unset ⇒ mirror never touches assignees [assignee_default_inert]"

  # 9) case-insensitive idempotency — GitHub logins are case-insensitive, so a configured
  #    login whose casing differs from the API's canonical spelling must be a NO-OP, not a
  #    perpetual add+remove of the same account. Config assignee "OctoCat" vs an issue already
  #    assigned "octocat" on an in-progress feature ⇒ no assign and no unassign lines.
  mkdir -p "$T/bin4"
  cat > "$T/bin4/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "--version ")         echo "gh version 2.62.0 (2024-11-27)"; exit 0 ;;
  "auth status")        echo "Token scopes: 'project', 'read:org', 'repo'"; exit 0 ;;
  "project view")       echo '{"id":"PID"}' ;;
  "project field-list") echo '{"fields":[{"id":"FS","name":"Status","options":[{"id":"o","name":"in-progress"}]},{"id":"FE","name":"Epic","options":[{"id":"oe","name":"E01 — Demo"}]}]}' ;;
  "project item-list")  echo '{"items":[{"id":"IT1","content":{"number":42}}]}' ;;
  "issue list")         echo '[{"number":42,"title":"E01-F01 — X","url":"https://github.com/acme-org/specs/issues/42","state":"OPEN","assignees":[{"login":"octocat"}]}]' ;;
  *)                    echo '{}' ;;
esac
exit 0
EOF
  chmod +x "$T/bin4/gh"
  HCI="$T/h-caseidem"; mkdir -p "$HCI/tools" "$HCI/state"
  cp "$TOOL" "$HCI/tools/sync-board.mjs"
  printf '{"epics":[{"id":"E01","title":"Demo","features":[{"id":"E01-F01","title":"X","status":"in-progress"}]}]}\n' > "$HCI/state/tasks.json"
  printf 'store:\n  tasks: local\nmirror:\n  board:\n    provider: "github-projects"\n    owner: "acme-org"\n    project_number: 7\n    repo: "acme-org/specs"\n    assignee: "OctoCat"\n' > "$HCI/harness.config.yaml"
  OUT="$(PATH="$T/bin4:$PATH" node "$HCI/tools/sync-board.mjs" --dry-run 2>&1)" || { echo "$OUT"; fail "case-idempotency dry-run errored"; }
  printf '%s' "$OUT" | grep -Eqi 'would (assign|unassign)' && { echo "$OUT"; fail "case-mismatched login was not idempotent (add/remove churn)"; }
  pass "assignee diff is case-insensitive (login casing ⇒ no churn) [assignee_case_idempotent]"

  # 10) PREFLIGHT fails CLOSED (R7) — with a FULLY configured github-projects mirror, a
  #     `gh` that is (a) absent, (b) below the minimum Projects-v2 version, or (c) missing
  #     the required scope must each exit NON-ZERO, print a message NAMING gh (+ the
  #     Projects-v2 / scope requirement), and make NO board-mutating call — the preflight
  #     runs before the first project/issue query, so the recording shim shows no mutation.
  HPF="$T/h-preflight"; mk_harness "$HPF" 'mirror:
  board:
    provider: "github-projects"
    owner: "acme-org"
    project_number: 7
    repo: "acme-org/specs"'

  # (a) gh ABSENT — a curated PATH that has `node` (so the tool can run) but NO `gh` at all.
  mkdir -p "$T/bin-nogh"
  ln -sf "$(command -v node)" "$T/bin-nogh/node"
  rm -f "$T/gh-called"
  if PATH="$T/bin-nogh" node "$HPF/tools/sync-board.mjs" >"$T/pf-absent.out" 2>&1; then
    fail "preflight passed with gh absent (must fail closed)"
  fi
  grep -qi 'gh' "$T/pf-absent.out" || { cat "$T/pf-absent.out"; fail "gh-absent error does not name gh"; }
  # (mutation impossible with no gh; nothing to assert on the shim here.)

  # A fake gh that reports a BELOW-MINIMUM version and records every call (so we can prove
  # no mutation happened). It never emits project/issue JSON, so if the tool got past the
  # preflight it would crash anyway — but it must fail on the version check first.
  mkdir -p "$T/bin-old"
  cat > "$T/bin-old/gh" <<EOF
#!/bin/sh
echo "called: \$*" >> "$T/pf-old-called"
case "\$1 \$2" in
  "--version ") echo "gh version 2.20.0 (2023-01-01)" ;;
  "auth status") echo "Token scopes: 'project', 'repo'" ;;
esac
exit 0
EOF
  chmod +x "$T/bin-old/gh"
  rm -f "$T/pf-old-called"
  if PATH="$T/bin-old:$PATH" node "$HPF/tools/sync-board.mjs" >"$T/pf-old.out" 2>&1; then
    fail "preflight passed with a too-old gh (must fail closed)"
  fi
  grep -qi 'gh' "$T/pf-old.out"     || { cat "$T/pf-old.out"; fail "too-old-gh error does not name gh"; }
  grep -qi '2.31' "$T/pf-old.out"   || { cat "$T/pf-old.out"; fail "too-old-gh error does not name the min Projects-v2 version"; }
  # NO board-mutating call: the shim may see --version/auth status, but never project/issue mutations.
  if [ -f "$T/pf-old-called" ]; then
    grep -Eqi 'project (item-edit|item-add|view)|issue (create|close|reopen|edit)' "$T/pf-old-called" \
      && { cat "$T/pf-old-called"; fail "too-old gh still made a board query/mutation"; }
  fi
  pass "preflight: too-old gh ⇒ non-zero, names gh + min version, no board mutation [preflight_gh_capability_fails_closed:old]"

  # A fake gh at a fine version but whose token LACKS the `project` scope.
  mkdir -p "$T/bin-noscope"
  cat > "$T/bin-noscope/gh" <<EOF
#!/bin/sh
echo "called: \$*" >> "$T/pf-scope-called"
case "\$1 \$2" in
  "--version ") echo "gh version 2.62.0 (2024-11-27)" ;;
  "auth status") echo "Token scopes: 'read:org', 'repo'"; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$T/bin-noscope/gh"
  rm -f "$T/pf-scope-called"
  if PATH="$T/bin-noscope:$PATH" node "$HPF/tools/sync-board.mjs" >"$T/pf-scope.out" 2>&1; then
    fail "preflight passed with a token missing the project scope (must fail closed)"
  fi
  grep -qi 'gh' "$T/pf-scope.out"      || { cat "$T/pf-scope.out"; fail "missing-scope error does not name gh"; }
  grep -qi 'project' "$T/pf-scope.out" || { cat "$T/pf-scope.out"; fail "missing-scope error does not name the project scope requirement"; }
  if [ -f "$T/pf-scope-called" ]; then
    grep -Eqi 'project (item-edit|item-add|view)|issue (create|close|reopen|edit)' "$T/pf-scope-called" \
      && { cat "$T/pf-scope-called"; fail "under-scoped gh still made a board query/mutation"; }
  fi
  pass "preflight: missing project scope ⇒ non-zero, names gh + scope, no board mutation [preflight_gh_capability_fails_closed:scope]"

  # A fake gh (supported version) that writes its `auth status` output to STDERR (as gh < 2.33
  # does — cli/cli#7920) while exiting 0. The preflight must capture stdout+stderr and thus SEE
  # the required scopes on the stderr stream, so scope verification SUCCEEDS and the tool
  # proceeds PAST the preflight (no scope-missing error). It then reaches the reconcile loop;
  # this shim returns empty project/issue JSON so that loop runs harmlessly and exits 0.
  mkdir -p "$T/bin-stderr"
  cat > "$T/bin-stderr/gh" <<EOF
#!/bin/sh
echo "called: \$*" >> "$T/pf-stderr-called"
case "\$1 \$2" in
  "--version ")         echo "gh version 2.62.0 (2024-11-27)"; exit 0 ;;
  # gh < 2.33 emits the scopes line on STDERR, not stdout (cli/cli#7920):
  "auth status")        echo "Token scopes: 'project', 'read:org', 'repo'" 1>&2; exit 0 ;;
  "project view")       echo '{"id":"PID"}' ;;
  "project field-list") echo '{"fields":[{"id":"FS","name":"Status","options":[{"id":"o","name":"X"}]},{"id":"FE","name":"Epic","options":[]}]}' ;;
  "project item-list")  echo '{"items":[]}' ;;
  "issue list")         echo '[]' ;;
  *)                    echo '{}' ;;
esac
exit 0
EOF
  chmod +x "$T/bin-stderr/gh"
  rm -f "$T/pf-stderr-called"
  # --dry-run keeps this a pure read; success proves the scope check saw the stderr-only scopes.
  if ! PATH="$T/bin-stderr:$PATH" node "$HPF/tools/sync-board.mjs" --dry-run >"$T/pf-stderr.out" 2>&1; then
    cat "$T/pf-stderr.out"; fail "preflight rejected a valid login whose gh writes auth status to stderr (gh<2.33 path)"
  fi
  grep -qi 'missing required scope' "$T/pf-stderr.out" \
    && { cat "$T/pf-stderr.out"; fail "stderr-captured scopes were not recognized (scope check saw an empty stream)"; }
  # No board MUTATION (dry-run + read-only preflight): the shim may see reads, never edits.
  if [ -f "$T/pf-stderr-called" ]; then
    grep -Eqi 'project (item-edit|item-add)|issue (create|close|reopen|edit)' "$T/pf-stderr-called" \
      && { cat "$T/pf-stderr-called"; fail "stderr-auth path made a board mutation under --dry-run"; }
  fi
  pass "preflight: gh writes auth status to stderr (gh<2.33) ⇒ stdout+stderr captured, scopes recognized, proceeds [preflight_gh_auth_status_stderr]"

  # A fake gh (supported version) whose token has only `read:project` (NOT the read/write
  # `project` scope). The bare-`project` requirement must NOT be satisfied by the qualified
  # `read:project` — the preflight must FAIL CLOSED before any board call, naming the missing
  # project scope, instead of passing and later failing mid-mutation.
  mkdir -p "$T/bin-readproject"
  cat > "$T/bin-readproject/gh" <<EOF
#!/bin/sh
echo "called: \$*" >> "$T/pf-readproject-called"
case "\$1 \$2" in
  "--version ") echo "gh version 2.62.0 (2024-11-27)" ;;
  "auth status") echo "Token scopes: 'read:project', 'repo'"; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$T/bin-readproject/gh"
  rm -f "$T/pf-readproject-called"
  if PATH="$T/bin-readproject:$PATH" node "$HPF/tools/sync-board.mjs" >"$T/pf-readproject.out" 2>&1; then
    fail "preflight passed with only read:project (must fail closed on the bare project scope)"
  fi
  grep -qi 'gh' "$T/pf-readproject.out"      || { cat "$T/pf-readproject.out"; fail "read:project error does not name gh"; }
  grep -qi 'project' "$T/pf-readproject.out" || { cat "$T/pf-readproject.out"; fail "read:project error does not name the missing project scope"; }
  if [ -f "$T/pf-readproject-called" ]; then
    grep -Eqi 'project (item-edit|item-add|view)|issue (create|close|reopen|edit)' "$T/pf-readproject-called" \
      && { cat "$T/pf-readproject-called"; fail "read:project under-scoped gh still made a board query/mutation"; }
  fi
  pass "preflight: read:project does NOT satisfy bare project scope ⇒ fails closed, no board mutation [preflight_gh_read_project_fails_closed]"

  # A fake gh whose token has `repo:status` (a NARROWER scope) but NOT the bare `repo` scope,
  # plus a valid `project`. Substring/regex matching wrongly satisfied bare `repo` from inside
  # `repo:status`; with exact-token matching the bare-`repo` requirement is NOT satisfied, so the
  # preflight must FAIL CLOSED before any board call, naming the missing `repo` scope. (Round-2.)
  mkdir -p "$T/bin-repostatus"
  cat > "$T/bin-repostatus/gh" <<EOF
#!/bin/sh
echo "called: \$*" >> "$T/pf-repostatus-called"
case "\$1 \$2" in
  "--version ") echo "gh version 2.62.0 (2024-11-27)" ;;
  "auth status") echo "Token scopes: 'project', 'repo:status'"; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$T/bin-repostatus/gh"
  rm -f "$T/pf-repostatus-called"
  if PATH="$T/bin-repostatus:$PATH" node "$HPF/tools/sync-board.mjs" >"$T/pf-repostatus.out" 2>&1; then
    fail "preflight passed with only repo:status (must fail closed on the bare repo scope)"
  fi
  grep -qi 'gh' "$T/pf-repostatus.out"   || { cat "$T/pf-repostatus.out"; fail "repo:status error does not name gh"; }
  grep -qi 'repo' "$T/pf-repostatus.out" || { cat "$T/pf-repostatus.out"; fail "repo:status error does not name the missing repo scope"; }
  if [ -f "$T/pf-repostatus-called" ]; then
    grep -Eqi 'project (item-edit|item-add|view)|issue (create|close|reopen|edit)' "$T/pf-repostatus-called" \
      && { cat "$T/pf-repostatus-called"; fail "repo:status under-scoped gh still made a board query/mutation"; }
  fi
  pass "preflight: repo:status does NOT satisfy bare repo scope ⇒ fails closed, no board mutation [preflight_gh_repo_status_fails_closed]"

  # 11) gh-ONLY / no-MCP (R1) — a configured run dispatches ONLY to `gh`; neither the tool
  #     source nor the recorded calls mention any MCP transport. (The recording shim from
  #     bin/ answers preflight + returns empty JSON so the reconcile loop runs harmlessly.)
  # No MCP *transport* in the tool — inspect only CODE lines (strip `//` and `#` comments,
  # so the preflight's "never MCP" comment doesn't trip this). Every GitHub call is `gh`.
  grep -vE '^\s*(//|#|\*)' "$TOOL" | grep -qi 'mcp' \
    && fail "tool code references an MCP transport (must be gh-only)"
  HMCP="$T/h-ghonly"; mk_harness "$HMCP" 'mirror:
  board:
    provider: "github-projects"
    owner: "acme-org"
    project_number: 7
    repo: "acme-org/specs"'
  rm -f "$T/gh-called"
  PATH="$T/bin:$PATH" node "$HMCP/tools/sync-board.mjs" >/dev/null 2>&1 || true
  [ -f "$T/gh-called" ] || fail "gh-only run never dispatched to gh"
  grep -qi 'mcp' "$T/gh-called" && { cat "$T/gh-called"; fail "a run dispatched to a non-gh MCP transport"; }
  pass "configured run dispatches to gh only, never MCP [gh_only_no_mcp]"

  # 12) SINGLE github-projects code path (R2) — exactly one tool implements the provider
  #     branch; no sibling GitHub-Projects script exists in tools/.
  N_IMPL="$(grep -rlF "github-projects" "$ROOT/tools" | wc -l | tr -d ' ')"
  [ "$N_IMPL" = "1" ] || { grep -rlF "github-projects" "$ROOT/tools"; fail "expected exactly one github-projects code path in tools/, found $N_IMPL"; }
  grep -q "github-projects" "$TOOL" || fail "the single tool does not carry the github-projects provider branch"
  pass "exactly one github-projects code path (the single mirror tool) [single_github_codepath]"

  # 13) IDEMPOTENT reconcile (R3) — with a dispatching fake gh that already returns the
  #     feature's issue AND its project item, a run must NOT create a duplicate issue or
  #     re-add the item to the project (it reconciles the existing mapping).
  mkdir -p "$T/bin-recon"
  cat > "$T/bin-recon/gh" <<EOF
#!/bin/sh
echo "called: \$*" >> "$T/recon-called"
case "\$1 \$2" in
  "--version ")         echo "gh version 2.62.0 (2024-11-27)"; exit 0 ;;
  "auth status")        echo "Token scopes: 'project', 'repo'"; exit 0 ;;
  "project view")       echo '{"id":"PID"}' ;;
  "project field-list") echo '{"fields":[{"id":"FS","name":"Status","options":[{"id":"o","name":"pending"}]},{"id":"FE","name":"Epic","options":[{"id":"oe","name":"E01 — Demo"}]}]}' ;;
  "project item-list")  echo '{"items":[{"id":"IT1","content":{"number":42}}]}' ;;
  "issue list")         echo '[{"number":42,"title":"E01-F01 — X","url":"https://github.com/acme-org/specs/issues/42","state":"OPEN","assignees":[]}]' ;;
  *)                    echo '{}' ;;
esac
exit 0
EOF
  chmod +x "$T/bin-recon/gh"
  HRC="$T/h-reconcile"; mk_harness "$HRC" 'mirror:
  board:
    provider: "github-projects"
    owner: "acme-org"
    project_number: 7
    repo: "acme-org/specs"'
  rm -f "$T/recon-called"
  PATH="$T/bin-recon:$PATH" node "$HRC/tools/sync-board.mjs" >/dev/null 2>&1 || { cat "$T/recon-called" 2>/dev/null; fail "reconcile run errored"; }
  grep -Eqi 'issue create' "$T/recon-called" && { cat "$T/recon-called"; fail "re-run created a DUPLICATE issue for an already-mapped feature"; }
  grep -Eqi 'project item-add' "$T/recon-called" && { cat "$T/recon-called"; fail "re-run RE-ADDED an already-present project item (duplicate)"; }
  pass "re-run reconciles existing issue+item, no duplicate [reconcile_idempotent_rerun]"

  # 14) DRY-RUN mutates nothing (R11) — against a dispatching fake gh with NO pre-existing
  #     issue/item, --dry-run prints "would …" intents and issues zero mutating gh call.
  mkdir -p "$T/bin-dry"
  cat > "$T/bin-dry/gh" <<EOF
#!/bin/sh
echo "called: \$*" >> "$T/dry-called"
case "\$1 \$2" in
  "--version ")         echo "gh version 2.62.0 (2024-11-27)"; exit 0 ;;
  "auth status")        echo "Token scopes: 'project', 'repo'"; exit 0 ;;
  "project view")       echo '{"id":"PID"}' ;;
  "project field-list") echo '{"fields":[{"id":"FS","name":"Status","options":[{"id":"o","name":"pending"}]},{"id":"FE","name":"Epic","options":[{"id":"oe","name":"E01 — Demo"}]}]}' ;;
  "project item-list")  echo '{"items":[]}' ;;
  "issue list")         echo '[]' ;;
  *)                    echo '{}' ;;
esac
exit 0
EOF
  chmod +x "$T/bin-dry/gh"
  HDR="$T/h-dryrun"; mk_harness "$HDR" 'mirror:
  board:
    provider: "github-projects"
    owner: "acme-org"
    project_number: 7
    repo: "acme-org/specs"'
  cp "$HDR/state/tasks.json" "$T/dry-tasks-before"
  rm -f "$T/dry-called"
  OUT="$(PATH="$T/bin-dry:$PATH" node "$HDR/tools/sync-board.mjs" --dry-run 2>&1)" || { echo "$OUT"; fail "dry-run errored"; }
  printf '%s' "$OUT" | grep -qi 'would' || { echo "$OUT"; fail "dry-run did not print a 'would …' intent"; }
  grep -Eqi 'issue create|project item-add|item-edit|issue (close|reopen|edit)' "$T/dry-called" \
    && { cat "$T/dry-called"; fail "--dry-run made a mutating gh call"; }
  cmp -s "$HDR/state/tasks.json" "$T/dry-tasks-before" || fail "--dry-run wrote state/tasks.json (must mutate nothing)"
  pass "--dry-run prints intents, issues no mutating gh call, leaves tasks.json unchanged [dry_run_mutates_nothing]"

  # 15) ONE-WAY (R10) — after a real (non-dry) dispatching run, the fixture tasks.json is
  #     byte-for-byte unchanged: the mirror writes only the board, never back into state.
  #     (Fixture-local snapshot in the temp dir — NOT a diff against main.)
  cp "$HRC/state/tasks.json" "$T/oneway-before"
  PATH="$T/bin-recon:$PATH" node "$HRC/tools/sync-board.mjs" >/dev/null 2>&1 || true
  cmp -s "$HRC/state/tasks.json" "$T/oneway-before" || fail "sync wrote state/tasks.json (mirror must be one-way)"
  pass "sync never writes state/tasks.json (one-way) [one_way_never_writes_tasks_json]"

  # 16) NO new committed config key (R5) — the tool reads owner/project_number/repo from the
  #     EXISTING mirror.board shape and introduces no new mirror.board.* key or committed
  #     secret. Assert the tool references only the known key set under mirror.board.
  for k in provider owner project_number repo status_map assignee; do
    grep -q "'$k'" "$TOOL" || fail "tool no longer reads the existing mirror.board key '$k'"
  done
  # E12-F01 adds the jira-scoped keys (base_url/project_key/pat_file/issue_type_map) under
  # the SAME mirror.board block — recognized additions, not a fork.
  for k in base_url project_key pat_file issue_type_map; do
    grep -q "'$k'" "$TOOL" || fail "tool does not read the jira mirror.board key '$k'"
  done
  # No stray mirror.board key beyond the known set, and no committed token/secret literal.
  UNKNOWN="$(grep -oE "\['mirror', 'board', '[a-z_]+'\]" "$TOOL" | grep -oE "'[a-z_]+'\]" | sed "s/[]']//g" \
    | grep -vE '^(provider|owner|project_number|repo|status_map|assignee|base_url|project_key|pat_file|issue_type_map)$' || true)"
  [ -z "$UNKNOWN" ] || fail "tool introduced a new mirror.board key: $UNKNOWN"
  grep -Eqi 'ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}' "$TOOL" && fail "tool contains a committed GitHub token literal"
  pass "config read from existing mirror.board shape; no new key/secret [no_new_config_key]"

  # ══════════════════════════════════════════════════════════════════════════════
  # JIRA provider (E12-F01) — REST + Bearer PAT (Server/DC), NO MCP, status only.
  # Exercised against a STUBBED Jira REST endpoint: a local recording HTTP server that
  # logs every request (method, path, Authorization header, body) and returns canned JSON.
  # We assert on the RECORDED calls (dispatch/idempotency/headers), never a live Jira.
  # A unique SENTINEL PAT value is used so we can grep for its ABSENCE in committed
  # artifacts + tool output (secret hygiene).
  # ══════════════════════════════════════════════════════════════════════════════
  SENTINEL_PAT='SENTINELpat_DEADBEEF_do_not_leak_123456'

  # A dependency-free Node recording server. Behavior is controlled via env:
  #   J_REC   — request log file (one line per request: "METHOD PATH auth=<hdr>")
  #   J_BODY  — request-body log file (JSON bodies, one per line)
  #   J_MODE  — normal | existing | auth401 | auth403
  #   J_PORTFILE — file to write the bound port to (server binds 127.0.0.1:0)
  cat > "$T/jira-stub.mjs" <<'EOF'
import { createServer } from 'node:http';
import { writeFileSync, appendFileSync } from 'node:fs';
const REC = process.env.J_REC, BODYLOG = process.env.J_BODY;
const MODE = process.env.J_MODE || 'normal';
const PORTFILE = process.env.J_PORTFILE;
const srv = createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', () => {
    appendFileSync(REC, `${req.method} ${req.url} auth=${req.headers['authorization'] || ''}\n`);
    if (body) appendFileSync(BODYLOG, body.replace(/\n/g, ' ') + '\n');
    const send = (code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
    if (MODE === 'auth401') return send(401, { errorMessages: ['auth failed'] });
    if (MODE === 'auth403') return send(403, { errorMessages: ['forbidden'] });
    const u = req.url.split('?')[0];
    if (req.method === 'GET' && u === '/rest/api/2/search') {
      if (MODE === 'existing') return send(200, { issues: [{ key: 'HAR-1', fields: { status: { name: 'pending' } } }] });
      return send(200, { issues: [] });
    }
    if (req.method === 'POST' && u === '/rest/api/2/issue') return send(201, { key: 'HAR-NEW' });
    if (req.method === 'GET' && /\/rest\/api\/2\/issue\/[^/]+\/transitions$/.test(u)) {
      return send(200, { transitions: [
        { id: '11', name: 'To pending', to: { name: 'pending' } },
        { id: '21', name: 'Go review', to: { name: 'Custom Review' } },
        { id: '31', name: 'To in-progress', to: { name: 'in-progress' } },
      ] });
    }
    if (req.method === 'POST' && /\/rest\/api\/2\/issue\/[^/]+\/transitions$/.test(u)) return send(204, {});
    return send(200, {});
  });
});
srv.listen(0, '127.0.0.1', () => { writeFileSync(PORTFILE, String(srv.address().port)); });
EOF

  # start_jira_stub <mode> <recfile> <bodyfile> — starts the stub, echoes its base_url.
  # The server's PID is written to $T/jira-stub.pid so stop_jira_stub (running in the PARENT
  # shell, not the command-substitution subshell) can kill it reliably.
  start_jira_stub() {
    _mode="$1"; _rec="$2"; _bodyf="$3"
    : > "$_rec"; : > "$_bodyf"
    _pf="$T/jira-port"; rm -f "$_pf"
    # Redirect the server's stdio to a file so a backgrounded server never holds open the
    # command-substitution pipe of the `OUT="$(start_jira_stub …)"` caller (which would hang).
    J_REC="$_rec" J_BODY="$_bodyf" J_MODE="$_mode" J_PORTFILE="$_pf" node "$T/jira-stub.mjs" >"$T/jira-stub.log" 2>&1 &
    echo $! > "$T/jira-stub.pid"
    # wait for the port file
    _i=0; while [ ! -s "$_pf" ] && [ "$_i" -lt 50 ]; do sleep 0.1; _i=$((_i+1)); done
    [ -s "$_pf" ] || { kill "$(cat "$T/jira-stub.pid" 2>/dev/null)" 2>/dev/null; fail "jira stub server did not start"; }
    echo "http://127.0.0.1:$(cat "$_pf")"
  }
  stop_jira_stub() { [ -f "$T/jira-stub.pid" ] && kill "$(cat "$T/jira-stub.pid")" 2>/dev/null; rm -f "$T/jira-stub.pid"; return 0; }

  # mk_jira <dir> <base_url> <extra-board-yaml>  — a .harness layout with a jira mirror.
  mk_jira() {
    _h="$1"; _url="$2"; _extra="$3"
    mkdir -p "$_h/tools" "$_h/state"
    cp "$TOOL" "$_h/tools/sync-board.mjs"
    printf '{"epics":[{"id":"E01","title":"Demo","features":[{"id":"E01-F01","title":"X","status":"in-progress"}]}]}\n' > "$_h/state/tasks.json"
    {
      printf 'store:\n  tasks: local\nmirror:\n  board:\n    provider: "jira"\n'
      printf '    base_url: "%s"\n    project_key: "HAR"\n' "$_url"
      printf '%s' "$_extra"
    } > "$_h/harness.config.yaml"
  }

  # ── R1 — configured jira run projects via Jira REST ONLY, no MCP transport ──
  JR="$T/jira-rec-r1"; JB="$T/jira-body-r1"
  URL="$(start_jira_stub normal "$JR" "$JB")"
  HJ1="$T/hj-r1"; mk_jira "$HJ1" "$URL" '    pat_file: "'"$HJ1"'/pat"
'
  printf '%s' "$SENTINEL_PAT" > "$HJ1/pat"
  OUT="$(PATH="$T/bin:$PATH" JIRA_PAT="" node "$HJ1/tools/sync-board.mjs" 2>&1)" || { echo "$OUT"; stop_jira_stub; fail "jira run errored"; }
  stop_jira_stub
  [ -s "$JR" ] || fail "configured jira run made no REST call to the stub endpoint"
  grep -q '/rest/api/2/' "$JR" || { cat "$JR"; fail "jira run did not hit a Jira REST /rest/api/2/ endpoint"; }
  # No MCP transport anywhere in the tool CODE (strip comments), nor in the recorded calls.
  grep -vE '^\s*(//|#|\*)' "$TOOL" | grep -qi 'mcp' && fail "tool code references an MCP transport (jira must be REST-only)"
  grep -qi 'mcp' "$JR" && { cat "$JR"; fail "jira run dispatched to a non-REST MCP transport"; }
  pass "configured jira run projects via Jira REST only, never MCP [jira_rest_only_no_mcp]"

  # ── R2 — exactly one jira code path (the single mirror tool's jira branch) ──
  N_JIMPL="$(grep -rlF "'jira'" "$ROOT/tools" | wc -l | tr -d ' ')"
  [ "$N_JIMPL" = "1" ] || { grep -rlF "'jira'" "$ROOT/tools"; fail "expected exactly one jira code path in tools/, found $N_JIMPL"; }
  grep -q "provider === 'jira'" "$TOOL" || fail "the single tool does not carry the jira provider branch"
  pass "exactly one jira code path (the single mirror tool) [single_jira_codepath]"

  # ── R5 — auth is Server/DC Bearer PAT header (not Cloud Basic) ──
  JR="$T/jira-rec-r5"; JB="$T/jira-body-r5"
  URL="$(start_jira_stub normal "$JR" "$JB")"
  HJ5="$T/hj-r5"; mk_jira "$HJ5" "$URL" ''
  OUT="$(PATH="$T/bin:$PATH" JIRA_PAT="$SENTINEL_PAT" node "$HJ5/tools/sync-board.mjs" 2>&1)" || { echo "$OUT"; stop_jira_stub; fail "jira bearer run errored"; }
  stop_jira_stub
  grep -q "auth=Bearer $SENTINEL_PAT" "$JR" || { fail "jira request did not carry an Authorization: Bearer <PAT> header"; }
  grep -qi 'auth=Basic' "$JR" && { cat "$JR"; fail "jira built a Cloud Basic auth header (must be Bearer PAT in F01)"; }
  pass "jira authenticates with a Server/DC Bearer PAT header, never Basic [jira_bearer_pat_header]"

  # ── R6 — PAT from JIRA_PAT env (precedence) else gitignored pat_file ──
  # env precedence: env and pat_file hold DIFFERENT sentinels; the request uses the env one.
  JR="$T/jira-rec-r6e"; JB="$T/jira-body-r6e"
  URL="$(start_jira_stub normal "$JR" "$JB")"
  ENV_PAT="ENVpat_wins_9999"; FILE_PAT="FILEpat_loses_0000"
  HJ6="$T/hj-r6e"; mk_jira "$HJ6" "$URL" '    pat_file: "'"$HJ6"'/pat"
'
  printf '%s' "$FILE_PAT" > "$HJ6/pat"
  OUT="$(PATH="$T/bin:$PATH" JIRA_PAT="$ENV_PAT" node "$HJ6/tools/sync-board.mjs" 2>&1)" || { echo "$OUT"; stop_jira_stub; fail "jira env-precedence run errored"; }
  stop_jira_stub
  grep -q "auth=Bearer $ENV_PAT" "$JR"  || { cat "$JR"; fail "JIRA_PAT env did not take precedence over pat_file"; }
  grep -q "auth=Bearer $FILE_PAT" "$JR" && { cat "$JR"; fail "pat_file value used despite JIRA_PAT env being set (env must win)"; }
  pass "JIRA_PAT env takes precedence over pat_file [jira_pat_env_precedence]"

  # file fallback: JIRA_PAT unset ⇒ the request uses the (trimmed) pat_file value.
  JR="$T/jira-rec-r6f"; JB="$T/jira-body-r6f"
  URL="$(start_jira_stub normal "$JR" "$JB")"
  HJ6F="$T/hj-r6f"; mk_jira "$HJ6F" "$URL" '    pat_file: "'"$HJ6F"'/pat"
'
  printf '%s\n' "$FILE_PAT" > "$HJ6F/pat"   # trailing newline must be trimmed
  OUT="$(PATH="$T/bin:$PATH" JIRA_PAT="" node "$HJ6F/tools/sync-board.mjs" 2>&1)" || { echo "$OUT"; stop_jira_stub; fail "jira file-fallback run errored"; }
  stop_jira_stub
  grep -q "auth=Bearer $FILE_PAT" "$JR" || { cat "$JR"; fail "pat_file fallback PAT (trimmed) was not used when JIRA_PAT unset"; }
  pass "pat_file used (trimmed) when JIRA_PAT unset [jira_pat_file_fallback]"

  # ── R7 — no PAT resolvable ⇒ non-zero, names JIRA_PAT + pat_file, no network call ──
  JR="$T/jira-rec-r7"; JB="$T/jira-body-r7"
  URL="$(start_jira_stub normal "$JR" "$JB")"
  HJ7="$T/hj-r7"; mk_jira "$HJ7" "$URL" '    pat_file: "'"$HJ7"'/does-not-exist"
'
  if PATH="$T/bin:$PATH" JIRA_PAT="" node "$HJ7/tools/sync-board.mjs" >"$T/r7.out" 2>&1; then
    stop_jira_stub; fail "jira with no PAT should exit non-zero"
  fi
  stop_jira_stub
  grep -q 'JIRA_PAT' "$T/r7.out"        || { cat "$T/r7.out"; fail "no-PAT error does not name JIRA_PAT"; }
  grep -q 'does-not-exist' "$T/r7.out"  || { cat "$T/r7.out"; fail "no-PAT error does not name the pat_file path"; }
  [ ! -s "$JR" ] || { cat "$JR"; fail "no-PAT path made a Jira network call (must fail closed BEFORE any request)"; }
  pass "missing PAT fails closed, names JIRA_PAT + pat_file, no network call [jira_missing_pat_fails_closed]"

  # ── R9 — missing base_url/project_key ⇒ non-zero, names key, no network call ──
  # (No base_url ⇒ no endpoint to hit; assert it errors naming the key before any request.)
  HJ9="$T/hj-r9"; mkdir -p "$HJ9/tools" "$HJ9/state"
  cp "$TOOL" "$HJ9/tools/sync-board.mjs"
  printf '{"epics":[{"id":"E01","title":"Demo","features":[{"id":"E01-F01","title":"X","status":"pending"}]}]}\n' > "$HJ9/state/tasks.json"
  printf 'store:\n  tasks: local\nmirror:\n  board:\n    provider: "jira"\n    project_key: "HAR"\n' > "$HJ9/harness.config.yaml"
  if PATH="$T/bin:$PATH" JIRA_PAT="$SENTINEL_PAT" node "$HJ9/tools/sync-board.mjs" >"$T/r9.out" 2>&1; then
    fail "jira with no base_url should exit non-zero"
  fi
  grep -q 'base_url' "$T/r9.out" || { cat "$T/r9.out"; fail "misconfig error does not name the missing base_url key"; }
  pass "missing base_url errors before any network call [jira_misconfig_errors]"

  # ── R3 — re-run reconciles by feature-id key, creates NO duplicate issue ──
  JR="$T/jira-rec-r3"; JB="$T/jira-body-r3"
  URL="$(start_jira_stub existing "$JR" "$JB")"   # search returns an EXISTING issue for the feature
  HJ3="$T/hj-r3"; mk_jira "$HJ3" "$URL" ''
  OUT="$(PATH="$T/bin:$PATH" JIRA_PAT="$SENTINEL_PAT" node "$HJ3/tools/sync-board.mjs" 2>&1)" || { echo "$OUT"; stop_jira_stub; fail "jira reconcile run errored"; }
  stop_jira_stub
  grep -Eq 'POST /rest/api/2/issue( |$|\?)' "$JR" && { cat "$JR"; fail "re-run CREATED a duplicate issue for an already-mapped feature"; }
  grep -Eq 'POST /rest/api/2/issue/[^/]+/transitions' "$JR" || { cat "$JR"; fail "reconcile did not transition the existing issue"; }
  pass "re-run reconciles existing issue, no duplicate create [jira_reconcile_idempotent_rerun]"

  # ── R10 — epic→Epic, feature→Story defaults; issue_type_map overrides honored ──
  # defaults: no existing issues ⇒ create calls carry issuetype Epic (epic) + Story (feature).
  JR="$T/jira-rec-r10"; JB="$T/jira-body-r10"
  URL="$(start_jira_stub normal "$JR" "$JB")"
  HJ10="$T/hj-r10"; mk_jira "$HJ10" "$URL" ''
  OUT="$(PATH="$T/bin:$PATH" JIRA_PAT="$SENTINEL_PAT" node "$HJ10/tools/sync-board.mjs" 2>&1)" || { echo "$OUT"; stop_jira_stub; fail "jira issue-type default run errored"; }
  stop_jira_stub
  grep -q '"name":"Epic"' "$JB"  || { cat "$JB"; fail "epic did not default to Jira issue type Epic"; }
  grep -q '"name":"Story"' "$JB" || { cat "$JB"; fail "feature did not default to Jira issue type Story"; }
  # override: feature→Task via issue_type_map.
  JR="$T/jira-rec-r10o"; JB="$T/jira-body-r10o"
  URL="$(start_jira_stub normal "$JR" "$JB")"
  HJ10O="$T/hj-r10o"; mk_jira "$HJ10O" "$URL" '    issue_type_map:
      feature: "Task"
'
  OUT="$(PATH="$T/bin:$PATH" JIRA_PAT="$SENTINEL_PAT" node "$HJ10O/tools/sync-board.mjs" 2>&1)" || { echo "$OUT"; stop_jira_stub; fail "jira issue-type override run errored"; }
  stop_jira_stub
  grep -q '"name":"Task"' "$JB"  || { cat "$JB"; fail "issue_type_map override feature→Task not honored"; }
  grep -q '"name":"Story"' "$JB" && { cat "$JB"; fail "feature still created as Story despite issue_type_map override"; }
  pass "issue types default Epic/Story, issue_type_map overrides honored [jira_issue_type_map]"

  # ── R11 — status → Jira workflow via status_map (identity default); transitioned ──
  # identity: feature status in-progress ⇒ transition targeting the 'in-progress' state.
  JR="$T/jira-rec-r11"; JB="$T/jira-body-r11"
  URL="$(start_jira_stub existing "$JR" "$JB")"
  HJ11="$T/hj-r11"; mk_jira "$HJ11" "$URL" ''
  OUT="$(PATH="$T/bin:$PATH" JIRA_PAT="$SENTINEL_PAT" node "$HJ11/tools/sync-board.mjs" 2>&1)" || { echo "$OUT"; stop_jira_stub; fail "jira status identity run errored"; }
  stop_jira_stub
  grep -Eq 'POST /rest/api/2/issue/[^/]+/transitions' "$JR" || { cat "$JR"; fail "identity status did not issue a transition"; }
  grep -q '"id":"31"' "$JB" || { cat "$JB"; fail "identity status_map did not transition to the in-progress state (transition 31)"; }
  # override: status_map in-progress -> "Custom Review" ⇒ transition to that named state (id 21).
  JR="$T/jira-rec-r11o"; JB="$T/jira-body-r11o"
  URL="$(start_jira_stub existing "$JR" "$JB")"
  HJ11O="$T/hj-r11o"; mk_jira "$HJ11O" "$URL" '    status_map:
      in-progress: "Custom Review"
'
  OUT="$(PATH="$T/bin:$PATH" JIRA_PAT="$SENTINEL_PAT" node "$HJ11O/tools/sync-board.mjs" 2>&1)" || { echo "$OUT"; stop_jira_stub; fail "jira status override run errored"; }
  stop_jira_stub
  grep -q '"id":"21"' "$JB" || { cat "$JB"; fail "status_map override in-progress→Custom Review not used (expected transition 21)"; }
  pass "status maps to Jira workflow state via status_map (identity default), transitioned [jira_status_map_transition]"

  # ── R12 — assignee is a NO-OP for jira in F01 (no owner→assignee wiring) ──
  JR="$T/jira-rec-r12"; JB="$T/jira-body-r12"
  URL="$(start_jira_stub existing "$JR" "$JB")"
  HJ12="$T/hj-r12"; mk_jira "$HJ12" "$URL" '    assignee: "@me"
'
  OUT="$(PATH="$T/bin:$PATH" JIRA_PAT="$SENTINEL_PAT" node "$HJ12/tools/sync-board.mjs" 2>&1)" || { echo "$OUT"; stop_jira_stub; fail "jira assignee no-op run errored"; }
  stop_jira_stub
  grep -qi 'assignee' "$JB" && { cat "$JB"; fail "jira sent an assignee field (must be a no-op in F01)"; }
  grep -Eqi '/rest/api/2/issue/[^/]+/assignee' "$JR" && { cat "$JR"; fail "jira made an assignee-setting REST call (deferred to E10)"; }
  pass "assignee is a recognized no-op for jira in F01 [jira_assignee_noop]"

  # ── R13 — one-way: sync never writes state/tasks.json (fixture-local snapshot) ──
  JR="$T/jira-rec-r13"; JB="$T/jira-body-r13"
  URL="$(start_jira_stub normal "$JR" "$JB")"
  HJ13="$T/hj-r13"; mk_jira "$HJ13" "$URL" ''
  cp "$HJ13/state/tasks.json" "$T/jira-oneway-before"
  PATH="$T/bin:$PATH" JIRA_PAT="$SENTINEL_PAT" node "$HJ13/tools/sync-board.mjs" >/dev/null 2>&1 || true
  cmp -s "$HJ13/state/tasks.json" "$T/jira-oneway-before" || { stop_jira_stub; fail "jira sync wrote state/tasks.json (mirror must be one-way)"; }
  # dry-run too.
  PATH="$T/bin:$PATH" JIRA_PAT="$SENTINEL_PAT" node "$HJ13/tools/sync-board.mjs" --dry-run >/dev/null 2>&1 || true
  cmp -s "$HJ13/state/tasks.json" "$T/jira-oneway-before" || { stop_jira_stub; fail "jira --dry-run wrote state/tasks.json (must mutate nothing)"; }
  stop_jira_stub
  pass "jira sync never writes state/tasks.json (one-way) [jira_one_way_never_writes_tasks_json]"

  # ── R14 — --dry-run prints intended Jira changes, mutates nothing (no create/transition) ──
  JR="$T/jira-rec-r14"; JB="$T/jira-body-r14"
  URL="$(start_jira_stub normal "$JR" "$JB")"
  HJ14="$T/hj-r14"; mk_jira "$HJ14" "$URL" ''
  OUT="$(PATH="$T/bin:$PATH" JIRA_PAT="$SENTINEL_PAT" node "$HJ14/tools/sync-board.mjs" --dry-run 2>&1)" || { echo "$OUT"; stop_jira_stub; fail "jira dry-run errored"; }
  stop_jira_stub
  printf '%s' "$OUT" | grep -qi 'would' || { echo "$OUT"; fail "jira --dry-run did not print a 'would …' intent"; }
  grep -Eq 'POST /rest/api/2/issue( |$|\?)' "$JR" && { cat "$JR"; fail "jira --dry-run made a mutating create call"; }
  grep -Eq 'POST /rest/api/2/issue/[^/]+/transitions' "$JR" && { cat "$JR"; fail "jira --dry-run made a mutating transition call"; }
  pass "jira --dry-run prints intents, issues no mutating REST call [jira_dry_run_mutates_nothing]"

  # ── R15 — Jira 401/403 ⇒ non-zero, actionable, PAT not echoed ──
  for code in auth401 auth403; do
    JR="$T/jira-rec-$code"; JB="$T/jira-body-$code"
    URL="$(start_jira_stub "$code" "$JR" "$JB")"
    HJA="$T/hj-$code"; mk_jira "$HJA" "$URL" ''
    if PATH="$T/bin:$PATH" JIRA_PAT="$SENTINEL_PAT" node "$HJA/tools/sync-board.mjs" >"$T/$code.out" 2>&1; then
      stop_jira_stub; fail "jira $code should exit non-zero (fail closed)"
    fi
    stop_jira_stub
    grep -Eqi 'PAT|scope|permission|auth' "$T/$code.out" || { cat "$T/$code.out"; fail "$code error is not actionable (PAT/scope/permission)"; }
    grep -qF "$SENTINEL_PAT" "$T/$code.out" && { fail "$code error echoed the PAT value (must never leak)"; }
  done
  pass "jira 401/403 fail closed, actionable, PAT never echoed [jira_auth_error_fails_closed]"

  # ── R8 — PAT never leaks: never in tasks.json / seeded config / tool output ──
  # Gather EVERY jira output captured above + the fixture tasks.json + configs, and grep for
  # the sentinel PAT — it must appear NOWHERE (secret hygiene). (The .out files intentionally
  # used the sentinel via env; R15 already asserts the auth-error path doesn't echo it.)
  JR="$T/jira-rec-r8"; JB="$T/jira-body-r8"
  URL="$(start_jira_stub normal "$JR" "$JB")"
  HJ8="$T/hj-r8"; mk_jira "$HJ8" "$URL" '    pat_file: "'"$HJ8"'/pat"
'
  printf '%s' "$SENTINEL_PAT" > "$HJ8/pat"
  OUT="$(PATH="$T/bin:$PATH" JIRA_PAT="" node "$HJ8/tools/sync-board.mjs" 2>&1)" || { echo "$OUT"; stop_jira_stub; fail "jira hygiene run errored"; }
  DRYOUT="$(PATH="$T/bin:$PATH" JIRA_PAT="" node "$HJ8/tools/sync-board.mjs" --dry-run 2>&1)" || true
  stop_jira_stub
  printf '%s\n%s' "$OUT" "$DRYOUT" | grep -qF "$SENTINEL_PAT" && { fail "PAT sentinel leaked into tool stdout/stderr"; }
  grep -qF "$SENTINEL_PAT" "$HJ8/state/tasks.json" && fail "PAT sentinel leaked into state/tasks.json"
  grep -qF "$SENTINEL_PAT" "$HJ8/harness.config.yaml" && fail "PAT sentinel leaked into the mirror config"
  # The committed tool + repo config must never carry the sentinel (or any PAT literal).
  grep -qF "$SENTINEL_PAT" "$TOOL" && fail "PAT sentinel present in the committed tool"
  grep -qF "$SENTINEL_PAT" "$ROOT/harness.config.yaml" && fail "PAT sentinel present in the committed config"
  pass "PAT never written to tasks.json/config/output, never logged [jira_pat_never_leaks]"

  # ── R17 — docs pin the jira mirror REST+PAT contract (governing phrases) ──
  grep -qi 'jira contract' "$DOCS"                 || fail "board-mirror.md has no jira contract section"
  grep -qi 'Server / Data Center\|Server/DC\|Server / Data Center' "$DOCS" || fail "jira docs do not pin Server/DC"
  grep -qi 'Bearer' "$DOCS"                        || fail "jira docs do not name the Bearer PAT auth"
  grep -qi 'Cloud' "$DOCS"                         || fail "jira docs do not state Cloud is out of F01 scope"
  grep -qi 'JIRA_PAT' "$DOCS"                       || fail "jira docs do not name the JIRA_PAT env var"
  grep -qi 'pat_file' "$DOCS"                       || fail "jira docs do not name the gitignored pat_file"
  grep -qi 'precedence' "$DOCS"                     || fail "jira docs do not state the env/file precedence"
  grep -qi 'base_url' "$DOCS"                       || fail "jira docs do not name base_url"
  grep -qi 'project_key' "$DOCS"                    || fail "jira docs do not name project_key"
  grep -qi 'issue_type_map' "$DOCS"                 || fail "jira docs do not name issue_type_map"
  grep -qi 'status_map' "$DOCS"                     || fail "jira docs do not name status_map workflow mapping"
  grep -qi 'REST' "$DOCS"                           || fail "jira docs do not reaffirm the REST transport"
  grep -qi 'E10' "$DOCS"                            || fail "jira docs do not defer assignee to E10"
  grep -qi 'mirror' "$ROOT/store/jira.md"           || fail "store/jira.md lacks the mirror cross-reference"
  grep -qi 'board-mirror.md' "$ROOT/store/jira.md"  || fail "store/jira.md does not cross-reference board-mirror.md"
  pass "docs pin the jira Server/DC REST+PAT mirror contract + cross-ref [jira_docs_pin_rest_pat_contract]"

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
