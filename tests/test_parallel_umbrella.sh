#!/bin/sh
# Synthetic contracts for umbrella discovery, aggregate execution and helper isolation.
set -eu
SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
W="$(mktemp -d)"
trap 'chmod -R u+w "$W" 2>/dev/null || :; rm -rf "$W"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok - $*"; }
F="$W/repo"
mkdir -p "$F/tools" "$F/tests/lib/umbrella"
cp "$SRC/tools/run-tests.sh" "$F/tools/"
MARKERS="$W/markers"; export MARKERS
reset_groups() {
  : > "$MARKERS"
  for n in 01 02 03 04 05 06 07 08 09 10 11 12 13; do
    printf '#!/bin/sh\nset -eu\nprintf "%s\\n" >> "$MARKERS"\n' "$n" > "$F/tests/test_umbrella_${n}_fixture.sh"
  done
}
run_status() {
  RC=0
  "$@" > "$W/output" 2>&1 || RC=$?
}
reset_groups
# A distinctive aggregate proves exclusion rather than a lucky duplicate-free dispatcher.
echo 'echo aggregate >> "$MARKERS"' > "$F/tests/test_umbrella.sh"
run_status sh "$F/tools/run-tests.sh"
[ "$RC" = 0 ] || fail 'default discovery failed'
sort "$MARKERS" > "$W/actual"
printf '%s\n' 01 02 03 04 05 06 07 08 09 10 11 12 13 > "$W/expected"
cmp -s "$W/actual" "$W/expected" || fail 'default_discovery_once: aggregate included or group missing/duplicated'
pass default_discovery_once
cp "$SRC/tests/test_umbrella.sh" "$F/tests/"
for mode in direct explicit; do
  reset_groups
  if [ "$mode" = direct ]; then run_status sh "$F/tests/test_umbrella.sh"
  else run_status sh "$F/tools/run-tests.sh" "$F/tests/test_umbrella.sh"; fi
  [ "$RC" = 0 ] || fail "aggregate_order: $mode failed"
  cmp -s "$MARKERS" "$W/expected" || fail "aggregate_order: $mode order"
done
pass aggregate_order
for kind in plain errexit; do
  for mode in direct explicit default; do
    reset_groups
    if [ "$kind" = plain ]; then
      printf 'set -eu\necho deliberate-child-failure >&2\nexit 9\n' > "$F/tests/test_umbrella_02_fixture.sh"
    else
      printf 'set -eu\necho deliberate-child-failure >&2\nfalse\necho forbidden >> "$MARKERS"\n' > "$F/tests/test_umbrella_02_fixture.sh"
    fi
    case "$mode" in
      direct) run_status sh "$F/tests/test_umbrella.sh" ;;
      explicit) run_status sh "$F/tools/run-tests.sh" "$F/tests/test_umbrella.sh" ;;
      default) run_status sh "$F/tools/run-tests.sh" ;;
    esac
    [ "$RC" != 0 ] || fail "failed_group: $kind $mode returned success"
    grep -q deliberate-child-failure "$W/output" || fail "failed_group: $kind $mode diagnostic missing"
    if grep -q forbidden "$MARKERS"; then fail "errexit: $mode continued"; fi
  done
done
pass failed_group_and_errexit
# Child sh must resolve through the runner's selected strict-shell shim.
reset_groups
# Record the shim target while alive; the runner removes its workdir on exit.
cat > "$F/tests/test_umbrella_02_fixture.sh" <<'CHILD'
set -eu
p="$(command -v sh)"
if [ "${p##*/}" = sh ] && grep -q '^exec ' "$p" 2>/dev/null; then
  sed -n 's/^exec \([^ ]*\).*/\1/p' "$p" > "$MARKERS.shell"
else
  printf '%s\n' "$p" > "$MARKERS.shell"
fi
CHILD
run_status sh "$F/tools/run-tests.sh" "$F/tests/test_umbrella.sh"
[ "$RC" = 0 ] || fail strict_child
SELECTED="$(sed -n 's/.*suites passed (\([^ ]*\) .*/\1/p' "$W/output")"
[ "$(cat "$MARKERS.shell")" = "$SELECTED" ] || fail 'strict_child: child interpreter differs from runner'
pass strict_child
for kind in helper group; do
  for mode in default explicit; do
    reset_groups
    echo 'echo canary >> "$MARKERS"' > "$F/tests/test_canary.sh"
    if [ "$kind" = helper ]; then BAD="$F/tests/lib/umbrella/bad.sh"
    else BAD="$F/tests/test_umbrella_02_fixture.sh"; fi
    echo 'if then' > "$BAD"
    if [ "$mode" = default ]; then run_status sh "$F/tools/run-tests.sh"
    else run_status sh "$F/tools/run-tests.sh" "$F/tests/test_umbrella.sh"; fi
    [ "$RC" = 3 ] || fail "parse_before_execution: $kind $mode status $RC"
    [ ! -s "$MARKERS" ] || fail "parse_before_execution: $kind $mode executed a suite"
    rm "$BAD"
  done
done
pass parse_before_execution
cp "$SRC/tests/lib/umbrella/common.sh" "$SRC/tests/lib/umbrella/audit.sh" "$F/tests/lib/umbrella/"
cat > "$F/tests/helper_user.sh" <<'USER'
set -eu
. "$(dirname "$0")/lib/umbrella/common.sh"
. "$SRC/tests/lib/umbrella/audit.sh"
printf '%s\n%s\n' "$T" "$AU" > "$ROOT_RECORD"
mkdir "$AU/ro"
: > "$AU/ro/file"
chmod 0555 "$AU/ro"
# Rendezvous ensures these isolated roots coexist.
: > "$ROOT_RECORD.ready"
while [ ! -f "$PEER_RECORD.ready" ]; do sleep 0.1; done
exit "$END_STATUS"
USER
ROOT_RECORD="$W/one" PEER_RECORD="$W/two" END_STATUS=0 sh "$F/tests/helper_user.sh" & p1=$!
ROOT_RECORD="$W/two" PEER_RECORD="$W/one" END_STATUS=7 sh "$F/tests/helper_user.sh" & p2=$!
r1=0; wait "$p1" || r1=$?
r2=0; wait "$p2" || r2=$?
[ "$r1" = 0 ] && [ "$r2" = 7 ] || fail 'fixture_cleanup: helper users wrong exit'
cat "$W/one" "$W/two" > "$W/roots"
[ "$(sort -u "$W/roots" | wc -l | tr -d ' ')" = 4 ] || fail 'fixture_cleanup: shared root'
while IFS= read -r owned; do
  [ ! -e "$owned" ] || fail "fixture_cleanup: leaked $owned"
done < "$W/roots"
pass fixture_cleanup
