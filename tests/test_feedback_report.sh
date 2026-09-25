#!/bin/sh
# test_feedback_report.sh — test contract for E32-F02 (tools/harness-report.sh).
# Zero-dependency POSIX sh (+ awk/grep/sed/git), matching the house style of
# tests/test_feedback_config.sh: a self-cleaning mktemp tree, fail/pass helpers,
# dash-clean. `gh` is STUBBED on PATH and records argv; no test touches the network.
#
# R1-R12 map to E32-F02.tests.md. The stub records every argv on its own line, so the
# exactness assertions (R6 title, R9 search query) can do full-string equality on a real
# argv value rather than a substring of a joined log.
#
# A note on the fixture: make_fixture builds an INSTALLED target
# (<tmp>/fxN/.harness/{tools,harness.config.yaml,.harness-version}), git-inits the project,
# and runs .harness/tools/harness-report.sh by path. That is what makes R5 s harness-vs-
# project path distinction clean, and it exercises the .harness-version stamp an installed
# target actually carries (there is no VERSION file under .harness/).
#
# The markdown section slicer below loads tests/lib/fence.awk and calls fence_delim($0),
# per the one-copy fence rule (tests/test_change_size.sh R9d).

set -eu
LC_ALL=C
export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL="$SRC/tools/harness-report.sh"

T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-report)"
trap 'rm -rf "$T"' EXIT

STUBDIR="$T/bin"
GLOG="$T/gh.log"
BODY="$T/body.out"
mkdir -p "$STUBDIR"
# The host has a real gh (a mise shim) later on PATH; prepending the stub makes the stub win.
PATH="$STUBDIR:$PATH"
export PATH
# Never inherit a session token from the caller environment.
unset HARNESS_FEEDBACK_SESSION_ID 2>/dev/null || true

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── the stubbed gh ────────────────────────────────────────────────────────────────────────
# Records argv (one per line, each call opened by a CALL marker) and serves configurable
# output/exit codes through SH_* controls (see run_ok). On `issue create` it also copies the
# --body-file target out, because the tool deletes its own temp dir on exit.
make_stub() {
  cat > "$STUBDIR/gh" <<'STUB'
#!/bin/sh
{
  printf 'CALL\n'
  for _a in "$@"; do printf '%s\n' "$_a"; done
} >> "${GH_LOG:?GH_LOG unset}"
case "${1:-}/${2:-}" in
  auth/status)
    [ "${GH_AUTH_RC:-0}" -eq 0 ] || exit "${GH_AUTH_RC}"
    exit 0 ;;
  issue/list)
    [ "${GH_LIST_RC:-0}" -eq 0 ] || exit "${GH_LIST_RC}"
    if [ -n "${GH_LIST_JSON:-}" ]; then printf '%s\n' "${GH_LIST_JSON}"; fi
    exit 0 ;;
  issue/create)
    _prev=""
    for _a in "$@"; do
      if [ "$_prev" = "--body-file" ]; then
        if [ -n "${GH_BODY_OUT:-}" ]; then cat "$_a" > "$GH_BODY_OUT" 2>/dev/null || true; fi
        break
      fi
      _prev="$_a"
    done
    [ "${GH_CREATE_RC:-0}" -eq 0 ] || exit "${GH_CREATE_RC}"
    printf 'https://example.invalid/issues/1\n'
    exit 0 ;;
esac
exit 0
STUB
  chmod +x "$STUBDIR/gh"
}
make_stub

# ── fixture builder ───────────────────────────────────────────────────────────────────────
# mktemp -d, NOT a shell counter: make_fixture is called through command substitution, so a
# counter increment would happen in a subshell and every fixture would collide on fx1 while
# a previous test's report files survived in it.
make_fixture() { # make_fixture [enabled] [repo] [max_per_session] [installed-version]
  # ${x-DEFAULT} (no colon): an EXPLICIT empty arg must stay empty, so R3's "missing/empty
  # repo resolves to the shipped default" fixture really exercises the tool's default and
  # not a fixture that wrote the default in itself.
  _fx="$(mktemp -d "$T/fx.XXXXXX" 2>/dev/null)" || fail "could not create a fixture dir"
  mkdir -p "$_fx/.harness/tools" "$_fx/bin"
  cp -R "$SRC/tools/." "$_fx/.harness/tools/" 2>/dev/null || true
  printf '%s\n' "${4-9.9.9}" > "$_fx/.harness/.harness-version"
  {
    printf 'feedback:\n'
    printf '  enabled: %s\n' "${1-true}"
    printf '  repo: %s\n' "${2-github.com/araozmd/harness-sdd}"
    printf '  max_per_session: %s\n' "${3-3}"
  } > "$_fx/.harness/harness.config.yaml"
  git -C "$_fx" init -q 2>/dev/null || true
  printf '%s\n' "$_fx"
}

# use_fx <fixture> — point the per-test log/body at this fixture and clear the stub controls.
use_fx() {
  GLOG="$1/gh.log"
  BODY="$1/body.out"
  : > "$GLOG"
  unset SH_AUTH_RC SH_LIST_RC SH_CREATE_RC SH_LIST_JSON 2>/dev/null || true
}

# ── runners ───────────────────────────────────────────────────────────────────────────────
# run_ok asserts the R4 non-functional contract on EVERY call: the tool exits 0. The SH_*
# controls feed the stub; use_fx clears them between tests.
run_ok() {
  _fx="$1"; shift
  _rc=0
  GH_LOG="$GLOG" GH_BODY_OUT="$BODY" \
  GH_AUTH_RC="${SH_AUTH_RC:-0}" GH_LIST_RC="${SH_LIST_RC:-0}" GH_CREATE_RC="${SH_CREATE_RC:-0}" \
  GH_LIST_JSON="${SH_LIST_JSON:-}" \
  PATH="$STUBDIR:$PATH" sh "$_fx/.harness/tools/harness-report.sh" "$@" || _rc=$?
  [ "$_rc" -eq 0 ] \
    || fail "harness-report.sh exited $_rc — the tool has no non-zero exit path (args: $*)"
}

# run_nogh — the gh-missing case: a PATH with the needed utilities and no gh at all
# (/usr/bin:/bin holds git, date, sed, grep, awk and NOT gh — verified by the caller below).
run_nogh() {
  _fx="$1"; shift
  _rc=0
  GH_LOG="$GLOG" GH_BODY_OUT="$BODY" PATH=/usr/bin:/bin \
    sh "$_fx/.harness/tools/harness-report.sh" "$@" || _rc=$?
  [ "$_rc" -eq 0 ] \
    || fail "harness-report.sh exited $_rc with no gh on PATH — a missing gh must never fail the caller (args: $*)"
}

# ── observability helpers ─────────────────────────────────────────────────────────────────
gh_calls() {
  [ -f "$GLOG" ] || { echo 0; return 0; }
  grep -c '^CALL$' "$GLOG" 2>/dev/null || true
}
create_count() {
  [ -f "$GLOG" ] || { echo 0; return 0; }
  grep -cx 'create' "$GLOG" 2>/dev/null || true
}
comment_count() {
  [ -f "$GLOG" ] || { echo 0; return 0; }
  grep -cx 'comment' "$GLOG" 2>/dev/null || true
}
report_count() { ls "$1/.harness/progress/feedback/"*.md 2>/dev/null | wc -l | tr -d ' '; }
latest_report() { ls -t "$1/.harness/progress/feedback/"*.md 2>/dev/null | head -n 1; }
# argv_value <flag> — the argv token following the first exact occurrence of <flag>.
argv_value() { awk -v f="$1" 'p{print;exit} $0==f{p=1}' "$GLOG"; }
# absent <token> <file> <message>
absent() { if grep -qF -- "$1" "$2" 2>/dev/null; then fail "$3"; fi; }
# present <token> <file> <message>
present() { grep -qF -- "$1" "$2" 2>/dev/null || fail "$3"; }

# ── R1 ────────────────────────────────────────────────────────────────────────────────────
test_marker_grammar() {
  _fx="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  use_fx "$_fx"
  run_ok "$_fx" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --command run-tests.sh --exit-code 1 \
    --role builder --phase builder --session-id s-marker

  # Positive control: a missing/empty body must not let every assertion pass vacuously.
  [ -s "$BODY" ] \
    || fail "R1: no created body was captured — the positive control did not file, so the marker assertions below prove nothing"

  _mk1="$(sed -n '1p' "$BODY")"
  printf '%s\n' "$_mk1" | grep -qE '^<!-- harness-feedback:v1 host=[A-Za-z0-9._-]+ version=[0-9]+\.[0-9]+\.[0-9]+ trigger=(harness-malfunction|contradictory-instruction|workaround|missing-capability) -->$' \
    || fail "R1: the created body's first line is not the exact marker grammar (got: $_mk1)"
  [ "$(grep -cE '^<!-- harness-feedback:' "$BODY")" = "1" ] \
    || fail "R1: expected exactly 1 harness-feedback marker line, got $(grep -cE '^<!-- harness-feedback:' "$BODY")"
  _mcount="$(grep -c 'harness-feedback:' "$BODY")" || _mcount=0
  [ "$_mcount" = "1" ] \
    || fail "R1: the body carries $_mcount occurrences of 'harness-feedback:', expected exactly 1 (the marker); no other marker may appear anywhere in the body"
  [ "$_mk1" = "<!-- harness-feedback:v1 host=github.com version=9.9.9 trigger=harness-malfunction -->" ] \
    || fail "R1: marker fields, field order or bytes are wrong; expected the fixture version 9.9.9 and host github.com (got: $_mk1)"

  # A non-semver installed version must file NOTHING upstream — a marker that violates its
  # own grammar is never emitted — and still write the local report.
  _fx2="$(make_fixture true github.com/araozmd/harness-sdd 3 0.86.0-rc1)"
  use_fx "$_fx2"
  run_ok "$_fx2" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --session-id s-version
  [ "$(create_count)" = "0" ] || fail "R1: a non-semver VERSION created an upstream issue"
  [ "$(report_count "$_fx2")" -ge 1 ] || fail "R1: a non-semver VERSION wrote no local report"
  _rep="$(latest_report "$_fx2")"
  present 'Outcome: rejected' "$_rep" "R1: the non-semver VERSION local report does not record outcome rejected"
  present 'Reason: version' "$_rep" "R1: the non-semver VERSION local report does not name the version reason"
  pass "R1 marker grammar exact, exactly one marker, non-semver VERSION files nothing but reports locally (R1) [test_marker_grammar]"
}

# ── R2 ────────────────────────────────────────────────────────────────────────────────────
test_disabled_is_silent() {
  _fx="$(make_fixture false github.com/araozmd/harness-sdd 3 9.9.9)"
  use_fx "$_fx"
  run_ok "$_fx" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --session-id s-off
  [ "$(gh_calls)" = "0" ] \
    || fail "R2: disabled reporting still invoked gh $(gh_calls) time(s); expected zero"
  [ "$(report_count "$_fx")" = "0" ] \
    || fail "R2: disabled reporting wrote $(report_count "$_fx") report file(s); expected zero"

  # Positive control: the SAME path with enabled: true must file. Without this the two
  # negatives above would pass even if the whole report path were broken.
  _fx2="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  use_fx "$_fx2"
  run_ok "$_fx2" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --session-id s-on
  [ "$(create_count)" = "1" ] \
    || fail "R2 positive control: enabled: true did not create an issue, so the disabled-case negatives are vacuous"
  [ "$(report_count "$_fx2")" -ge 1 ] \
    || fail "R2 positive control: enabled: true wrote no local report, so the disabled-case negatives are vacuous"
  pass "R2 enabled: false invokes no gh and writes no report; enabled: true files and reports (R2) [test_disabled_is_silent]"
}

# ── R3 ────────────────────────────────────────────────────────────────────────────────────
test_repo_resolution() {
  # (a) two parts mean OWNER/REPO on github.com.
  _fx="$(make_fixture true acme/fork 3 9.9.9)"
  use_fx "$_fx"
  run_ok "$_fx" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --session-id s-a
  [ "$(sed -n '1p' "$BODY")" = "<!-- harness-feedback:v1 host=github.com version=9.9.9 trigger=harness-malfunction -->" ] \
    || fail "R3: a two-part repo did not resolve the marker host to github.com (got: $(sed -n '1p' "$BODY"))"
  [ "$(argv_value --repo)" = "acme/fork" ] \
    || fail "R3: a two-part repo did not target acme/fork (got: $(argv_value --repo))"
  [ "$(argv_value --hostname)" = "github.com" ] \
    || fail "R3: auth did not target github.com for a two-part repo (got: $(argv_value --hostname))"

  # (b) three parts mean HOST/OWNER/REPO, and the auth check targets that host.
  _fx2="$(make_fixture true ghe.example.com/acme/fork 3 9.9.9)"
  use_fx "$_fx2"
  run_ok "$_fx2" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --session-id s-b
  [ "$(sed -n '1p' "$BODY")" = "<!-- harness-feedback:v1 host=ghe.example.com version=9.9.9 trigger=harness-malfunction -->" ] \
    || fail "R3: a three-part repo did not carry host ghe.example.com in the marker (got: $(sed -n '1p' "$BODY"))"
  [ "$(argv_value --hostname)" = "ghe.example.com" ] \
    || fail "R3: auth did not target the repo host ghe.example.com (got: $(argv_value --hostname))"
  [ "$(argv_value --repo)" = "acme/fork" ] \
    || fail "R3: a three-part repo did not target owner/repo acme/fork (got: $(argv_value --repo))"

  # (c) missing/empty resolves to the shipped default.
  _fx3="$(make_fixture true '' 3 9.9.9)"
  use_fx "$_fx3"
  run_ok "$_fx3" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --session-id s-c
  [ "$(argv_value --repo)" = "araozmd/harness-sdd" ] \
    || fail "R3: an empty repo did not resolve to the shipped default owner/repo (got: $(argv_value --repo))"
  [ "$(argv_value --hostname)" = "github.com" ] \
    || fail "R3: an empty repo did not resolve the default host github.com (got: $(argv_value --hostname))"

  # (d) malformed values turn reporting off exactly as R2: no gh, no report files, exit 0.
  for _bad in 'https://github.com/acme/fork' 'a/b/c/d' 'acme/'; do
    _b="$(make_fixture true "$_bad" 3 9.9.9)"
    use_fx "$_b"
    run_ok "$_b" --trigger harness-malfunction --symptom tool-failure \
      --file tools/run-tests.sh --session-id s-d
    [ "$(gh_calls)" = "0" ] \
      || fail "R3: malformed repo '$_bad' still invoked gh; it must turn reporting off like R2"
    [ "$(report_count "$_b")" = "0" ] \
      || fail "R3: malformed repo '$_bad' wrote a report file; a malformed repo turns reporting off entirely"
  done
  pass "R3 repo grammar resolves host/target and malformed values turn reporting off (R3) [test_repo_resolution]"
}

# ── R4 ────────────────────────────────────────────────────────────────────────────────────
test_field_allowlist_rejects() {
  _reject_case() { # <desc> <args...>
    _d="$1"; shift
    _f="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
    use_fx "$_f"
    run_ok "$_f" "$@" --session-id s-r4 --file tools/run-tests.sh
    [ "$(create_count)" = "0" ] \
      || fail "R4: '$_d' created an upstream issue; it must be rejected"
    [ "$(report_count "$_f")" -ge 1 ] \
      || fail "R4: '$_d' wrote no local report; every reject still writes the local copy"
  }
  _create_case() { # <desc> <args...> — the positive control that proves the predicate is live
    _d="$1"; shift
    _f="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
    use_fx "$_f"
    run_ok "$_f" "$@" --session-id s-r4 --file tools/run-tests.sh
    [ "$(create_count)" = "1" ] \
      || fail "R4: '$_d' did NOT create; the allow-list predicate is not live for this field"
  }

  _reject_case "bad trigger"   --trigger not-a-trigger --symptom tool-failure
  _create_case "valid trigger" --trigger harness-malfunction --symptom tool-failure
  _reject_case "bad symptom"   --trigger harness-malfunction --symptom not-a-symptom
  _create_case "valid symptom" --trigger harness-malfunction --symptom tool-failure
  _reject_case "bad role"      --trigger harness-malfunction --symptom tool-failure --role wizard
  _create_case "valid role"    --trigger harness-malfunction --symptom tool-failure --role builder
  _reject_case "bad phase"     --trigger harness-malfunction --symptom tool-failure --phase lunch
  _create_case "valid phase"   --trigger harness-malfunction --symptom tool-failure --phase builder
  _reject_case "bad exit code (non-numeric)" --trigger harness-malfunction --symptom tool-failure --exit-code 12x
  _reject_case "bad exit code (too long)"    --trigger harness-malfunction --symptom tool-failure --exit-code 1234
  _create_case "valid exit code"             --trigger harness-malfunction --symptom tool-failure --exit-code 7
  # The command field is SEMANTIC: a plausible but unshipped name must reject, a shipped
  # basename must create. That is what proves it is not merely a charset check.
  _reject_case "unshipped command" --trigger harness-malfunction --symptom tool-failure --command my-project-tool
  _create_case "shipped command"   --trigger harness-malfunction --symptom tool-failure --command run-tests.sh
  # Missing required fields take the same reject path as an out-of-list value.
  _reject_case "missing trigger" --symptom tool-failure
  _reject_case "missing symptom" --trigger harness-malfunction

  # FULL enum coverage: every member of every vocabulary must be accepted. A mutant that
  # drops ONE code from an enum has no other way to red, so each member gets its own
  # positive control (delete a code and this loop names it).
  for _tr in harness-malfunction contradictory-instruction workaround missing-capability; do
    _create_case "trigger $_tr" --trigger "$_tr" --symptom tool-failure
  done
  for _sy in init-failure install-failure tool-failure board-write-failure gate-unsatisfiable \
             instruction-conflict doc-conflict workflow-gap state-corruption; do
    _create_case "symptom $_sy" --trigger harness-malfunction --symptom "$_sy"
  done
  for _ro in orchestrator architect builder builder-heavy reviewer scout \
             driller fixer planner inception doc-critic pr-fixer; do
    _create_case "role $_ro" --trigger harness-malfunction --symptom tool-failure --role "$_ro"
  done
  for _ph in inception architect builder reviewer scout slice-dispatch handoff install; do
    _create_case "phase $_ph" --trigger harness-malfunction --symptom tool-failure --phase "$_ph"
  done
  pass "R4 each allow-list rejects an out-of-list value and accepts every valid member; missing trigger/symptom reject (R4) [test_field_allowlist_rejects]"
}

# ── R5 ────────────────────────────────────────────────────────────────────────────────────
test_harness_owned_file_filter() {
  _fx="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  mkdir -p "$_fx/src"
  printf 'secret project code\n' > "$_fx/src/secret-app.py"
  use_fx "$_fx"
  run_ok "$_fx" --trigger harness-malfunction --symptom tool-failure \
    --file src/secret-app.py --file tools/run-tests.sh --file /etc/passwd --file ../escape \
    --session-id s-files

  [ -s "$BODY" ] || fail "R5: no created body — the harness-owned positive control did not file"
  _title="$(argv_value --title)"
  printf '%s\n' "$_title" | grep -qF 'tools/run-tests.sh' \
    || fail "R5: the accepted harness-owned file is missing from the title (got: $_title)"
  present 'File: tools/run-tests.sh' "$BODY" "R5: the accepted harness-owned file is missing from the body"
  absent 'src/secret-app.py' "$BODY" "R5: a project path reached the body"
  printf '%s\n' "$_title" | grep -qF 'src/secret-app.py' \
    && fail "R5: a project path reached the title (got: $_title)"
  absent '/etc/passwd' "$BODY" "R5: an absolute path reached the body"
  absent '../escape' "$BODY" "R5: a .. escape reached the body"
  printf '%s\n' "$_title" | grep -qF '/etc/passwd' \
    && fail "R5: an absolute path reached the title"
  printf '%s\n' "$_title" | grep -qF '../escape' \
    && fail "R5: a .. escape reached the title"

  # No accepted file at all: no upstream issue, local report.
  _fx2="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  mkdir -p "$_fx2/src"
  printf 'secret project code\n' > "$_fx2/src/secret-app.py"
  use_fx "$_fx2"
  run_ok "$_fx2" --trigger harness-malfunction --symptom tool-failure \
    --file src/secret-app.py --session-id s-nofile
  [ "$(create_count)" = "0" ] \
    || fail "R5: a report with no accepted harness-owned file created an upstream issue"
  [ "$(report_count "$_fx2")" -ge 1 ] \
    || fail "R5: a report with no accepted harness-owned file wrote no local report"
  pass "R5 harness-owned files pass into title/body, project/absolute/.. paths are dropped, none accepted means local-only (R5) [test_harness_owned_file_filter]"
}

# ── R6 ────────────────────────────────────────────────────────────────────────────────────
test_title_format() {
  _fx="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  use_fx "$_fx"
  run_ok "$_fx" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --command run-tests.sh --exit-code 1 \
    --role builder --phase builder --session-id s-title
  _t="$(argv_value --title)"
  [ "$_t" = "[harness-feedback] harness-malfunction tool-failure in tools/run-tests.sh" ] \
    || fail "R6: the --title argv is not the exact fixed title (got: $_t)"

  # A second trigger/symptom/file combination proves the variables are the accepted ones,
  # not a hard-coded fixture.
  _fx2="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  use_fx "$_fx2"
  run_ok "$_fx2" --trigger workaround --symptom doc-conflict \
    --file tools/change-size.sh --session-id s-title2
  _t2="$(argv_value --title)"
  [ "$_t2" = "[harness-feedback] workaround doc-conflict in tools/change-size.sh" ] \
    || fail "R6: the title does not track the accepted fields (got: $_t2)"
  pass "R6 the issue title is exactly [harness-feedback] <trigger> <symptom> in <first accepted file> (R6) [test_title_format]"
}

# ── R7 ────────────────────────────────────────────────────────────────────────────────────
test_body_allowlisted_no_freeform() {
  _fx="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  _notes="$T/notes-r7.txt"
  printf 'agent observed the board write fail\nZEBRAFISH-NOTE-90817\n' > "$_notes"
  use_fx "$_fx"
  run_ok "$_fx" --trigger harness-malfunction --symptom board-write-failure \
    --file tools/run-tests.sh --exit-code 1 --role builder --phase builder \
    --session-id s-body --notes-file "$_notes"

  [ -s "$BODY" ] || fail "R7: no created body — the positive control did not file"
  # Negative: the free-form token is never transmitted.
  absent 'ZEBRAFISH-NOTE-90817' "$BODY" "R7: free-form notes text reached the upstream body"
  absent 'ZEBRAFISH-NOTE-90817' "$GLOG" "R7: free-form notes text reached a gh argv (title/search)"
  # Structural: every line after the marker is a Label: value line.
  _off="$(awk 'NR > 1 && $0 !~ /^[A-Za-z][A-Za-z ]*: / { print }' "$BODY")"
  [ -z "$_off" ] \
    || fail "R7: the upstream body carries a line that is not a marker or Label: value line: $_off"
  # …and the label lines are in the plan's FIXED order.
  _ord="$(sed -n 's/^\([A-Za-z][A-Za-z ]*\): .*/\1/p' "$BODY" | tr '\n' '|')"
  [ "$_ord" = "Harness version|Trigger|Symptom|File|Exit code|Role|Phase|" ] \
    || fail "R7: the body's Label: value lines are not in the fixed order (got: $_ord)"
  # Positive control: the same token IS preserved in the local copy, so the negative above
  # is not dead.
  _rep="$(latest_report "$_fx")"
  [ -n "$_rep" ] || fail "R7: no local report was written"
  present 'ZEBRAFISH-NOTE-90817' "$_rep" "R7: the free-form notes are missing from the local copy (the negative is then vacuous)"
  pass "R7 the upstream body is marker + allow-listed Label: value lines only; notes stay in the local copy (R7) [test_body_allowlisted_no_freeform]"
}

# ── R8 ────────────────────────────────────────────────────────────────────────────────────
test_redaction_corpus() {
  _in="$T/r8-in.txt"
  cat > "$_in" <<'EOF'
Token: ghp_abcdefghijklmnop
Token2: gho_abcdefghijklmnop
Token3: ghu_abcdefghijklmnop
Token4: ghs_abcdefghijklmnop
Token5: ghr_abcdefghijklmnop
Token6: github_pat_abcdefghijklmnop
Token7: sk-abcdefghijklmnop
Token8: AKIAABCDEFGHIJKLMNOP
Email: user@example.com
Path: /home/secret/place
Path2: /tmp/secret/place
Path3: /Users/alice/secret
Path4: /private/var/secret
Path5: /private/tmp
EOF
  _out="$T/r8-out.txt"
  sh "$TOOL" redact < "$_in" > "$_out"

  # Positive controls on the INPUT: each raw shape must be present before the pass, or the
  # absence assertions below would be vacuous. Every named corpus shape is covered so a
  # mutant that drops one prefix or one alternative reds here and names it.
  for _raw in 'ghp_abcdefghijklmnop' 'gho_abcdefghijklmnop' 'ghu_abcdefghijklmnop' \
              'ghs_abcdefghijklmnop' 'ghr_abcdefghijklmnop' 'github_pat_abcdefghijklmnop' \
              'sk-abcdefghijklmnop' 'AKIAABCDEFGHIJKLMNOP' \
              'user@example.com' '/home/secret/place' '/tmp/secret/place' '/Users/alice/secret' \
              '/private/var/secret' '/private/tmp'; do
    present "$_raw" "$_in" "R8 positive control: the input does not contain the raw shape $_raw"
    absent "$_raw" "$_out" "R8: redact left the raw shape $_raw in its output"
  done
  present '[REDACTED-SECRET]' "$_out" "R8: redact emitted no [REDACTED-SECRET] token"
  present '[REDACTED-EMAIL]' "$_out" "R8: redact emitted no [REDACTED-EMAIL] token"
  present '[REDACTED-PATH]' "$_out" "R8: redact emitted no [REDACTED-PATH] token"

  # Marker preservation in redact mode: the first line is the marker and must survive
  # byte-exact even though a corpus-shaped host sits inside it; the label line is redacted.
  _min="$T/r8-marker-in.txt"
  cat > "$_min" <<'EOF'
<!-- harness-feedback:v1 host=sk-abcdef version=9.9.9 trigger=harness-malfunction -->
File: ghp_abcdefghijklmnop
EOF
  _mout="$T/r8-marker-out.txt"
  sh "$TOOL" redact < "$_min" > "$_mout"
  [ "$(sed -n '1p' "$_mout")" = "<!-- harness-feedback:v1 host=sk-abcdef version=9.9.9 trigger=harness-malfunction -->" ] \
    || fail "R8: redact rewrote the marker line (got: $(sed -n '1p' "$_mout"))"
  [ "$(sed -n '2p' "$_mout")" = "File: [REDACTED-SECRET]" ] \
    || fail "R8: redact did not redact the label line (got: $(sed -n '2p' "$_mout"))"

  # The same pass on the real CREATE path: a token-shaped harness-owned file basename passes
  # R5 and must be redacted in the File: line, while the token-shaped host in the marker
  # stays byte-exact.
  _fx="$(make_fixture true sk-abcdef/acme/fork 3 9.9.9)"
  printf 'token-shaped tool\n' > "$_fx/.harness/tools/ghp_abcdefghijklmnop"
  use_fx "$_fx"
  run_ok "$_fx" --trigger harness-malfunction --symptom tool-failure \
    --file tools/ghp_abcdefghijklmnop --session-id s-redact
  [ "$(sed -n '1p' "$BODY")" = "<!-- harness-feedback:v1 host=sk-abcdef version=9.9.9 trigger=harness-malfunction -->" ] \
    || fail "R8: the create-path marker was redacted or altered (got: $(sed -n '1p' "$BODY"))"
  absent 'ghp_abcdefghijklmnop' "$BODY" "R8: the token-shaped file basename was not redacted on the create path"
  present 'File: tools/[REDACTED-SECRET]' "$BODY" "R8: the File: line does not carry the redaction token"
  pass "R8 the fixed corpus is redacted in redact mode and on the create path, while the marker stays byte-exact (R8) [test_redaction_corpus]"
}

# ── R9 ────────────────────────────────────────────────────────────────────────────────────
test_duplicate_skips_create() {
  # (a) CONTROL: an issue whose title merely mentions the words — here it EMBEDS the fixed
  # title inside a longer title — must NOT suppress a distinct report. An inexact
  # matcher (substring, prefix, case-folded) would wrongly turn this red.
  _fx="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  use_fx "$_fx"
  SH_LIST_JSON='[{"number":9,"title":"Re: [harness-feedback] harness-malfunction tool-failure in tools/run-tests.sh (possible duplicate?)"}]'
  run_ok "$_fx" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --session-id s-dup-a
  [ "$(create_count)" = "1" ] \
    || fail "R9: a returned issue whose title merely mentions the words suppressed a distinct report; matching must be exact, not substring/prefix"
  [ "$(argv_value --search)" = "in:title [harness-feedback] harness-malfunction tool-failure in tools/run-tests.sh" ] \
    || fail "R9: the search query is not title-scoped (got: $(argv_value --search))"
  [ "$(argv_value --json)" = "number,title" ] \
    || fail "R9: the duplicate search did not request number,title (got: $(argv_value --json))"

  # (b) an EXACT title match means no create and no comment; the local copy is still written.
  _fx2="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  use_fx "$_fx2"
  SH_LIST_JSON='[{"number":8,"title":"[harness-feedback] harness-malfunction tool-failure in tools/run-tests.sh"}]'
  run_ok "$_fx2" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --session-id s-dup-b
  [ "$(create_count)" = "0" ] \
    || fail "R9: an exact duplicate title still created an issue"
  [ "$(comment_count)" = "0" ] \
    || fail "R9: a duplicate posted a comment; it must do neither create nor comment"
  [ "$(report_count "$_fx2")" -ge 1 ] \
    || fail "R9: a duplicate wrote no local report"
  present 'Outcome: duplicate' "$(latest_report "$_fx2")" \
    "R9: the duplicate local report does not record outcome duplicate"
  pass "R9 duplicate search is title-scoped and exact; a mention still creates, an exact title creates and comments nothing (R9) [test_duplicate_skips_create]"
}

# ── R10 ───────────────────────────────────────────────────────────────────────────────────
test_session_cap() {
  _fx="$(make_fixture true github.com/araozmd/harness-sdd 2 9.9.9)"
  use_fx "$_fx"
  run_ok "$_fx" --trigger harness-malfunction --symptom tool-failure --file tools/run-tests.sh --session-id S1
  [ "$(create_count)" = "1" ] || fail "R10: first call under the cap did not create"
  run_ok "$_fx" --trigger harness-malfunction --symptom tool-failure --file tools/run-tests.sh --session-id S1
  [ "$(create_count)" = "2" ] || fail "R10: second call under max_per_session=2 did not create"
  # The boundary is EXACT: the third call on the same session must create nothing.
  run_ok "$_fx" --trigger harness-malfunction --symptom tool-failure --file tools/run-tests.sh --session-id S1
  [ "$(create_count)" = "2" ] || fail "R10: the third call exceeded max_per_session=2 (got $(create_count) creates)"
  # A DIFFERENT token resets the count.
  run_ok "$_fx" --trigger harness-malfunction --symptom tool-failure --file tools/run-tests.sh --session-id S2
  [ "$(create_count)" = "3" ] || fail "R10: a new session id did not reset the cap"
  [ "$(cat "$_fx/.harness/progress/feedback/.session-count")" = "S2 1" ] \
    || fail "R10: the ledger did not reset for the new token (got: $(cat "$_fx/.harness/progress/feedback/.session-count"))"

  # Missing token: no create, local outcome no-session.
  _fx2="$(make_fixture true github.com/araozmd/harness-sdd 2 9.9.9)"
  use_fx "$_fx2"
  run_ok "$_fx2" --trigger harness-malfunction --symptom tool-failure --file tools/run-tests.sh
  [ "$(create_count)" = "0" ] || fail "R10: a missing session token created an issue; it must fail closed"
  present 'Outcome: no-session' "$(latest_report "$_fx2")" \
    "R10: a missing session token did not record outcome no-session"

  # Invalid token (a space and a bang fail [A-Za-z0-9._-]{1,64}).
  _fx3="$(make_fixture true github.com/araozmd/harness-sdd 2 9.9.9)"
  use_fx "$_fx3"
  run_ok "$_fx3" --trigger harness-malfunction --symptom tool-failure --file tools/run-tests.sh \
    --session-id 'bad token!'
  [ "$(create_count)" = "0" ] || fail "R10: an invalid session token created an issue; it must fail closed"
  present 'Outcome: no-session' "$(latest_report "$_fx3")" \
    "R10: an invalid session token did not record outcome no-session"

  # max_per_session: 0 files nothing upstream.
  _fx4="$(make_fixture true github.com/araozmd/harness-sdd 0 9.9.9)"
  use_fx "$_fx4"
  run_ok "$_fx4" --trigger harness-malfunction --symptom tool-failure --file tools/run-tests.sh --session-id S0
  [ "$(create_count)" = "0" ] || fail "R10: max_per_session=0 created an issue"
  [ "$(report_count "$_fx4")" -ge 1 ] || fail "R10: max_per_session=0 wrote no local report"

  # The env-var form of the token works too (the interface names it).
  _fx5="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  use_fx "$_fx5"
  export HARNESS_FEEDBACK_SESSION_ID=env-session
  run_ok "$_fx5" --trigger harness-malfunction --symptom tool-failure --file tools/run-tests.sh
  unset HARNESS_FEEDBACK_SESSION_ID
  [ "$(create_count)" = "1" ] \
    || fail "R10: HARNESS_FEEDBACK_SESSION_ID was not honored as the session token"
  pass "R10 the per-session cap is exact, resets on a new token, and fails closed with no token; 0 files nothing (R10) [test_session_cap]"
}

# ── R11 ───────────────────────────────────────────────────────────────────────────────────
test_local_copy_and_fallback() {
  _notes="$T/notes-r11.txt"
  printf 'verbatim notes line ZEBRAFISH-R11\n' > "$_notes"

  # Positive control: a filed report AND a local copy with the structured fields + notes.
  _fx="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  use_fx "$_fx"
  run_ok "$_fx" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --role builder --phase builder --notes-file "$_notes" --session-id s-r11
  [ "$(create_count)" = "1" ] || fail "R11 positive control: the normal stub did not create"
  _rep="$(latest_report "$_fx")"
  [ -n "$_rep" ] || fail "R11: a filed report wrote no local copy"
  present 'Outcome: filed' "$_rep" "R11: the filed local copy does not record outcome filed"
  present 'Trigger: harness-malfunction' "$_rep" "R11: the local copy is missing the structured trigger"
  present 'Symptom: tool-failure' "$_rep" "R11: the local copy is missing the structured symptom"
  present 'File: tools/run-tests.sh' "$_rep" "R11: the local copy is missing the accepted file"
  present 'ZEBRAFISH-R11' "$_rep" "R11: the free-form notes are not in the local copy verbatim"

  # gh missing entirely: local copy only, exit 0.
  _fx2="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  use_fx "$_fx2"
  run_nogh "$_fx2" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --session-id s-nogh
  [ "$(report_count "$_fx2")" -ge 1 ] || fail "R11: a missing gh wrote no local copy"
  present 'Outcome: fallback' "$(latest_report "$_fx2")" \
    "R11: a missing gh did not record outcome fallback"

  # gh present but unauthenticated on the resolved host: local copy only, no create, exit 0.
  _fx3="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  use_fx "$_fx3"
  SH_AUTH_RC=1
  run_ok "$_fx3" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --session-id s-noauth
  [ "$(create_count)" = "0" ] || fail "R11: an unauthenticated gh still created an issue"
  present 'Outcome: fallback' "$(latest_report "$_fx3")" \
    "R11: an unauthenticated gh did not record outcome fallback"

  # gh present and authenticated but the create call fails: local copy only, exit 0.
  _fx4="$(make_fixture true github.com/araozmd/harness-sdd 3 9.9.9)"
  use_fx "$_fx4"
  SH_CREATE_RC=1
  run_ok "$_fx4" --trigger harness-malfunction --symptom tool-failure \
    --file tools/run-tests.sh --session-id s-createfail
  [ "$(report_count "$_fx4")" -ge 1 ] || fail "R11: a failing gh create wrote no local copy"
  present 'Outcome: fallback' "$(latest_report "$_fx4")" \
    "R11: a failing gh create did not record outcome fallback"
  pass "R11 every enabled report writes the local copy; gh missing/unauthenticated/failing fall back and exit 0 (R11) [test_local_copy_and_fallback]"
}

# ── R12 ───────────────────────────────────────────────────────────────────────────────────
# Section slicer, fence-aware (tests/lib/fence.awk, E99-F131) — docs/INSTALL.md carries a
# fenced YAML example, so a bare heading reset would truncate the section at a line inside
# the block. tests/test_change_size.sh R9d requires this exact load-and-call shape.
FENCE_AWK="$(cat "$SRC/tests/lib/fence.awk")"
_section() { # _section <heading-literal> <file>
  awk -v h="$1" "$FENCE_AWK"'
    fence_delim($0) { if (k) print; next }
    !fence && index($0,h)==1 { k=1; print; next }
    !fence && k && /^## / { exit }
    k { print }
  ' "$2"
}

test_shipping_artifacts() {
  [ -x "$TOOL" ] \
    || fail "R12: tools/harness-report.sh is not executable in the source tree (the installer chmod cannot fix a source mode)"
  [ "$(cat "$SRC/VERSION")" = "0.86.0" ] \
    || fail "R12: VERSION is not 0.86.0 (got $(cat "$SRC/VERSION"))"

  _sec="$(printf 'chmod +x "$H/tools/harness-report.sh"')"
  grep -qF "$_sec" "$SRC/harness-install.sh" \
    || fail "R12: harness-install.sh has no chmod +x entry for tools/harness-report.sh"

  _cl="$T/changelog-086.txt"
  _section '## [0.86.0]' "$SRC/CHANGELOG.md" > "$_cl"
  [ -s "$_cl" ] || fail "R12: could not extract the ## [0.86.0] CHANGELOG section — the heading is missing"
  grep -qF 'harness-report.sh' "$_cl" \
    || fail "R12: the CHANGELOG [0.86.0] section does not name tools/harness-report.sh"

  _is="$T/install-feedback.txt"
  _section '## Harness feedback' "$SRC/docs/INSTALL.md" > "$_is"
  [ -s "$_is" ] || fail "R12: could not extract the '## Harness feedback' section from docs/INSTALL.md"
  if grep -qF 'No reporter ships yet' "$_is"; then
    fail "R12: the INSTALL.md feedback section still carries the stale 'No reporter ships yet' sentence"
  fi
  grep -qF 'E32-F02' "$_is" || fail "R12: the INSTALL.md feedback section does not name E32-F02"
  grep -qF 'E32-F03' "$_is" || fail "R12: the INSTALL.md feedback section does not name E32-F03"
  pass "R12 VERSION, the chmod entry, the CHANGELOG [0.86.0] span and the corrected INSTALL.md feedback span all ship (R12) [test_shipping_artifacts]"
}

# ── non-functional ────────────────────────────────────────────────────────────────────────
test_suite_is_executable() {
  [ -x "$SRC/tests/test_feedback_report.sh" ] \
    || fail "non-functional: tests/test_feedback_report.sh is not executable"
  # The gh-missing case relies on this PATH having no gh; assert the premise so a host that
  # grows a /usr/bin/gh turns this into a loud failure rather than a false fallback.
  if PATH=/usr/bin:/bin command -v gh >/dev/null 2>&1; then
    fail "non-functional: /usr/bin:/bin now resolves gh, so the gh-missing fallback case no longer proves the absence path"
  fi
  pass "tests/test_feedback_report.sh is executable and the gh-missing PATH premise holds (non-functional) [test_suite_is_executable]"
}

# ── run ───────────────────────────────────────────────────────────────────────────────────
test_marker_grammar
test_disabled_is_silent
test_repo_resolution
test_field_allowlist_rejects
test_harness_owned_file_filter
test_title_format
test_body_allowlisted_no_freeform
test_redaction_corpus
test_duplicate_skips_create
test_session_cap
test_local_copy_and_fallback
test_shipping_artifacts
test_suite_is_executable

echo "all feedback report tests passed"
