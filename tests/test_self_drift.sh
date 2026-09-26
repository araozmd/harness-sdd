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
  for _e in "$SRC"/* "$SRC"/.claude "$SRC"/.codex "$SRC"/.agents "$SRC"/.escalation-arming; do
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
  diff -r "$1/.codex/agents" "$SRC/.codex/agents" 2>&1 || true
  diff -r "$1/.agents/skills" "$SRC/.agents/skills" 2>&1 || true
  diff -r "$1/.opencode/command" "$SRC/.opencode/command" 2>&1 || true
  diff -r "$1/.opencode/agent" "$SRC/.opencode/agent" 2>&1 || true
  # `-u` so the OpenCode FILE diff names its path in the header; a bare `diff` of two files
  # prints only the hunks, and the R1 gate-red arm asserts the path is named.
  diff -u "$1/opencode.json" "$SRC/opencode.json" 2>&1 || true
  diff "$1/.escalation-arming" "$SRC/.escalation-arming" 2>&1 || true
}

# The green fixture inherits `opencode.json` through the `"$SRC"/*` glob; drop it (and any
# `.opencode/` a future fixture might copy) before `--self`. This is the falsifiability
# condition for the OpenCode arm: without it, the regenerated-vs-committed comparison is
# green against a stale committed artifact and proves the repo's state, not the code
# (`progress/lessons.md` 2026-09-05, copied-fixture).
purge_inherited_opencode() {
  rm -f "$1/opencode.json"
  rm -rf "$1/.opencode"
}

# ── R1 gate-green: emitters and committed glue are in sync RIGHT NOW ──────────
F="$(fixture green)"
# The copy inherits the COMMITTED manifest; drop it so R2 proves --self WRITES the
# ledger rather than inheriting a stale-but-correct copy (a dropped write survived
# exactly this way in mutation testing).
rm -f "$F/.claude/.glue-manifest"
rm -rf "$F/.codex/agents" "$F/.agents/skills"
# R6/R1 falsifiability: the OpenCode glue must be REGENERATED, not inherited.
purge_inherited_opencode "$F"
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

# ── R6 gate-red: an OPENCODE emitter edit without regeneration is caught too ──
# Emitter-specific: this mutates gen_opencode_json's orchestrator description, so only
# the OpenCode-owned opencode.json can carry the divergence. Asserting both the token and
# the PATH is what proves the comparison reaches the OpenCode surface (a .claude-only
# gate would red on the OTHER arm's mutation and stay silent here).
O="$(fixture opencode-red)"
purge_inherited_opencode "$O"
sed 's/The Leader: routes the next task, delegates\./The MUTATED OpenCode Leader: routes the next task, delegates./' \
  "$O/harness-install.sh" > "$O/harness-install.sh.t" && mv "$O/harness-install.sh.t" "$O/harness-install.sh"
grep -q "MUTATED OpenCode Leader" "$O/harness-install.sh" || fail "setup: OpenCode emitter mutation did not apply"
sh "$O/harness-install.sh" --self >/dev/null 2>&1 || fail "mutated OpenCode --self exited non-zero"
_d="$(glue_diff "$O")"
printf '%s\n' "$_d" | grep -q "MUTATED OpenCode Leader" \
  || fail "an OpenCode emitter edit did not surface in the comparison — the gate cannot catch OpenCode divergence (R6)"
printf '%s\n' "$_d" | grep -q "opencode.json" \
  || fail "the OpenCode drift diff does not name opencode.json — the gate cannot attribute the divergence (R6)"
pass "an OpenCode emitter edit without regeneration is caught and named (R6) [opencode_gate_red]"

# ── R2: the manifest ledger ───────────────────────────────────────────────────
# `.claude/commands/` is NOT purged before the fixture's `--self`, and `--self` leaves an
# edited file "unchanged and unclaimed", so a HAND EDIT to a committed `.claude/commands/*.md`
# is invisible to the byte-diff (it compares the edit to itself). The manifest ledger is that
# class's only backstop: after the manifest is deleted, an edited file cannot be re-adopted,
# so it drops out of the fresh manifest and these `_must` greps red. Every committed command
# unit must therefore be listed here — including E32-F03's `sdd-report`.
[ -f "$F/.claude/.glue-manifest" ] || fail "no .glue-manifest after --self (R2)"
for _must in .claude/agents/builder.md .claude/commands/sdd-next.md .claude/commands/sdd-report.md .codex/agents/builder.toml .agents/skills/sdd-next/SKILL.md .agents/skills/sdd-next/agents/openai.yaml .agents/skills/sdd-report/SKILL.md .agents/skills/sdd-report/agents/openai.yaml .escalation-arming opencode.json .opencode/command/sdd-next.md .opencode/command/sdd-test-concurrency.md .opencode/command/sdd-report.md .opencode/agent/pr-fixer.md; do
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

# E29-F01 R7 + E31-F02 R6: each native artifact class participates in the existing
# manifest, and (F02) so does every OpenCode-owned file. The OpenCode paths are asserted
# here AND in the R2 ledger loop above, so a gate that only compares bytes without a
# manifest entry (or vice versa) cannot pass on one surface alone.
for _path in .codex/agents/builder.toml .agents/skills/sdd-next/SKILL.md .agents/skills/sdd-next/agents/openai.yaml opencode.json .opencode/command/sdd-next.md .opencode/agent/pr-fixer.md; do
  _case="$(fixture native-drift)"
  sh "$_case/harness-install.sh" --self >/dev/null 2>&1 || fail "native drift setup failed"
  [ -f "$_case/$_path" ] || fail "native drift precondition missing $_path"
  printf '\n# drift\n' >> "$_case/$_path"
  (cd "$_case" && ./init.sh) > "$T/native-drift.log" 2>&1 || fail "native drift must remain warn-only"
  grep -qF "$_path" "$T/native-drift.log" || fail "manifest missed edited $_path"
  rm -f "$_case/$_path"
  (cd "$_case" && ./init.sh) > "$T/native-missing.log" 2>&1 || fail "native missing must remain warn-only"
  grep -qF "$_path" "$T/native-missing.log" || fail "manifest missed removed $_path"
  rm -rf "$_case"
done
pass "native role, skill, and policy edits/removals trigger source drift (R7) [codex_manifest_and_idempotence]"
echo "ALL PASSED (test_self_drift.sh)"
