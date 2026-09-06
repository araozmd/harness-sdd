#!/bin/sh
# test_self_drift.sh — E26-F02 divergence-by-construction gate for the self glue.
#
# R1: regenerating the glue in a pristine copy must reproduce the COMMITTED glue
# byte-for-byte — an emitter edited without `--self`, or a hand-edited generated file,
# fails this suite (which runs under verification.test_command, the CI-equivalent).
# R2: `--self` records a cksum ledger at .claude/.glue-manifest.
# R3: init.sh surfaces staleness as ONE warn-only line, source layout only.
#
# Zero dependencies; self-cleaning temp dir; POSIX sh.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
trap 'rm -rf "$T"' EXIT
export CODEX_HOME="$T/codex-home"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# fixture <name> — copy the source tree (minus VCS/heavy dirs) and print the path.
fixture() {
  _fx="$T/$1"
  mkdir -p "$_fx"
  for _e in "$SRC"/* "$SRC"/.claude "$SRC"/.escalation-arming; do
    [ -e "$_e" ] || continue
    case "$(basename "$_e")" in .git|node_modules) continue ;; esac
    cp -R "$_e" "$_fx/" 2>/dev/null || true
  done
  printf '%s\n' "$_fx"
}

# glue_diff <copy-dir> — diff the copy's regenerated glue against the COMMITTED $SRC
# glue; prints divergences (empty = in sync). The single comparison helper both R1
# arms drive.
glue_diff() {
  diff -r "$1/.claude/agents" "$SRC/.claude/agents" 2>&1 || true
  diff -r "$1/.claude/commands" "$SRC/.claude/commands" 2>&1 || true
  diff "$1/.escalation-arming" "$SRC/.escalation-arming" 2>&1 || true
}

# ── R1 gate-green: emitters and committed glue are in sync RIGHT NOW ──────────
F="$(fixture green)"
# The copy inherits the COMMITTED manifest; drop it so R2 proves --self WRITES the
# ledger rather than inheriting a stale-but-correct copy (a dropped write survived
# exactly this way in mutation testing).
rm -f "$F/.claude/.glue-manifest"
sh "$F/harness-install.sh" --self >"$T/out1.txt" 2>&1 \
  || { cat "$T/out1.txt" >&2; fail "--self exited non-zero"; }
_d="$(glue_diff "$F")"
[ -z "$_d" ] || { printf '%s\n' "$_d" >&2; \
  fail "regenerated glue differs from the committed copy — an emitter changed without 'sh harness-install.sh --self', or a generated file was hand-edited. Regenerate and commit. (R1)"; }
pass "committed glue == regenerated glue, byte for byte (R1) [gate_green]"

# ── R1 gate-red: an emitter edit WITHOUT regeneration is exactly what fails ───
R="$(fixture red)"
sed 's/You are the Builder for this project\./You are the MUTATED Builder for this project./' \
  "$R/harness-install.sh" > "$R/harness-install.sh.t" && mv "$R/harness-install.sh.t" "$R/harness-install.sh"
grep -q "MUTATED Builder" "$R/harness-install.sh" || fail "setup: emitter mutation did not apply"
sh "$R/harness-install.sh" --self >/dev/null 2>&1 || fail "mutated --self exited non-zero"
_d="$(glue_diff "$R")"
printf '%s\n' "$_d" | grep -q "MUTATED" \
  || fail "an emitter edit did not surface in the comparison — the gate cannot catch divergence (R1)"
pass "an emitter edit without regeneration is caught by the same comparison (R1) [gate_red]"

# ── R2: the manifest ledger ───────────────────────────────────────────────────
[ -f "$F/.claude/.glue-manifest" ] || fail "no .glue-manifest after --self (R2)"
for _must in .claude/agents/builder.md .claude/commands/sdd-next.md .escalation-arming; do
  grep -q " $_must\$" "$F/.claude/.glue-manifest" || fail "manifest misses $_must (R2)"
done
grep -q "glue-manifest" "$F/.claude/.glue-manifest" && fail "manifest lists itself (R2)"
while IFS= read -r _l; do
  [ -n "$_l" ] || continue
  _p="$(printf '%s\n' "$_l" | awk '{print $3}')"
  [ "$(cd "$F" && cksum "$_p")" = "$_l" ] || fail "manifest entry stale for $_p right after --self (R2)"
done < "$F/.claude/.glue-manifest"
pass "manifest lists every glue file + arming, verifies, never itself (R2) [manifest_ledger]"

# ── R3: init.sh warn fires on a hand edit, exit stays 0 ───────────────────────
echo "hand edit" >> "$F/.claude/agents/scout.md"
( cd "$F" && ./init.sh ) >"$T/init-stale.txt" 2>&1 \
  || fail "init.sh failed on stale glue — staleness must be warn-only (R3)"
grep -q "diverges from its --self manifest" "$T/init-stale.txt" \
  || fail "no staleness warn line after a hand edit (R3)"
grep -q "scout.md" "$T/init-stale.txt" || fail "warn line does not name the edited file (R3)"
pass "hand edit → one warn-only line, init.sh still exits 0 (R3) [warn_fires]"

# ── R3: silent when clean; silent with no manifest (target-layout proxy) ──────
C="$(fixture clean)"
sh "$C/harness-install.sh" --self >/dev/null 2>&1 || fail "clean --self exited non-zero"
( cd "$C" && ./init.sh ) >"$T/init-clean.txt" 2>&1 || fail "init.sh failed on a clean tree (R3)"
grep -q "diverges from its --self manifest" "$T/init-clean.txt" \
  && fail "staleness warn fired on a clean tree (R3)"
rm -f "$C/.claude/.glue-manifest"
( cd "$C" && ./init.sh ) >"$T/init-nomani.txt" 2>&1 || fail "init.sh failed with no manifest (R3)"
grep -q "diverges from its --self manifest" "$T/init-nomani.txt" \
  && fail "staleness warn fired with no manifest present (R3)"
pass "silent when clean and when the manifest is absent (R3) [warn_silent]"

echo "ALL PASSED (test_self_drift.sh)"
