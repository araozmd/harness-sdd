#!/bin/sh
# test_pi_front.sh — E35-F01, the pi front-end key.
#
# Covers R1–R12 of specs/epics/E35-pi-first-class/F01-pi-frontend-key/.
#
# HERMETIC. This machine may have a real `pi` on PATH and may leak PI_* variables into the
# test shell. Every installer run therefore goes through `inst`, which is `env -i` with only
# a sandbox PATH (the real PATH minus every directory that holds a `pi` executable), an
# isolated HOME and an isolated CODEX_HOME. A stub `pi` is added to PATH only where R9
# needs one, and it records itself and exits non-zero: it exists to be FOUND, never RUN.
# No case runs pi, a model or the network; nothing is written outside `mktemp -d`.
#
# Zero dependencies beyond python3 (parses the roster JSON) and git (R10).

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INST="$SRC/harness-install.sh"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-pi)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── the sandbox PATH: real PATH minus every directory holding a `pi` ─────────────────────
_sp_out=""; _sp_oifs="$IFS"; IFS=:
set -- $PATH
IFS="$_sp_oifs"
for _sp_d in "$@"; do
  [ -n "$_sp_d" ] || continue
  [ -x "$_sp_d/pi" ] && continue
  if [ -z "$_sp_out" ]; then _sp_out="$_sp_d"; else _sp_out="$_sp_out:$_sp_d"; fi
done
SANDBOX_PATH="$_sp_out"
env -i PATH="$SANDBOX_PATH" sh -c 'command -v pi' >/dev/null 2>&1 \
  && fail "sandbox setup: 'pi' still resolves on the sandbox PATH — R9 absence would test this machine"
for _c in awk sed grep sort tr cp mv rm mkdir cat cmp mktemp find python3 git; do
  env -i PATH="$SANDBOX_PATH" sh -c "command -v $_c" >/dev/null 2>&1 \
    || fail "sandbox setup: '$_c' is missing from the sandbox PATH"
done

mkdir -p "$T/home" "$T/ch"
OUT="$T/out"

# inst <path-prefix|-> <extra-env|-> <installer args…> — run the installer hermetically,
# capturing stdout+stderr in $OUT. Returns the installer's status.
# $1 is a bin dir prepended to the sandbox PATH ("-" for none); $2 is one VAR=value ("-" none).
inst() {
  _i_bin="$1"; _i_env="$2"; shift 2
  _i_path="$SANDBOX_PATH"
  if [ "$_i_bin" != "-" ]; then _i_path="$_i_bin:$SANDBOX_PATH"; fi
  _i_rc=0
  if [ "$_i_env" = "-" ]; then
    env -i PATH="$_i_path" HOME="$T/home" CODEX_HOME="$T/ch" \
      sh "$INST" "$@" </dev/null >"$OUT" 2>&1 || _i_rc=$?
  else
    env -i PATH="$_i_path" HOME="$T/home" CODEX_HOME="$T/ch" "$_i_env" \
      sh "$INST" "$@" </dev/null >"$OUT" 2>&1 || _i_rc=$?
  fi
  return "$_i_rc"
}
# ok_inst — the same, but a non-zero exit is a fixture failure.
ok_inst() { inst "$@" || { cat "$OUT" >&2; fail "setup: installer exited non-zero ($*)"; }; }

new_target() { _nt="$T/$1"; rm -rf "$_nt"; mkdir -p "$_nt"; printf '%s\n' "$_nt"; }

agents_of() { tr '\n' ' ' < "$1/.harness/.agents" | sed 's/ $//'; }
prompts_of() { ls "$1/.pi/prompts" 2>/dev/null | sed 's/\.md$//' | sort | tr '\n' ' ' | sed 's/ $//'; }
units_of() { ls "$1/.agents/skills" 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//'; }
set_pr_loop() { sed "s|^  enabled: .*|  enabled: $2|" "$1/.harness/harness.config.yaml" > "$1/.harness/c.t" \
  && mv "$1/.harness/c.t" "$1/.harness/harness.config.yaml"; }
cks() { find "$1/.agents/skills" -type f 2>/dev/null | sort | while IFS= read -r _f; do cksum "$_f"; done; }

FENCE_AWK="$(cat "$SRC/tests/lib/fence.awk")"
STD="sdd-drill sdd-fix sdd-fix-parallel sdd-new sdd-next sdd-plan sdd-report"

# ── R1 ─────────────────────────────────────────────────────────────────────────────────────
test_pi_is_selectable() {
  _t="$(new_target r1a)"; ok_inst - - --agents=pi "$_t"
  [ "$(agents_of "$_t")" = "pi" ] || fail "R1: --agents=pi persisted '$(agents_of "$_t")', expected 'pi'"
  # A later non-interactive re-run that names no selection keeps pi.
  ok_inst - - "$_t"
  [ "$(agents_of "$_t")" = "pi" ] || fail "R1: a no-selection re-run dropped pi (got '$(agents_of "$_t")')"
  _t="$(new_target r1b)"; ok_inst - HARNESS_AGENTS=pi "$_t"
  [ "$(agents_of "$_t")" = "pi" ] || fail "R1: HARNESS_AGENTS=pi persisted '$(agents_of "$_t")'"
  _t="$(new_target r1c)"; ok_inst - - --agents=all "$_t"
  [ "$(agents_of "$_t")" = "antigravity claude codex opencode pi" ] \
    || fail "R1: --agents=all resolved to '$(agents_of "$_t")'"
  pass "pi is selectable, persists across a bare re-run, and --agents=all yields five keys (R1)"
}

# ── R2 ─────────────────────────────────────────────────────────────────────────────────────
test_no_pi_glue_when_unselected() {
  _t="$(new_target r2)"
  ok_inst - - --agents=claude,codex,opencode "$_t"
  ok_inst - - --agents=claude,codex,opencode "$_t"
  [ ! -e "$_t/.pi" ] || fail "R2: an unselected pi created .pi/"
  [ ! -e "$_t/.harness/.pi-prompts" ] || fail "R2: an unselected pi created .harness/.pi-prompts/"
  pass "no .pi/ path and no pi ledger when pi was never selected (R2)"
}

# ── R3 ─────────────────────────────────────────────────────────────────────────────────────
test_pi_claims_shared_units() {
  _t="$(new_target r3)"; ok_inst - - --agents=pi --pr-loop=false "$_t"
  [ "$(units_of "$_t")" = "$STD" ] || fail "R3: pi-only units are '$(units_of "$_t")', expected '$STD'"
  for _c in $STD; do
    [ -f "$_t/.agents/skills/$_c/SKILL.md" ] || fail "R3: missing $_c/SKILL.md"
    [ -f "$_t/.agents/skills/$_c/agents/openai.yaml" ] || fail "R3: missing $_c/agents/openai.yaml"
  done
  [ ! -e "$_t/.agents/skills/sdd-triage" ] || fail "R3: the source-only sdd-triage reached a target"
  _t="$(new_target r3b)"; ok_inst - - --agents=pi --pr-loop=true "$_t"
  [ -f "$_t/.agents/skills/sdd-pr-loop/SKILL.md" ] || fail "R3: --pr-loop=true did not install sdd-pr-loop"
  pass "a pi-only install claims the shared units, gated on pr_loop, never sdd-triage (R3)"
}

# ── R4 ─────────────────────────────────────────────────────────────────────────────────────
test_pi_reclaim_only_when_last_claimant() {
  for _keep in codex opencode antigravity; do
    _t="$(new_target "r4-$_keep")"; ok_inst - - --agents="$_keep,pi" "$_t"
    cks "$_t" > "$T/before"
    ok_inst - - --agents="$_keep" "$_t"
    cks "$_t" > "$T/after"
    cmp -s "$T/before" "$T/after" || fail "R4: deselecting pi from $_keep,pi changed the shared units"
  done
  _t="$(new_target r4-last)"; ok_inst - - --agents=pi "$_t"
  ok_inst - - --agents=claude "$_t"
  [ -z "$(units_of "$_t")" ] || fail "R4: pristine units survived the last claimant leaving ('$(units_of "$_t")')"
  _t="$(new_target r4-edit)"; ok_inst - - --agents=pi "$_t"
  printf '\nuser edit\n' >> "$_t/.agents/skills/sdd-next/SKILL.md"
  ok_inst - - --agents=claude "$_t"
  [ -f "$_t/.agents/skills/sdd-next/SKILL.md" ] || fail "R4: an edited SKILL.md was reclaimed"
  [ -f "$_t/.agents/skills/sdd-next/agents/openai.yaml" ] || fail "R4: the edited unit's companion was reclaimed"
  [ ! -e "$_t/.agents/skills/sdd-new" ] || fail "R4: a pristine sibling unit survived"
  pass "units survive while another claimant remains and are reclaimed pristine-only when pi leaves last (R4)"
}

# ── R5 ─────────────────────────────────────────────────────────────────────────────────────
test_skill_adapter_names_pi() {
  _t="$(new_target r5a)"; ok_inst - - --agents=codex,pi --pr-loop=true "$_t"
  for _u in "$_t"/.agents/skills/sdd-*; do
    _c="${_u##*/}"; _f="$_u/SKILL.md"
    awk "$FENCE_AWK"'
      fence_delim($0) { if (k) print; next }
      !fence && /^## Invocation adapter/ { k=1; next }
      !fence && /^## / { k=0; next }
      k' "$_f" > "$T/adapter"
    grep -qF 'In Antigravity or OpenCode, invoke' "$T/adapter" || fail "R5: $_c lost the original adapter sentence"
    grep -qF "in Codex, invoke \`\$$_c\`" "$T/adapter" || fail "R5: $_c lost the Codex invocation"
    grep -qF "In pi, invoke \`/$_c\`" "$T/adapter" || fail "R5: $_c adapter does not name /$_c for pi"
    grep -qF "\`/skill:$_c\`" "$T/adapter" || fail "R5: $_c adapter does not name /skill:$_c"
    grep -q 'trusted' "$T/adapter" || fail "R5: $_c adapter names no trust prerequisite"
    grep -E '^In pi,' "$T/adapter" > "$T/piline" || fail "R5: $_c has no 'In pi,' line"
    [ "$(wc -l < "$T/piline" | tr -d ' ')" = 1 ] || fail "R5: $_c has more than one pi sentence"
    grep -q '\$' "$T/piline" && fail "R5: the pi sentence of $_c contains a dollar sign"
    grep -q '/skills' "$T/piline" && fail "R5: the pi sentence of $_c names /skills"
    # The original adapter line is byte-compatible: the original sentence stays on one line.
    grep -F 'In Antigravity or OpenCode, invoke' "$T/adapter" | grep -qF "all accompanying text as \`\$ARGUMENTS\`" \
      || fail "R5: $_c original adapter line was split or rewritten"
  done
  # Same bytes whether or not pi is also selected: pi adds no per-claimant variation.
  _t2="$(new_target r5b)"; ok_inst - - --agents=codex --pr-loop=true "$_t2"
  cks "$_t" | sed 's/^[0-9]* [0-9]* //' | sort > "$T/n1"
  for _c in sdd-next sdd-new; do
    cmp -s "$_t/.agents/skills/$_c/SKILL.md" "$_t2/.agents/skills/$_c/SKILL.md" \
      || fail "R5: $_c SKILL.md differs between --agents=codex and --agents=codex,pi"
  done
  pass "the shared adapter keeps its sentence and adds one pi sentence with no \$ and no /skills (R5)"
}

# ── R6 ─────────────────────────────────────────────────────────────────────────────────────
test_pi_prompt_templates_shape_and_set() {
  for _g in false true; do
    _t="$(new_target "r6-$_g")"; ok_inst - - --agents=pi --pr-loop="$_g" "$_t"
    [ "$(prompts_of "$_t")" = "$(units_of "$_t")" ] \
      || fail "R6 (pr_loop=$_g): .pi/prompts is '$(prompts_of "$_t")' but the shared units are '$(units_of "$_t")'"
    if [ "$_g" = true ]; then
      [ -f "$_t/.pi/prompts/sdd-pr-loop.md" ] || fail "R6: no sdd-pr-loop template while pr_loop is on"
    else
      [ ! -e "$_t/.pi/prompts/sdd-pr-loop.md" ] || fail "R6: sdd-pr-loop template while pr_loop is off"
    fi
    for _p in "$_t"/.pi/prompts/*.md; do
      _c="$(basename "$_p" .md)"
      [ "$(sed -n 1p "$_p")" = '---' ] || fail "R6: $_c line 1 is not ---"
      [ "$(sed -n 3p "$_p")" = '---' ] || fail "R6: $_c line 3 is not ---"
      [ "$(sed -n 2p "$_p")" = "$(sed -n 3p "$_t/.agents/skills/$_c/SKILL.md")" ] \
        || fail "R6: $_c description differs from the skill's"
      sed -n 2p "$_p" | grep -q '^description: .' || fail "R6: $_c has an empty description"
      grep -qF ".agents/skills/$_c/SKILL.md" "$_p" || fail "R6: $_c does not point at its shared unit"
      [ "$(grep -o '\$' "$_p" | wc -l | tr -d ' ')" = 1 ] || fail "R6: $_c has other than exactly one dollar sign"
      grep -qF '$ARGUMENTS' "$_p" || fail "R6: $_c lacks \$ARGUMENTS"
      grep -q 'argument-hint' "$_p" && fail "R6: $_c carries an argument-hint key"
    done
  done
  # Byte-idempotent re-install.
  _t="$(new_target r6-idem)"; ok_inst - - --agents=pi "$_t"
  find "$_t/.pi" "$_t/.harness/.pi-prompts" -type f | sort | while IFS= read -r _f; do cksum "$_f"; done > "$T/i1"
  ok_inst - - --agents=pi "$_t"
  find "$_t/.pi" "$_t/.harness/.pi-prompts" -type f | sort | while IFS= read -r _f; do cksum "$_f"; done > "$T/i2"
  cmp -s "$T/i1" "$T/i2" || fail "R6: a re-install changed template or stamp bytes"
  # Each stamp is a byte copy of its template.
  for _p in "$_t"/.pi/prompts/*.md; do
    cmp -s "$_p" "$_t/.harness/.pi-prompts/$(basename "$_p")" || fail "R6: stamp differs from $(basename "$_p")"
  done
  pass "templates match the shared-unit set, have the exact shape, one \$ARGUMENTS, and re-install idempotently (R6)"
}

# ── R7 ─────────────────────────────────────────────────────────────────────────────────────
test_pi_prompt_ownership() {
  # (a) a user-authored template survives install.
  _t="$(new_target r7a)"; mkdir -p "$_t/.pi/prompts"; printf 'mine\n' > "$_t/.pi/prompts/sdd-next.md"
  ok_inst - - --agents=pi "$_t"
  [ "$(cat "$_t/.pi/prompts/sdd-next.md")" = mine ] || fail "R7a: a user template was overwritten"
  grep -q 'foreign or edited' "$OUT" || fail "R7a: no foreign-or-edited warning"
  [ ! -e "$_t/.harness/.pi-prompts/sdd-next.md" ] || fail "R7a: a foreign file got a stamp"
  [ -f "$_t/.pi/prompts/sdd-new.md" ] || fail "R7a: the other templates were not written"
  # (b) editing then deselecting leaves the edited file, removes the rest and their stamps.
  _t="$(new_target r7b)"; ok_inst - - --agents=pi "$_t"
  printf 'edited\n' >> "$_t/.pi/prompts/sdd-new.md"
  ok_inst - - --agents=claude "$_t"
  [ -f "$_t/.pi/prompts/sdd-new.md" ] || fail "R7b: an edited template was deleted"
  grep -q 'has no matching stamp' "$OUT" || fail "R7b: no warning for the surviving edit"
  [ "$(ls "$_t/.pi/prompts" | tr '\n' ' ')" = "sdd-new.md " ] \
    || fail "R7b: pristine templates survived: $(ls "$_t/.pi/prompts" | tr '\n' ' ')"
  [ -z "$(ls "$_t/.harness/.pi-prompts" 2>/dev/null)" ] || fail "R7b: stamps survived"
  # (c) pristine deselect prunes everything but keeps .pi/ when it holds other files.
  _t="$(new_target r7c)"; mkdir -p "$_t/.pi"; printf '{}\n' > "$_t/.pi/settings.json"
  ok_inst - - --agents=pi "$_t"
  ok_inst - - --agents=claude "$_t"
  [ ! -e "$_t/.pi/prompts" ] || fail "R7c: .pi/prompts survived a pristine deselect"
  [ -f "$_t/.pi/settings.json" ] || fail "R7c: .pi/settings.json was touched"
  [ ! -e "$_t/.harness/.pi-prompts" ] || fail "R7c: the stamp ledger survived"
  _t="$(new_target r7c2)"; ok_inst - - --agents=pi "$_t"; ok_inst - - --agents=claude "$_t"
  [ ! -e "$_t/.pi" ] || fail "R7c: an empty .pi/ was not pruned"
  # (d) pr_loop gate-off removes only the pr-loop template while pi stays selected.
  _t="$(new_target r7d)"; ok_inst - - --agents=pi --pr-loop=true "$_t"
  [ -f "$_t/.pi/prompts/sdd-pr-loop.md" ] || fail "R7d: precondition — no pr-loop template"
  ok_inst - - --agents=pi --pr-loop=false "$_t"
  [ ! -e "$_t/.pi/prompts/sdd-pr-loop.md" ] || fail "R7d: gate-off kept the pr-loop template"
  [ ! -e "$_t/.harness/.pi-prompts/sdd-pr-loop.md" ] || fail "R7d: gate-off kept the pr-loop stamp"
  [ -f "$_t/.pi/prompts/sdd-next.md" ] || fail "R7d: gate-off removed an unrelated template"
  # (d2) an edited pr-loop template survives gate-off.
  _t="$(new_target r7d2)"; ok_inst - - --agents=pi --pr-loop=true "$_t"
  printf 'x\n' >> "$_t/.pi/prompts/sdd-pr-loop.md"
  ok_inst - - --agents=pi --pr-loop=false "$_t"
  [ -f "$_t/.pi/prompts/sdd-pr-loop.md" ] || fail "R7d2: gate-off deleted an edited template"
  # (e) a symlinked .pi/prompts is left untouched with a warning.
  _t="$(new_target r7e)"; mkdir -p "$T/outside-r7e" "$_t/.pi"; ln -s "$T/outside-r7e" "$_t/.pi/prompts"
  ok_inst - - --agents=pi "$_t"
  [ -z "$(ls "$T/outside-r7e")" ] || fail "R7e: wrote through a symlinked .pi/prompts"
  grep -q 'symlink' "$OUT" || fail "R7e: no symlink warning"
  ok_inst - - --agents=claude "$_t"
  [ -L "$_t/.pi/prompts" ] || fail "R7e: the symlink was removed on deselect"
  # (f) a lost stamp ledger: a byte-fresh template is still provably pristine, so it is
  # re-installed and, on a second target, reclaimed; an edited one is not.
  _t="$(new_target r7f)"; ok_inst - - --agents=pi "$_t"
  rm -rf "$_t/.harness/.pi-prompts"; printf 'x\n' >> "$_t/.pi/prompts/sdd-fix.md"
  ok_inst - - --agents=pi "$_t"
  grep -q 'foreign or edited' "$OUT" || fail "R7f: an edited template with a lost stamp was not warned about"
  [ "$(tail -n 1 "$_t/.pi/prompts/sdd-fix.md")" = x ] || fail "R7f: an edited template with a lost stamp was overwritten"
  [ -f "$_t/.harness/.pi-prompts/sdd-next.md" ] || fail "R7f: a fresh-equal template was not re-stamped"
  rm -rf "$_t/.harness/.pi-prompts"
  ok_inst - - --agents=claude "$_t"
  [ "$(ls "$_t/.pi/prompts" | tr '\n' ' ')" = "sdd-fix.md " ] \
    || fail "R7f: with a lost stamp, byte-fresh templates were not reclaimed (left: $(ls "$_t/.pi/prompts" | tr '\n' ' '))"
  pass "templates are pristine-only on install, deselect and gate-off; symlinks are refused (R7)"
}

# ── R7 / R10 hardening (reviewer round 1: M26, M24/M25, M18, M13) ────────────────────────
# A symlink-refusal test on a REMOVAL path needs a byte-fresh victim in the symlink target,
# or a delete-through is unobservable (progress/lessons.md, 2026-10-13).
test_pi_symlink_and_stamp_guards() {
  # donor: byte-fresh templates (pr-loop on, so sdd-pr-loop.md exists) to plant as victims.
  _d="$(new_target r7x-donor)"; ok_inst - - --agents=pi --pr-loop=true "$_d"
  _victims() { rm -rf "$1"; mkdir -p "$1"; cp "$_d"/.pi/prompts/*.md "$1/"; }
  _nv="$(ls "$_d/.pi/prompts" | wc -l | tr -d ' ')"
  [ "$_nv" = 8 ] || fail "R7x: donor precondition — expected 8 templates, got $_nv"
  # (g) deselect through a symlinked .pi/prompts must not delete the outside templates (M26).
  _t="$(new_target r7g)"; mkdir -p "$_t/.pi"; _victims "$T/outside-r7g"; ln -s "$T/outside-r7g" "$_t/.pi/prompts"
  ok_inst - - --agents=pi --pr-loop=true "$_t"
  ok_inst - - --agents=claude "$_t"
  [ -L "$_t/.pi/prompts" ] || fail "R7g: the symlink was removed on deselect"
  [ "$(ls "$T/outside-r7g" | wc -l | tr -d ' ')" = 8 ] \
    || fail "R7g: deselect deleted templates THROUGH a symlinked .pi/prompts (left: $(ls "$T/outside-r7g" | tr '\n' ' '))"
  grep -q 'symlink' "$OUT" || fail "R7g: no symlink warning on deselect"
  # one warning per template that exists; none for the never-installed sdd-pr-loop (pr_loop off).
  _t="$(new_target r7g2)"; mkdir -p "$_t/.pi"; _victims "$T/outside-r7g2"; rm -f "$T/outside-r7g2/sdd-pr-loop.md"
  ln -s "$T/outside-r7g2" "$_t/.pi/prompts"
  ok_inst - - --agents=pi --pr-loop=false "$_t"
  ok_inst - - --agents=claude "$_t"
  [ "$(grep -c 'symlinked or non-regular destination component' "$OUT")" = 7 ] \
    || fail "R7g: expected 7 symlink warnings (none for the never-installed sdd-pr-loop), got $(grep -c 'symlinked or non-regular destination component' "$OUT")"
  # (h) the same on pr_loop gate-off with pi still selected.
  _t="$(new_target r7h)"; mkdir -p "$_t/.pi"; _victims "$T/outside-r7h"; ln -s "$T/outside-r7h" "$_t/.pi/prompts"
  ok_inst - - --agents=pi --pr-loop=true "$_t"
  ok_inst - - --agents=pi --pr-loop=false "$_t"
  [ -f "$T/outside-r7h/sdd-pr-loop.md" ] \
    || fail "R7h: gate-off deleted sdd-pr-loop.md THROUGH a symlinked .pi/prompts"
  [ "$(ls "$T/outside-r7h" | wc -l | tr -d ' ')" = 8 ] || fail "R7h: gate-off changed the outside templates"
  # (i) a symlinked stamp ledger: install writes nothing through it (M24) ...
  _t="$(new_target r7i)"; mkdir -p "$T/outside-r7i" "$_t/.harness"; ln -s "$T/outside-r7i" "$_t/.harness/.pi-prompts"
  ok_inst - - --agents=pi "$_t"
  [ -z "$(ls "$T/outside-r7i")" ] || fail "R7i: install wrote stamps THROUGH a symlinked .harness/.pi-prompts"
  grep -q 'symlinked or non-regular stamp component' "$OUT" || fail "R7i: no symlinked-stamp warning on install"
  [ -L "$_t/.harness/.pi-prompts" ] || fail "R7i: the stamp-ledger symlink was replaced"
  # ... and deselect removes nothing through it (M25): real stamps AND fresh templates are victims.
  _t="$(new_target r7j)"; ok_inst - - --agents=pi "$_t"
  mkdir -p "$T/outside-r7j"; cp "$_t"/.harness/.pi-prompts/*.md "$T/outside-r7j/"
  rm -rf "$_t/.harness/.pi-prompts"; ln -s "$T/outside-r7j" "$_t/.harness/.pi-prompts"
  ok_inst - - --agents=claude "$_t"
  [ "$(ls "$T/outside-r7j" | wc -l | tr -d ' ')" = 7 ] \
    || fail "R7j: deselect removed stamps THROUGH a symlinked .harness/.pi-prompts (left: $(ls "$T/outside-r7j" | wc -l | tr -d ' '))"
  [ "$(ls "$_t/.pi/prompts" | wc -l | tr -d ' ')" = 7 ] || fail "R7j: deselect removed live templates despite the symlinked ledger"
  grep -q 'symlinked or non-regular stamp component' "$OUT" || fail "R7j: no symlinked-stamp warning on deselect"
  # (m) a non-regular stamp leaf (a directory) is unsafe: re-install copies nothing into it,
  # deselect leaves the live template and the ledger node in place and does not abort.
  _t="$(new_target r7m)"; ok_inst - - --agents=pi "$_t"
  rm -f "$_t/.harness/.pi-prompts/sdd-next.md"; mkdir "$_t/.harness/.pi-prompts/sdd-next.md"
  ok_inst - - --agents=pi "$_t"
  [ -z "$(ls -A "$_t/.harness/.pi-prompts/sdd-next.md")" ] || fail "R7m: install copied a stamp INTO a directory stamp leaf"
  grep -q 'symlinked or non-regular stamp component' "$OUT" || fail "R7m: no non-regular-stamp warning on install"
  ok_inst - - --agents=claude "$_t"
  [ -f "$_t/.pi/prompts/sdd-next.md" ] || fail "R7m: deselect deleted the live template behind a directory stamp leaf"
  [ -d "$_t/.harness/.pi-prompts/sdd-next.md" ] || fail "R7m: deselect removed the directory stamp leaf"
  [ ! -e "$_t/.pi/prompts/sdd-new.md" ] || fail "R7m: deselect stopped reconciling the other templates"
  # (n) a ledger that exists as a regular FILE is unsafe too: install must not abort on mkdir.
  _t="$(new_target r7n)"; mkdir -p "$_t/.harness"; printf 'not a dir\n' > "$_t/.harness/.pi-prompts"
  ok_inst - - --agents=pi "$_t"
  [ -f "$_t/.harness/.pi-prompts" ] || fail "R7n: the file-shaped ledger was replaced"
  grep -q 'symlinked or non-regular stamp component' "$OUT" || fail "R7n: no non-regular-stamp warning for a file-shaped ledger"
  # (o) a live parent that exists as a regular FILE (`.pi`, then `.pi/prompts`) is unsafe:
  # install must not abort on mkdir, the operator's file survives, the shared units still land.
  for _pc in .pi .pi/prompts; do
    _t="$(new_target "r7o-$(printf '%s' "$_pc" | tr '/.' '__')")"; mkdir -p "$_t/$(dirname "$_pc")"
    printf 'operator file\n' > "$_t/$_pc"
    ok_inst - - --agents=pi "$_t"
    [ "$(cat "$_t/$_pc")" = 'operator file' ] || fail "R7o: the file-shaped $_pc was replaced"
    grep -q 'symlinked or non-regular destination component' "$OUT" || fail "R7o: no non-regular warning for a file-shaped $_pc"
    [ -f "$_t/.agents/skills/sdd-next/SKILL.md" ] || fail "R7o: install stopped before the shared units with a file-shaped $_pc"
    [ ! -e "$_t/.harness/.pi-prompts/sdd-next.md" ] || fail "R7o: a stamp was written for a template that was never installed ($_pc)"
    ok_inst - - --agents=claude "$_t"
    [ "$(cat "$_t/$_pc")" = 'operator file' ] || fail "R7o: deselect removed the file-shaped $_pc"
  done
  # (p) a live template leaf that is a DIRECTORY is unsafe on install and on deselect.
  _t="$(new_target r7p)"; mkdir -p "$_t/.pi/prompts/sdd-next.md"; : > "$_t/.pi/prompts/sdd-next.md/keep"
  ok_inst - - --agents=pi "$_t"
  [ -f "$_t/.pi/prompts/sdd-next.md/keep" ] || fail "R7p: install disturbed a directory-shaped template leaf"
  grep -q 'symlinked or non-regular destination component' "$OUT" || fail "R7p: no non-regular warning for a directory leaf"
  [ -f "$_t/.pi/prompts/sdd-new.md" ] || fail "R7p: the sibling templates were not installed"
  # a stamp that pre-existed an unsafe live leaf is DROPPED (ownership ends), not retained.
  _t2="$(new_target r7p2)"; ok_inst - - --agents=pi "$_t2"
  [ -f "$_t2/.harness/.pi-prompts/sdd-next.md" ] || fail "R7p: precondition, no stamp after a clean install"
  rm -f "$_t2/.pi/prompts/sdd-next.md"; mkdir "$_t2/.pi/prompts/sdd-next.md"
  ok_inst - - --agents=pi "$_t2"
  [ ! -e "$_t2/.harness/.pi-prompts/sdd-next.md" ] || fail "R7p: stamp kept for an unsafe (directory) live leaf"
  # reclaim half: a clean install whose live leaf later becomes a directory loses its stamp on
  # deselect, and again on pr-loop gate-off (pi still selected); the directory survives both.
  _t3="$(new_target r7p3)"; ok_inst - - --agents=pi "$_t3"
  rm -f "$_t3/.pi/prompts/sdd-next.md"; mkdir "$_t3/.pi/prompts/sdd-next.md"
  ok_inst - - --agents=claude "$_t3"
  [ ! -e "$_t3/.harness/.pi-prompts/sdd-next.md" ] || fail "R7p: deselect kept the stamp for an unsafe (directory) live leaf"
  [ -d "$_t3/.pi/prompts/sdd-next.md" ] || fail "R7p: deselect removed the directory live leaf"
  _t4="$(new_target r7p4)"; ok_inst - - --agents=pi --pr-loop=true "$_t4"
  [ -f "$_t4/.harness/.pi-prompts/sdd-pr-loop.md" ] || fail "R7p: precondition, no pr-loop stamp after a clean install"
  rm -f "$_t4/.pi/prompts/sdd-pr-loop.md"; mkdir "$_t4/.pi/prompts/sdd-pr-loop.md"
  ok_inst - - --agents=pi --pr-loop=false "$_t4"
  [ ! -e "$_t4/.harness/.pi-prompts/sdd-pr-loop.md" ] || fail "R7p: gate-off kept the stamp for an unsafe (directory) live leaf"
  [ -d "$_t4/.pi/prompts/sdd-pr-loop.md" ] || fail "R7p: gate-off removed the directory live leaf"
  ok_inst - - --agents=claude "$_t"
  [ -f "$_t/.pi/prompts/sdd-next.md/keep" ] || fail "R7p: deselect removed the directory-shaped template leaf"
  [ ! -e "$_t/.pi/prompts/sdd-new.md" ] || fail "R7p: deselect stopped reconciling the sibling templates"
  # (q) a SYMLINKED `.pi` (the parent of prompts/): `rmdir .pi/prompts` follows an INTERMEDIATE
  # symlink, so only an EMPTY outside prompts/ can observe a prune-through (mutant K, round 3).
  for _v in empty fresh; do
    _t="$(new_target r7q-$_v)"; _o="$T/outside-r7q-$_v"; rm -rf "$_o"; mkdir -p "$_o/prompts"
    [ "$_v" = fresh ] && cp "$_d"/.pi/prompts/*.md "$_o/prompts/"
    _before="$(ls -A "$_o/prompts" | wc -l | tr -d ' ')"
    ln -s "$_o" "$_t/.pi"
    ok_inst - - --agents=pi --pr-loop=true "$_t"
    grep -q 'symlink' "$OUT" || fail "R7q($_v): no symlink warning on install"
    [ "$(ls -A "$_o" | tr '\n' ' ')" = "prompts " ] || fail "R7q($_v): install wrote through a symlinked .pi ($(ls -A "$_o" | tr '\n' ' '))"
    [ "$(ls -A "$_o/prompts" | wc -l | tr -d ' ')" = "$_before" ] || fail "R7q($_v): install changed the outside prompts/"
    ok_inst - - --agents=pi --pr-loop=false "$_t"
    [ -d "$_o/prompts" ] || fail "R7q($_v): gate-off deleted the outside prompts/ THROUGH a symlinked .pi"
    [ "$(ls -A "$_o/prompts" | wc -l | tr -d ' ')" = "$_before" ] || fail "R7q($_v): gate-off changed the outside prompts/"
    ok_inst - - --agents=claude "$_t"
    [ -L "$_t/.pi" ] || fail "R7q($_v): the .pi symlink was removed on deselect"
    [ -d "$_o/prompts" ] || fail "R7q($_v): deselect deleted the outside prompts/ THROUGH a symlinked .pi"
    [ "$(ls -A "$_o/prompts" | wc -l | tr -d ' ')" = "$_before" ] || fail "R7q($_v): deselect changed the outside prompts/"
  done
  # (k) install -> user edit -> re-install drops the stale stamp, so the file is no longer owned (M18).
  _t="$(new_target r7k)"; ok_inst - - --agents=pi "$_t"
  printf 'user edit\n' >> "$_t/.pi/prompts/sdd-new.md"
  ok_inst - - --agents=pi "$_t"
  grep -q 'foreign or edited' "$OUT" || fail "R7k: no foreign-or-edited warning on re-install"
  [ ! -e "$_t/.harness/.pi-prompts/sdd-new.md" ] || fail "R7k: a stale stamp outlived the user's edit"
  git -C "$_t" init -q 2>/dev/null
  _p="$(cd "$_t" && sh .harness/tools/harness-owned-paths.sh all .harness)"
  printf '%s\n' "$_p" | grep -qxF ':(literal).pi/prompts/sdd-new.md' && fail "R10k: owned-paths claims the user-edited sdd-new.md"
  printf '%s\n' "$_p" | grep -qxF ':(literal).pi/prompts/sdd-next.md' || fail "R10k: owned-paths lost the untouched sdd-next.md"
  # (l) R10: with the ledger INTACT, a .agents without pi yields no .pi/ pathspec (M13).
  _t="$(new_target r10l)"; ok_inst - - --agents=pi "$_t"
  git -C "$_t" init -q 2>/dev/null
  _p="$(cd "$_t" && sh .harness/tools/harness-owned-paths.sh all .harness)"
  printf '%s\n' "$_p" | grep -qxF ':(literal).pi/prompts/sdd-next.md' || fail "R10l: precondition — pi templates not claimed"
  # `codex` (not `claude`): a list with no skill claimant returns earlier, which would mask the pi guard.
  printf 'codex\n' > "$_t/.harness/.agents"
  [ -f "$_t/.harness/.pi-prompts/sdd-next.md" ] || fail "R10l: precondition — the ledger is not intact"
  _p="$(cd "$_t" && sh .harness/tools/harness-owned-paths.sh all .harness)"
  printf '%s\n' "$_p" | grep -q '\.pi/' && fail "R10l: a .pi/ pathspec was emitted although .agents lacks pi"
  pass "symlinked prompts/ledger are refused on removal paths; a stale stamp is dropped; .agents gates .pi/ ownership (R7, R10)"
}

# ── R8 ─────────────────────────────────────────────────────────────────────────────────────
test_pi_host_detection() {
  _t="$(new_target r8a)"; ok_inst - PI_CODING_AGENT=true --agents=host "$_t"
  [ "$(agents_of "$_t")" = pi ] || fail "R8: PI_CODING_AGENT=true selected '$(agents_of "$_t")', expected pi"
  _t="$(new_target r8b)"
  env -i PATH="$SANDBOX_PATH" HOME="$T/home" CODEX_HOME="$T/ch" PI_CODING_AGENT=true CLAUDECODE=1 \
    sh "$INST" --agents=host "$_t" </dev/null >"$OUT" 2>&1 || fail "R8: nested markers install failed"
  [ "$(agents_of "$_t")" = claude ] || fail "R8: two markers were not undetected (got '$(agents_of "$_t")')"
  _t="$(new_target r8c)"; ok_inst - AI_AGENT=pi --agents=host "$_t"
  [ "$(agents_of "$_t")" = claude ] || fail "R8: AI_AGENT=pi alone selected '$(agents_of "$_t")'"
  _t="$(new_target r8d)"; ok_inst - PI_SESSION_ID=abc --agents=host "$_t"
  [ "$(agents_of "$_t")" = claude ] || fail "R8: PI_SESSION_ID alone selected '$(agents_of "$_t")'"
  _t="$(new_target r8e)"; ok_inst - PI_CODING_AGENT= --agents=host "$_t"
  [ "$(agents_of "$_t")" = claude ] || fail "R8: an empty PI_CODING_AGENT selected '$(agents_of "$_t")'"
  grep -q '^pi PI_CODING_AGENT$' "$INST" || fail "R8: the HOST_MARKERS row is missing"
  pass "PI_CODING_AGENT alone selects pi; nested, generic or empty markers do not (R8)"
}

# ── R9 ─────────────────────────────────────────────────────────────────────────────────────
test_pi_worker_roster() {
  _b="$T/bin-pi"; rm -rf "$_b"; mkdir -p "$_b"
  printf '#!/bin/sh\nexit 3\n' > "$_b/pi"; chmod +x "$_b/pi"
  _rq() { python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
ws=d.get("workers",d) if isinstance(d,dict) else d
e=[w for w in ws if w.get("key")=="pi"]
if not e: print("none"); sys.exit()
w=e[0]; caps=w.get("capabilities",[])
print(w.get("command"), " ".join(sorted(caps)))' "$1"; }
  _t="$(new_target r9a)"; ok_inst "$_b" - --agents=claude "$_t"
  set_roster() { sed "s|^  roster: .*|  roster: true|" "$1/.harness/harness.config.yaml" > "$1/c.t" && mv "$1/c.t" "$1/.harness/harness.config.yaml"; }
  set_roster "$_t"; ok_inst "$_b" - --agents=claude "$_t"
  _got="$(_rq "$_t/.harness/workers.json")"
  case "$_got" in "pi "*) : ;; *) fail "R9: no pi roster entry with command pi (got '$_got')" ;; esac
  case "$_got" in *non-interactive*) : ;; *) fail "R9: pi entry lacks non-interactive ($_got)" ;; esac
  case "$_got" in *host-detectable*) : ;; *) fail "R9: pi entry lacks host-detectable ($_got)" ;; esac
  case "$_got" in *harness-selected*) fail "R9: pi is not selected yet carries harness-selected ($_got)" ;; esac
  ok_inst "$_b" - --agents=claude,pi "$_t"
  _got="$(_rq "$_t/.harness/workers.json")"
  case "$_got" in *harness-selected*) : ;; *) fail "R9: pi selected but entry lacks harness-selected ($_got)" ;; esac
  # No pi on PATH: no pi entry.
  _t="$(new_target r9b)"; ok_inst - - --agents=claude "$_t"; set_roster "$_t"; ok_inst - - --agents=claude "$_t"
  [ "$(_rq "$_t/.harness/workers.json")" = none ] || fail "R9: a pi entry exists although pi is not on PATH"
  pass "the roster lists pi with its capabilities only when a pi executable is on PATH (R9)"
}

# ── R10 ────────────────────────────────────────────────────────────────────────────────────
test_pi_owned_paths() {
  _t="$(new_target r10)"; ok_inst - - --agents=pi --pr-loop=false "$_t"
  git -C "$_t" init -q 2>/dev/null
  _p="$(cd "$_t" && sh .harness/tools/harness-owned-paths.sh all .harness)"
  for _c in $STD; do
    printf '%s\n' "$_p" | grep -qxF ":(literal).pi/prompts/$_c.md" || fail "R10: no pathspec for $_c template"
    printf '%s\n' "$_p" | grep -qxF ":(literal).agents/skills/$_c/SKILL.md" || fail "R10: no pathspec for the $_c unit"
  done
  [ "$(printf '%s\n' "$_p" | grep -c '^:(literal)\.pi/prompts/')" = 7 ] || fail "R10: wrong template pathspec count"
  # Deselect pi: no .pi/ pathspec.
  ok_inst - - --agents=claude "$_t"
  _p="$(cd "$_t" && sh .harness/tools/harness-owned-paths.sh all .harness)"
  printf '%s\n' "$_p" | grep -q '\.pi/' && fail "R10: a .pi/ pathspec outlived pi"
  # Symlinked ledger: nothing claimed.
  _t="$(new_target r10s)"; ok_inst - - --agents=pi "$_t"
  mv "$_t/.harness/.pi-prompts" "$T/ledger-r10s"; ln -s "$T/ledger-r10s" "$_t/.harness/.pi-prompts"
  _p="$(cd "$_t" && sh .harness/tools/harness-owned-paths.sh all .harness)"
  # E35-F02: the agents ledger is a SECOND, independent ledger, so only the prompts claim is
  # asserted absent here (the agents ledger in this target is legitimately real).
  printf '%s\n' "$_p" | grep -q '\.pi/prompts/' && fail "R10: a symlinked ledger was trusted"
  # A stamp survives but the live leaf was replaced by a DIRECTORY: it is never claimed (round 3).
  _t="$(new_target r10d)"; ok_inst - - --agents=pi "$_t"
  git -C "$_t" init -q 2>/dev/null
  rm -f "$_t/.pi/prompts/sdd-next.md"; mkdir "$_t/.pi/prompts/sdd-next.md"; : > "$_t/.pi/prompts/sdd-next.md/notes.txt"
  [ -f "$_t/.harness/.pi-prompts/sdd-next.md" ] || fail "R10d: precondition — the stamp did not survive"
  _p="$(cd "$_t" && sh .harness/tools/harness-owned-paths.sh all .harness)"
  printf '%s\n' "$_p" | grep -qxF ':(literal).pi/prompts/sdd-next.md' && fail "R10d: a directory leaf was claimed as harness-owned"
  printf '%s\n' "$_p" | grep -qxF ':(literal).pi/prompts/sdd-new.md' || fail "R10d: the sibling template lost its claim"
  # ./.harness/init.sh passes once the install is committed.
  _t="$(new_target r10i)"; ok_inst - - --agents=pi "$_t"
  (cd "$_t" && git init -q && git config user.email t@example.com && git config user.name t \
    && git add -A && git commit -q -m base) >/dev/null 2>&1
  (cd "$_t" && env -i PATH="$SANDBOX_PATH" HOME="$T/home" ./.harness/init.sh) >"$OUT" 2>&1 \
    || { cat "$OUT" >&2; fail "R10: ./.harness/init.sh failed in a committed pi target"; }
  pass "harness-owned-paths reports pi templates only while pi is listed and the ledger is trustworthy (R10)"
}

# ── R11 ────────────────────────────────────────────────────────────────────────────────────
test_escalation_arming_skips_pi() {
  _cfg() {
    sed -e 's|^  builder: .*|  builder: standard|' -e 's|^  builder-heavy: .*|  builder-heavy: reasoning|' \
      "$1/.harness/harness.config.yaml" > "$1/c.t" && mv "$1/c.t" "$1/.harness/harness.config.yaml"
    grep -q '^  pin.claude.reasoning:' "$1/.harness/harness.config.yaml" \
      || awk '{print} /^models:/{print "  pin.claude.reasoning: opus"}' "$1/.harness/harness.config.yaml" > "$1/c.t" \
      && mv "$1/c.t" "$1/.harness/harness.config.yaml"
  }
  _a="$(new_target r11a)"; ok_inst - - --agents=claude "$_a"; _cfg "$_a"; ok_inst - - --agents=claude "$_a"
  _b="$(new_target r11b)"; ok_inst - - --agents=claude,pi "$_b"; _cfg "$_b"; ok_inst - - --agents=claude,pi "$_b"
  [ -f "$_a/.harness/.escalation-arming" ] || fail "R11: the claude-only control wrote no arming file"
  [ -f "$_b/.harness/.escalation-arming" ] || fail "R11: claude,pi wrote no arming file"
  grep -q '^pi=' "$_b/.harness/.escalation-arming" && fail "R11: the arming file carries a pi= line"
  [ "$(sed -n 1p "$_a/.harness/.escalation-arming")" = "$(sed -n 1p "$_b/.harness/.escalation-arming")" ] \
    || fail "R11: pi changed the verdict (claude-only '$(sed -n 1p "$_a/.harness/.escalation-arming")' vs claude,pi '$(sed -n 1p "$_b/.harness/.escalation-arming")')"
  cmp -s "$_a/.harness/.escalation-arming" "$_b/.harness/.escalation-arming" \
    || fail "R11: the arming file differs between claude and claude,pi"
  # pi alone: no detail line either.
  _c="$(new_target r11c)"; ok_inst - - --agents=pi "$_c"
  [ ! -f "$_c/.harness/.escalation-arming" ] || ! grep -q '^pi=' "$_c/.harness/.escalation-arming" \
    || fail "R11: a pi-only arming file carries pi="
  pass "pi is excluded from the escalation-arming file and its verdict (R11)"
}

# ── R12 ────────────────────────────────────────────────────────────────────────────────────
test_pi_operator_text() {
  _t="$(new_target r12a)"
  inst - - --agents=gemini "$_t" && fail "R12: --agents=gemini was accepted"
  grep -qw 'pi' "$OUT" || fail "R12: the gemini retirement error does not name pi"
  # recorded gemini + claude re-run warns with a replacement list naming pi.
  _t="$(new_target r12b)"; ok_inst - - --agents=claude "$_t"
  printf 'gemini\nclaude\n' > "$_t/.harness/.agents"
  ok_inst - - "$_t"
  grep 'retiring recorded agent' "$OUT" | grep -qw 'pi' || fail "R12: the recorded-gemini warning does not name pi"
  # unknown recorded key's die names --agents=pi
  printf 'bogus\n' > "$_t/.harness/.agents"
  inst - - "$_t" && fail "R12: an unknown recorded key was accepted"
  grep -qF -- '--agents=pi' "$OUT" || fail "R12: the unknown-recorded die does not name --agents=pi"
  printf 'gemini\n' > "$_t/.harness/.agents"
  inst - - "$_t" && fail "R12: a gemini-only record was accepted"
  grep -qF -- '--agents=pi' "$OUT" || fail "R12: the no-supported-agent die does not name --agents=pi"
  # manifest line
  _t="$(new_target r12c)"; ok_inst - - --agents=pi "$_t"
  grep -qF 'claude|codex|opencode|antigravity|pi' "$_t/.harness/manifest.txt" || fail "R12: manifest agent line lacks pi"
  grep -qF '.pi/prompts/sdd-*.md' "$_t/.harness/manifest.txt" || fail "R12: manifest does not list .pi/prompts"
  grep -qF '.harness/.pi-prompts/' "$_t/.harness/manifest.txt" || fail "R12: manifest does not list the ledger"
  # banners (fresh installs)
  _t="$(new_target r12d)"; ok_inst - - --agents=pi "$_t"
  grep -qF 'pi: open the repo, trust the project' "$OUT" || fail "R12: pi-only banner lacks the trust step"
  grep -qF 'then /reload (or restart pi)' "$OUT" || fail "R12: pi-only banner lacks the /reload step"
  grep -qF 'pi: run /sdd-next' "$OUT" || fail "R12: pi-only banner lacks /sdd-next"
  _t="$(new_target r12e)"; ok_inst - - --agents=claude,pi "$_t"
  grep -qF '(Claude Code/pi)' "$OUT" || fail "R12: claude,pi banner lacks (Claude Code/pi)"
  grep -qF 'pi: trust the project first' "$OUT" || fail "R12: claude,pi banner lacks the trust line"
  grep -qF 'then /reload (or restart pi)' "$OUT" || fail "R12: claude,pi banner lacks the /reload step"
  # Antigravity single-host banner is unchanged.
  _t="$(new_target r12f)"; ok_inst - - --agents=antigravity "$_t"
  grep -qF '3. Antigravity: open the repo and run /sdd-plan' "$OUT" || fail "R12: Antigravity banner changed"
  # docs
  for _d in README.md AGENTS.md docs/HARNESS.md docs/INSTALL.md docs/WORKFLOW.md; do
    grep -qw 'pi' "$SRC/$_d" || fail "R12: $_d does not name pi"
    grep -qE '/trust|--approve|`-a`' "$SRC/$_d" || fail "R12: $_d lacks the pi trust prerequisite"
    grep -q 'pi-dispatch.sh' "$SRC/$_d" || fail "R12: $_d lacks the pi role-isolation note (pi-dispatch.sh)"
    grep -q 'arrives with E35-F02' "$SRC/$_d" && fail "R12: $_d still says role isolation arrives with E35-F02"
  done
  # An UPGRADE that adds pi (or rewrites its templates) must also tell an open session to
  # /reload — the fresh-install advice block never runs on upgrades (Codex #4265595907).
  _t="$(new_target r12u)"; ok_inst - - --agents=claude "$_t"
  ok_inst - - --agents=claude "$_t"
  grep -q 'upgrade complete' "$OUT" || fail "R12u: precondition — the re-run was not an upgrade"
  grep -q 'pi: run /reload' "$OUT" && fail "R12u: a pi reload notice printed on an upgrade without pi"
  ok_inst - - --agents=claude,pi "$_t"
  grep -q 'upgrade complete' "$OUT" || fail "R12u: precondition — adding pi was not an upgrade"
  grep -q 'pi: run /reload (or restart pi)' "$OUT" || fail "R12u: an upgrade that added pi gave no /reload notice"
  pass "operator-facing text and the five docs name pi, the trust prerequisite and pi role isolation (R12)"
}

test_pi_is_selectable
test_no_pi_glue_when_unselected
test_pi_claims_shared_units
test_pi_reclaim_only_when_last_claimant
test_skill_adapter_names_pi
test_pi_prompt_templates_shape_and_set
test_pi_prompt_ownership
test_pi_symlink_and_stamp_guards
test_pi_host_detection
test_pi_worker_roster
test_pi_owned_paths
test_escalation_arming_skips_pi
test_pi_operator_text
echo "All pi front-end tests passed."
