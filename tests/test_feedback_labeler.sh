#!/bin/sh
# test_feedback_labeler.sh — test contract for E32-F04.
#
# Covers R1-R11 of E32-F04.spec.md (see E32-F04.tests.md for the row-by-row mapping). Zero
# dependency POSIX sh (+ awk/grep/sed/git), matching the house style of
# tests/test_feedback_report.sh: a self-cleaning mktemp tree, fail/pass helpers, dash-clean.
#
# NO test makes a network call or runs a real GitHub Action: `gh` is STUBBED on PATH and
# records its argv one token per line (each call opened by a `CALL` line); the workflow is
# asserted statically from its bytes. Fixture bodies are written under this suite's mktemp
# tree at run time — nothing is committed under tests/fixtures/** (that tree is frozen
# installer data).
#
# Every negative ships with a positive control on its own shape (a middle predicate that
# must match the pristine artifact), per the discrimination requirements in E32-F04.tests.md.

set -eu
LC_ALL=C
export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$SRC/.github/scripts/feedback-labeler.sh"
WF="$SRC/.github/workflows/harness-feedback-labeler.yml"

T="$(mktemp -d 2>/dev/null || mktemp -d -t feedback-labeler)"
trap 'rm -rf "$T"' EXIT

STUBDIR="$T/bin"
GLOG="$T/gh.log"
mkdir -p "$STUBDIR"
# The host may carry a real gh (a mise shim) later on PATH; prepending the stub makes it win.
PATH="$STUBDIR:$PATH"
export PATH

# label-issue needs the workflow's env: values. GH_REPO is the `github.repository` shape
# (owner/repo), never host-qualified.
GH_REPO='acme/harness-sdd'
GH_TOKEN='stub-token'
export GH_REPO GH_TOKEN

# The grammar, cited from E32-F02 (ADR-0006).
MARKER_RE='^<!-- harness-feedback:v1 host=[A-Za-z0-9._-]+ version=[0-9]+\.[0-9]+\.[0-9]+ trigger=(harness-malfunction|contradictory-instruction|workaround|missing-capability) -->$'
MARKER_HM='<!-- harness-feedback:v1 host=github.com version=9.9.9 trigger=harness-malfunction -->'
MARKER_MC='<!-- harness-feedback:v1 host=github.com version=9.9.9 trigger=missing-capability -->'
MARKER_CI='<!-- harness-feedback:v1 host=github.com version=9.9.9 trigger=contradictory-instruction -->'
MARKER_WA='<!-- harness-feedback:v1 host=github.com version=9.9.9 trigger=workaround -->'
EXP_BUG="$(printf 'harness-feedback\nbug')"
EXP_ENH="$(printf 'harness-feedback\nenhancement')"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── the stubbed gh ────────────────────────────────────────────────────────────────────────
# Records argv (one token per line, each call opened by `CALL`) and serves configurable
# outcomes through GH_* controls. Nothing here touches the network.
make_stub() {
  cat > "$STUBDIR/gh" <<'STUB'
#!/bin/sh
{
  printf 'CALL\n'
  for _a in "$@"; do printf '%s\n' "$_a"; done
} >> "${GH_LOG:?GH_LOG unset}"

case "${1:-}/${2:-}" in
  api/--include)
    # label probe: gh api --include repos/<repo>/labels/<name>
    _name="${3##*/}"
    if [ -n "${GH_PROBE_RC:-}" ]; then
      printf 'HTTP/2.0 500 Internal Server Error\n'
      exit "${GH_PROBE_RC}"
    fi
    case " ${GH_PRESENT:-} " in
      *" $_name "*) printf 'HTTP/2.0 200 OK\n'; exit 0 ;;
    esac
    printf 'HTTP/2.0 404 Not Found\n'
    exit 1 ;;
  api/*)
    # body fetch: gh api repos/<repo>/issues/<n> --jq .body
    [ "${GH_FETCH_RC:-0}" -eq 0 ] || exit "${GH_FETCH_RC}"
    if [ -n "${GH_BODY_FILE:-}" ]; then cat "$GH_BODY_FILE"; fi
    exit 0 ;;
  label/create)
    [ "${GH_CREATE_RC:-0}" -eq 0 ] || exit "${GH_CREATE_RC}"
    exit 0 ;;
  issue/edit)
    [ "${GH_EDIT_RC:-0}" -eq 0 ] || exit "${GH_EDIT_RC}"
    exit 0 ;;
  issue/comment)
    exit 0 ;;
esac
exit 0
STUB
  chmod +x "$STUBDIR/gh"
}
make_stub

# ── observability helpers ─────────────────────────────────────────────────────────────────
# calls_joined — one line per call, argv joined by single spaces (CALL is the separator).
calls_joined() {
  [ -f "$GLOG" ] || return 0
  awk '
    /^CALL$/ { if (buf != "") print buf; buf = ""; next }
    { buf = (buf == "" ? $0 : buf " " $0) }
    END { if (buf != "") print buf }
  ' "$GLOG"
}
count_calls() { # <ERE over the joined call line>
  [ -f "$GLOG" ] || { echo 0; return 0; }
  calls_joined | grep -E "$1" | wc -l | tr -d ' '
}
create_count() { count_calls '^label create '; }
edit_count()   { count_calls '^issue edit '; }
comment_count(){ count_calls '^issue comment '; }
created_labels() { [ -f "$GLOG" ] || return 0; calls_joined | sed -n 's/^label create \([^ ]*\) .*/\1/p'; }
# label_create_flag <label> <flag> — the argv value following <flag> on that label's create.
# Read from the RAW token-per-line log, not the space-joined form, so a value containing
# spaces (e.g. a description) survives intact.
label_create_flag() {
  [ -f "$GLOG" ] || return 0
  awk -v lab="$1" -v f="$2" '
    /^CALL$/ { next }
    { n++; a[n] = $0 }
    END {
      for (i = 1; i <= n; i++) {
        if (a[i] == "label" && a[i+1] == "create" && a[i+2] == lab) {
          for (j = i + 3; j <= n; j++) if (a[j] == f) { print a[j+1]; exit }
        }
      }
    }
  ' "$GLOG"
}
# argv_value <flag> — the token following the FIRST occurrence of <flag> in the whole log.
argv_value() {
  [ -f "$GLOG" ] || return 0
  calls_joined | awk -v f="$1" '{ for (i = 1; i <= NF; i++) if ($i == f) { print $(i + 1); exit } }'
}
has_call() { # <ERE>
  [ -f "$GLOG" ] || return 1
  calls_joined | grep -qE "$1"
}

# ── runners ───────────────────────────────────────────────────────────────────────────────
run_parse() { sh "$SCRIPT" parse "$1"; }
run_label_rc() { # echoes the exit status, never aborts the suite
  _lrc=0
  GH_LOG="$GLOG" sh "$SCRIPT" label-issue "$1" >/dev/null 2>&1 || _lrc=$?
  printf '%s' "$_lrc"
}
run_label_ok() {
  _rc="$(run_label_rc "$1")"
  [ "$_rc" = "0" ] || fail "label-issue $1 exited $_rc; expected 0"
}
clear_controls() {
  unset GH_BODY_FILE GH_FETCH_RC GH_PRESENT GH_PROBE_RC GH_CREATE_RC GH_EDIT_RC 2>/dev/null || true
  : > "$GLOG"
}

# ── static YAML extractors ────────────────────────────────────────────────────────────────
# _yaml_block <column-0 key> <file> — the key's block up to the next column-0 key, blank and
# comment lines dropped. (Section extraction, not a whole-file grep: a block moved into
# another workflow or key cannot satisfy an assertion about THIS key.)
_yaml_block() {
  awk -v key="$1" '
    $0 == key ":" || substr($0, 1, length(key) + 2) == key ": " { k = 1; print; next }
    k && /^[^[:space:]#]/ { exit }
    k && /^[[:space:]]*#/ { next }
    k && /^[[:space:]]*$/ { next }
    k { print }
  ' "$2"
}
# _run_block <file> — every `run:` line (and its deeper-indented continuation lines).
_run_block() {
  awk '
    /^[[:space:]]*run:/ { k = 1; print; next }
    k && /^[[:space:]]/ { print; next }
    k { exit }
  ' "$1"
}

# ── R1 ────────────────────────────────────────────────────────────────────────────────────
test_trigger_opened_only() {
  _blk="$(_yaml_block on "$WF")"
  [ -n "$_blk" ] \
    || fail "R1: could not extract the on: block from $WF — the key was renamed or removed"
  _n="$(printf '%s\n' "$_blk" | wc -l | tr -d ' ')"
  [ "$_n" -ge 3 ] \
    || fail "R1 positive control: the on: block extracted only $_n line(s); expected the full on:/issues:/types: block"
  _exp="$(printf 'on:\n  issues:\n    types: [opened]')"
  [ "$_blk" = "$_exp" ] \
    || fail "R1: the on: block is not exactly issues: types: [opened] (got: $(printf '%s' "$_blk" | tr '\n' '|'))"
  pass "R1 the workflow triggers on issues: opened only, asserted by full-string equality of the isolated on: block [test_trigger_opened_only]"
}

# ── R3 ────────────────────────────────────────────────────────────────────────────────────
test_permissions_and_pinning() {
  _pblk="$(_yaml_block permissions "$WF")"
  [ -n "$_pblk" ] || fail "R3: could not extract the permissions: block from $WF"
  _n="$(printf '%s\n' "$_pblk" | wc -l | tr -d ' ')"
  [ "$_n" = "3" ] \
    || fail "R3 positive control: the permissions: block extracted $_n line(s); expected exactly permissions:/issues:/contents:"
  _exp="$(printf 'permissions:\n  issues: write\n  contents: read')"
  [ "$_pblk" = "$_exp" ] \
    || fail "R3: the permissions: block is not the pinned two-key block (got: $(printf '%s' "$_pblk" | tr '\n' '|'))"

  _uses="$(sed -n 's/^[[:space:]]*-[[:space:]]*uses:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$WF")"
  [ -n "$_uses" ] \
    || fail "R3 positive control: the workflow has no 'uses:' line, so the SHA-pin assertion is vacuous"
  for _u in $_uses; do
    case "$_u" in
      *@*) ;;
      *) fail "R3: action '$_u' carries no @<ref>" ;;
    esac
    _ref="${_u##*@}"
    printf '%s\n' "$_ref" | grep -qE '^[0-9a-f]{40}$' \
      || fail "R3: action '$_u' is not pinned by a full 40-hex commit SHA (ref: $_ref)"
  done
  pass "R3 permissions: is exactly issues: write + contents: read and every uses: is 40-hex SHA-pinned [test_permissions_and_pinning]"
}

# ── R2 ────────────────────────────────────────────────────────────────────────────────────
test_workflow_untrusted_input() {
  # No issue text may reach a run: shell line.
  _run_blk="$(_run_block "$WF")"
  [ -n "$_run_blk" ] \
    || fail "R2 positive control: the workflow has no run: line, so the run:-negative is vacuous"
  if printf '%s\n' "$_run_blk" | grep -qF '${{'; then
    fail "R2: a run: line carries a \${{ }} expression"
  fi
  grep -qF '${{' "$WF" \
    || fail "R2 positive control: the workflow contains no \${{ }} at all, so the run:-negative proves nothing"
  printf '%s\n' "$_run_blk" | grep -qF '.github/scripts/feedback-labeler.sh' \
    || fail "R2: the run: line does not invoke the checked-in parser"

  # The only event field used is .number.
  _fields="$(grep -oE 'github\.event\.issue\.[A-Za-z0-9_]+' "$WF" | LC_ALL=C sort -u)"
  [ -n "$_fields" ] \
    || fail "R2 positive control: no github.event.issue.* token was extracted, so the set-equality check is dead"
  [ "$_fields" = "github.event.issue.number" ] \
    || fail "R2: the only github.event.issue.* field used must be .number (got: $(printf '%s' "$_fields" | tr '\n' ' '))"
  grep -qF 'github.event' "$WF" \
    || fail "R2 positive control: no github.event reference exists, so the comment-token search space is dead"
  if grep -qF 'github.event.comment' "$WF"; then
    fail "R2: the workflow references github.event.comment"
  fi

  # The whole expression vocabulary is exactly token / repository / issue.number.
  _exprs="$(grep -oE 'github\.[A-Za-z0-9_.]+' "$WF" | LC_ALL=C sort -u)"
  _exp="$(printf 'github.event.issue.number\ngithub.repository\ngithub.token' | LC_ALL=C sort -u)"
  [ "$_exprs" = "$_exp" ] \
    || fail "R2: expression fields must be exactly github.token/github.repository/github.event.issue.number (got: $(printf '%s' "$_exprs" | tr '\n' ' '))"

  # Unit: the body reaches the parser only as a fetched file, never as an argv token.
  clear_controls
  _canary='E32F04-BODY-CANARY-4729'
  _body="$T/r2-body.md"
  {
    printf '%s\n' "$MARKER_HM"
    printf 'free text %s\n' "$_canary"
  } > "$_body"
  export GH_BODY_FILE="$_body"
  run_label_ok 7
  has_call '^api repos/acme/harness-sdd/issues/7 --jq \.body$' \
    || fail "R2: the body was not fetched via 'gh api repos/<repo>/issues/<n> --jq .body'"
  if calls_joined | grep -qF "$_canary"; then
    fail "R2: the issue body text appeared in a gh argv — it must reach the parser only as a file"
  fi
  unset GH_BODY_FILE
  pass "R2 no issue text reaches run:/expressions; only token/repository/issue.number, body fetched as a file [test_workflow_untrusted_input]"
}

# ── R4 ────────────────────────────────────────────────────────────────────────────────────
test_parse_valid_marker() {
  _f="$T/r4-valid.md"
  {
    printf '%s\n' "$MARKER_HM"
    printf 'free text after the marker\n'
  } > "$_f"
  # Positive control: the fixture's first line is a grammar match read alone.
  sed -n '1p' "$_f" | grep -qE "$MARKER_RE" \
    || fail "R4 positive control: the fixture's first line is not the grammar — the fixture is malformed"
  _out="$(run_parse "$_f")"
  [ "$_out" = "$EXP_BUG" ] \
    || fail "R4: a valid marker did not yield the exact label set (got: $(printf '%s' "$_out" | tr '\n' '|'))"

  # Other lines are inert: trailing field-shaped text must not change the classification.
  _f2="$T/r4-inert.md"
  {
    printf '%s\n' "$MARKER_HM"
    printf 'trigger=missing-capability\n'
    printf 'host=evil.example\n'
    printf 'version=0.0.0\n'
  } > "$_f2"
  _out2="$(run_parse "$_f2")"
  [ "$_out2" = "$EXP_BUG" ] \
    || fail "R4: text after the marker changed the label set; those bytes must be inert (got: $(printf '%s' "$_out2" | tr '\n' '|'))"
  pass "R4 a valid first-line marker yields the trigger's exact label set and later lines are inert [test_parse_valid_marker]"
}

# ── R5 ────────────────────────────────────────────────────────────────────────────────────
test_parse_rejects_non_reports() {
  _reject_case() { # <desc> <file>
    _d="$1"; _file="$2"
    _out="$(run_parse "$_file")"
    [ -z "$_out" ] \
      || fail "R5: '$_d' produced a label set (got: $(printf '%s' "$_out" | tr '\n' '|')); a non-report must print zero bytes"
    clear_controls
    export GH_BODY_FILE="$_file"
    _rc="$(run_label_rc 7)"
    [ "$_rc" = "0" ] || fail "R5: '$_d' exited $_rc; a non-report must exit 0"
    [ "$(create_count)" = "0" ] || fail "R5: '$_d' created a label"
    [ "$(edit_count)" = "0" ] || fail "R5: '$_d' edited the issue"
    [ "$(comment_count)" = "0" ] || fail "R5: '$_d' posted a comment"
    unset GH_BODY_FILE
  }

  _n1="$T/r5-nomarker.md"
  printf 'just some prose with no marker\n' > "$_n1"
  _reject_case "no marker" "$_n1"

  _n2="$T/r5-line2.md"
  {
    printf 'preamble\n'
    printf '%s\n' "$MARKER_HM"
  } > "$_n2"
  _reject_case "marker on line 2" "$_n2"

  _n3="$T/r5-v2.md"
  printf '%s\n' '<!-- harness-feedback:v2 host=github.com version=9.9.9 trigger=workaround -->' > "$_n3"
  _reject_case "v2 marker" "$_n3"

  _n4="$T/r5-missing-trigger.md"
  printf '%s\n' '<!-- harness-feedback:v1 host=github.com version=9.9.9 -->' > "$_n4"
  _reject_case "missing trigger" "$_n4"

  _n5="$T/r5-extra-field.md"
  printf '%s\n' '<!-- harness-feedback:v1 host=github.com version=9.9.9 trigger=workaround extra=x -->' > "$_n5"
  _reject_case "extra field" "$_n5"

  _n6="$T/r5-bad-trigger.md"
  printf '%s\n' '<!-- harness-feedback:v1 host=github.com version=9.9.9 trigger=workaround-taken -->' > "$_n6"
  _reject_case "bad trigger (workaround-taken is not a trigger)" "$_n6"

  _n7="$T/r5-bad-version.md"
  printf '%s\n' '<!-- harness-feedback:v1 host=github.com version=9.9 trigger=workaround -->' > "$_n7"
  _reject_case "non-semver version" "$_n7"

  _n8="$T/r5-double-space.md"
  printf '%s\n' '<!-- harness-feedback:v1  host=github.com version=9.9.9 trigger=workaround -->' > "$_n8"
  _reject_case "double space" "$_n8"

  _n9="$T/r5-space-prefix.md"
  printf '%s\n' ' <!-- harness-feedback:v1 host=github.com version=9.9.9 trigger=workaround -->' > "$_n9"
  _reject_case "leading space" "$_n9"

  _n10="$T/r5-second-marker.md"
  {
    printf '%s\n' "$MARKER_HM"
    printf 'a second harness-feedback: token on a later line\n'
  } > "$_n10"
  _reject_case "valid marker + second harness-feedback: token" "$_n10"

  # Positive control: the SAME harness with a valid marker DOES label and edit, so the
  # zeroes above are not the only possible outcome.
  _ok="$T/r5-valid.md"
  printf '%s\n' "$MARKER_HM" > "$_ok"
  _out="$(run_parse "$_ok")"
  [ "$_out" = "$EXP_BUG" ] \
    || fail "R5 positive control: the valid fixture did not classify, so the reject zeroes are vacuous"
  clear_controls
  export GH_BODY_FILE="$_ok" GH_PRESENT='harness-feedback bug'
  run_label_ok 7
  [ "$(edit_count)" = "1" ] \
    || fail "R5 positive control: a valid marker produced $(edit_count) issue edit call(s), expected 1"
  unset GH_BODY_FILE GH_PRESENT
  pass "R5 every rejection shape prints zero bytes and mutates nothing; the same harness labels a valid marker [test_parse_rejects_non_reports]"
}

# ── R6 ────────────────────────────────────────────────────────────────────────────────────
test_label_mapping() {
  _map_case() { # <trigger> <expected label set> <marker>
    _t="$1"; _exp="$2"; _m="$3"
    _f="$T/r6-$_t.md"
    printf '%s\n' "$_m" > "$_f"
    sed -n '1p' "$_f" | grep -qE "$MARKER_RE" \
      || fail "R6 positive control: the '$_t' fixture is not a grammar-valid first line"
    _out="$(run_parse "$_f")"
    [ "$_out" = "$_exp" ] \
      || fail "R6: trigger '$_t' mapped to [$(printf '%s' "$_out" | tr '\n' ' ')], expected [$(printf '%s' "$_exp" | tr '\n' ' ')]"
  }
  _map_case missing-capability       "$EXP_ENH" "$MARKER_MC"
  _map_case harness-malfunction      "$EXP_BUG" "$MARKER_HM"
  _map_case contradictory-instruction "$EXP_BUG" "$MARKER_CI"
  _map_case workaround               "$EXP_BUG" "$MARKER_WA"
  pass "R6 all four trigger->label mappings, each with harness-feedback, asserted by full-string equality [test_label_mapping]"
}

# ── R7 ────────────────────────────────────────────────────────────────────────────────────
test_parse_injection() {
  _can="$T/r7-canary"
  rm -f "$_can"

  _inj="$T/r7-injection.md"
  {
    printf '%s\n' "$MARKER_HM"
    printf '$(touch "%s")\n' "$_can"
    printf '`touch "%s"`\n' "$_can"
    printf '; touch "%s"\n' "$_can"
    printf '${{ github.event.issue.body }}\n'
    printf ' trigger=missing-capability -->\n'
  } > "$_inj"

  # Positive control: the canary string really is in the fixture (search shape is live).
  grep -qF "$_can" "$_inj" \
    || fail "R7 positive control: the injection fixture does not contain the canary path, so the absence assertion is dead"

  _out="$(run_parse "$_inj")"
  [ "$_out" = "$EXP_BUG" ] \
    || fail "R7: an injection body with a valid first line did not classify by that line (got: $(printf '%s' "$_out" | tr '\n' '|'))"
  [ ! -e "$_can" ] || fail "R7: parse executed body text (canary created)"

  clear_controls
  export GH_BODY_FILE="$_inj" GH_PRESENT='harness-feedback bug'
  run_label_ok 7
  [ ! -e "$_can" ] || fail "R7: label-issue executed body text (canary created)"
  [ "$(edit_count)" = "1" ] || fail "R7: the injection body did not label by its first line"
  unset GH_BODY_FILE GH_PRESENT

  # Forged marker that is NOT the first line: empty set, no mutation, no execution.
  rm -f "$_can"
  _forged="$T/r7-forged.md"
  {
    printf '${{ github.event.issue.body }}\n'
    printf '%s\n' "$MARKER_CI"
    printf '`touch "%s"`\n' "$_can"
  } > "$_forged"
  grep -qF "$_can" "$_forged" \
    || fail "R7 positive control: the forged fixture lacks the canary path"
  _out2="$(run_parse "$_forged")"
  [ -z "$_out2" ] \
    || fail "R7: a marker not on the first line classified (got: $(printf '%s' "$_out2" | tr '\n' '|'))"
  clear_controls
  export GH_BODY_FILE="$_forged"
  _rc="$(run_label_rc 7)"
  [ "$_rc" = "0" ] || fail "R7: the forged-marker body exited $_rc; expected 0"
  [ "$(create_count)" = "0" ] || fail "R7: the forged-marker body created a label"
  [ "$(edit_count)" = "0" ] || fail "R7: the forged-marker body edited the issue"
  [ "$(comment_count)" = "0" ] || fail "R7: the forged-marker body posted a comment"
  [ ! -e "$_can" ] || fail "R7: the forged-marker body executed text (canary created)"
  unset GH_BODY_FILE
  pass "R7 metacharacters/command substitutions/\${{ }}/embedded-newline attempts execute nothing; classification is first-line only [test_parse_injection]"
}

# ── R8 ────────────────────────────────────────────────────────────────────────────────────
test_label_ensure_create_only_missing() {
  _valid="$T/r8-valid.md"
  printf '%s\n' "$MARKER_HM" > "$_valid"

  # (a) one present, one absent: exactly one create, with the pinned values; no touch of the
  # present one, and never --force.
  clear_controls
  export GH_BODY_FILE="$_valid" GH_PRESENT='harness-feedback'
  run_label_ok 7
  [ "$(create_count)" = "1" ] \
    || fail "R8: one present + one absent label produced $(create_count) create call(s), expected 1"
  [ "$(created_labels)" = "bug" ] \
    || fail "R8: the created label is [$(created_labels | tr '\n' ' ')], expected bug"
  [ "$(label_create_flag bug --color)" = "d73a4a" ] \
    || fail "R8: bug was created with color '$(label_create_flag bug --color)', expected d73a4a"
  [ "$(label_create_flag bug --description)" = "Something isn't working" ] \
    || fail "R8: bug was created with description '$(label_create_flag bug --description)', expected the pinned text"
  if created_labels | grep -qx 'harness-feedback'; then
    fail "R8: an existing label (harness-feedback) was re-created"
  fi
  if calls_joined | grep -q -- '--force'; then
    fail "R8: a label create used --force (would modify an existing label)"
  fi

  # (b) both absent: both created (positive control that the probe's absent branch is live).
  clear_controls
  export GH_BODY_FILE="$_valid"
  run_label_ok 7
  [ "$(create_count)" = "2" ] \
    || fail "R8 positive control: both labels absent produced $(create_count) create call(s), expected 2"
  [ "$(label_create_flag harness-feedback --color)" = "5319e7" ] \
    || fail "R8 positive control: harness-feedback was not created with the pinned color 5319e7"

  # (c) a hard probe error must NOT be read as absent: non-zero exit, zero creates.
  clear_controls
  export GH_BODY_FILE="$_valid" GH_PROBE_RC=1
  _rc="$(run_label_rc 7)"
  [ "$_rc" != "0" ] \
    || fail "R8: a hard label-probe error exited 0; a transient error must abort non-zero"
  [ "$(create_count)" = "0" ] \
    || fail "R8: a hard probe error still created $(create_count) label(s); only a definitive 404 is 'absent'"
  unset GH_PROBE_RC
  pass "R8 absent labels are created with the pinned values, existing labels are untouched, a probe error aborts non-zero with zero creates [test_label_ensure_create_only_missing]"
}

# ── R9 ────────────────────────────────────────────────────────────────────────────────────
test_apply_and_no_comment() {
  _valid="$T/r9-valid.md"
  printf '%s\n' "$MARKER_HM" > "$_valid"

  clear_controls
  export GH_BODY_FILE="$_valid" GH_PRESENT='harness-feedback bug'
  run_label_ok 7
  [ "$(edit_count)" = "1" ] \
    || fail "R9 positive control: the apply path issued $(edit_count) issue edit call(s), expected exactly 1"
  [ "$(argv_value --add-label)" = "harness-feedback,bug" ] \
    || fail "R9: --add-label was '$(argv_value --add-label)', expected the full comma list in the pinned order"
  [ "$(comment_count)" = "0" ] \
    || fail "R9: the labeler posted a comment; it must post none"

  # Fetch failure: non-zero, zero edit/comment.
  clear_controls
  export GH_FETCH_RC=1
  _rc="$(run_label_rc 7)"
  [ "$_rc" != "0" ] \
    || fail "R9: a failing body fetch exited 0; it must exit non-zero so the failure is visible"
  [ "$(edit_count)" = "0" ] || fail "R9: a failing body fetch still edited the issue"
  [ "$(comment_count)" = "0" ] || fail "R9: a failing body fetch posted a comment"
  unset GH_FETCH_RC

  # Edit failure: non-zero, no comment.
  clear_controls
  export GH_BODY_FILE="$_valid" GH_PRESENT='harness-feedback bug' GH_EDIT_RC=1
  _rc="$(run_label_rc 7)"
  [ "$_rc" != "0" ] \
    || fail "R9: a failing issue edit exited 0; a label mutation failure must exit non-zero"
  [ "$(comment_count)" = "0" ] || fail "R9: a failing issue edit posted a comment"
  unset GH_BODY_FILE GH_PRESENT GH_EDIT_RC
  pass "R9 one gh issue edit --add-label with exactly the set, zero comments, failing fetch/mutation exits non-zero [test_apply_and_no_comment]"
}

# ── R10 ───────────────────────────────────────────────────────────────────────────────────
test_source_only_placement() {
  [ -f "$WF" ] || fail "R10: $WF is missing"
  [ -f "$SCRIPT" ] || fail "R10: $SCRIPT is missing"
  case "$WF" in "$SRC/.github/"*) : ;; *) fail "R10: the workflow does not live under .github/" ;; esac
  case "$SCRIPT" in "$SRC/.github/"*) : ;; *) fail "R10: the parser does not live under .github/" ;; esac

  # Positive control: harness-install.sh DOES reference F02's installed tool, so the grep is
  # live and the absences below are meaningful.
  grep -qF 'harness-report.sh' "$SRC/harness-install.sh" \
    || fail "R10 positive control: harness-install.sh does not reference harness-report.sh, so the installer-absence check is vacuous"
  if grep -qF 'feedback-labeler' "$SRC/harness-install.sh"; then
    fail "R10: harness-install.sh references feedback-labeler — the surface must not be installed"
  fi
  if grep -qF '.github/workflows' "$SRC/harness-install.sh"; then
    fail "R10: harness-install.sh references .github/workflows — the surface must not be installed"
  fi

  # No VERSION bump / no CHANGELOG entry vs the base ref.
  _base=""
  for _ref in origin/main main; do
    if git -C "$SRC" rev-parse --verify --quiet "$_ref" >/dev/null 2>&1; then _base="$_ref"; break; fi
  done
  if [ -z "$_base" ]; then
    printf 'note: R10 VERSION/CHANGELOG no-diff assertion N/A — neither origin/main nor main resolves (not treated as a pass)\n'
  else
    _changed="$(git -C "$SRC" diff --name-only "$_base" -- VERSION CHANGELOG.md)"
    [ -z "$_changed" ] \
      || fail "R10: this CI-only change touched $_base:$_changed — no VERSION bump and no CHANGELOG entry are owed"
  fi
  pass "R10 both surfaces live under .github/, the installer references neither, and VERSION/CHANGELOG are unchanged vs base [test_source_only_placement]"
}

# ── R11 ───────────────────────────────────────────────────────────────────────────────────
test_parser_interface() {
  [ -f "$SCRIPT" ] || fail "R11: $SCRIPT is missing"
  # Worktree bit (what `./script` needs)...
  [ -x "$SCRIPT" ] || fail "R11: the worktree executable bit is not set on $SCRIPT"
  # ...AND the committed contract (git's tracked mode). Two different mutants, two arms.
  _mode="$(git -C "$SRC" ls-files -s -- .github/scripts/feedback-labeler.sh | awk '{print $1}')"
  [ "$_mode" = "100755" ] \
    || fail "R11: the tracked mode is '${_mode:-<none>}', expected 100755"

  sh -n "$SCRIPT" || fail "R11: sh -n failed on $SCRIPT under $(command -v sh)"

  # parse classifies a fixture with NO gh on PATH (proving it needs no GitHub access).
  _f="$T/r11-valid.md"
  printf '%s\n' "$MARKER_HM" > "$_f"
  _out="$(PATH=/usr/bin:/bin sh "$SCRIPT" parse "$_f")"
  [ "$_out" = "$EXP_BUG" ] \
    || fail "R11: parse without gh on PATH did not classify (got: $(printf '%s' "$_out" | tr '\n' '|'))"
  # Positive control: that PATH really has no gh, so the assertion exercises absence.
  if PATH=/usr/bin:/bin command -v gh >/dev/null 2>&1; then
    fail "R11: /usr/bin:/bin resolves gh, so the no-GitHub-access assertion is not exercising absence"
  fi
  pass "R11 the parser is a checked-in, executable, tracked-100755 POSIX sh script whose parse mode needs no gh [test_parser_interface]"
}

# ── run ───────────────────────────────────────────────────────────────────────────────────
test_trigger_opened_only
test_permissions_and_pinning
test_workflow_untrusted_input
test_parse_valid_marker
test_parse_rejects_non_reports
test_label_mapping
test_parse_injection
test_label_ensure_create_only_missing
test_apply_and_no_comment
test_source_only_placement
test_parser_interface

echo "all feedback labeler tests passed"
