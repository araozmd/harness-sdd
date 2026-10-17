#!/bin/sh
# test_pi_agents.sh — E35-F02, pi role sub-agents (.pi/agents + tools/pi-dispatch.sh, --self).
#
# Covers R1–R10 and R12 of specs/epics/E35-pi-first-class/F02-pi-role-subagents/ (R11 lives
# in test_self_drift.sh).
#
# HERMETIC. This machine may have a real `pi` on PATH and may leak PI_* variables into the
# test shell. Every installer and dispatcher run therefore goes through `env -i` with only a
# sandbox PATH (the real PATH minus every directory that holds a `pi` executable), an isolated
# HOME and CODEX_HOME. The only `pi` that ever runs is the STUB written below, which records
# its argv and exits `$STUB_RC`. No case runs the real pi, a model or the network.
#
# THE SHAPE MATRIX (progress/lessons.md 2026-10-14). `test_pi_agent_shape_matrix` is driven
# by ONE table: a row per (component, shape, operation) of the plan's "Filesystem shape
# matrix". Each row is run by the `--cell` re-entry of THIS file (cells are independent
# targets, run in parallel via xargs). A coverage guard fails when any expected
# (component, shape) is missing for any of I, G+, D, G-.
#
# Zero dependencies beyond python3 (argv decoding), git (R9) and cp -a.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SELF="$SRC/tests/test_pi_agents.sh"
INST="$SRC/harness-install.sh"
CELLMODE=0; CELLROW=""
if [ "${1:-}" = --cell ]; then
  CELLMODE=1; CELLROW="$2"; T="$PIA_T"
else
  T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-pia)"
  trap 'rm -rf "$T"' EXIT
fi

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
  && fail "sandbox setup: 'pi' still resolves on the sandbox PATH — the 127 and stub cases would test this machine"
for _c in awk sed grep sort tr cp mv rm mkdir cat cmp mktemp find python3 git readlink cksum ln xargs; do
  env -i PATH="$SANDBOX_PATH" sh -c "command -v $_c" >/dev/null 2>&1 \
    || fail "sandbox setup: '$_c' is missing from the sandbox PATH"
done

mkdir -p "$T/home" "$T/ch"
OUT="$T/out"

# inst <installer-path|-> <path-prefix|-> <installer args…> — run an installer hermetically,
# capturing stdout+stderr in $OUT. "-" as the first argument means the real installer.
inst_with() {
  _iw_inst="$1"; _iw_bin="$2"; shift 2
  [ "$_iw_inst" != "-" ] || _iw_inst="$INST"
  _iw_path="$SANDBOX_PATH"
  if [ "$_iw_bin" != "-" ]; then _iw_path="$_iw_bin:$SANDBOX_PATH"; fi
  _iw_rc=0
  env -i PATH="$_iw_path" HOME="$T/home" CODEX_HOME="$T/ch" \
    sh "$_iw_inst" "$@" </dev/null >"$OUT" 2>&1 || _iw_rc=$?
  return "$_iw_rc"
}
inst() { inst_with - - "$@"; }
ok_inst() { inst "$@" || { cat "$OUT" >&2; fail "setup: installer exited non-zero ($*)"; }; }
new_target() { _nt="$T/$1"; rm -rf "$_nt"; mkdir -p "$_nt"; printf '%s\n' "$_nt"; }
set_pr_loop() { sed "s|^  enabled: .*|  enabled: $2|" "$1/.harness/harness.config.yaml" > "$1/.harness/c.t" \
  && mv "$1/.harness/c.t" "$1/.harness/harness.config.yaml"; }

# snap <path> — a one-line identity for ANY node: link target, content cksum, dir listing.
snap() {
  if [ -L "$1" ]; then printf 'L %s\n' "$(readlink "$1")"
  elif [ -f "$1" ]; then printf 'F %s\n' "$(cksum < "$1")"
  elif [ -d "$1" ]; then printf 'D %s\n' "$(ls -A "$1" | sort | tr '\n' ' ')"
  elif [ -e "$1" ]; then echo X
  else echo absent; fi
}
# tree_snap <dir> — every entry and every file's cksum (a victim directory's full identity).
tree_snap() {
  [ -d "$1" ] || { echo absent; return 0; }
  ( cd "$1" && find . | sort && find . -type f | sort | while IFS= read -r _f; do cksum "$_f"; done )
}

ROLES8="orchestrator architect builder builder-heavy reviewer scout doc-critic pr-fixer"
ROLES7="orchestrator architect builder builder-heavy reviewer scout doc-critic"

# The plan's tool table, written out independently of the installer: role|Claude|pi|nested.
ref_table() { cat <<'EOF'
orchestrator|Read, Bash, Edit, Grep, Glob, Task|read, bash, edit, grep, find, ls|yes
architect|Read, Write, Edit, Grep, Glob, Bash, Task|read, bash, edit, write, grep, find, ls|yes
builder|Read, Write, Edit, Bash, Grep, Glob|read, bash, edit, write, grep, find, ls|no
builder-heavy|Read, Write, Edit, Bash, Grep, Glob|read, bash, edit, write, grep, find, ls|no
reviewer|Read, Bash, Grep, Glob, Edit|read, bash, edit, grep, find, ls|no
scout|Read, Grep, Glob, Bash|read, bash, grep, find, ls|no
doc-critic|Read, Grep, Glob, Write|read, write, grep, find, ls|no
pr-fixer|Read, Edit, Bash, Grep, Glob|read, bash, edit, grep, find, ls|no
EOF
}
# ref_pi <claude-list> — the suite's OWN translation, structured differently from pi_tools().
ref_pi() {
  _o=""
  for _p in read:Read bash:Bash edit:Edit write:Write grep:Grep find:Glob ls:Glob; do
    case ", $1," in *", ${_p##*:},"*) _o="${_o:+$_o, }${_p%%:*}" ;; esac
  done
  printf '%s' "$_o"
}
ref_col() { ref_table | awk -F'|' -v r="$1" -v c="$2" '$1==r {print $c; exit}'; }

# A mini source tree (the installer needs its body next to it): lets a test run a MUTATED
# copy of harness-install.sh without copying scratchpad/ and specs/.
mini_src() {
  _ms="$1"; mkdir -p "$_ms/specs"
  for _e in agents AGENTS.md CHANGELOG.md CLAUDE.md docs harness.config.yaml harness-install.sh \
            init.sh store tools VERSION README.md umbrella.gitignore.example umbrella.manifest.example.yaml; do
    cp -R "$SRC/$_e" "$_ms/"
  done
  cp -R "$SRC/specs/_templates" "$SRC/specs/adr" "$SRC/specs/glossary.md" "$SRC/specs/product.md" "$_ms/specs/"
}

# ── the stub `pi` ────────────────────────────────────────────────────────────────────────
STUBBIN="$T/stubbin"; mkdir -p "$STUBBIN"
cat > "$STUBBIN/pi" <<'EOF'
#!/bin/sh
: "${STUB_LOG:?}"
printf '%s\0' "$@" > "$STUB_LOG/argv"
pwd -P > "$STUB_LOG/cwd"
prev=""
for a in "$@"; do
  if [ "$prev" = --append-system-prompt ]; then cp "$a" "$STUB_LOG/appended"; fi
  prev="$a"
done
printf 'STUB-STDOUT'
exit "${STUB_RC:-0}"
EOF
chmod +x "$STUBBIN/pi"
# argv_n <logdir> — element count; argv_i <logdir> <i> — element i, raw bytes.
argv_n() { python3 -I -c 'import sys;a=open(sys.argv[1],"rb").read().split(b"\0");a.pop();print(len(a))' "$1/argv"; }
argv_i() { python3 -I -c 'import sys;a=open(sys.argv[1],"rb").read().split(b"\0");sys.stdout.buffer.write(a[int(sys.argv[2])])' "$1/argv" "$2"; }

# ── shared fixtures: a pristine pi-only install per pr_loop state ─────────────────────────
mk_bases() {
  [ -d "$T/base-true" ] && return 0
  mkdir -p "$T/b1" "$T/b2"
  ok_inst --agents=pi --pr-loop=true "$T/b1"; mv "$T/b1" "$T/base-true"
  ok_inst --agents=pi --pr-loop=false "$T/b2"; mv "$T/b2" "$T/base-false"
  [ "$(ls "$FRESH" | wc -l | tr -d ' ')" = 8 ] || fail "setup: base-true holds $(ls "$FRESH" | wc -l) role files, expected 8"
  [ "$(ls "$T/base-false/.pi/agents" | wc -l | tr -d ' ')" = 7 ] || fail "setup: base-false does not hold 7 role files"
}
FRESH="$T/base-true/.pi/agents"

# mutate <file> <old> <new> — replace EXACTLY one occurrence (a no-op mutation is a setup failure).
mutate() {
  python3 -I -c 'import sys
p,o,n=sys.argv[1:4]
s=open(p).read()
if s.count(o)!=1: sys.exit("mutate: %d occurrences of %r"%(s.count(o),o))
open(p,"w").write(s.replace(o,n))' "$1" "$2" "$3" || fail "setup: mutation did not apply ($2)"
}

# ── R1 ─────────────────────────────────────────────────────────────────────────────────────
test_pi_agent_files_set_and_frontmatter() {
  mk_bases
  # the descriptions, read from the installer's own role table (ag_personas / PR_FIXER_DESC)
  _desc() {
    if [ "$1" = pr-fixer ]; then sed -n 's/^PR_FIXER_DESC="\(.*\)"$/\1/p' "$INST" | sed -n '1p'
    else sed -n '/^  ag_personas() {/,/^  }/p' "$INST" | awk -F'	' -v r="$1" 'NF==2 && $1==r {print $2; exit}'; fi
  }
  [ "$(ls "$T/base-true/.pi/agents" | tr '\n' ' ')" = "architect.md builder-heavy.md builder.md doc-critic.md orchestrator.md pr-fixer.md reviewer.md scout.md " ] \
    || fail "R1: --pr-loop=true role set is '$(ls "$T/base-true/.pi/agents" | tr '\n' ' ')'"
  [ "$(ls "$T/base-false/.pi/agents" | tr '\n' ' ')" = "architect.md builder-heavy.md builder.md doc-critic.md orchestrator.md reviewer.md scout.md " ] \
    || fail "R1: --pr-loop=false role set is '$(ls "$T/base-false/.pi/agents" | tr '\n' ' ')'"
  for _r in $ROLES8; do
    _d="$(_desc "$_r")"; [ -n "$_d" ] || fail "R1: setup — no description found for $_r"
    _exp="---
name: $_r
description: $_d
tools: $(ref_col "$_r" 3)
systemPromptMode: append
inheritProjectContext: true
inheritSkills: false"
    if [ "$(ref_col "$_r" 4)" = yes ]; then _exp="$_exp
allowNestedSubagents: true"; fi
    _exp="$_exp
---"
    _got="$(awk 'NR==1{print; next} {print} /^---$/{exit}' "$FRESH/$_r.md")"
    [ "$_got" = "$_exp" ] || fail "R1: $_r frontmatter differs:
--- expected
$_exp
--- got
$_got"
    if grep -qE '^(model|thinking):' "$FRESH/$_r.md"; then fail "R1: $_r carries a model:/thinking: line in an all-inherit install"; fi
  done
  # a re-install is byte-idempotent (role files AND stamps)
  _t="$(new_target r1i)"; cp -a "$T/base-true/." "$_t/"
  _b="$(cd "$_t" && cksum .pi/agents/*.md .harness/.pi-agents/*.md)"
  ok_inst --agents=pi --pr-loop=true "$_t"
  [ "$(cd "$_t" && cksum .pi/agents/*.md .harness/.pi-agents/*.md)" = "$_b" ] || fail "R1: a re-install changed the role files or stamps"
  for _r in $ROLES8; do cmp -s "$_t/.pi/agents/$_r.md" "$_t/.harness/.pi-agents/$_r.md" || fail "R1: stamp != live for $_r"; done
  pass "pi role files: exact set, exact frontmatter, no model/thinking in the all-inherit install, idempotent (R1)"
}

# ── R2 ─────────────────────────────────────────────────────────────────────────────────────
test_no_pi_agents_when_unselected() {
  _t="$(new_target r2)"
  ok_inst --agents=claude,codex,opencode "$_t"
  ok_inst --agents=claude,codex,opencode "$_t"
  [ ! -e "$_t/.pi/agents" ] || fail "R2: an unselected pi created .pi/agents"
  [ ! -e "$_t/.harness/.pi-agents" ] || fail "R2: an unselected pi created .harness/.pi-agents"
  [ -x "$_t/.harness/tools/pi-dispatch.sh" ] || fail "R2: the dispatcher is not installed executable with the body"
  pass "no .pi/agents path and no agents ledger when pi was never selected (R2)"
}

# ── R3 ─────────────────────────────────────────────────────────────────────────────────────
test_tool_translation_table() {
  mk_bases
  # (a) table-driven, in one claude,pi install: Claude shims AND pi files against the plan table
  _t="$(new_target r3a)"; ok_inst --agents=claude,pi --pr-loop=true "$_t"
  for _r in $ROLES8; do
    _c="$(ref_col "$_r" 2)"; _p="$(ref_col "$_r" 3)"
    [ "$(sed -n 's/^tools: //p' "$_t/.claude/agents/$_r.md" | sed -n '1p')" = "$_c" ] || fail "R3a: .claude/agents/$_r.md tools: is not '$_c'"
    [ "$(sed -n 's/^tools: //p' "$_t/.pi/agents/$_r.md" | sed -n '1p')" = "$_p" ] || fail "R3a: .pi/agents/$_r.md tools: is not '$_p'"
    [ "$(ref_pi "$_c")" = "$_p" ] || fail "R3a: setup — the suite's table columns for $_r are not a translation of each other"
  done
  # (b) dedup and order, via a copied installer whose scout row is rewritten
  _m="$T/r3b-src"; mini_src "$_m"
  mutate "$_m/harness-install.sh" 'scout)         printf '"'"'%s'"'"' "Read, Grep, Glob, Bash" ;;' 'scout)         printf '"'"'%s'"'"' "Glob, Glob, Read" ;;'
  _t="$(new_target r3b)"; inst_with "$_m/harness-install.sh" - --agents=pi --pr-loop=true "$_t" || { cat "$OUT" >&2; fail "R3b: mutated installer failed"; }
  [ "$(sed -n 's/^tools: //p' "$_t/.pi/agents/scout.md")" = "read, find, ls" ] \
    || fail "R3b: 'Glob, Glob, Read' did not translate to 'read, find, ls' (got '$(sed -n 's/^tools: //p' "$_t/.pi/agents/scout.md")')"
  # (c) an unknown token fails the install, names the token, and writes no role file
  _m="$T/r3c-src"; mini_src "$_m"
  mutate "$_m/harness-install.sh" 'builder|builder-heavy) printf '"'"'%s'"'"' "Read, Write, Edit, Bash, Grep, Glob" ;;' 'builder|builder-heavy) printf '"'"'%s'"'"' "Read, Write, Edit, Bash, Grep, Glob, WebFetch" ;;'
  _t="$(new_target r3c)"
  if inst_with "$_m/harness-install.sh" - --agents=pi --pr-loop=true "$_t"; then fail "R3c: an unknown Claude tool did not fail the install"; fi
  grep -q 'WebFetch' "$OUT" || fail "R3c: the failure does not name the token"
  [ ! -e "$_t/.pi/agents" ] || fail "R3c: a role file directory was written before the preflight failed"
  [ ! -e "$_t/.harness/.pi-agents" ] || fail "R3c: a stamp ledger was written before the preflight failed"
  # (c2) a role with no row in the Claude table fails the install the same way (preflight)
  _m="$T/r3c2-src"; mini_src "$_m"
  mutate "$_m/harness-install.sh" 'doc-critic	Advisory doc review pass' 'ghost-role	A role with no tool row.
doc-critic	Advisory doc review pass'
  _t="$(new_target r3c2)"
  if inst_with "$_m/harness-install.sh" - --agents=pi --pr-loop=true "$_t"; then fail "R3c2: a role without a Claude tool row did not fail the install"; fi
  grep -q 'ghost-role' "$OUT" || fail "R3c2: the failure does not name the role"
  [ ! -e "$_t/.pi/agents" ] || fail "R3c2: a role file directory was written before the preflight failed"
  # (d) exactly one definition each; no literal tool list left at an emit_agent call
  [ "$(grep -c '^  claude_role_tools() {' "$INST")" = 1 ] || fail "R3d: claude_role_tools() is not defined exactly once"
  [ "$(grep -c '^  pi_tools() {' "$INST")" = 1 ] || fail "R3d: pi_tools() is not defined exactly once"
  if grep -qE 'emit_agent [a-z-]+ "Read' "$INST"; then fail "R3d: an emit_agent call still carries a literal tool list"; fi
  # (e) the read-only scout gets neither edit nor write
  _s="$(sed -n 's/^tools: //p' "$FRESH/scout.md")"
  case ", $_s," in *", edit,"*|*", write,"*) fail "R3e: scout's pi tools include edit or write: $_s" ;; esac
  pass "one tool table, one translation: order, dedup, unknown token, read-only scout (R3)"
}

# ── R4 ─────────────────────────────────────────────────────────────────────────────────────
test_pi_agent_body_pointer() {
  mk_bases
  for _r in $ROLES8; do
    _f="$FRESH/$_r.md"
    _body="$(awk 'c>=2{print} /^---$/{c++}' "$_f")"
    printf '%s\n' "$_body" | grep -qF "Read \`.harness/agents/$_r.md\` with the read tool" || fail "R4: $_r body lacks the pointer to .harness/agents/$_r.md"
    printf '%s\n' "$_body" | grep -qF './.harness/init.sh' || fail "R4: $_r body lacks the init.sh requirement"
    printf '%s\n' "$_body" | grep -qF 'halt on a non-zero exit' || fail "R4: $_r body lacks the halt-on-failure rule"
    printf '%s\n' "$_body" | grep -qF '.harness/progress/' || fail "R4: $_r body lacks the progress/ hand-off rule"
    [ "$(grep -c '^---$' "$_f")" = 2 ] || fail "R4: $_r has a stray '---' line (frontmatter delimiter in the body)"
    case "$_body" in *'$'*) fail "R4: $_r body contains a '\$'" ;; esac
    if [ "$(ref_col "$_r" 4)" = yes ]; then
      { printf '%s\n' "$_body" | grep -qF '`subagent` tool' && printf '%s\n' "$_body" | grep -qF '.harness/tools/pi-dispatch.sh <role> <task-file>'; } \
        || fail "R4: nested role $_r lacks the delegation paragraph"
    else
      if printf '%s\n' "$_body" | grep -qF 'subagent'; then fail "R4: non-nested role $_r carries the delegation paragraph"; fi
      if printf '%s\n' "$_body" | grep -qF 'pi-dispatch.sh'; then fail "R4: non-nested role $_r names the dispatcher"; fi
    fi
  done
  pass "role bodies: pointer, init, hand-off, no delimiter, no \$, delegation only on nested roles (R4)"
}

# ── the shape matrix (R5, R6) ─────────────────────────────────────────────────────────────
# ONE table, one row per cell of the plan's "Filesystem shape matrix":
#   component shape op outcome warnings warning-kind
# component  L1 .pi · L2 .pi/agents · L3 .pi/agents/<role>.md · S1 .harness/.pi-agents ·
#            S2 .harness/.pi-agents/<role>.md
# shape      A absent · F file (file-where-dir) · Dd directory (dir-where-file) · Sv symlink to a
#            node holding a byte-fresh victim · Sve (L1 only) symlink to a dir holding an EMPTY
#            agents/ (the prune victim) · Sx dangling symlink · Fs/Ff/Fe (L3) stamped / fresh /
#            edited regular file
# op         I install · G+ pr_loop false→true · D deselect pi · G- pr_loop true→false
# outcome    W written · RM removed · KD left, stamp dropped · KD0 nothing there, stamp dropped ·
#            KK leaf, stamp and victim all left
# warnings   the exact number of `.pi/agents/…` / `.harness/.pi-agents/…` warning lines in the
#            run (ALL = one per role the operation processes)
# XP         PRECEDENCE cells (shape = two planted shapes joined by `_`): both the live path and the
#            stamp path are hostile, so the stamp-unsafe check must win (kind `stamp`, KK).
# kind       dest (… destination component) · stamp (… stamp component) · foreign (foreign or
#            edited) · nostamp (no matching stamp) · - (none)
MATRIX_ROWS() { cat <<'EOF'
L1 A I W 0 -
L1 A G+ W 0 -
L1 A D RM 0 -
L1 A G- RM 0 -
L1 F I KD ALL dest
L1 F G+ KD ALL dest
L1 F D KD0 0 -
L1 F G- KD0 0 -
L1 Sv I KD ALL dest
L1 Sv G+ KD ALL dest
L1 Sv D KD ALL dest
L1 Sv G- KD 1 dest
L1 Sve I KD ALL dest
L1 Sve G+ KD ALL dest
L1 Sve D KD0 0 -
L1 Sve G- KD0 0 -
L1 Sx I KD ALL dest
L1 Sx G+ KD ALL dest
L1 Sx D KD0 0 -
L1 Sx G- KD0 0 -
L2 A I W 0 -
L2 A G+ W 0 -
L2 A D KD0 0 -
L2 A G- KD0 0 -
L2 F I KD ALL dest
L2 F G+ KD ALL dest
L2 F D KD0 0 -
L2 F G- KD0 0 -
L2 Sv I KD ALL dest
L2 Sv G+ KD ALL dest
L2 Sv D KD ALL dest
L2 Sv G- KD 1 dest
L2 Sx I KD ALL dest
L2 Sx G+ KD ALL dest
L2 Sx D KD0 0 -
L2 Sx G- KD0 0 -
L3 A I W 0 -
L3 A G+ W 0 -
L3 A D KD0 0 -
L3 A G- KD0 0 -
L3 Fs I W 0 -
L3 Fs G+ W 0 -
L3 Fs D RM 0 -
L3 Fs G- RM 0 -
L3 Ff I W 0 -
L3 Ff G+ W 0 -
L3 Ff D RM 0 -
L3 Ff G- RM 0 -
L3 Fe I KD 1 foreign
L3 Fe G+ KD 1 foreign
L3 Fe D KD 1 nostamp
L3 Fe G- KD 1 nostamp
L3 Dd I KD 1 dest
L3 Dd G+ KD 1 dest
L3 Dd D KD 1 dest
L3 Dd G- KD 1 dest
L3 Sv I KD 1 dest
L3 Sv G+ KD 1 dest
L3 Sv D KD 1 dest
L3 Sv G- KD 1 dest
L3 Sx I KD 1 dest
L3 Sx G+ KD 1 dest
L3 Sx D KD 1 dest
L3 Sx G- KD 1 dest
S1 A I W 0 -
S1 A G+ W 0 -
S1 A D RM 0 -
S1 A G- RM 0 -
S1 F I KK ALL stamp
S1 F G+ KK ALL stamp
S1 F D KK ALL stamp
S1 F G- KK 1 stamp
S1 Sv I KK ALL stamp
S1 Sv G+ KK ALL stamp
S1 Sv D KK ALL stamp
S1 Sv G- KK 1 stamp
S1 Sx I KK ALL stamp
S1 Sx G+ KK ALL stamp
S1 Sx D KK ALL stamp
S1 Sx G- KK 1 stamp
S2 Dd I KK 1 stamp
S2 Dd G+ KK 1 stamp
S2 Dd D KK 1 stamp
S2 Dd G- KK 1 stamp
S2 Sv I KK 1 stamp
S2 Sv G+ KK 1 stamp
S2 Sv D KK 1 stamp
S2 Sv G- KK 1 stamp
S2 Sx I KK 1 stamp
S2 Sx G+ KK 1 stamp
S2 Sx D KK 1 stamp
S2 Sx G- KK 1 stamp
XP L3Sv_S2Sv I KK 1 stamp
XP L3Sv_S2Sv G+ KK 1 stamp
XP L3Sv_S2Sv D KK 1 stamp
XP L3Sv_S2Sv G- KK 1 stamp
XP L3Dd_S2Dd I KK 1 stamp
XP L3Dd_S2Dd G+ KK 1 stamp
XP L3Dd_S2Dd D KK 1 stamp
XP L3Dd_S2Dd G- KK 1 stamp
XP L1F_S1Sv I KK ALL stamp
XP L1F_S1Sv G+ KK ALL stamp
XP L1F_S1Sv D KK ALL stamp
XP L1F_S1Sv G- KK 1 stamp
XP L2Sv_S1Sx I KK ALL stamp
XP L2Sv_S1Sx G+ KK ALL stamp
XP L2Sv_S1Sx D KK ALL stamp
XP L2Sv_S1Sx G- KK 1 stamp
EOF
}
# The expected coverage, written independently of the table above.
MATRIX_SHAPES="L1:A L1:F L1:Sv L1:Sve L1:Sx L2:A L2:F L2:Sv L2:Sx L3:A L3:Fs L3:Ff L3:Fe L3:Dd L3:Sv L3:Sx S1:A S1:F S1:Sv S1:Sx S2:Dd S2:Sv S2:Sx XP:L3Sv_S2Sv XP:L3Dd_S2Dd XP:L1F_S1Sv XP:L2Sv_S1Sx"
MATRIX_OPS="I G+ D G-"

# guard_ck — identity of the operator-owned neighbours no operation may touch.
guard_ck() {
  for _g in "$t/sentinel.txt" "$t/.pi/settings.json" "$t/.pi/prompts/keep.md"; do
    if [ -f "$_g" ]; then cksum < "$_g"; else echo none; fi
  done
}

cfail() { echo "FAIL: [cell $CELLID] $1" >&2; exit 1; }

# plant_cell <comp> <shape> — put one hostile shape in place (see the header for the vocabulary).
plant_cell() {
  _live="$t/.pi/agents/$X.md"; _stamp="$t/.harness/.pi-agents/$X.md"; _fresh="$FRESH/$X.md"
  case "$1:$2" in
    L1:A)   rm -rf "$t/.pi"; HN="$t/.pi" ;;
    L1:F)   rm -rf "$t/.pi"; echo foreign > "$t/.pi"; HN="$t/.pi" ;;
    L1:Sv)  rm -rf "$t/.pi"; mkdir -p "$V/agents"; cp "$FRESH"/*.md "$V/agents/"; ln -s "$V" "$t/.pi"; HN="$t/.pi" ;;
    L1:Sve) rm -rf "$t/.pi"; mkdir -p "$V/agents"; ln -s "$V" "$t/.pi"; HN="$t/.pi" ;;
    L1:Sx)  rm -rf "$t/.pi"; ln -s "$c/nowhere" "$t/.pi"; HN="$t/.pi" ;;
    L2:A)   rm -rf "$t/.pi/agents"; HN="$t/.pi/agents" ;;
    L2:F)   rm -rf "$t/.pi/agents"; echo foreign > "$t/.pi/agents"; HN="$t/.pi/agents" ;;
    L2:Sv)  rm -rf "$t/.pi/agents"; mkdir -p "$V"; cp "$FRESH"/*.md "$V/"; ln -s "$V" "$t/.pi/agents"; HN="$t/.pi/agents" ;;
    L2:Sx)  rm -rf "$t/.pi/agents"; ln -s "$c/nowhere" "$t/.pi/agents"; HN="$t/.pi/agents" ;;
    L3:*)
      mkdir -p "$t/.pi/agents" "$t/.harness/.pi-agents"; HN="$_live"
      case "$2" in
        A)  rm -f "$_live"; cp "$_fresh" "$_stamp" ;;
        Fs) printf 'OLD stamped bytes\n' > "$_live"; cp "$_live" "$_stamp" ;;
        Ff) cp "$_fresh" "$_live"; rm -f "$_stamp" ;;
        Fe) { cat "$_fresh"; echo "an operator edit"; } > "$_live"; cp "$_fresh" "$_stamp" ;;
        Dd) rm -f "$_live"; mkdir "$_live"; echo keep > "$_live/child"; cp "$_fresh" "$_stamp" ;;
        Sv) rm -f "$_live"; mkdir -p "$V"; cp "$_fresh" "$V/$X.md"; ln -s "$V/$X.md" "$_live"; cp "$_fresh" "$_stamp" ;;
        Sx) rm -f "$_live"; ln -s "$c/nowhere" "$_live"; cp "$_fresh" "$_stamp" ;;
      esac ;;
    S1:*)
      HN="$t/.harness/.pi-agents"; rm -rf "$HN"
      case "$2" in
        A)  : ;;
        F)  echo foreign > "$HN" ;;
        Sv) mkdir -p "$V"; cp "$FRESH"/*.md "$V/"; ln -s "$V" "$HN" ;;
        Sx) ln -s "$c/nowhere" "$HN" ;;
      esac ;;
    S2:*)
      mkdir -p "$t/.pi/agents" "$t/.harness/.pi-agents"; HN="$_stamp"
      if [ ! -e "$_live" ] && [ ! -L "$_live" ]; then cp "$_fresh" "$_live"; fi   # keep a hostile live node an XP cell planted
      rm -rf "$_stamp"
      case "$2" in
        Dd) mkdir "$_stamp"; echo keep > "$_stamp/child" ;;
        Sv) mkdir -p "$V/s"; cp "$_fresh" "$V/s/$X.md"; ln -s "$V/s/$X.md" "$_stamp" ;;
        Sx) ln -s "$c/nowhere" "$_stamp" ;;
      esac ;;
  esac
}

cell_check_role() { # <role> <outcome code>
  _r="$1"; _code="$2"
  _lv="$t/.pi/agents/$_r.md"; _sv="$t/.harness/.pi-agents/$_r.md"
  case "$_code" in
    W)
      { [ -f "$_lv" ] && [ ! -L "$_lv" ]; } || cfail "$_r: expected a written regular file at .pi/agents/$_r.md"
      cmp -s "$_lv" "$FRESH/$_r.md" || cfail "$_r: written bytes differ from the freshly generated role file"
      { [ -f "$_sv" ] && [ ! -L "$_sv" ] && cmp -s "$_sv" "$_lv"; } || cfail "$_r: stamp missing, not a regular file, or != the live bytes"
      ;;
    RM)
      { [ ! -e "$_lv" ] && [ ! -L "$_lv" ]; } || cfail "$_r: the role file survived a removal"
      { [ ! -e "$_sv" ] && [ ! -L "$_sv" ]; } || cfail "$_r: the stamp survived a removal"
      ;;
    KD|KD0)
      [ "$(snap "$_lv")" = "$(cat "$c/pre-live-$_r")" ] || cfail "$_r: the live node changed (was '$(cat "$c/pre-live-$_r")', now '$(snap "$_lv")')"
      { [ ! -e "$_sv" ] && [ ! -L "$_sv" ]; } || cfail "$_r: the stamp was not dropped"
      ;;
    KK)
      [ "$(snap "$_lv")" = "$(cat "$c/pre-live-$_r")" ] || cfail "$_r: the live node changed (was '$(cat "$c/pre-live-$_r")', now '$(snap "$_lv")')"
      [ "$(snap "$_sv")" = "$(cat "$c/pre-stamp-$_r")" ] || cfail "$_r: the unsafe stamp node changed"
      ;;
    *) cfail "bad outcome code '$_code'" ;;
  esac
}

# run_cell <comp> <shape> <op> <outcome> <warnings> <kind>
run_cell() {
  comp="$1"; shape="$2"; op="$3"; outcome="$4"; wcount="$5"; wkind="$6"
  CELLID="$comp:$shape:$op"
  c="$T/cells/$comp-$shape-$op"; rm -rf "$c"; mkdir -p "$c"
  t="$c/t"; V="$c/victim"; OUT="$c/out"
  case "$op" in G+) cp -a "$T/base-false" "$t" ;; *) cp -a "$T/base-true" "$t" ;; esac
  # G- is an installer re-run with pr_loop off: its §5f-pi pass INSTALLS the seven non-pr-fixer
  # roles (the I-row outcome for a directory/ledger shape) and §7b RECLAIMS pr-fixer alone (the
  # G- row). AR is the set the G- row governs; IR the install-processed set of that run.
  leaf=0; case "$comp:$shape" in L3:*|S2:*|XP:L3*) leaf=1 ;; esac
  IR=""; ICODE=""; ICOUNT=0; IKIND="-"
  case "$op" in
    G-) AR="pr-fixer"
        if [ "$leaf" = 0 ]; then
          IR="$ROLES7"
          set -- $(MATRIX_ROWS | awk -v c="$comp" -v s="$shape" '$1==c && $2==s && $3=="I" {print $4, $5, $6}')
          ICODE="$1"; IKIND="$3"; case "$2" in ALL) ICOUNT=7 ;; *) ICOUNT="$2" ;; esac
        fi ;;
    *) AR="$ROLES8" ;;
  esac
  case "$op" in G+|G-) X=pr-fixer ;; *) X=reviewer ;; esac
  # canary: on an installing op, take a clean role's live file AND stamp away so a write is observable
  if [ "$leaf" = 1 ] && { [ "$op" = I ] || [ "$op" = "G+" ]; }; then rm -f "$t/.pi/agents/scout.md" "$t/.harness/.pi-agents/scout.md"; fi
  if [ "$comp" = XP ]; then
    # PRECEDENCE cells: BOTH the live path and the stamp path are hostile. The stamp-unsafe check
    # must win (the stamp warning, nothing touched, stamp NOT dropped): the live-first order would
    # print the destination warning instead, or none at all.
    for _part in $(printf '%s' "$shape" | tr '_' ' '); do plant_cell "$(printf '%s' "$_part" | cut -c1-2)" "${_part#??}"; done
  else
    plant_cell "$comp" "$shape"
  fi
  # the operator-owned neighbours that no operation may touch, and the sentinel outside scope
  echo sentinel > "$t/sentinel.txt"
  if [ -d "$t/.pi" ] && [ ! -L "$t/.pi" ]; then
    printf '{"keep":1}\n' > "$t/.pi/settings.json"
    if [ ! -L "$t/.pi/prompts" ] && { [ ! -e "$t/.pi/prompts" ] || [ -d "$t/.pi/prompts" ]; }; then
      mkdir -p "$t/.pi/prompts"; echo "operator prompt" > "$t/.pi/prompts/keep.md"
    fi
  fi
  # ── snapshot ──
  for _r in $ROLES8; do
    snap "$t/.pi/agents/$_r.md" > "$c/pre-live-$_r"
    snap "$t/.harness/.pi-agents/$_r.md" > "$c/pre-stamp-$_r"
  done
  pre_node="$(snap "$HN")"
  pre_victim="$(tree_snap "$V")"
  pre_guard="$(guard_ck)"
  scope() { ( cd "$t" && { ls -A | grep -vxF -e .claude -e CLAUDE.md -e .pi -e .agents -e .harness -e .gitignore; \
      ls -A .harness | grep -vxF -e .pi-agents -e .pi-prompts -e .codex-skills -e .agents | sed 's|^|.harness/|'; } | sort ); }
  pre_scope="$(scope)"
  # ── run the operation ──
  rc=0
  case "$op" in
    I|"G+") inst --agents=pi --pr-loop=true "$t" || rc=$? ;;
    D)      inst --agents=claude "$t" || rc=$? ;;
    G-)     inst --agents=pi --pr-loop=false "$t" || rc=$? ;;
  esac
  [ "$rc" = 0 ] || { cat "$OUT" >&2; cfail "the installer exited $rc (must continue with status 0)"; }
  # ── invariants ──
  [ "$(guard_ck)" = "$pre_guard" ] \
    || cfail ".pi/settings.json, .pi/prompts/keep.md or the sentinel changed"
  [ "$(scope)" = "$pre_scope" ] || cfail "a path outside the matrix scope changed: $(printf '%s\n%s\n' "$pre_scope" "$(scope)" | sort | uniq -u | tr '\n' ' ')"
  [ "$(tree_snap "$V")" = "$pre_victim" ] || cfail "the victim changed (a write-through or delete-through)"
  # ── warning count and kind ──
  _nw="$(grep -c '^⚠️  \(\.pi/agents/\|\.harness/\.pi-agents/\)' "$OUT" || true)"
  case "$wcount" in ALL) _want="$(set -- $AR; echo $#)" ;; *) _want="$wcount" ;; esac
  _want=$((_want + ICOUNT))
  if [ "$wkind" = "-" ]; then wkind="$IKIND"; fi
  [ "$_nw" = "$_want" ] || { grep '^⚠️' "$OUT" >&2 || true; cfail "expected $_want pi-agent warning(s), got $_nw"; }
  case "$wkind" in
    dest)    _ws='symlinked or non-regular destination component' ;;
    stamp)   _ws='symlinked or non-regular stamp component' ;;
    foreign) _ws='foreign or edited pi role file' ;;
    nostamp) _ws='has no matching stamp' ;;
    -)       _ws='' ;;
  esac
  if [ -n "$_ws" ]; then
    grep '^⚠️  \(\.pi/agents/\|\.harness/\.pi-agents/\)' "$OUT" | grep -qF -- "$_ws" || cfail "no pi-agent warning contains '$_ws'"
    # every pi-agent warning is of the expected kind, and none doubles up on a role
    if [ "$(grep '^⚠️  \(\.pi/agents/\|\.harness/\.pi-agents/\)' "$OUT" | grep -cF -- "$_ws")" != "$_nw" ]; then cfail "a pi-agent warning of an unexpected kind"; fi
    if [ "$(grep '^⚠️  \(\.pi/agents/\|\.harness/\.pi-agents/\)' "$OUT" | sed 's/^⚠️  //; s/ .*//' | sort | uniq -d | wc -l | tr -d ' ')" != 0 ]; then cfail "more than one warning for a single role path"; fi
  fi
  # ── per-role outcomes ──
  for _r in $IR; do cell_check_role "$_r" "$ICODE"; done
  for _r in $AR; do
    if [ "$leaf" = 1 ] && [ "$_r" = "$X" ]; then _code="$outcome"
    else
      case "$op" in I|"G+") _code=W ;; D) _code=RM ;; G-) _code=SKIP ;; esac
      # a dir/ledger shape applies to every role; a leaf shape to X only
      [ "$leaf" = 1 ] || _code="$outcome"
    fi
    [ "$_code" = SKIP ] || cell_check_role "$_r" "$_code"
  done
  # G- (leaf): the roles it does not process are left exactly as they were
  if [ "$op" = G- ] && [ "$leaf" = 1 ]; then
    for _r in $ROLES7; do
      [ "$(snap "$t/.pi/agents/$_r.md")" = "$(cat "$c/pre-live-$_r")" ] || cfail "gate-off touched the live file of $_r"
      [ "$(snap "$t/.harness/.pi-agents/$_r.md")" = "$(cat "$c/pre-stamp-$_r")" ] || cfail "gate-off touched the stamp of $_r"
    done
    [ ! -e "$t/.pi/prompts/sdd-pr-loop.md" ] || cfail "gate-off kept the F01 pr-loop prompt (canary)"
  fi
  # the hostile node itself: untouched unless the outcome is a write/removal on it
  case "$outcome:$ICODE" in
    KD:|KD0:|KK:|KD:KD*|KD0:KD*|KK:KD*|KD:KK|KD0:KK|KK:KK)
      [ "$(snap "$HN")" = "$pre_node" ] || cfail "the hostile node changed (was '$pre_node', now '$(snap "$HN")')" ;;
  esac
  # L1 Sve: the EMPTY agents/ behind the symlink must survive (a prune-through victim)
  if [ "$shape" = Sve ]; then [ -d "$V/agents" ] || cfail "the empty agents/ behind the symlinked .pi was pruned through"; fi
  # D: with no unsafe stamp path left, the ledger directory is pruned
  if [ "$op" = D ] && [ "$outcome" != KK ] && [ "$comp" != S1 ]; then
    [ ! -e "$t/.harness/.pi-agents" ] || cfail "the emptied stamp ledger was not pruned on deselect"
  fi
  # a dropped stamp with no installing op leaves no stamp for any processed role (dir cells)
  if [ "$leaf" = 0 ] && [ "$outcome" != KK ] && [ "$outcome" != W ] && [ "$comp" != S1 ]; then
    for _r in $AR; do [ ! -e "$t/.harness/.pi-agents/$_r.md" ] || cfail "a stamp for $_r survived"; done
  fi
  if { [ "$op" = I ] || [ "$op" = "G+" ]; } && ! grep -q 'pi role agents installed' "$OUT"; then
    cfail "the install did not reach the end of the pi role block"
  fi
}

test_pi_agent_shape_matrix() {
  mk_bases
  # ── coverage guard: every expected (component, shape) × op is a row; no extras ──
  _rows="$(MATRIX_ROWS)"
  for _cs in $MATRIX_SHAPES; do
    for _op in $MATRIX_OPS; do
      printf '%s\n' "$_rows" | awk -v c="${_cs%%:*}" -v s="${_cs##*:}" -v o="$_op" '$1==c && $2==s && $3==o {n++} END{exit !(n==1)}' \
        || fail "matrix coverage: no single row for ${_cs%%:*} ${_cs##*:} $_op"
    done
  done
  _nshapes="$(set -- $MATRIX_SHAPES; echo $#)"; _nops="$(set -- $MATRIX_OPS; echo $#)"
  [ "$(printf '%s\n' "$_rows" | grep -c .)" = "$((_nshapes * _nops))" ] || fail "matrix coverage: the table has rows outside the expected component/shape/op grid"
  mkdir -p "$T/cells"
  # ── run every cell (independent targets, in parallel) ──
  if ! printf '%s\n' "$_rows" | PIA_T="$T" xargs -P 8 -I{} sh "$SELF" --cell {} 2>"$T/cells.err" >"$T/cells.out"; then
    cat "$T/cells.err" >&2
    fail "shape matrix: at least one cell failed (see FAIL lines above)"
  fi
  [ "$(grep -c '^cell-ok ' "$T/cells.out")" = "$((_nshapes * _nops))" ] || { cat "$T/cells.out" "$T/cells.err" >&2; fail "shape matrix: not every cell reported ok"; }
  # ── upgrade row: a 0.92.0-shaped target (prompts only) gains the role files, prompts untouched ──
  _t="$(new_target up)"; cp -a "$T/base-true/." "$_t/"
  rm -rf "$_t/.pi/agents" "$_t/.harness/.pi-agents"
  ( cd "$_t/.pi/prompts" && cksum *.md ) > "$T/up.before"
  ok_inst --agents=pi --pr-loop=true "$_t"
  [ "$(ls "$_t/.pi/agents" | wc -l | tr -d ' ')" = 8 ] || fail "upgrade: the 0.92.0-shaped target did not gain its 8 role files"
  ( cd "$_t/.pi/prompts" && cksum *.md ) | cmp -s - "$T/up.before" || fail "upgrade: .pi/prompts changed"
  pass "shape matrix: $((_nshapes * _nops)) cells ($_nshapes shapes x $_nops operations) all hold, plus the 0.92.0 upgrade row (R5, R6)"
}

test_pi_agent_reclaim() {
  mk_bases
  # (a) a pristine deselect removes .pi/agents/, the ledger and every stamp; .pi stays only
  # while something else lives in it.
  _t="$(new_target rc1)"; cp -a "$T/base-true/." "$_t/"
  mkdir -p "$_t/.pi/prompts"; echo mine > "$_t/.pi/prompts/keep.md"
  ok_inst --agents=claude "$_t"
  grep -q "removed deselected agent 'pi' role files:.*\.pi/agents/scout\.md" "$OUT" || fail "R6a: the deselect did not report the removed role files"
  grep -q "removed deselected agent 'pi' role files:.*\.pi/agents/pr-fixer\.md" "$OUT" || fail "R6a: the deselect report omits pr-fixer"
  [ ! -e "$_t/.pi/agents" ] || fail "R6a: .pi/agents survived a pristine deselect"
  [ ! -e "$_t/.harness/.pi-agents" ] || fail "R6a: the stamp ledger survived"
  [ -f "$_t/.pi/prompts/keep.md" ] || fail "R6a: .pi/prompts/keep.md was touched"
  [ -d "$_t/.pi" ] || fail "R6a: .pi was pruned while .pi/prompts still holds a file"
  _t="$(new_target rc2)"; cp -a "$T/base-true/." "$_t/"
  printf '{}\n' > "$_t/.pi/settings.json"
  ok_inst --agents=claude "$_t"
  [ -f "$_t/.pi/settings.json" ] && [ -d "$_t/.pi" ] || fail "R6a: .pi/settings.json or .pi did not survive"
  [ ! -e "$_t/.pi/agents" ] || fail "R6a: .pi/agents survived alongside settings.json"
  _t="$(new_target rc3)"; cp -a "$T/base-true/." "$_t/"
  ok_inst --agents=claude "$_t"
  [ ! -e "$_t/.pi" ] || fail "R6a: an emptied .pi/ was not pruned"
  # (b) gate-off removes pr-fixer only
  _t="$(new_target rc4)"; cp -a "$T/base-true/." "$_t/"
  ok_inst --agents=pi --pr-loop=false "$_t"
  grep -q 'reclaimed /sdd-pr-loop glue:.*\.pi/agents/pr-fixer\.md' "$OUT" || fail "R6b: the gate-off report omits .pi/agents/pr-fixer.md"
  [ ! -e "$_t/.pi/agents/pr-fixer.md" ] && [ ! -e "$_t/.harness/.pi-agents/pr-fixer.md" ] || fail "R6b: gate-off kept pr-fixer or its stamp"
  [ "$(ls "$_t/.pi/agents" | wc -l | tr -d ' ')" = 7 ] && [ "$(ls "$_t/.harness/.pi-agents" | wc -l | tr -d ' ')" = 7 ] \
    || fail "R6b: gate-off removed more than pr-fixer"
  # (d) a deselect reclaims pr-fixer even when pr_loop has since been turned off (all roles, not just the enabled ones)
  _t="$(new_target rc6)"; cp -a "$T/base-true/." "$_t/"; set_pr_loop "$_t" false
  ok_inst --agents=claude "$_t"
  [ ! -e "$_t/.pi/agents" ] && [ ! -e "$_t/.harness/.pi-agents" ] || fail "R6d: a pristine pr-fixer survived a deselect made while pr_loop was off"
  # (c) an edited pr-fixer survives the gate-off; an edited role survives deselect
  _t="$(new_target rc5)"; cp -a "$T/base-true/." "$_t/"; echo edit >> "$_t/.pi/agents/pr-fixer.md"
  ok_inst --agents=pi --pr-loop=false "$_t"
  [ -f "$_t/.pi/agents/pr-fixer.md" ] || fail "R6c: an edited pr-fixer was deleted by the gate-off"
  echo edit >> "$_t/.pi/agents/scout.md"
  ok_inst --agents=claude "$_t"
  [ -f "$_t/.pi/agents/scout.md" ] && [ "$(ls "$_t/.pi/agents" | wc -l | tr -d ' ')" = 2 ] || fail "R6c: deselect did not leave exactly the two edited files"
  pass "deselect and gate-off reclaim only pristine role files, pruning .pi/agents, the ledger and .pi only when empty (R6)"
}

# A hard-linked live leaf or stamp is a regular file, so the node-type matrix cannot see it:
# a rewrite must replace the leaf, never write through to its other name (reviewer finding).
test_pi_unit_hardlink_not_written_through() {
  mk_bases
  for _k in agents/scout prompts/sdd-next; do
    _t="$(new_target hl-${_k%%/*})"; cp -a "$T/base-true/." "$_t/"
    _leaf="$_t/.pi/$_k.md"; _st="$_t/.harness/.pi-${_k%%/*}/${_k#*/}.md"
    printf 'old\n' > "$_leaf"; cp "$_leaf" "$_st"         # pristine-but-stale: stamp matches live
    printf 'old\n' > "$T/outside-live"; printf 'old\n' > "$T/outside-stamp"
    rm -f "$_leaf" "$_st"; ln "$T/outside-live" "$_leaf"; ln "$T/outside-stamp" "$_st"
    ok_inst --agents=pi --pr-loop=true "$_t"
    [ "$(cat "$T/outside-live")" = old ] || fail "hard link: install wrote through .pi/$_k.md to its other name"
    [ "$(cat "$T/outside-stamp")" = old ] || fail "hard link: install wrote through the $_k stamp to its other name"
    [ "$(cat "$_leaf")" != old ] && cmp -s "$_leaf" "$_st" || fail "hard link: .pi/$_k.md was not refreshed with a matching stamp"
    ls "$(dirname "$_leaf")" "$(dirname "$_st")" | grep -q 'harness-new' && fail "hard link: a .harness-new sibling was left behind"
  done
  pass "a hard-linked unit or stamp is replaced, never written through"
}

# ── R7: the dispatcher's argv contract ────────────────────────────────────────────────────
# run_disp <target> <logdir> <path-prefix|-> <args…> — run the dispatcher via its shebang, from a
# foreign cwd, in a scrubbed environment. stdout -> $T/d.out, stderr -> $T/d.err; returns its status.
run_disp() {
  _rd_t="$1"; _rd_log="$2"; _rd_bin="$3"; shift 3
  _rd_path="$SANDBOX_PATH"; [ "$_rd_bin" = "-" ] || _rd_path="$_rd_bin:$SANDBOX_PATH"
  mkdir -p "$_rd_log" "$T/elsewhere" "$T/dtmp"
  _rd_rc=0
  # RD_SIGDFL=1 starts the dispatcher with SIGINT/SIGTERM at their DEFAULT disposition. A suite run
  # in the background (xargs, run-tests.sh, nohup) inherits SIGINT as IGNORED, and a shell cannot
  # trap a signal that was ignored on entry — so the signal cases must not depend on how THIS
  # suite was launched. python's os.execv keeps the reset disposition.
  if [ "${RD_SIGDFL:-0}" = 1 ]; then
    ( cd "$T/elsewhere" && env -i PATH="$_rd_path" HOME="$T/home" TMPDIR="$T/dtmp" STUB_LOG="$_rd_log" STUB_RC="${RD_RC:-0}" \
        python3 -I -c 'import os,signal,sys
for n in (signal.SIGINT, signal.SIGTERM): signal.signal(n, signal.SIG_DFL)
os.execv(sys.argv[1], sys.argv[1:])' "$_rd_t/.harness/tools/pi-dispatch.sh" "$@" ) >"$T/d.out" 2>"$T/d.err" </dev/null || _rd_rc=$?
  else
    ( cd "$T/elsewhere" && env -i PATH="$_rd_path" HOME="$T/home" TMPDIR="$T/dtmp" STUB_LOG="$_rd_log" STUB_RC="${RD_RC:-0}" \
        "$_rd_t/.harness/tools/pi-dispatch.sh" "$@" ) >"$T/d.out" 2>"$T/d.err" </dev/null || _rd_rc=$?
  fi
  return "$_rd_rc"
}

test_dispatch_argv_and_passthrough() {
  mk_bases
  _t="$(new_target r7)"; cp -a "$T/base-true/." "$_t/"
  mkdir -p "$T/dir with space"; _task="$T/dir with space/task file.md"
  printf 'line1\n--tools evil\n\n\n' > "$_task"
  _log="$T/r7log"; rm -rf "$_log"
  run_disp "$_t" "$_log" "$STUBBIN" reviewer "$_task" || fail "R7a: dispatcher exited $? against a valid input"
  [ "$(argv_n "$_log")" = 9 ] || fail "R7a: pi received $(argv_n "$_log") arguments, expected 9"
  _i=0
  for _e in -p -a --no-session --no-skills --tools "read,bash,edit,grep,find,ls" --append-system-prompt; do
    [ "$(argv_i "$_log" "$_i")" = "$_e" ] || fail "R7a: argv[$_i] is '$(argv_i "$_log" "$_i")', expected '$_e'"
    _i=$((_i + 1))
  done
  _tmp="$(argv_i "$_log" 7)"
  _msg="$(argv_i "$_log" 8)"
  # the message: a fixed one-line preamble naming the role, a blank line, the task (trailing newlines stripped)
  printf 'You are the harness reviewer role (dispatched by pi-dispatch.sh). Your task follows.\n\nline1\n--tools evil' > "$T/msg.exp"
  argv_i "$_log" 8 > "$T/msg.got"
  cmp -s "$T/msg.exp" "$T/msg.got" || fail "R7a: the message is not the fixed preamble + blank line + task text (got: $_msg)"
  [ "$(cat "$_log/cwd")" = "$(cd "$_t" && pwd -P)" ] || fail "R7a: pi ran in '$(cat "$_log/cwd")', not the target root"
  awk 'c>=2{print} /^---$/{c++}' "$_t/.pi/agents/reviewer.md" > "$T/body.exp"
  cmp -s "$T/body.exp" "$_log/appended" || fail "R7a: the appended system prompt is not, byte for byte, the role file's post-frontmatter body"
  [ "$(cat "$T/d.out")" = "STUB-STDOUT" ] || fail "R7a: stdout is not pi's, unchanged: '$(cat "$T/d.out")'"
  # (c) no temp file remains
  [ ! -e "$_tmp" ] || fail "R7c: the temp prompt file '$_tmp' was left behind"
  case "$_tmp" in "$T/dtmp/"*) ;; *) fail "R7c: the dispatcher's temp file '$_tmp' is outside the sandboxed TMPDIR" ;; esac
  [ -z "$(ls -A "$T/dtmp")" ] || fail "R7c: the dispatcher left files behind: $(ls -A "$T/dtmp" | tr '\n' ' ')"
  # (b) pi's exit status passes through
  rm -rf "$_log"
  RD_RC=7; _rc=0; run_disp "$_t" "$_log" "$STUBBIN" reviewer "$_task" || _rc=$?
  [ "$_rc" = 7 ] || fail "R7b: pi's status 7 became $_rc"
  RD_RC=0; _rc=0; run_disp "$_t" "$_log" "$STUBBIN" reviewer "$_task" || _rc=$?
  [ "$_rc" = 0 ] || fail "R7b: pi's status 0 became $_rc"
  [ ! -e "$(argv_i "$_log" 7)" ] || fail "R7c: the temp prompt file survived a run"
  # (d) model / thinking keys, when the role file carries them, precede --tools
  { awk 'NR==1{print; next} /^---$/ && !d {print "model: prov/m-1"; print "thinking: high"; d=1} {print}' "$_t/.pi/agents/scout.md"; } > "$T/scout.mt"
  cp "$T/scout.mt" "$_t/.pi/agents/scout.md"
  rm -rf "$_log"; run_disp "$_t" "$_log" "$STUBBIN" scout "$_task" || fail "R7d: dispatcher failed with model/thinking keys"
  [ "$(argv_n "$_log")" = 13 ] || fail "R7d: expected 13 arguments with --model and --thinking, got $(argv_n "$_log")"
  _i=0
  for _e in -p -a --no-session --no-skills --model prov/m-1 --thinking high --tools "read,bash,grep,find,ls" --append-system-prompt; do
    [ "$(argv_i "$_log" "$_i")" = "$_e" ] || fail "R7d: argv[$_i] is '$(argv_i "$_log" "$_i")', expected '$_e'"
    _i=$((_i + 1))
  done
  # a role file WITHOUT the keys passes neither flag (covered by R7a's exact 9-element argv)
  # (d2) role names with a dash or a digit are legal: builder-heavy is a shipped role, r2d2 is a hand-written one
  rm -rf "$_log"; run_disp "$_t" "$_log" "$STUBBIN" builder-heavy "$_task" || fail "R7d2: the dashed role builder-heavy was rejected ($(cat "$T/d.err"))"
  sed 's/^name: reviewer$/name: r2d2/' "$FRESH/reviewer.md" > "$_t/.pi/agents/r2d2.md"
  rm -rf "$_log"; run_disp "$_t" "$_log" "$STUBBIN" r2d2 "$_task" || fail "R7d2: a role name with digits was rejected ($(cat "$T/d.err"))"
  rm -f "$_t/.pi/agents/r2d2.md"
  # (e) a RELATIVE task path, from the task's own directory, still reaches pi (resolved before the cd)
  rm -rf "$_log"; mkdir -p "$_log"
  ( cd "$T/dir with space" && env -i PATH="$STUBBIN:$SANDBOX_PATH" HOME="$T/home" STUB_LOG="$_log" \
      "$_t/.harness/tools/pi-dispatch.sh" reviewer "task file.md" ) >"$T/d.out" 2>"$T/d.err" \
    || { cat "$T/d.err" >&2; fail "R7e: a relative task path was not resolved before the cd"; }
  case "$(argv_i "$_log" 8)" in *"--tools evil"*) ;; *) fail "R7e: the relative task's contents did not reach pi" ;; esac
  # (f) the model / thinking vocabularies: every legal value is accepted, near-misses are not
  _ok_kv() { # <key> <value> <expect-flag-value>
    cp "$FRESH/reviewer.md" "$_t/.pi/agents/reviewer.md"
    awk -v k="$1" -v v="$2" 'NR==1{print; next} /^---$/ && !d {print k ": " v; d=1} {print}' "$FRESH/reviewer.md" > "$_t/.pi/agents/reviewer.md"
    rm -rf "$_log"; _rcv=0; run_disp "$_t" "$_log" "$STUBBIN" reviewer "$_task" || _rcv=$?
    [ "$_rcv" = "$3" ] || fail "R7f: '$1: $2' exited $_rcv, expected $3 ($(cat "$T/d.err"))"
  }
  for _v in off minimal low medium high xhigh max; do _ok_kv thinking "$_v" 0; done
  for _v in huge Max HIGH 'high ' minimum; do _ok_kv thinking "$_v" 3; done
  for _v in 'a.b_c:d/e@f-1' 'Provider/Model-9' 'x'; do _ok_kv model "$_v" 0; done
  for _v in 'a b' 'a$b' 'a;b' 'a`b' 'a(b' 'a|b' 'a*b'; do _ok_kv model "$_v" 3; done
  # tools: the allowed charset is [A-Za-z0-9_:,.*/+-] after spaces are removed
  _ok_tools() { # <tools value> <expected rc>
    awk -v v="$1" '/^tools: /{print "tools: " v; next} {print}' "$FRESH/reviewer.md" > "$_t/.pi/agents/reviewer.md"
    rm -rf "$_log"; _rcv=0; run_disp "$_t" "$_log" "$STUBBIN" reviewer "$_task" || _rcv=$?
    [ "$_rcv" = "$2" ] || fail "R7f: 'tools: $1' exited $_rcv, expected $2 ($(cat "$T/d.err"))"
  }
  _ok_tools 'read, bash, mcp:srv/tool.*, my_tool+1-x' 0
  _ok_tools 'read;rm' 3; _ok_tools 'read bash$' 3; _ok_tools 'read|bash' 3; _ok_tools 'read`id`' 3; _ok_tools 'read&' 3; _ok_tools '"read"' 3
  # (g) a key-looking line in the BODY is ignored ...
  { cat "$FRESH/reviewer.md"; echo 'tools: read;rm'; echo 'thinking: huge'; echo 'model: a b'; } > "$_t/.pi/agents/reviewer.md"
  rm -rf "$_log"; run_disp "$_t" "$_log" "$STUBBIN" reviewer "$_task" || fail "R7g: a key-looking body line broke the dispatch ($(cat "$T/d.err"))"
  [ "$(argv_i "$_log" 5)" = "read,bash,edit,grep,find,ls" ] || fail "R7g: a body tools: line leaked into --tools"
  # ... but a DUPLICATE tools: key in the frontmatter is refused: pi-subagents is last-wins and
  # fm_get first-wins, so the two dispatch paths would grant different tools (R6, Codex review).
  { awk 'NR==1{print; next} /^---$/ && !d {print "tools: read;rm"; d=1} {print}' "$FRESH/reviewer.md"; } > "$_t/.pi/agents/reviewer.md"
  rm -rf "$_log"; _rcv=0; run_disp "$_t" "$_log" "$STUBBIN" reviewer "$_task" || _rcv=$?
  [ "$_rcv" = 3 ] && [ ! -e "$_log/argv" ] || fail "R7g: a duplicate frontmatter tools: key was not refused (rc=$_rcv)"
  # (h) pi killed by a signal aimed at the dispatcher: the temp file is still removed, status is 128+n
  cp "$FRESH/reviewer.md" "$_t/.pi/agents/reviewer.md"
  mkdir -p "$T/sigbin"
  for _sig in TERM:143 INT:130; do
    # the stub signals its parent, then keeps running for a second: a dispatcher that TRAPS the
    # signal waits for the child before exiting (so child-done exists on return); one that does
    # not is killed on the spot and the marker appears only after it is gone.
    cat > "$T/sigbin/pi" <<EOSIG
#!/bin/sh
printf '%s\0' "\$@" > "\$STUB_LOG/argv"
kill -${_sig%%:*} "\$PPID"
sleep 1
: > "\$STUB_LOG/child-done"
exit 0
EOSIG
    chmod +x "$T/sigbin/pi"
    _log="$T/r7log-${_sig%%:*}"; rm -rf "$_log"; _rcv=0; RD_SIGDFL=1 run_disp "$_t" "$_log" "$T/sigbin" reviewer "$_task" || _rcv=$?
    RD_SIGDFL=0
    [ "$_rcv" = "${_sig##*:}" ] || fail "R7h: a ${_sig%%:*} aimed at the dispatcher exited $_rcv, expected ${_sig##*:}"
    [ -e "$_log/child-done" ] || fail "R7h: the dispatcher did not wait for pi to finish before exiting on a ${_sig%%:*}"
    [ ! -e "$(argv_i "$_log" 7)" ] || fail "R7h: the temp prompt file survived a ${_sig%%:*}"
  done
  pass "dispatcher: exact argv, cwd, body file, stdout and exit passthrough, no temp file, model/thinking (R7)"
}

# ── R8: fail closed, in order ─────────────────────────────────────────────────────────────
test_dispatch_fail_closed() {
  mk_bases
  _task="$T/r8-task.md"; echo "do it" > "$_task"
  _row() { # <name> <expected rc> <bin|stub|nostub> <setup-fn> <args…>
    _rn="$1"; _rexp="$2"; _rbin="$3"; _rsetup="$4"; shift 4
    _rt="$T/r8-$_rn"; rm -rf "$_rt"; cp -a "$T/base-true" "$_rt"
    $_rsetup "$_rt"
    _rlog="$T/r8log-$_rn"; rm -rf "$_rlog"
    _rrc=0
    if [ "$_rbin" = stub ]; then run_disp "$_rt" "$_rlog" "$STUBBIN" "$@" || _rrc=$?
    else run_disp "$_rt" "$_rlog" - "$@" || _rrc=$?; fi
    [ "$_rrc" = "$_rexp" ] || fail "R8[$_rn]: exit $_rrc, expected $_rexp (stderr: $(cat "$T/d.err"))"
    if [ "$_rexp" != 0 ]; then
      [ ! -s "$T/d.out" ] || fail "R8[$_rn]: stdout is not empty: $(cat "$T/d.out")"
      case "$(sed -n '1p' "$T/d.err")" in pi-dispatch:*) ;; *) fail "R8[$_rn]: stderr does not start with 'pi-dispatch:': $(cat "$T/d.err")" ;; esac
      [ ! -e "$_rlog/argv" ] || fail "R8[$_rn]: pi was invoked"
    fi
  }
  nop() { :; }
  v_l1f() { rm -rf "$1/.pi"; echo foreign > "$1/.pi"; }
  v_l1sv() { mkdir -p "$T/r8v-l1/agents"; cp "$FRESH"/*.md "$T/r8v-l1/agents/"; rm -rf "$1/.pi"; ln -s "$T/r8v-l1" "$1/.pi"; }
  v_l1sx() { rm -rf "$1/.pi"; ln -s "$T/nowhere-r8" "$1/.pi"; }
  v_l1a() { rm -rf "$1/.pi"; }
  v_l2f() { rm -rf "$1/.pi/agents"; echo foreign > "$1/.pi/agents"; }
  v_l2sv() { mkdir -p "$T/r8v-l2"; cp "$FRESH"/*.md "$T/r8v-l2/"; rm -rf "$1/.pi/agents"; ln -s "$T/r8v-l2" "$1/.pi/agents"; }
  v_l2sx() { rm -rf "$1/.pi/agents"; ln -s "$T/nowhere-r8" "$1/.pi/agents"; }
  v_l2a() { rm -rf "$1/.pi/agents"; }
  v_l3dd() { rm -f "$1/.pi/agents/reviewer.md"; mkdir "$1/.pi/agents/reviewer.md"; }
  v_l3sv() { cp "$FRESH/reviewer.md" "$T/r8v-l3.md"; rm -f "$1/.pi/agents/reviewer.md"; ln -s "$T/r8v-l3.md" "$1/.pi/agents/reviewer.md"; }
  v_l3sx() { rm -f "$1/.pi/agents/reviewer.md"; ln -s "$T/nowhere-r8" "$1/.pi/agents/reviewer.md"; }
  v_l3a() { rm -f "$1/.pi/agents/reviewer.md"; }
  v_noclose() { { echo '---'; echo 'name: reviewer'; echo 'tools: read'; echo 'body'; } > "$1/.pi/agents/reviewer.md"; }
  v_nofm() { { echo 'name: reviewer'; echo 'tools: read'; } > "$1/.pi/agents/reviewer.md"; }
  v_notools() { sed '/^tools:/d' "$FRESH/reviewer.md" > "$1/.pi/agents/reviewer.md"; }
  v_emptytools() { sed 's/^tools: .*/tools: /' "$FRESH/reviewer.md" > "$1/.pi/agents/reviewer.md"; }
  v_badtools() { sed 's/^tools: .*/tools: read;rm/' "$FRESH/reviewer.md" > "$1/.pi/agents/reviewer.md"; }
  v_badthink() { sed 's/^tools: /thinking: huge\ntools: /' "$FRESH/reviewer.md" > "$1/.pi/agents/reviewer.md"; }
  v_badmodel() { sed 's/^tools: /model: a b\ntools: /' "$FRESH/reviewer.md" > "$1/.pi/agents/reviewer.md"; }
  v_emptymodel() { sed 's/^tools: /model: \ntools: /' "$FRESH/reviewer.md" > "$1/.pi/agents/reviewer.md"; }
  v_nolead() { { echo 'name: reviewer'; echo 'tools: read'; echo '---'; echo 'body'; } > "$1/.pi/agents/reviewer.md"; }
  v_edited() { echo "an operator edit" >> "$1/.pi/agents/reviewer.md"; }
  # exit 2: usage
  _row noargs 2 stub nop
  _row onearg 2 stub nop reviewer
  _row threeargs 2 stub nop reviewer "$_task" extra
  _row roleUpper 2 stub nop Rev "$_task"
  _row roleDash 2 stub nop -x "$_task"
  _row roleNewline 2 stub nop "$(printf 'reviewer\nx')" "$_task"
  _row roleEmpty 2 stub nop "" "$_task"
  _row taskAbsent 2 stub nop reviewer "$T/does-not-exist.md"
  _row taskDir 2 stub nop reviewer "$T"
  ln -sf "$T/dangling-target" "$T/r8-dangling.md"
  _row taskDangling 2 stub nop reviewer "$T/r8-dangling.md"
  # the check order: a bad task wins over a bad role file, which wins over a missing pi
  _row taskBeatsRoleFile 2 stub v_l3a reviewer "$T/does-not-exist.md"
  _row roleFileBeatsNoPi 3 nostub v_l3a reviewer "$_task"
  _row badRoleFileNoPi 3 nostub v_badtools reviewer "$_task"
  # exit 3: the plan's DISP column
  _row roleFileAbsent 3 stub nop nosuchrole "$_task"
  _row L1A 3 stub v_l1a reviewer "$_task"
  _row L1F 3 stub v_l1f reviewer "$_task"
  _row L1Sv 3 stub v_l1sv reviewer "$_task"
  _row L1Sx 3 stub v_l1sx reviewer "$_task"
  _row L2A 3 stub v_l2a reviewer "$_task"
  _row L2F 3 stub v_l2f reviewer "$_task"
  _row L2Sv 3 stub v_l2sv reviewer "$_task"
  _row L2Sx 3 stub v_l2sx reviewer "$_task"
  _row L3A 3 stub v_l3a reviewer "$_task"
  _row L3Dd 3 stub v_l3dd reviewer "$_task"
  _row L3Sv 3 stub v_l3sv reviewer "$_task"
  _row L3Sx 3 stub v_l3sx reviewer "$_task"
  _row noClosing 3 stub v_noclose reviewer "$_task"
  _row noFrontmatter 3 stub v_nofm reviewer "$_task"
  _row noLeadingDelimiter 3 stub v_nolead reviewer "$_task"
  _row toolsMissing 3 stub v_notools reviewer "$_task"
  _row toolsEmpty 3 stub v_emptytools reviewer "$_task"
  _row toolsBad 3 stub v_badtools reviewer "$_task"
  _row thinkingBad 3 stub v_badthink reviewer "$_task"
  _row modelBad 3 stub v_badmodel reviewer "$_task"
  _row modelEmpty 3 stub v_emptymodel reviewer "$_task"
  # an unreadable task file is a usage error (root reads anything, so this arm only runs unprivileged)
  if [ "$(id -u)" != 0 ]; then
    cp "$_task" "$T/r8-unreadable.md"; chmod 000 "$T/r8-unreadable.md"
    _row taskUnreadable 2 stub nop reviewer "$T/r8-unreadable.md"
    chmod 600 "$T/r8-unreadable.md"
  fi
  # exit 127: a valid role file and no pi
  _row noPi 127 nostub nop reviewer "$_task"
  # and the dispatcher is NOT an ownership check: an edited (but well-formed) role file runs
  _row editedRuns 0 stub v_edited reviewer "$_task"
  _row L3Fs 0 stub nop reviewer "$_task"
  [ -s "$T/r8log-editedRuns/argv" ] || fail "R8: an edited role file did not reach pi"
  pass "dispatcher fails closed with exit 2, then 3, then 127, never invoking pi (R8)"
}

# ── R9 ─────────────────────────────────────────────────────────────────────────────────────
test_pi_agents_owned_paths() {
  mk_bases
  _owned() { ( cd "$1" && sh .harness/tools/harness-owned-paths.sh all .harness ); }
  _t="$(new_target r9)"; cp -a "$T/base-true/." "$_t/"; git -C "$_t" init -q 2>/dev/null
  _p="$(_owned "$_t")"
  for _r in $ROLES8; do
    printf '%s\n' "$_p" | grep -qxF ":(literal).pi/agents/$_r.md" || fail "R9: no pathspec for $_r"
  done
  [ "$(printf '%s\n' "$_p" | grep -c '^:(literal)\.pi/agents/')" = 8 ] || fail "R9: wrong role pathspec count"
  printf '%s\n' "$_p" | grep -qxF ':(literal).pi/prompts/sdd-next.md' || fail "R9: the F01 prompt lines are gone (regression)"
  # a foreign stamp that is not a role file name still must not be claimed through the prompts glob
  mkdir -p "$_t/.harness/.pi-prompts"; echo n > "$_t/.harness/.pi-prompts/notes.md"
  printf '%s\n' "$(_owned "$_t")" | grep -qxF ':(literal).pi/prompts/notes.md' && fail "R9: the prompts ledger lost its sdd-*.md glob"
  # seven refusal cases
  _no() { printf '%s\n' "$(_owned "$1")" | grep -q '^:(literal)\.pi/agents/' && fail "R9: $2: a .pi/agents pathspec was printed"; return 0; }
  _t2="$(new_target r9a)"; cp -a "$T/base-true/." "$_t2/"; git -C "$_t2" init -q 2>/dev/null
  ok_inst --agents=claude "$_t2"; _no "$_t2" "after --agents=claude"
  _t2="$(new_target r9b)"; cp -a "$T/base-true/." "$_t2/"; git -C "$_t2" init -q 2>/dev/null
  mv "$_t2/.harness/.pi-agents" "$T/r9b-ledger"; ln -s "$T/r9b-ledger" "$_t2/.harness/.pi-agents"; _no "$_t2" "symlinked ledger"
  _t2="$(new_target r9c)"; cp -a "$T/base-true/." "$_t2/"; git -C "$_t2" init -q 2>/dev/null
  rm -rf "$_t2/.harness/.pi-agents"; echo f > "$_t2/.harness/.pi-agents"; _no "$_t2" "file-shaped ledger"
  _t2="$(new_target r9d)"; cp -a "$T/base-true/." "$_t2/"; git -C "$_t2" init -q 2>/dev/null
  mv "$_t2/.pi" "$T/r9d-pi"; ln -s "$T/r9d-pi" "$_t2/.pi"; _no "$_t2" "symlinked .pi"
  _t2="$(new_target r9e)"; cp -a "$T/base-true/." "$_t2/"; git -C "$_t2" init -q 2>/dev/null
  rm -rf "$_t2/.pi"; echo f > "$_t2/.pi"; _no "$_t2" "file-shaped .pi"
  _t2="$(new_target r9f)"; cp -a "$T/base-true/." "$_t2/"; git -C "$_t2" init -q 2>/dev/null
  mv "$_t2/.pi/agents" "$T/r9f-agents"; ln -s "$T/r9f-agents" "$_t2/.pi/agents"; _no "$_t2" "symlinked .pi/agents"
  _t2="$(new_target r9g)"; cp -a "$T/base-true/." "$_t2/"; git -C "$_t2" init -q 2>/dev/null
  rm -f "$_t2/.pi/agents/scout.md"; mkdir "$_t2/.pi/agents/scout.md"
  printf '%s\n' "$(_owned "$_t2")" | grep -qxF ':(literal).pi/agents/scout.md' && fail "R9: a directory leaf was claimed"
  printf '%s\n' "$(_owned "$_t2")" | grep -qxF ':(literal).pi/agents/reviewer.md' || fail "R9: the sibling role lost its claim"
  # a symlinked live leaf is not claimed either
  _t2="$(new_target r9h)"; cp -a "$T/base-true/." "$_t2/"; git -C "$_t2" init -q 2>/dev/null
  cp "$FRESH/scout.md" "$T/r9h-scout.md"; rm -f "$_t2/.pi/agents/scout.md"; ln -s "$T/r9h-scout.md" "$_t2/.pi/agents/scout.md"
  printf '%s\n' "$(_owned "$_t2")" | grep -qxF ':(literal).pi/agents/scout.md' && fail "R9: a symlinked leaf was claimed"
  # pi not LISTED in .harness/.agents: an intact ledger is not trusted (prompts and agents alike)
  _t2="$(new_target r9j)"; cp -a "$T/base-true/." "$_t2/"; git -C "$_t2" init -q 2>/dev/null
  # `codex` (not `claude`): a list with no skill claimant returns before the pi block is reached
  echo codex > "$_t2/.harness/.agents"
  printf '%s\n' "$(_owned "$_t2")" | grep -q '^:(literal)\.pi/' && fail "R9: a .pi pathspec was printed while pi is not listed in .agents"
  # a file-shaped .pi/agents (ledger intact): nothing claimed; the prompts claims are unaffected
  _t2="$(new_target r9k)"; cp -a "$T/base-true/." "$_t2/"; git -C "$_t2" init -q 2>/dev/null
  rm -rf "$_t2/.pi/agents"; echo f > "$_t2/.pi/agents"; _no "$_t2" "file-shaped .pi/agents"
  printf '%s\n' "$(_owned "$_t2")" | grep -qxF ':(literal).pi/prompts/sdd-next.md' || fail "R9: a file-shaped .pi/agents removed the prompts claims"
  # a symlinked and a directory-shaped STAMP leaf are not claimed (the sibling stamps still are)
  _t2="$(new_target r9l)"; cp -a "$T/base-true/." "$_t2/"; git -C "$_t2" init -q 2>/dev/null
  cp "$FRESH/scout.md" "$T/r9l-victim.md"; rm -f "$_t2/.harness/.pi-agents/scout.md"; ln -s "$T/r9l-victim.md" "$_t2/.harness/.pi-agents/scout.md"
  rm -f "$_t2/.harness/.pi-agents/reviewer.md"; mkdir "$_t2/.harness/.pi-agents/reviewer.md"
  _p="$(_owned "$_t2")"
  printf '%s\n' "$_p" | grep -qxF ':(literal).pi/agents/scout.md' && fail "R9: a symlinked stamp leaf was claimed"
  printf '%s\n' "$_p" | grep -qxF ':(literal).pi/agents/reviewer.md' && fail "R9: a directory-shaped stamp leaf was claimed"
  printf '%s\n' "$_p" | grep -qxF ':(literal).pi/agents/builder.md' || fail "R9: the sibling stamp lost its claim"
  # ./.harness/init.sh passes once the install is committed
  _t3="$(new_target r9i)"; cp -a "$T/base-true/." "$_t3/"
  ( cd "$_t3" && git init -q && git config user.email t@example.com && git config user.name t \
    && git add -A && git commit -q -m base ) >/dev/null 2>&1
  ( cd "$_t3" && env -i PATH="$SANDBOX_PATH" HOME="$T/home" ./.harness/init.sh ) >"$OUT" 2>&1 \
    || { cat "$OUT" >&2; fail "R9: ./.harness/init.sh failed in a committed pi target"; }
  pass "harness-owned-paths claims role stamps only while pi is listed and every component is safe (R9)"
}

# ── R10: --self ────────────────────────────────────────────────────────────────────────────
# self_fixture <name> — the source tree minus the heavy dirs, with the committed glue, and with
# .pi/ removed so --self must REGENERATE it (lessons 2026-09-05: an inherited .pi proves nothing).
self_fixture() {
  _sf="$T/$1"; rm -rf "$_sf"; mini_src "$_sf"
  for _e in .claude .codex .agents .opencode .pi opencode.json .escalation-arming; do
    [ -e "$SRC/$_e" ] && cp -R "$SRC/$_e" "$_sf/"
  done
  rm -rf "$_sf/.pi"
  printf '%s\n' "$_sf"
}
self_run() { env -i PATH="$SANDBOX_PATH" HOME="$T/home" CODEX_HOME="$T/ch" sh "$1/harness-install.sh" "$2" ${3:+"$3"} </dev/null >"$OUT" 2>&1; }

test_self_emits_pi() {
  # (a) bare --self
  F="$(self_fixture self-a)"
  self_run "$F" --self || { cat "$OUT" >&2; fail "R10a: --self exited non-zero"; }
  [ "$(ls "$F/.pi/agents" | wc -l | tr -d ' ')" = 8 ] || fail "R10a: --self wrote $(ls "$F/.pi/agents" 2>/dev/null | wc -l) role files, expected 8 (pr_loop is enabled here)"
  [ -f "$F/.pi/prompts/sdd-triage.md" ] || fail "R10a: the source-only sdd-triage prompt was not written"
  [ "$(ls "$F/.pi/prompts" | wc -l | tr -d ' ')" = 9 ] || fail "R10a: expected 9 prompt templates"
  for _f in "$F"/.pi/agents/*.md "$F"/.pi/prompts/*.md; do
    _rel="${_f#"$F"/}"
    grep -qF " $_rel" "$F/.claude/.glue-manifest" || fail "R10a: $_rel is not in .claude/.glue-manifest"
    if grep -q '\.harness/' "$_f"; then fail "R10a: $_rel still contains '.harness/' (self_transform missed it)"; fi
  done
  [ ! -e "$F/.harness" ] || fail "R10a: --self created .harness/ in the source tree"
  # R3(f): the Claude shims are byte-identical to the committed ones
  diff -r "$F/.claude/agents" "$SRC/.claude/agents" >/dev/null || fail "R3f/R10: .claude/agents differ from the committed shims after --self"
  # the committed pi glue equals the regenerated one (R10f)
  diff -r "$F/.pi" "$SRC/.pi" >/dev/null || fail "R10f: the committed .pi/ differs from what --self regenerates — run 'sh harness-install.sh --self'"
  # (e) a second --self is a byte no-op
  ( cd "$F" && find .pi .claude -type f | sort | while IFS= read -r _f; do cksum "$_f"; done ) > "$T/self.b1"
  self_run "$F" --self || fail "R10e: the second --self failed"
  ( cd "$F" && find .pi .claude -type f | sort | while IFS= read -r _f; do cksum "$_f"; done ) | cmp -s - "$T/self.b1" || fail "R10e: a second --self changed bytes"
  # (R7e) the source-layout dispatcher resolves the repository itself as the project root
  _log="$T/self-log"; rm -rf "$_log"; mkdir -p "$_log" "$T/elsewhere"; echo "task" > "$T/self-task.md"
  ( cd "$T/elsewhere" && env -i PATH="$STUBBIN:$SANDBOX_PATH" HOME="$T/home" STUB_LOG="$_log" \
      "$F/tools/pi-dispatch.sh" scout "$T/self-task.md" ) >/dev/null 2>"$T/d.err" || { cat "$T/d.err" >&2; fail "R7e: the source-layout dispatcher failed"; }
  [ "$(cat "$_log/cwd")" = "$(cd "$F" && pwd -P)" ] || fail "R7e: the source-layout root is '$(cat "$_log/cwd")', not the repository"
  grep -q 'selected Claude/Codex/OpenCode/pi source glue reconciled' "$OUT" || fail "R10: the --self success line does not name pi"
  # allowed(): a manifest claim outside .pi/agents/*.md and .pi/prompts/sdd-*.md is IGNORED, so a
  # pristine-looking operator file there is never adopted nor removed as "deselected glue"
  for _forged in .pi/agents/notes.txt .pi/prompts/other.md .pi/prompts/sdd-extra.txt .pi/settings.json; do
    mkdir -p "$F/$(dirname "$_forged")"; echo "operator file" > "$F/$_forged"
    ( cd "$F" && printf '%s %s\n' "$(cksum < "$_forged" | tr ' ' ' ' )" "$_forged" ) >> "$F/.claude/.glue-manifest"
  done
  self_run "$F" --self || { cat "$OUT" >&2; fail "R10: --self failed with forged manifest claims"; }
  for _forged in .pi/agents/notes.txt .pi/prompts/other.md .pi/prompts/sdd-extra.txt .pi/settings.json; do
    [ "$(cat "$F/$_forged" 2>/dev/null)" = "operator file" ] || fail "R10: --self removed or rewrote the operator file $_forged named by a forged manifest claim"
    if grep -q " $_forged\$" "$F/.claude/.glue-manifest"; then fail "R10: the manifest still claims $_forged"; fi
  done
  # (b) --agents=pi, (c) --agents=claude leaves .pi absent
  F="$(self_fixture self-b)"; self_run "$F" --self --agents=pi || { cat "$OUT" >&2; fail "R10b: --self --agents=pi failed"; }
  [ -f "$F/.pi/agents/scout.md" ] || fail "R10b: --agents=pi wrote no role file"
  F="$(self_fixture self-c)"; self_run "$F" --self --agents=claude || { cat "$OUT" >&2; fail "R10c: --self --agents=claude failed"; }
  [ ! -e "$F/.pi" ] || fail "R10c: --agents=claude created .pi/"
  F="$(self_fixture self-d0)"; self_run "$F" --self --agents=all || { cat "$OUT" >&2; fail "R10: --agents=all failed"; }
  [ -f "$F/.pi/agents/builder.md" ] || fail "R10: --self --agents=all did not emit pi"
  F="$(self_fixture self-d1)"
  if self_run "$F" --self --agents=antigravity; then fail "R10: --self accepted the unsupported antigravity key"; fi
  grep -q 'claude,codex,opencode,pi' "$OUT" || fail "R10: the unsupported-key error does not name the four supported keys"
  # (d) the SELF column of the shape matrix: unchanged and unclaimed, victim untouched
  F="$(self_fixture self-d)"; self_run "$F" --self || fail "R10d: setup --self failed"
  mkdir -p "$T/self-victim"; cp "$F"/.pi/agents/*.md "$T/self-victim/"
  ( cd "$T/self-victim" && cksum *.md ) > "$T/self-victim.ck"
  mv "$F/.pi/agents" "$T/self-agents-moved"; ln -s "$T/self-victim" "$F/.pi/agents"
  rm -f "$F/.pi/prompts/sdd-next.md"
  self_run "$F" --self || { cat "$OUT" >&2; fail "R10d: --self aborted on a symlinked .pi/agents"; }
  grep -c 'left unchanged and unclaimed' "$OUT" | grep -qx '[1-9][0-9]*' || fail "R10d: no 'unchanged and unclaimed' warning for a symlinked .pi/agents"
  ( cd "$T/self-victim" && cksum *.md ) | cmp -s - "$T/self-victim.ck" || fail "R10d: --self wrote through a symlinked .pi/agents"
  if grep -q '^[0-9]* [0-9]* \.pi/agents/' "$F/.claude/.glue-manifest"; then fail "R10d: a symlinked .pi/agents path was claimed in the manifest"; fi
  [ -f "$F/.pi/prompts/sdd-next.md" ] || fail "R10d: the unrelated pi prompt was not regenerated"
  F="$(self_fixture self-d2)"; self_run "$F" --self || fail "R10d: setup --self failed"
  rm -f "$F/.pi/agents/reviewer.md"; mkdir "$F/.pi/agents/reviewer.md"; echo keep > "$F/.pi/agents/reviewer.md/child"
  echo "edited, unmanifested" > "$F/.pi/agents/scout.md"; sed -i '/ \.pi\/agents\/scout\.md$/d' "$F/.claude/.glue-manifest"
  self_run "$F" --self || { cat "$OUT" >&2; fail "R10d: --self aborted on a directory/edited role file"; }
  [ "$(grep -c 'left unchanged and unclaimed' "$OUT")" = 2 ] || fail "R10d: expected 2 unclaimed warnings, got $(grep -c 'left unchanged and unclaimed' "$OUT")"
  [ -f "$F/.pi/agents/reviewer.md/child" ] || fail "R10d: the directory at .pi/agents/reviewer.md was disturbed"
  [ "$(cat "$F/.pi/agents/scout.md")" = "edited, unmanifested" ] || fail "R10d: an edited role file was overwritten"
  if grep -q ' \.pi/agents/\(scout\|reviewer\)\.md$' "$F/.claude/.glue-manifest"; then fail "R10d: an unclaimed path was recorded in the manifest"; fi
  pass "--self accepts pi, regenerates .pi/agents + .pi/prompts claimed in the manifest, refuses hostile shapes (R10)"
}

# ── R12 ────────────────────────────────────────────────────────────────────────────────────
test_pi_dispatch_prose_and_docs() {
  # (a) agents/orchestrator.md: the pi paragraph sits AFTER the Antigravity one and BEFORE the
  # `- Spawn each sub-agent` bullet — sliced by position, not a whole-file grep.
  _sec="$(awk '/^For Antigravity, because subagent personas/{k=1} /^- Spawn each sub-agent/{k=0} k' "$SRC/agents/orchestrator.md" | tr '\n' ' ')"
  _pi="${_sec#*For pi, }"
  [ "$_pi" != "$_sec" ] || fail "R12a: no 'For pi,' paragraph between the Antigravity paragraph and the Spawn bullet"
  case "$_sec" in *"For pi, "*"For Antigravity"*) fail "R12a: the pi paragraph precedes the Antigravity one" ;; esac
  for _tok in 'subagent' 'tools/pi-dispatch.sh <role> <task-file>' 'stop and report' 'never delegate the `orchestrator` role'; do
    printf '%s' "$_pi" | grep -qF -- "$_tok" || fail "R12a: the pi paragraph lacks '$_tok'"
  done
  # (b) the shared sdd-next body reaches the generated glue
  _t="$(new_target r12b)"; ok_inst --agents=claude,codex,pi "$_t"
  for _f in .claude/commands/sdd-next.md .agents/skills/sdd-next/SKILL.md; do
    grep -qF 'In pi, delegate each role' "$_t/$_f" || fail "R12b: $_f lacks the pi delegation line"
    grep -qF '.harness/tools/pi-dispatch.sh' "$_t/$_f" || fail "R12b: $_f lacks the dispatcher path"
  done
  # (c) the installer manifest text
  for _tok in '.pi/agents/*.md' '.harness/.pi-agents/' 'pi-dispatch.sh'; do
    grep -qF -- "$_tok" "$_t/.harness/manifest.txt" || fail "R12c: .harness/manifest.txt lacks '$_tok'"
  done
  # (d) the five docs
  for _d in README.md AGENTS.md docs/HARNESS.md docs/INSTALL.md docs/WORKFLOW.md; do
    grep -qF '.pi/agents' "$SRC/$_d" || fail "R12d: $_d does not mention .pi/agents"
    grep -qF 'pi-dispatch.sh' "$SRC/$_d" || fail "R12d: $_d does not mention pi-dispatch.sh"
    if grep -q 'arrives with E35-F02' "$SRC/$_d"; then fail "R12d: $_d still says role isolation arrives with E35-F02"; fi
  done
  pass "Orchestrator paragraph placement, sdd-next line, manifest text and the five docs (R12)"
}

# ── E35-F03: the hostile-pin table (ONE copy per suite; the plan's rows 1-35) ─────────────
# Fields: row-id <TAB> yaml-rhs <TAB> value-read <TAB> installer-verdict <TAB> dispatcher
# (no thinking:) <TAB> dispatcher (thinking: high). Both value fields are expanded with
# printf '%b' (bytes a here-doc cannot hold: UTF-8, ESC, TAB, newline, a literal backslash-n
# written as two backslashes). Rows 36-38 fail charset/length WITHOUT a slash, so they pin the
# check ORDER (charset and length before form: a form verdict would echo the value). @EMPTY@ is the empty value (IFS-tab would drop the field);
# @256@ / @257@ are a valid-charset id of exactly 256 / 257 bytes. A dash in a dispatcher
# column means the row cannot reach a role file.
TAB="$(printf '\t')"
pin_rows() { cat <<'PINROWS'
1	""	@EMPTY@	absent	—	—
2	"anthropic/claude-sonnet-4-5"	anthropic/claude-sonnet-4-5	ok	pass	pass
3	"openrouter/meta-llama/llama-3.1-8b-instruct:free"	openrouter/meta-llama/llama-3.1-8b-instruct:free	ok	pass	pass
4	"amazon-bedrock/anthropic.claude-3-5-sonnet-20240620-v1:0"	amazon-bedrock/anthropic.claude-3-5-sonnet-20240620-v1:0	ok	pass	pass
5	"openrouter/anthropic/claude-3.7-sonnet:thinking"	openrouter/anthropic/claude-3.7-sonnet:thinking	ok	pass	pass
6	"google-vertex/claude-sonnet-4@20250514"	google-vertex/claude-sonnet-4@20250514	ok	pass	pass
7	"Prov/id:HIGH"	Prov/id:HIGH	ok	pass	pass
8	'anthropic/claude-opus-4'	anthropic/claude-opus-4	ok	pass	pass
9	anthropic/claude-opus-4  # note	anthropic/claude-opus-4	ok	pass	pass
10	@256@	@256@	ok	pass	pass
11	@257@	@257@	length	3	3
12	"claude-sonnet"	claude-sonnet	form	pass	pass
13	"/claude"	/claude	form	pass	pass
14	"anthropic/"	anthropic/	form	pass	pass
15	"anthropic//claude"	anthropic//claude	form	pass	pass
16	"anthropic/claude/"	anthropic/claude/	form	pass	pass
17	"anthropic/claude:"	anthropic/claude:	form	pass	pass
18	"-x/claude"	-x/claude	form	3	3
19	".hidden/claude"	.hidden/claude	form	pass	pass
20	"anthropic/claude:high"	anthropic/claude:high	suffix	pass	3
21	"anthropic/claude:high:low"	anthropic/claude:high:low	suffix	pass	3
22	"anthropic/claude:max"	anthropic/claude:max	suffix	pass	3
23	"anthropic/claude sonnet"	anthropic/claude sonnet	charset	3	3
24	anthropic/claude   	anthropic/claude   	charset	3	3
25	"a/b;rm -rf ~"	a/b;rm -rf ~	charset	3	3
26	"a/$(id)"	a/$(id)	charset	3	3
27	"a/b`id`"	a/b`id`	charset	3	3
28	"a/b\\nc"	a/b\\nc	charset	3	3
29	"a/b|c"	a/b|c	charset	3	3
30	"a/b'c"	a/b'c	charset	3	3
31	"a/b\0303\0251"	a/b\0303\0251	charset	3	3
32	"a/b\0033[31m"	a/b\0033[31m	charset	3	3
33	"a/b\0011c"	a/b\0011c	charset	3	3
34	inherit	inherit	inherit	—	—
35	"a/b\n    c"	a/b	ok	pass	pass
36	"qz\0033[2Jx"	qz\0033[2Jx	charset	3	3
37	"zq zq"	zq zq	charset	3	3
38	@257N@	@257N@	length	3	3
PINROWS
}
# expand_pin <field> — decode one table value field into the real bytes.
expand_pin() {
  case "$1" in
    @EMPTY@) return 0 ;;
    @256@) printf 'p/%0254d' 0; return 0 ;;
    @257@) printf 'p/%0255d' 0; return 0 ;;
    @257N@) printf '%0257d' 0 | tr 0 ';'; return 0 ;;
  esac
  printf '%b' "$1"
}
# load_row <tab-line> — split a table line into R_ID R_RHS R_VAL R_INST R_D1 R_D2 (decoded).
load_row() {
  IFS="$TAB" read -r R_ID _r_rhs _r_val R_INST R_D1 R_D2 <<ROWEOF
$1
ROWEOF
  R_RHS="$(expand_pin "$_r_rhs"; printf x)"; R_RHS="${R_RHS%x}"
  R_VAL="$(expand_pin "$_r_val"; printf x)"; R_VAL="${R_VAL%x}"
}

# ═══ E35-F03: pi model routing ═══════════════════════════════════════════════════════════
pa_cfg() { printf '%s\n' "$1/.harness/harness.config.yaml"; }
# pa_tier <target> <role> <tier> — rewrite one `models.<role>` line.
pa_tier() {
  _c="$(pa_cfg "$1")"
  sed "s/^  $2: .*/  $2: $3/" "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  grep -q "^  $2: $3\$" "$_c" || fail "setup: could not set models.$2 = $3"
}
# pa_pin <target> <front-end> <tier> <raw-rhs> — insert `  pin.<fe>.<tier>: <rhs>` verbatim.
pa_pin() {
  _c="$(pa_cfg "$1")"
  PUT_LINE="  pin.$2.$3: $4" awk '{ print } !d && /^models:[[:space:]]*(#.*)?$/ { print ENVIRON["PUT_LINE"]; d=1 }' \
    "$_c" > "$_c.t" && mv "$_c.t" "$_c"
}
# pa_unpin <target> <front-end> <tier> — delete a pin line again.
pa_unpin() { _c="$(pa_cfg "$1")"; grep -v "^  pin\.$2\.$3:" "$_c" > "$_c.t" && mv "$_c.t" "$_c"; }
# fm_keys <file> — the frontmatter key sequence of a role file.
fm_keys() { awk 'NR==1{next} /^---$/{exit} {sub(/:.*/,""); printf "%s ", $0}' "$1"; }
# body_of <file> — everything after the closing ---.
body_of() { awk 'c>=2{print} /^---$/{c++}' "$1"; }

# ── R4: model:/thinking: lines, in order, only when non-empty ────────────────────────────
test_pi_agent_model_thinking_lines() {
  mk_bases
  _t="$(new_target r4)"; ok_inst --agents=pi --pr-loop=true "$_t"
  pa_tier "$_t" builder standard; pa_pin "$_t" pi standard '"anthropic/claude-sonnet-4-5"'
  pa_tier "$_t" reviewer reasoning; pa_tier "$_t" orchestrator cheap
  ok_inst --agents=pi --pr-loop=true "$_t"
  _base="name description"; _tail="tools systemPromptMode inheritProjectContext inheritSkills"
  [ "$(fm_keys "$_t/.pi/agents/builder.md")" = "$_base model thinking $_tail " ] || fail "R4a: builder keys: $(fm_keys "$_t/.pi/agents/builder.md")"
  [ "$(fm_keys "$_t/.pi/agents/reviewer.md")" = "$_base thinking $_tail " ] || fail "R4a: reviewer keys: $(fm_keys "$_t/.pi/agents/reviewer.md")"
  [ "$(fm_keys "$_t/.pi/agents/scout.md")" = "$_base $_tail " ] || fail "R4a: scout keys: $(fm_keys "$_t/.pi/agents/scout.md")"
  [ "$(fm_keys "$_t/.pi/agents/orchestrator.md")" = "$_base thinking $_tail allowNestedSubagents " ] \
    || fail "R4a: orchestrator keys: $(fm_keys "$_t/.pi/agents/orchestrator.md")"
  [ "$(sed -n 's/^model: //p' "$_t/.pi/agents/builder.md")" = anthropic/claude-sonnet-4-5 ] || fail "R4a: builder model value"
  [ "$(sed -n 's/^thinking: //p' "$_t/.pi/agents/builder.md")" = medium ] || fail "R4a: builder thinking value"
  for _r in $ROLES8; do
    body_of "$_t/.pi/agents/$_r.md" > "$T/r4.b1"; body_of "$FRESH/$_r.md" > "$T/r4.b2"
    cmp -s "$T/r4.b1" "$T/r4.b2" || fail "R4a: the body of $_r changed with the config"
  done
  # (b) an all-inherit install is byte-equal to the frozen E35-F02 output (30fcba3)
  diff -r "$FRESH" "$SRC/tests/fixtures/pi-agents-f02" >/dev/null \
    || fail "R4b: an all-inherit install differs from the frozen E35-F02 fixture tests/fixtures/pi-agents-f02"
  [ "$(ls "$SRC/tests/fixtures/pi-agents-f02" | wc -l | tr -d ' ')" = 8 ] || fail "R4b: the frozen fixture does not hold 8 role files"
  # (c) a re-install leaves every cksum unchanged
  _b="$(cd "$_t" && cksum .pi/agents/*.md .harness/.pi-agents/*.md)"
  ok_inst --agents=pi --pr-loop=true "$_t"
  [ "$(cd "$_t" && cksum .pi/agents/*.md .harness/.pi-agents/*.md)" = "$_b" ] || fail "R4c: a re-install changed the role files or stamps"
  # (d) pr-fixer follows models.default
  _t="$(new_target r4d)"; ok_inst --agents=pi --pr-loop=true "$_t"
  pa_tier "$_t" default cheap; ok_inst --agents=pi --pr-loop=true "$_t"
  [ "$(sed -n 's/^thinking: //p' "$_t/.pi/agents/pr-fixer.md")" = low ] || fail "R4d: pr-fixer did not follow models.default"
  grep -q '^thinking:' "$_t/.pi/agents/builder.md" && fail "R4d: an explicit inherit role followed models.default"
  pass "model:/thinking: lines: order, presence, frozen F02 baseline, idempotence, pr-fixer default (R4)"
}

# ── R5: pristine role files restamp on a config change ───────────────────────────────────
test_pi_agent_restamp_on_config_change() {
  _t="$(new_target r5)"; ok_inst --agents=pi --pr-loop=true "$_t"
  _live_eq_stamp() { for _r in $ROLES8; do cmp -s "$_t/.pi/agents/$_r.md" "$_t/.harness/.pi-agents/$_r.md" || fail "R5($1): stamp != live for $_r"; done; }
  _live_eq_stamp 1
  pa_tier "$_t" builder standard; pa_pin "$_t" pi standard '"a/one"'
  ok_inst --agents=pi --pr-loop=true "$_t"
  [ "$(sed -n 's/^model: //p' "$_t/.pi/agents/builder.md")" = a/one ] || fail "R5(2): F02-era file not restamped with the pin"
  _live_eq_stamp 2
  pa_unpin "$_t" pi standard; pa_pin "$_t" pi standard '"b/two"'
  ok_inst --agents=pi --pr-loop=true "$_t"
  [ "$(sed -n 's/^model: //p' "$_t/.pi/agents/builder.md")" = b/two ] || fail "R5(3): pin -> different pin not restamped"
  _live_eq_stamp 3
  echo "# operator edit" >> "$_t/.pi/agents/reviewer.md"; _edited="$(cksum < "$_t/.pi/agents/reviewer.md")"
  pa_tier "$_t" reviewer standard
  pa_unpin "$_t" pi standard; pa_pin "$_t" pi standard '"anthropic/claude:high"'
  ok_inst --agents=pi --pr-loop=true "$_t"
  grep -q '^model:' "$_t/.pi/agents/builder.md" && fail "R5(4): an invalid pin left model: in place"
  [ "$(sed -n 's/^thinking: //p' "$_t/.pi/agents/builder.md")" = medium ] || fail "R5(4): thinking was lost with the invalid pin"
  [ "$(cksum < "$_t/.pi/agents/reviewer.md")" = "$_edited" ] || fail "R5: an edited role file was rewritten"
  grep -q 'foreign or edited' "$OUT" || fail "R5: no F02 'foreign or edited' warning for the edited role file"
  pa_tier "$_t" builder inherit
  ok_inst --agents=pi --pr-loop=true "$_t"
  grep -qE '^(model|thinking):' "$_t/.pi/agents/builder.md" && fail "R5(5): inherit did not remove both lines"
  cmp -s "$_t/.pi/agents/builder.md" "$FRESH/builder.md" || fail "R5(5): builder is not back to the F02 bytes"
  # deselecting pi removes every pristine file (pr-fixer included) and leaves the edited one
  ok_inst --agents=claude --pr-loop=true "$_t"
  [ "$(ls "$_t/.pi/agents" 2>/dev/null | tr '\n' ' ')" = "reviewer.md " ] || fail "R5: deselect left '$(ls "$_t/.pi/agents" 2>/dev/null | tr '\n' ' ')'"
  pass "pristine role files restamp tier/pin/invalid/inherit; edited stays; deselect reclaims (R5)"
}

# ── R6: dispatcher parity with the installer's grammar ───────────────────────────────────
# role_with <target> <model-value|-> <thinking|-> — rewrite reviewer.md from the F02 bytes.
role_with() {
  { awk -v m="$2" -v th="$3" 'NR==1{print; next}
       /^description:/ { print; if (m != "-") print "model: " ENVIRON["PA_MODEL"]; if (th != "-") print "thinking: " th; next } {print}' \
       "$FRESH/reviewer.md"; } > "$1/.pi/agents/reviewer.md"
}
disp_row() { # <target> <model> <thinking|-> <expected pass|3> <label>
  _log="$T/plog"; rm -rf "$_log"
  PA_MODEL="$2" role_with "$1" "$2" "$3"
  _rc=0; run_disp "$1" "$_log" "$STUBBIN" reviewer "$T/ptask.md" || _rc=$?
  case "$4" in
    pass)
      [ "$_rc" = 0 ] || fail "R6 $5: expected pass, dispatcher exited $_rc: $(cat "$T/d.err")"
      [ "$(argv_i "$_log" 4)" = --model ] && [ "$(argv_i "$_log" 5)" = "$2" ] || fail "R6 $5: --model <value> is not argv[4..5]"
      if [ "$3" != - ]; then
        [ "$(argv_i "$_log" 6)" = --thinking ] && [ "$(argv_i "$_log" 7)" = "$3" ] && [ "$(argv_i "$_log" 8)" = --tools ] \
          || fail "R6 $5: --thinking $3 is not argv[6..7] before --tools"
      else
        [ "$(argv_i "$_log" 6)" = --tools ] || fail "R6 $5: --tools does not follow --model"
      fi ;;
    3)
      [ "$_rc" = 3 ] || fail "R6 $5: expected exit 3, got $_rc"
      [ ! -s "$T/d.out" ] || fail "R6 $5: stdout is not empty"
      case "$(sed -n 1p "$T/d.err")" in pi-dispatch:*) ;; *) fail "R6 $5: stderr does not start with pi-dispatch:" ;; esac
      [ ! -e "$_log/argv" ] || fail "R6 $5: pi was invoked" ;;
  esac
}
test_dispatch_model_thinking_parity() {
  mk_bases
  _t="$(new_target r6)"; cp -a "$T/base-true/." "$_t/"; echo task > "$T/ptask.md"
  _n=0
  while IFS= read -r _line; do
    load_row "$_line"
    [ "$R_D1" != "—" ] || continue
    disp_row "$_t" "$R_VAL" - "$R_D1" "row $R_ID/no-thinking"
    disp_row "$_t" "$R_VAL" high "$R_D2" "row $R_ID/thinking"
    # (c) the subset check, over the table itself
    if [ "$R_INST" = ok ] && { [ "$R_D1" != pass ] || [ "$R_D2" != pass ]; }; then
      fail "R6c: row $R_ID is installer-ok but the dispatcher rejects it"
    fi
    _n=$((_n + 1))
  done <<ROWS
$(pin_rows)
ROWS
  [ "$_n" -ge 36 ] || fail "R6: only $_n dispatcher rows exercised"
  # (b) dispatcher-only rows
  { awk 'NR==1{print; next} /^description:/{print; print "model: a/b"; print "model: c/d"; next} {print}' "$FRESH/reviewer.md"; } > "$_t/.pi/agents/reviewer.md"
  _rc=0; run_disp "$_t" "$T/plog2" "$STUBBIN" reviewer "$T/ptask.md" || _rc=$?; [ "$_rc" = 3 ] || fail "R6b: two model: lines -> $_rc, expected 3"
  { awk 'NR==1{print; next} /^description:/{print; print "thinking: low"; print "thinking: high"; next} {print}' "$FRESH/reviewer.md"; } > "$_t/.pi/agents/reviewer.md"
  _rc=0; run_disp "$_t" "$T/plog2" "$STUBBIN" reviewer "$T/ptask.md" || _rc=$?; [ "$_rc" = 3 ] || fail "R6b: two thinking: lines -> $_rc, expected 3"
  { awk 'NR==1{print; next} /^tools:/{print; print "tools: read,bash,edit,write"; next} {print}' "$FRESH/reviewer.md"; } > "$_t/.pi/agents/reviewer.md"
  _rc=0; run_disp "$_t" "$T/plog2" "$STUBBIN" reviewer "$T/ptask.md" || _rc=$?; [ "$_rc" = 3 ] || fail "R6b: two tools: lines -> $_rc, expected 3"
  { awk 'NR==1{print; next} /^description:/{print; print "thinking: max"; next} {print}' "$FRESH/reviewer.md"; } > "$_t/.pi/agents/reviewer.md"
  rm -rf "$T/plog2"; _rc=0; run_disp "$_t" "$T/plog2" "$STUBBIN" reviewer "$T/ptask.md" || _rc=$?; [ "$_rc" = 0 ] || fail "R6b: thinking: max -> $_rc, expected pass"
  # the suffix conflict for EVERY one of the seven levels
  for _lv in off minimal low medium high xhigh max; do
    disp_row "$_t" "a/b:$_lv" high 3 "suffix a/b:$_lv + thinking"
    disp_row "$_t" "a/b:$_lv" - pass "suffix a/b:$_lv alone"
  done
  # a bare level-word with no colon is a model name, not a suffix (the *:* guard)
  disp_row "$_t" high high pass "model: high"
  # (d) the charset bracket is textually the same in both validators
  grep -qF '[!A-Za-z0-9._:/@-]' "$INST" || fail "R6d: the installer lost the pin charset bracket"
  grep -qF '[!A-Za-z0-9._:/@-]' "$SRC/tools/pi-dispatch.sh" || fail "R6d: the dispatcher lost the pin charset bracket"
  awk '/^pi_pin_verdict\(\) \{/,/^\}/' "$INST" | grep -qF '[!A-Za-z0-9._:/@-]' || fail "R6d: the bracket is not inside pi_pin_verdict"
  # (e) an installer-stamped role file dispatches with exactly its frontmatter values
  _s="$(new_target r6e)"; ok_inst --agents=pi --pr-loop=true "$_s"
  pa_tier "$_s" builder standard; pa_pin "$_s" pi standard '"openrouter/x/y:free"'; ok_inst --agents=pi --pr-loop=true "$_s"
  rm -rf "$T/plog3"; run_disp "$_s" "$T/plog3" "$STUBBIN" builder "$T/ptask.md" || fail "R6e: an installer-stamped file did not dispatch"
  [ "$(argv_i "$T/plog3" 5)" = "$(sed -n 's/^model: //p' "$_s/.pi/agents/builder.md")" ] || fail "R6e: --model != the stamped model:"
  [ "$(argv_i "$T/plog3" 7)" = "$(sed -n 's/^thinking: //p' "$_s/.pi/agents/builder.md")" ] || fail "R6e: --thinking != the stamped thinking:"
  pass "dispatcher verdicts match the hostile-pin table; installer-ok rows all pass; stamped files dispatch verbatim (R6)"
}
# ── M4/M5 (+ the two constants): each dispatcher guard, proven by deleting it ────────────
dmut() { # <target> <old> <new> — replace exactly one occurrence in the target's dispatcher
  mutate "$1/.harness/tools/pi-dispatch.sh" "$2" "$3"
}
reaches_stub() { # <target> <model-value> <thinking|-> — does the role file reach the stub?
  rm -rf "$T/plog"; PA_MODEL="$2" role_with "$1" "$2" "$3"
  _rc=0; run_disp "$1" "$T/plog" "$STUBBIN" reviewer "$T/ptask.md" || _rc=$?
  [ "$_rc" = 0 ] && [ -e "$T/plog/argv" ]
}
test_dispatch_guard_mutation() {
  mk_bases; echo task > "$T/ptask.md"
  _t="$(new_target m45)"; cp -a "$T/base-true/." "$_t/"
  # control: the unmutated dispatcher refuses each shape
  reaches_stub "$_t" anthropic/claude:high high && fail "M4/M5 control: the real dispatcher accepted a suffix conflict"
  # M5: suffix-conflict check removed
  dmut "$_t" '  if [ -n "$thinking" ]; then
    case "${model##*:}" in' '  if false; then
    case "${model##*:}" in'
  reaches_stub "$_t" anthropic/claude:high high || fail "M5: without the suffix-conflict check row 20-with-thinking did not reach the stub"
  # M4: duplicate-key check removed
  _t="$(new_target m4)"; cp -a "$T/base-true/." "$_t/"
  dmut "$_t" '[ "$_n" -le 1 ] ||' 'true ||'
  { awk 'NR==1{print; next} /^description:/{print; print "model: a/b"; print "model: c/d"; next} {print}' "$FRESH/reviewer.md"; } > "$_t/.pi/agents/reviewer.md"
  rm -rf "$T/plog"; _rc=0; run_disp "$_t" "$T/plog" "$STUBBIN" reviewer "$T/ptask.md" || _rc=$?
  [ "$_rc" = 0 ] && [ -e "$T/plog/argv" ] || fail "M4: without the duplicate-key check two model: lines did not reach the stub"
  # the 256-byte cap and the leading-dash reject are constants too
  _t="$(new_target m6)"; cp -a "$T/base-true/." "$_t/"
  dmut "$_t" '[ "${#model}" -le 256 ] ||' 'true ||'
  _long="p/$(printf '%0255d' 0)"
  reaches_stub "$_t" "$_long" - || fail "M6: without the length cap a 257-byte model did not reach the stub"
  _t="$(new_target m7)"; cp -a "$T/base-true/." "$_t/"
  dmut "$_t" '    -*) fail 3 ' '    -zzz-no-match) fail 3 '
  reaches_stub "$_t" -x/claude - || fail "M7: without the leading-dash reject '-x/claude' did not reach the stub"
  pass "removing the duplicate-key, suffix-conflict, length or leading-dash check lets its row reach pi (M4-M7)"
}

# ── R9: pi in the escalation arming file ─────────────────────────────────────────────────
tiered_target() { # <name> <agents-csv> — builder standard / heavy reasoning, claude opus pin
  _tt="$(new_target "$1")"; ok_inst --agents="$2" --pr-loop=false "$_tt"
  pa_tier "$_tt" builder standard; pa_tier "$_tt" builder-heavy reasoning; pa_pin "$_tt" claude reasoning opus
  ok_inst --agents="$2" --pr-loop=false "$_tt"
  printf '%s\n' "$_tt"
}
test_pi_escalation_arming() {
  _b="$(tiered_target r9base claude,pi)"
  [ "$(cat "$_b/.harness/.escalation-arming")" = "armed
claude=raise
pi=raise" ] || fail "R9a: unexpected arming file: $(cat "$_b/.harness/.escalation-arming")"
  _case() { _ct="$(new_target "r9$1")"; cp -a "$_b/." "$_ct/"; printf '%s\n' "$_ct"; }
  _want() { [ "$(cat "$1/.harness/.escalation-arming")" = "blocked
claude=raise
pi=unstamped" ] || fail "R9$2: expected blocked/pi=unstamped, got: $(cat "$1/.harness/.escalation-arming")"; }
  # (b) hand-edited builder-heavy
  _x="$(_case b)"; echo "# edit" >> "$_x/.pi/agents/builder-heavy.md"; ok_inst --agents=claude,pi --pr-loop=false "$_x"; _want "$_x" b
  # (c) symlinked builder.md; the victim must not move
  _x="$(_case c)"; mkdir -p "$T/r9-victim"; cp "$_x/.pi/agents/builder.md" "$T/r9-victim/builder.md"; _vck="$(cksum < "$T/r9-victim/builder.md")"
  rm -f "$_x/.pi/agents/builder.md" "$_x/.harness/.pi-agents/builder.md"; ln -s "$T/r9-victim/builder.md" "$_x/.pi/agents/builder.md"
  ok_inst --agents=claude,pi --pr-loop=false "$_x"; _want "$_x" c
  [ "$(cksum < "$T/r9-victim/builder.md")" = "$_vck" ] || fail "R9c: the symlink victim changed"
  # (c2) a symlinked .pi/agents holding pristine copies: cmp must not be fooled
  _x="$(_case c2)"; rm -rf "$T/r9-dirvictim"; cp -a "$_x/.pi/agents" "$T/r9-dirvictim"; _dck="$(tree_snap "$T/r9-dirvictim")"
  rm -rf "$_x/.pi/agents"; ln -s "$T/r9-dirvictim" "$_x/.pi/agents"
  ok_inst --agents=claude,pi --pr-loop=false "$_x"; _want "$_x" c2
  [ "$(tree_snap "$T/r9-dirvictim")" = "$_dck" ] || fail "R9c2: the symlinked .pi/agents victim changed"
  # (d) a file-shaped .pi/agents: exit 0 (ok_inst), unstamped
  _x="$(_case d)"; rm -rf "$_x/.pi/agents"; echo foreign > "$_x/.pi/agents"; ok_inst --agents=claude,pi --pr-loop=false "$_x"; _want "$_x" d
  # (e) a pi-only all-inherit target grows no arming file
  _x="$(new_target r9e)"; ok_inst --agents=pi "$_x"
  [ ! -e "$_x/.harness/.escalation-arming" ] || fail "R9e: a pi-only all-inherit target grew an arming file"
  # (f) an edited scout does not matter
  _x="$(_case f)"; echo "# edit" >> "$_x/.pi/agents/scout.md"; ok_inst --agents=claude,pi --pr-loop=false "$_x"
  [ "$(tail -n 1 "$_x/.harness/.escalation-arming")" = pi=raise ] || fail "R9f: an edited scout.md changed the pi verdict"
  pass "pi=<verdict> line: raise, unstamped on edited/symlinked/file-shaped builder files, scout edits ignored, pi-only inherit absent (R9)"
}

# ── R10c: adding pi changes only the first line and the pi= line ─────────────────────────
test_pi_arming_preserves_other_lines() {
  _a="$(tiered_target r10a claude)"; _b="$(tiered_target r10b claude,pi)"
  sed '1d;/^pi=/d' "$_a/.harness/.escalation-arming" > "$T/r10.a"
  sed '1d;/^pi=/d' "$_b/.harness/.escalation-arming" > "$T/r10.b"
  cmp -s "$T/r10.a" "$T/r10.b" || fail "R10c: adding pi changed a non-pi arming line"
  grep -q '^pi=' "$_b/.harness/.escalation-arming" || fail "R10c: the claude,pi target lacks its pi= line"
  diff -r "$_a/.claude" "$_b/.claude" >/dev/null || fail "R10c: the .claude/ tree differs between claude and claude,pi"
  pass "adding pi to a selection leaves every other arming line and the .claude/ tree unchanged (R10)"
}

# ── R11d: docs and manifest text ─────────────────────────────────────────────────────────
test_pi_routing_docs() {
  grep -q 'pin\.pi\.' "$SRC/docs/INSTALL.md" && grep -q 'thinking' "$SRC/docs/INSTALL.md" || fail "R11d: docs/INSTALL.md lacks pin.pi. / thinking"
  grep '^| tier |' "$SRC/docs/INSTALL.md" | grep -F 'pi `model`' | grep -qF 'pi `thinking`' || fail "R11d: the INSTALL.md tier table lacks the two pi columns"
  awk 'BEGIN{RS=""} /model_reasoning_effort/ && /thinking/ {f=1} END{exit !f}' "$SRC/agents/orchestrator.md" \
    || fail "R11d: agents/orchestrator.md: no paragraph names both model_reasoning_effort and thinking"
  awk 'BEGIN{h="Which Builder runs"} /^```/{f=!f} !f && /^#+ /{k=(index($0,h)>0);next} k' "$SRC/docs/WORKFLOW.md" | tr '\n' ' ' | grep -qiE 'pi[^.]{0,200}thinking' \
    || fail "R11d: docs/WORKFLOW.md's 'Which Builder runs' section does not describe pi thinking"
  _t="$(new_target r11d)"; ok_inst --agents=pi "$_t"
  grep -qF 'resolve_pi_thinking' "$_t/.harness/manifest.txt" || fail "R11d: manifest.txt does not name resolve_pi_thinking"
  grep -qF '.pi/agents/builder' "$_t/.harness/manifest.txt" || fail "R11d: manifest.txt does not name the pi unstamped cause"
  for _d in README.md AGENTS.md docs/HARNESS.md docs/INSTALL.md docs/WORKFLOW.md; do
    tr '\n' ' ' < "$SRC/$_d" | grep -qE 'no `model:` or `thinking:`[^.]{0,60}\(E35-F03\)' && fail "R11d: $_d still says role files carry no model:/thinking: (E35-F03)"
  done
  grep -q '^## \[0.94.0\]' "$SRC/CHANGELOG.md" || fail "R11d: CHANGELOG.md lacks ## [0.94.0]"
  # E35-F04 bumped VERSION past 0.94.0; the heading check above pins the release, so this only
  # requires a well-formed semver (an equality here would red on every later release).
  grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' "$SRC/VERSION" || fail "R11d: VERSION is not a semver"
  pass "docs, manifest text, CHANGELOG and VERSION describe pi model routing (R11)"
}

# ── R12: --self resolves pi from the seed; pi=neither; the probe covers pi ───────────────
test_self_pi_arming() {
  # E35-F04 R2: --self never runs the pi preflight or any pi command. A logging stub pi sits on
  # PATH for every --self run in this test; its log must stay empty.
  _sa_bin="$T/selfarm-bin"; _sa_log="$T/selfarm-pi.log"; mkdir -p "$_sa_bin"; : > "$_sa_log"
  printf '#!/bin/sh\necho "$*" >> "%s"\nexit 0\n' "$_sa_log" > "$_sa_bin/pi"; chmod +x "$_sa_bin/pi"
  SANDBOX_PATH_SAVED="$SANDBOX_PATH"; SANDBOX_PATH="$_sa_bin:$SANDBOX_PATH"
  F="$(self_fixture selfarm-a)"; rm -f "$F/.escalation-arming"
  self_run "$F" --self || { cat "$OUT" >&2; fail "R12: --self exited non-zero"; }
  # (a) byte-equal to the committed role files, and no model/thinking lines
  diff -r "$F/.pi/agents" "$SRC/.pi/agents" >/dev/null || fail "R12a: regenerated .pi/agents differs from the committed files"
  grep -qE '^(model|thinking):' "$F"/.pi/agents/*.md && fail "R12a: a source role file carries model:/thinking:"
  # (b) the 5-line arming text
  [ "$(cat "$F/.escalation-arming")" = "blocked
claude=raise
codex=neither
opencode=neither
pi=neither" ] || fail "R12b: unexpected source arming file: $(cat "$F/.escalation-arming")"
  cmp -s "$F/.escalation-arming" "$SRC/.escalation-arming" || fail "R12b: the committed .escalation-arming differs from what --self writes"
  # (d) a second --self is a byte no-op, arming and manifest included
  ( cd "$F" && cksum .escalation-arming .claude/.glue-manifest ) > "$T/selfarm.b1"
  self_run "$F" --self || fail "R12d: second --self failed"
  ( cd "$F" && cksum .escalation-arming .claude/.glue-manifest ) | cmp -s - "$T/selfarm.b1" || fail "R12d: a second --self changed the arming file or manifest"
  # (c) the source unstamped probe covers the pi Builder files
  F="$(self_fixture selfarm-c)"; self_run "$F" --self || fail "R12c: setup --self failed"
  echo "# hand edit" >> "$F/.pi/agents/builder-heavy.md"
  self_run "$F" --self || { cat "$OUT" >&2; fail "R12c: --self failed over an edited builder-heavy.md"; }
  [ "$(sed -n 's/^pi=//p' "$F/.escalation-arming")" = unstamped ] || fail "R12c: an edited .pi/agents/builder-heavy.md did not read pi=unstamped: $(cat "$F/.escalation-arming")"
  [ "$(sed -n 1p "$F/.escalation-arming")" = blocked ] || fail "R12c: the first line is not blocked"
  SANDBOX_PATH="$SANDBOX_PATH_SAVED"
  [ ! -s "$_sa_log" ] || fail "E35-F04 R2: --self executed pi: $(cat "$_sa_log")"
  ! grep -q 'pi preflight' "$OUT" || fail "E35-F04 R2: --self printed a pi preflight line"
  pass "--self: pi=neither from the seed, committed bytes unchanged, probe covers pi, second run no-op, no pi executed (R12)"
}

# ── runner ─────────────────────────────────────────────────────────────────────────────────
if [ "$CELLMODE" = 1 ]; then
  # --cell "<comp> <shape> <op> <outcome> <warnings> <kind>": one matrix cell, run by xargs.
  set -- $CELLROW
  run_cell "$1" "$2" "$3" "$4" "$5" "$6"
  echo "cell-ok $1:$2:$3"
  exit 0
fi

test_pi_agent_files_set_and_frontmatter
test_no_pi_agents_when_unselected
test_tool_translation_table
test_pi_agent_body_pointer
test_pi_agent_shape_matrix
test_pi_agent_reclaim
test_pi_unit_hardlink_not_written_through
test_dispatch_argv_and_passthrough
test_dispatch_fail_closed
test_pi_agents_owned_paths
test_self_emits_pi
test_pi_dispatch_prose_and_docs
test_pi_agent_model_thinking_lines
test_pi_agent_restamp_on_config_change
test_dispatch_model_thinking_parity
test_dispatch_guard_mutation
test_pi_escalation_arming
test_pi_arming_preserves_other_lines
test_pi_routing_docs
test_self_pi_arming
echo "All pi role sub-agent tests passed."
