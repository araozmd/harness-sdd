#!/bin/sh
# test_update_check.sh — behavioral verification for E38-F01 (init.sh update check +
# consented upgrade with custom-config preservation).
#
# Every case builds a REAL installed target (git init + harness-install.sh + commit), serves
# a REAL git repository over file:// as "the harness remote", perturbs exactly one thing and
# runs the installed .harness/init.sh. Nothing touches the network: every gate run passes
# HARNESS_UPDATE_REMOTE=file://... (the default is an unreachable file:// path, never the
# public URL), and remote contact is READ FROM A git SHIM'S CALL LOG, not inferred from output.
#
# ANTI-TAUTOLOGY (the E24-F01 rule). Most requirements assert an absence (no line, no prompt,
# no contact). A check that does nothing at all satisfies all of them, so each absence is paired
# with a POSITIVE CONTROL on the same fixture that differs in exactly one input and does print /
# prompt / contact. An expected value with more than one producing code path proves nothing.
#
# Suite-wide constraints (permanent-suite anti-pattern): no VERSION literal (CUR is read, NEXT
# is derived), no diff against main, no DO-NOT-TOUCH diff, CODEX_HOME AND HOME sandboxed, both
# traps. The runner exports HARNESS_SKIP_UPDATE_CHECK=1 for the whole tree; every gate run
# here re-enables the check per call with HARNESS_SKIP_UPDATE_CHECK= (empty), so this suite
# does not depend on the runner. Must pass under dash.

set -eu
LC_ALL=C; export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-update)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)

REAL_PATH="$PATH"
REAL_GIT="$(command -v git)" || fail "git is not on PATH — a hard harness prerequisite"
export CODEX_HOME="$T/codex-home" HOME="$T/home"
mkdir -p "$CODEX_HOME" "$HOME"

# ── versions: derived, never a literal ────────────────────────────────────────────────
CUR="$(tr -d ' \r\n' < "$SRC/VERSION")"
_maj="${CUR%%.*}"; _rest="${CUR#*.}"; _min="${_rest%%.*}"
NEXT="$_maj.$((_min + 1)).0"
NEXT2="$_maj.$((_min + 2)).0"
OLDER="0.0.1"

# ── remote fixtures ───────────────────────────────────────────────────────────────────
copy_src() { # <dest> — the source tree minus VCS / heavy dirs
  mkdir -p "$1"
  for _e in "$SRC"/* "$SRC"/.[!.]*; do
    [ -e "$_e" ] || continue
    case "$(basename "$_e")" in .git|.worktrees|node_modules|scratchpad) continue ;; esac
    cp -R "$_e" "$1/"
  done
}

rgit() { _d="$1"; shift; git -C "$_d" -c user.email=test@harness.local -c user.name="harness test" "$@"; }

insert_after_set_eu() { # <installer> <snippet-file> — keeps the installer's mode
  awk -v f="$2" '{ print } !d && /^set -eu$/ { while ((getline l < f) > 0) print l; d = 1 }' "$1" > "$1.new"
  cat "$1.new" > "$1"; rm -f "$1.new"
}

bump_commit() { # <dir> <version> [snippet-file] — the incoming release
  printf '%s\n' "$2" > "$1/VERSION"
  echo '# E38 marker' >> "$1/agents/scout.md"
  [ -z "${3:-}" ] || insert_after_set_eu "$1/harness-install.sh" "$3"
  rgit "$1" add -A
  rgit "$1" commit -q -m "release $2"
}

build_remote() { # <dir> <kind>
  _bd="$1"; _bk="$2"
  copy_src "$_bd"
  git -C "$_bd" init -q .
  rgit "$_bd" add -A
  rgit "$_bd" commit -q -m "base"
  _snip=""
  case "$_bk" in
    same)   rgit "$_bd" tag "v$CUR" ;;
    older)  rgit "$_bd" tag "v$OLDER" ;;
    junk)   rgit "$_bd" tag "v$CUR"; rgit "$_bd" tag nightly; rgit "$_bd" tag v1.2; rgit "$_bd" tag v9.9.9-rc1 ;;
    newer*)
      rgit "$_bd" tag "v$CUR"
      case "$_bk" in
        newer-argvlog)
          printf '%s\n' '[ -z "${E38_ARGV_LOG:-}" ] || printf '"'"'%s\n'"'"' "$*" >> "$E38_ARGV_LOG"' > "$T/snip.$_bk"
          _snip="$T/snip.$_bk" ;;
        newer-badinstaller-config)
          cat > "$T/snip.$_bk" <<'EOS'
for _e38 in "$@"; do :; done
if [ -f "$_e38/.harness/harness.config.yaml" ]; then
  awk '/^[[:space:]]*test_command:/ { print "  test_command: \"HIJACKED\""; next } { print }' "$_e38/.harness/harness.config.yaml" > "$_e38/.harness/cfg.e38" \
    && mv "$_e38/.harness/cfg.e38" "$_e38/.harness/harness.config.yaml"
fi
EOS
          _snip="$T/snip.$_bk" ;;
        newer-badinstaller-claude)
          cat > "$T/snip.$_bk" <<'EOS'
for _e38 in "$@"; do :; done
[ ! -f "$_e38/CLAUDE.md" ] || printf 'TAMPERED outside the block\n' >> "$_e38/CLAUDE.md"
EOS
          _snip="$T/snip.$_bk" ;;
      esac
      bump_commit "$_bd" "$NEXT" "$_snip"
      rgit "$_bd" tag "v$NEXT"
      case "$_bk" in
        newer+junk) rgit "$_bd" tag nightly; rgit "$_bd" tag v1.2; rgit "$_bd" tag v9.9.9-rc1 ;;
        newer2) bump_commit "$_bd" "$NEXT2"; rgit "$_bd" tag "v$NEXT2" ;;
        newer-nobase) rgit "$_bd" tag -d "v$CUR" >/dev/null ;;
      esac ;;
    *) fail "unknown remote kind $_bk" ;;
  esac
}

remote_url() { # <kind> — file:// URL of the (memoised) remote of that kind
  _rd="$T/remote-$1"
  [ -d "$_rd/.git" ] || build_remote "$_rd" "$1"
  printf 'file://%s' "$_rd"
}

# ── git shim: logs every call; modes log | hang | fail-fetch ──────────────────────────
git_shim() { # <mode> — prints the shim dir
  _sd="$T/shim-$1"
  if [ ! -x "$_sd/git" ]; then
    mkdir -p "$_sd"
    cat > "$_sd/git" <<EOS
#!/bin/sh
echo "\$*" >> "$T/git-calls"
sub=""
for a in "\$@"; do case "\$a" in ls-remote|clone|fetch) sub=\$a; break ;; esac; done
case "$1:\$sub" in
  hang:ls-remote) sleep 37; exit 1 ;;
  fail-fetch:clone|fail-fetch:fetch) echo "shim: refusing \$sub" >&2; exit 128 ;;
esac
exec "$REAL_GIT" "\$@"
EOS
    chmod +x "$_sd/git"
  fi
  printf '%s' "$_sd"
}

# a PATH holding every executable the real PATH holds EXCEPT git (the gate still needs python3,
# bash, awk, ... — only `git` must be absent)
nogit_path() {
  _fd="$T/nogit-bin"
  if [ ! -d "$_fd" ]; then
    mkdir -p "$_fd"
    _oifs="$IFS"; IFS=:
    for _pd in $REAL_PATH; do
      [ -d "$_pd" ] || continue
      for _pf in "$_pd"/*; do
        _pb="$(basename "$_pf")"
        [ "$_pb" = git ] && continue
        [ -e "$_fd/$_pb" ] || ln -s "$_pf" "$_fd/$_pb" 2>/dev/null || true
      done
    done
    IFS="$_oifs"
  fi
  printf '%s' "$_fd"
}

# ── target fixtures ───────────────────────────────────────────────────────────────────
mk_template() { # <dir> [agents]
  mkdir -p "$1"
  git -C "$1" init -q .
  git -C "$1" config user.email "test@harness.local"
  git -C "$1" config user.name  "harness test"
  sh "$SRC/harness-install.sh" --agents="${2:-claude}" "$1" >/dev/null 2>&1 \
    || fail "harness-install.sh exited non-zero for $1"
  [ -f "$1/.harness/.harness-version" ] || fail "install produced no .harness-version in $1"
  git -C "$1" add -A
  git -C "$1" commit -q -m "installed harness"
  [ -z "$(git -C "$1" status --porcelain)" ] || fail "fixture $1 is dirty right after commit"
}
mk_template "$T/tpl"

mk_target() { cp -R "$T/tpl" "$1"; }   # a fresh, committed, installed single-repo target
commit_all() { git -C "$1" add -A && git -C "$1" commit -q -m "${2:-local edit}"; }

# run_gate <dir> <typed> [VAR=val ...] — GATE_OUT / GATE_RC / GATE_SECS; $SHIM_MODE picks the
# shim (default log); $GATE_PATH overrides PATH entirely.
run_gate() {
  _gd="$1"; _gt="$2"; shift 2
  : > "$T/git-calls"
  _gp="${GATE_PATH:-$(git_shim "${SHIM_MODE:-log}"):$REAL_PATH}"
  _g0="$(date +%s)"
  GATE_OUT="$(cd "$_gd" && printf '%b' "$_gt" | env PATH="$_gp" HARNESS_SKIP_UPDATE_CHECK= \
      HARNESS_UPDATE_REMOTE=file:///nonexistent "$@" ./.harness/init.sh 2>&1)" && GATE_RC=0 || GATE_RC=$?
  GATE_SECS=$(( $(date +%s) - _g0 ))
  # the script must actually have executed (interpreter death is not a verdict)
  case "$GATE_OUT" in
    *"harness-sdd init"*) : ;;
    *) fail "init.sh did not execute in $_gd (no banner): $GATE_OUT" ;;
  esac
}

ls_calls() { grep -c 'ls-remote' "$T/git-calls" 2>/dev/null || true; }
bell_n()   { printf '%s\n' "$GATE_OUT" | grep -c '🔔' || true; }
has()      { printf '%s\n' "$1" | grep -qF -- "$2"; }
stamp()    { tr -d ' \r\n' < "$1/.harness/.harness-version"; }
rec()      { sed -n "s/^$2=//p" "$1/.harness/progress/update-check/last" 2>/dev/null | head -n 1; }
NOTICE="🔔 harness v$NEXT available (installed v$CUR)"

# ═════════════════════════════════════════════════════════════════════════════════════
# R1 — the notice
# ═════════════════════════════════════════════════════════════════════════════════════
R1_notice_when_newer() {
  _u="$(remote_url newer)"
  mk_target "$T/r1"
  # the baseline: the same target with the check switched off
  run_gate "$T/r1" "" HARNESS_SKIP_UPDATE_CHECK=1
  _off_out="$GATE_OUT"; _off_rc="$GATE_RC"
  [ "$_off_rc" = 0 ] || fail "R1 C10: disabled baseline run failed (rc=$_off_rc): $_off_out"
  run_gate "$T/r1" "" HARNESS_UPDATE_REMOTE="$_u"
  [ "$GATE_RC" = "$_off_rc" ] || fail "R1 C10: the notice changed the gate exit code ($_off_rc -> $GATE_RC)"
  [ "$(bell_n)" = 1 ] || fail "R1 C10: expected exactly one 🔔 line, got $(bell_n): $GATE_OUT"
  printf '%s\n' "$GATE_OUT" | grep -qxF "$NOTICE" \
    || fail "R1 C10: the notice is not exactly '$NOTICE': $GATE_OUT"
  [ "$(printf '%s\n' "$GATE_OUT" | grep -v '🔔')" = "$(printf '%s\n' "$_off_out")" ] \
    || fail "R1 C10: a non-🔔 gate line differs from the disabled run"
  pass "newer tag => exactly one notice line, every other line and the exit code unchanged (R1) [R1_notice_when_newer]"
}

# ═════════════════════════════════════════════════════════════════════════════════════
# R2 — silent skips, each with a positive control
# ═════════════════════════════════════════════════════════════════════════════════════
R2_silent_skips_table() {
  _u="$(remote_url newer)"
  # C1 — source layout (no .harness-version): the harness's own gate, copied
  copy_src "$T/r2-src"
  [ ! -e "$T/r2-src/.harness-version" ] || fail "R2 C1: the source layout carries a .harness-version"
  : > "$T/git-calls"
  _c1="$(cd "$T/r2-src" && env PATH="$(git_shim log):$REAL_PATH" HARNESS_SKIP_UPDATE_CHECK= HARNESS_UPDATE_REMOTE="$_u" \
          HARNESS_UPDATE_ASSUME_TTY=1 ./init.sh 2>&1 </dev/null)" || true
  has "$_c1" "harness-sdd init" || fail "R2 C1: the source gate did not execute: $_c1"
  has "$_c1" "harness v" && fail "R2 C1: the source layout printed an update line: $_c1"
  [ "$(ls_calls)" = 0 ] || fail "R2 C1: the source layout contacted the remote"

  # C2 — env opt-out; control: the same run with the env empty
  mk_target "$T/r2-env"
  run_gate "$T/r2-env" "y\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1 HARNESS_SKIP_UPDATE_CHECK=1
  [ "$GATE_RC" = 0 ] || fail "R2 C2: opt-out run failed: $GATE_OUT"
  [ "$(bell_n)" = 0 ] && ! has "$GATE_OUT" "Install now?" || fail "R2 C2: the env opt-out was not silent: $GATE_OUT"
  [ "$(ls_calls)" = 0 ] || fail "R2 C2: the env opt-out contacted the remote"
  [ "$(stamp "$T/r2-env")" = "$CUR" ] || fail "R2 C2: the stamp changed"
  [ ! -e "$T/r2-env/.harness/progress/update-check" ] || fail "R2 C2: the opt-out still wrote a cache record"
  run_gate "$T/r2-env" "n\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$(bell_n)" = 1 ] && [ "$(ls_calls)" = 1 ] || fail "R2 C2 control: env empty did not produce the notice + one contact: $GATE_OUT"

  # C3 — config opt-out (update.check: false); control: true
  mk_target "$T/r2-cfg"
  grep -q '^  check: true' "$T/r2-cfg/.harness/harness.config.yaml" \
    || fail "R2 C3 precondition: the shipped config has no 'update: check: true'"
  sed '/^update:/,/^[^ #]/s/^  check: true/  check: false/' "$T/r2-cfg/.harness/harness.config.yaml" > "$T/r2-cfg.yaml"
  cat "$T/r2-cfg.yaml" > "$T/r2-cfg/.harness/harness.config.yaml"
  grep -q '^  check: false' "$T/r2-cfg/.harness/harness.config.yaml" || fail "R2 C3 precondition: the edit did not apply"
  run_gate "$T/r2-cfg" "y\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 0 ] && [ "$(bell_n)" = 0 ] && ! has "$GATE_OUT" "Install now?" \
    || fail "R2 C3: config opt-out was not silent: $GATE_OUT"
  [ "$(ls_calls)" = 0 ] || fail "R2 C3: config opt-out contacted the remote"
  sed '/^update:/,/^[^ #]/s/^  check: false/  check: true/' "$T/r2-cfg/.harness/harness.config.yaml" > "$T/r2-cfg.yaml"
  cat "$T/r2-cfg.yaml" > "$T/r2-cfg/.harness/harness.config.yaml"
  run_gate "$T/r2-cfg" "" HARNESS_UPDATE_REMOTE="$_u"
  [ "$(bell_n)" = 1 ] || fail "R2 C3 control: check: true did not produce the notice: $GATE_OUT"

  # C4 — umbrella child (umbrella.root non-empty); control: cleared
  mk_target "$T/r2-child"
  grep -q '^  root: ""' "$T/r2-child/.harness/harness.config.yaml" || fail "R2 C4 precondition: no 'root: \"\"' line"
  sed 's|^  root: ""|  root: "/some/umbrella"|' "$T/r2-child/.harness/harness.config.yaml" > "$T/r2-child.yaml"
  cat "$T/r2-child.yaml" > "$T/r2-child/.harness/harness.config.yaml"
  run_gate "$T/r2-child" "y\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 0 ] && [ "$(bell_n)" = 0 ] && ! has "$GATE_OUT" "Install now?" \
    || fail "R2 C4: an umbrella child was not silent: $GATE_OUT"
  [ "$(ls_calls)" = 0 ] || fail "R2 C4: an umbrella child contacted the remote"
  sed 's|^  root: "/some/umbrella"|  root: ""|' "$T/r2-child/.harness/harness.config.yaml" > "$T/r2-child.yaml"
  cat "$T/r2-child.yaml" > "$T/r2-child/.harness/harness.config.yaml"
  run_gate "$T/r2-child" "" HARNESS_UPDATE_REMOTE="$_u"
  [ "$(bell_n)" = 1 ] || fail "R2 C4 control: clearing umbrella.root did not produce the notice: $GATE_OUT"

  # C5 — git absent from PATH; control: the real PATH
  mk_target "$T/r2-nogit"
  _np="$(nogit_path)"
  PATH="$_np" command -v git >/dev/null 2>&1 && fail "R2 C5 precondition: git is still reachable on the sandbox PATH"
  GATE_PATH="$_np" run_gate "$T/r2-nogit" "" HARNESS_UPDATE_REMOTE="$_u"
  [ "$GATE_RC" = 0 ] && [ "$(bell_n)" = 0 ] && ! has "$GATE_OUT" "harness v" \
    || fail "R2 C5: a git-less PATH changed the gate (rc=$GATE_RC): $GATE_OUT"
  run_gate "$T/r2-nogit" "" HARNESS_UPDATE_REMOTE="$_u"
  [ "$(bell_n)" = 1 ] || fail "R2 C5 control: the real PATH did not produce the notice: $GATE_OUT"
  pass "source layout / env / config / umbrella child / no git => no contact, no line; each control prints (R2) [R2_silent_skips_table]"
}

# ═════════════════════════════════════════════════════════════════════════════════════
# R4 — same / older / junk are silent; junk never takes part in the maximum
# ═════════════════════════════════════════════════════════════════════════════════════
R4_same_older_junk_silent() {
  for _k in same older junk; do
    mk_target "$T/r4-$_k"
    run_gate "$T/r4-$_k" "" HARNESS_UPDATE_REMOTE="$(remote_url "$_k")"
    [ "$GATE_RC" = 0 ] || fail "R4 ($_k): gate rc=$GATE_RC: $GATE_OUT"
    [ "$(bell_n)" = 0 ] && ! has "$GATE_OUT" "available" || fail "R4 ($_k): printed an update line: $GATE_OUT"
    [ "$(ls_calls)" = 1 ] || fail "R4 ($_k): expected one remote contact (the silence must come from the verdict), got $(ls_calls)"
    has "$GATE_OUT" "9.9.9" && fail "R4 ($_k): a pre-release tag leaked into the output"
  done
  mk_target "$T/r4-nj"
  run_gate "$T/r4-nj" "" HARNESS_UPDATE_REMOTE="$(remote_url newer+junk)"
  printf '%s\n' "$GATE_OUT" | grep -qxF "$NOTICE" || fail "R4 C9d: newer+junk did not report v$NEXT: $GATE_OUT"
  has "$GATE_OUT" "9.9.9" && fail "R4 C9d: v9.9.9-rc1 took part in the maximum"
  pass "same / older / junk-only are silent with one contact; newer+junk still names v$NEXT, never 9.9.9 (R4) [R4_same_older_junk_silent]"
}

# ═════════════════════════════════════════════════════════════════════════════════════
# R3 — failure is silent, bounded and cached
# ═════════════════════════════════════════════════════════════════════════════════════
R3_failure_silent_bounded_cached() {
  # C7 — unreachable remote
  mk_target "$T/r3-fail"
  run_gate "$T/r3-fail" "y\n" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 0 ] || fail "R3 C7: a failing remote changed the gate exit code: $GATE_OUT"
  [ "$(bell_n)" = 0 ] && ! has "$GATE_OUT" "Install now?" || fail "R3 C7: a failing remote printed something: $GATE_OUT"
  [ "$(ls_calls)" = 1 ] || fail "R3 C7: expected exactly one contact, got $(ls_calls)"
  [ -f "$T/r3-fail/.harness/progress/update-check/last" ] || fail "R3 C7: the failed attempt was not recorded"
  [ -n "$(rec "$T/r3-fail" checked)" ] && [ -z "$(rec "$T/r3-fail" latest)" ] \
    || fail "R3 C7: record should carry checked=<time> and an empty latest"
  [ "$(stamp "$T/r3-fail")" = "$CUR" ] || fail "R3 C7: stamp changed"
  # C8b — failure cached: a second run inside the TTL makes no call
  run_gate "$T/r3-fail" "" HARNESS_UPDATE_REMOTE=file:///nonexistent
  [ "$(ls_calls)" = 0 ] || fail "R3 C8b: the failure was not cached — the remote was contacted again"
  [ "$(bell_n)" = 0 ] || fail "R3 C8b: printed a notice from a failed record"
  # positive control for the cache assertion: the same target, TTL=0, DOES contact again
  run_gate "$T/r3-fail" "" HARNESS_UPDATE_REMOTE=file:///nonexistent HARNESS_UPDATE_TTL=0
  [ "$(ls_calls)" = 1 ] || fail "R3 C8b control: TTL=0 did not re-contact the remote"

  # C8 — a hanging remote is abandoned at the bound
  mk_target "$T/r3-hang"
  run_gate "$T/r3-hang" "" HARNESS_SKIP_UPDATE_CHECK=1
  _base="$GATE_SECS"
  SHIM_MODE=hang run_gate "$T/r3-hang" "" HARNESS_UPDATE_REMOTE="$(remote_url newer)" HARNESS_UPDATE_TIMEOUT=2
  [ "$GATE_RC" = 0 ] || fail "R3 C8: a hanging remote changed the exit code: $GATE_OUT"
  [ "$(bell_n)" = 0 ] || fail "R3 C8: printed a notice though the remote never answered"
  [ "$(ls_calls)" = 1 ] || fail "R3 C8: expected one (hung) contact, got $(ls_calls)"
  [ "$GATE_SECS" -le $((_base + 2 + 3)) ] || fail "R3 C8: the gate took ${GATE_SECS}s, bound is baseline ${_base}s + 2s + 3s margin"
  [ "$GATE_SECS" -ge $((_base + 1)) ] || fail "R3 C8 control: the gate was not delayed (${GATE_SECS}s vs ${_base}s) — the shim did not hang"
  ps -ax -o command 2>/dev/null | grep -q '[s]leep 37' && fail "R3 C8: an orphan 'sleep 37' outlived the gate"
  [ -n "$(rec "$T/r3-hang" checked)" ] && [ -z "$(rec "$T/r3-hang" latest)" ] || fail "R3 C8: the abandoned attempt was not cached as a failure"
  pass "failing and hanging remotes: silent, exit unchanged, bounded, failure cached (R3) [R3_failure_silent_bounded_cached]"
}

# ═════════════════════════════════════════════════════════════════════════════════════
# R5 — cache and TTL
# ═════════════════════════════════════════════════════════════════════════════════════
R5_cache_ttl() {
  # C4b — the record is written, in an ignored place
  mk_target "$T/r5"
  run_gate "$T/r5" "" HARNESS_UPDATE_REMOTE="$(remote_url newer)"
  [ "$(ls_calls)" = 1 ] && [ "$(bell_n)" = 1 ] || fail "R5 C4b: expected one contact and the notice"
  [ "$(rec "$T/r5" latest)" = "v$NEXT" ] || fail "R5 C4b: record latest is '$(rec "$T/r5" latest)', want v$NEXT"
  case "$(rec "$T/r5" checked)" in ''|*[!0-9]*) fail "R5 C4b: record has no epoch 'checked'" ;; esac
  git -C "$T/r5" check-ignore -q .harness/progress/update-check/last \
    || fail "R5 C4b: the cache record is not ignored by the target's VCS"
  # C6 — a fresh record answers with the remote UNREACHABLE and zero contacts
  run_gate "$T/r5" "" HARNESS_UPDATE_REMOTE=file:///nonexistent
  [ "$(ls_calls)" = 0 ] || fail "R5 C6: a fresh record still contacted the remote"
  printf '%s\n' "$GATE_OUT" | grep -qxF "$NOTICE" || fail "R5 C6: the notice was not derived from the record: $GATE_OUT"
  # C6b — stale (TTL=0): one contact, record rewritten with the verdict of the new answer
  run_gate "$T/r5" "" HARNESS_UPDATE_REMOTE="$(remote_url same)" HARNESS_UPDATE_TTL=0
  [ "$(ls_calls)" = 1 ] || fail "R5 C6b: TTL=0 did not re-contact the remote"
  [ "$(bell_n)" = 0 ] || fail "R5 C6b: printed a notice for a remote that has nothing newer"
  [ "$(rec "$T/r5" latest)" = "v$CUR" ] || fail "R5 C6b: record not rewritten (latest='$(rec "$T/r5" latest)')"
  pass "record written + ignored; fresh record serves the notice with zero contacts; TTL=0 re-checks and rewrites (R5) [R5_cache_ttl]"
}

# ═════════════════════════════════════════════════════════════════════════════════════
# R6 — prompt only when interactive
# ═════════════════════════════════════════════════════════════════════════════════════
ptyrun_py() {
  [ -f "$T/ptyrun.py" ] || cat > "$T/ptyrun.py" <<'PYPTY'
# usage: ptyrun.py <modeflags subset of i,o,e> <typed (python escapes)> <outbase> -- cmd...
import codecs, os, pty, select, subprocess, sys, time
mode, typed, base = sys.argv[1], codecs.decode(sys.argv[2], "unicode_escape").encode(), sys.argv[3]
cmd = sys.argv[5:]
m, s = pty.openpty()
w = None
if "i" in mode:
    sin = s
else:
    r, w = os.pipe(); sin = r
sout = s if "o" in mode else os.open(base + ".out", os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
serr = s if "e" in mode else os.open(base + ".err", os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
p = subprocess.Popen(cmd, stdin=sin, stdout=sout, stderr=serr, close_fds=True)
os.close(s)
if w is not None:
    os.close(r)
    os.write(w, typed)
    os.close(w)
else:
    os.write(m, typed)
buf = b""
dead = time.monotonic() + 90
while True:
    if time.monotonic() > dead:
        p.kill()
        break
    r_, _, _ = select.select([m], [], [], 0.2)
    if r_:
        try:
            c = os.read(m, 4096)
        except OSError:
            break
        if not c:
            break
        buf += c
    elif p.poll() is not None:
        break
p.wait()
with open(base + ".tty", "wb") as fh:
    fh.write(buf)
with open(base + ".rc", "w") as fh:
    fh.write(str(p.returncode))
for f in ("out", "err"):
    if not os.path.exists(base + "." + f):
        open(base + "." + f, "w").close()
PYPTY
}

pty_gate() { # <dir> <mode i/o/e> <typed> <base> <remote> — a REAL pseudo-terminal run of the gate
  ptyrun_py
  ( cd "$1" && python3 "$T/ptyrun.py" "$2" "$3" "$4" -- env PATH="$(git_shim log):$REAL_PATH" \
      HARNESS_SKIP_UPDATE_CHECK= HARNESS_UPDATE_REMOTE="$5" ./.harness/init.sh ) \
    || fail "pty runner failed"
  PTY_RC="$(cat "$4.rc")"
  PTY_OUT="$(cat "$4.out" "$4.tty" | tr -d '\r')"
}

R6_prompt_only_interactive() {
  _u="$(remote_url newer)"
  # C11 — interactive, answer n
  mk_target "$T/r6"
  run_gate "$T/r6" "n\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 0 ] || fail "R6 C11: declining changed the gate exit code ($GATE_RC): $GATE_OUT"
  has "$GATE_OUT" "Install now? [y/N]" || fail "R6 C11: no prompt: $GATE_OUT"
  [ "$(bell_n)" = 1 ] || fail "R6 C11: expected the notice"
  # the prompt comes AFTER the notice
  [ "$(printf '%s\n' "$GATE_OUT" | grep -n '🔔' | head -n1 | cut -d: -f1)" -lt "$(printf '%s\n' "$GATE_OUT" | grep -n 'Install now?' | head -n1 | cut -d: -f1)" ] \
    || fail "R6 C11: the prompt is not after the notice"
  has "$GATE_OUT" "environment ready" || fail "R6 C11: the gate did not run to completion after declining"
  [ "$(rec "$T/r6" declined)" = "v$NEXT" ] || fail "R6 C11: declined version not recorded (got '$(rec "$T/r6" declined)')"
  [ "$(stamp "$T/r6")" = "$CUR" ] || fail "R6 C11: declining changed the stamp"
  # C12 — declined: the notice without the prompt, and the typed y is never consumed
  run_gate "$T/r6" "y\n" HARNESS_UPDATE_REMOTE=file:///nonexistent HARNESS_UPDATE_ASSUME_TTY=1
  [ "$(ls_calls)" = 0 ] || fail "R6 C12: a fresh record contacted the remote"
  [ "$(bell_n)" = 1 ] && ! has "$GATE_OUT" "Install now?" || fail "R6 C12: declined version should notice without prompting: $GATE_OUT"
  [ "$GATE_RC" = 0 ] && [ "$(stamp "$T/r6")" = "$CUR" ] || fail "R6 C12: the typed y was consumed (rc=$GATE_RC)"
  # C12b — a higher version prompts again
  run_gate "$T/r6" "n\n" HARNESS_UPDATE_REMOTE="$(remote_url newer2)" HARNESS_UPDATE_ASSUME_TTY=1 HARNESS_UPDATE_TTL=0
  [ "$(ls_calls)" = 1 ] || fail "R6 C12b: TTL=0 should contact once"
  printf '%s\n' "$GATE_OUT" | grep -qxF "🔔 harness v$NEXT2 available (installed v$CUR)" || fail "R6 C12b: no notice for v$NEXT2: $GATE_OUT"
  has "$GATE_OUT" "Install now? [y/N]" || fail "R6 C12b: a higher version did not prompt again"
  [ "$(rec "$T/r6" declined)" = "v$NEXT2" ] || fail "R6 C12b: declined not updated to v$NEXT2"
  # C13 — not interactive: typed y,y is never read, nothing happens
  mk_target "$T/r6-nt"
  run_gate "$T/r6-nt" "y\ny\n" HARNESS_UPDATE_REMOTE="$_u"
  [ "$GATE_RC" = 0 ] && [ "$(bell_n)" = 1 ] && ! has "$GATE_OUT" "Install now?" || fail "R6 C13: non-TTY must notice without prompting: $GATE_OUT"
  [ "$(stamp "$T/r6-nt")" = "$CUR" ] && [ ! -e "$T/r6-nt/.harness/progress/upgrade-backup" ] \
    || fail "R6 C13: a y typed off a terminal started an upgrade"
  # C21 — a real pty on stdin AND stdout prompts with no env hook
  mk_target "$T/r6-pty"
  pty_gate "$T/r6-pty" io 'n\n' "$T/pty21" "$_u"
  [ "$PTY_RC" = 0 ] || fail "R6 C21: pty gate rc=$PTY_RC: $PTY_OUT"
  has "$PTY_OUT" "Install now? [y/N]" || fail "R6 C21: a real terminal was not prompted: $PTY_OUT"
  [ "$(rec "$T/r6-pty" declined)" = "v$NEXT" ] || fail "R6 C21: the answer typed at the pty was not read"
  # C22 — a stdout-only terminal (stdin a pipe holding y) never prompts
  mk_target "$T/r6-po"
  pty_gate "$T/r6-po" o 'y\n' "$T/pty22" "$_u"
  has "$PTY_OUT" "🔔" || fail "R6 C22: no notice on a stdout terminal: $PTY_OUT"
  has "$PTY_OUT" "Install now?" && fail "R6 C22: prompted although stdin is not a terminal"
  [ "$(stamp "$T/r6-po")" = "$CUR" ] || fail "R6 C22: upgraded off a half-terminal"
  pass "prompts only when interactive; declined version remembered per version; real pty cells (R6) [R6_prompt_only_interactive]"
}

# ═════════════════════════════════════════════════════════════════════════════════════
# R11 — preview, then consent, before any write
# ═════════════════════════════════════════════════════════════════════════════════════
mk_edited_target() { # <dir> — reviewer.md edited (+2 lines) and a local addition, all committed
  mk_target "$1"
  printf 'local line one\nlocal line two\n' >> "$1/.harness/agents/reviewer.md"
  printf '# my own role\n' > "$1/.harness/agents/extra.md"
  commit_all "$1" "local harness customisation"
}

R11_preview_then_consent() {
  _u="$(remote_url newer)"
  # C17 — edited + added files are listed; n ⇒ rc 2, byte-identical tree
  mk_edited_target "$T/r11"
  touch "$T/r11.sentinel"
  sleep 1
  run_gate "$T/r11" "y\nn\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 2 ] || fail "R11 C17: declining at the preview must exit 2, got $GATE_RC: $GATE_OUT"
  [ "$(printf '%s\n' "$GATE_OUT" | grep -cE '^ +[MA] [a-z]')" = 2 ] || fail "R11 C17: expected exactly two file lines: $GATE_OUT"
  printf '%s\n' "$GATE_OUT" | grep -qE '^ +M agents/reviewer\.md \(\+2 -0\)$' || fail "R11 C17: no 'M agents/reviewer.md (+2 -0)' line: $GATE_OUT"
  printf '%s\n' "$GATE_OUT" | grep -qE '^ +A agents/extra\.md local addition$' || fail "R11 C17: no 'A agents/extra.md local addition' line: $GATE_OUT"
  has "$GATE_OUT" "$_u" || fail "R11 C17: the preview does not name the remote"
  has "$GATE_OUT" "tag v$NEXT" || fail "R11 C17: the preview does not name the tag whose installer runs"
  has "$GATE_OUT" "every line of each harness.config.yaml" || fail "R11 C17: no config preservation guarantee"
  has "$GATE_OUT" "CLAUDE.md / AGENTS.md" || fail "R11 C17: no entrypoint preservation guarantee"
  has "$GATE_OUT" "Proceed with the upgrade? [y/N]" || fail "R11 C17: no confirmation question"
  [ -z "$(git -C "$T/r11" status --porcelain)" ] || fail "R11 C17: the declined preview changed the tree: $(git -C "$T/r11" status --porcelain)"
  [ "$(stamp "$T/r11")" = "$CUR" ] || fail "R11 C17: stamp changed"
  [ ! -e "$T/r11/.harness/progress/upgrade-backup" ] || fail "R11 C17: a backup directory was created by a declined upgrade"
  [ "$(rec "$T/r11" declined)" = "v$NEXT" ] || fail "R11 C17: declining at the preview did not record the version"
  # C17d — nothing under the target (outside VCS data and the ignored progress dir) was written
  _w="$(find "$T/r11" \( -path "$T/r11/.git" -o -path "$T/r11/.harness/progress" \) -prune -o -type f -newer "$T/r11.sentinel" -print | head -n 5)"
  [ -z "$_w" ] || fail "R11 C17d: files were written before consent: $_w"
  # the next gate run: notice, no prompt
  run_gate "$T/r11" "y\n" HARNESS_UPDATE_REMOTE=file:///nonexistent HARNESS_UPDATE_ASSUME_TTY=1
  [ "$(bell_n)" = 1 ] && ! has "$GATE_OUT" "Install now?" || fail "R11 C17: after a preview decline the next run should notice without prompting"

  # C17b — clean body: the empty-list wording, and the question is still asked
  mk_target "$T/r11b"
  run_gate "$T/r11b" "y\nn\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 2 ] || fail "R11 C17b: rc $GATE_RC: $GATE_OUT"
  has "$GATE_OUT" "(no local edits to harness-owned files)" || fail "R11 C17b: no empty-list wording: $GATE_OUT"
  [ "$(printf '%s\n' "$GATE_OUT" | grep -cE '^ +[MA] [a-z]')" = 0 ] || fail "R11 C17b: a clean body listed files: $GATE_OUT"
  has "$GATE_OUT" "Proceed with the upgrade? [y/N]" || fail "R11 C17b: the question was skipped for a clean body"

  # C17c — baseline tag absent from the remote: stated fallback to the incoming tag
  mk_target "$T/r11c"
  run_gate "$T/r11c" "y\nn\n" HARNESS_UPDATE_REMOTE="$(remote_url newer-nobase)" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 2 ] || fail "R11 C17c: rc $GATE_RC: $GATE_OUT"
  has "$GATE_OUT" "v$CUR is not on the remote" || fail "R11 C17c: no stated fallback line: $GATE_OUT"
  printf '%s\n' "$GATE_OUT" | grep -qE '^ +M agents/scout\.md ' || fail "R11 C17c: agents/scout.md (differs in the incoming tag) was not listed: $GATE_OUT"
  pass "preview lists edited + added files before any write; n => rc 2 with an identical tree; clean + fallback wording (R11) [R11_preview_then_consent]"
}

# ═════════════════════════════════════════════════════════════════════════════════════
# R12 — backups precede replacement  /  R7 — the consented upgrade
# ═════════════════════════════════════════════════════════════════════════════════════
R12_backups_precede_replacement() {
  _u="$(remote_url newer)"
  mk_edited_target "$T/r12"
  mkdir -p "$T/r12.orig"
  cp "$T/r12/.harness/agents/reviewer.md" "$T/r12.orig/reviewer.md"
  cp "$T/r12/.harness/agents/extra.md" "$T/r12.orig/extra.md"
  for _f in harness.config.yaml; do cp "$T/r12/.harness/$_f" "$T/r12.orig/$_f"; done
  cp "$T/r12/CLAUDE.md" "$T/r12.orig/CLAUDE.md"; cp "$T/r12/AGENTS.md" "$T/r12.orig/AGENTS.md"
  run_gate "$T/r12" "y\ny\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 3 ] || fail "R12 C18: a consented upgrade must exit 3, got $GATE_RC: $GATE_OUT"
  _bk="$T/r12/.harness/progress/upgrade-backup/$CUR"
  cmp -s "$T/r12.orig/reviewer.md" "$_bk/agents/reviewer.md" || fail "R12 C18: the reviewer.md backup differs from the pre-upgrade original"
  cmp -s "$T/r12.orig/extra.md" "$_bk/agents/extra.md" || fail "R12 C18: the extra.md backup differs from the pre-upgrade original"
  for _f in harness.config.yaml CLAUDE.md AGENTS.md; do
    cmp -s "$T/r12.orig/$_f" "$_bk/preservation/root/$_f" || fail "R12 C18: preservation snapshot of $_f is missing or differs"
  done
  [ ! -e "$T/r12/.harness/agents/extra.md" ] || fail "R12 C18: the local addition survived (then the backup proves nothing)"
  ! cmp -s "$T/r12.orig/reviewer.md" "$T/r12/.harness/agents/reviewer.md" || fail "R12 C18: reviewer.md was not replaced (control)"
  git -C "$T/r12" check-ignore -q .harness/progress/upgrade-backup/$CUR/agents/reviewer.md || fail "R12 C18: the backup is not ignored by the target's VCS"
  # C18b — a second upgrade from the same old version never overwrites the first backup
  sh "$SRC/harness-install.sh" "$T/r12" </dev/null >/dev/null 2>&1 || fail "R12 C18b: could not re-install v$CUR by hand"
  [ "$(stamp "$T/r12")" = "$CUR" ] || fail "R12 C18b precondition: the hand re-install did not restore v$CUR (stamp $(stamp "$T/r12"))"
  printf 'second content\n' >> "$T/r12/.harness/agents/reviewer.md"
  commit_all "$T/r12" "re-installed old version + edit"
  run_gate "$T/r12" "y\ny\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 3 ] || fail "R12 C18b: second upgrade rc $GATE_RC: $GATE_OUT"
  cmp -s "$T/r12.orig/reviewer.md" "$_bk/agents/reviewer.md" || fail "R12 C18b: the first backup was overwritten"
  grep -q 'second content' "$T/r12/.harness/progress/upgrade-backup/$CUR.2/agents/reviewer.md" \
    || fail "R12 C18b: the second backup did not land in a sibling directory"
  pass "backups (edited, added, snapshots) byte-identical to the originals, ignored, never overwritten (R12) [R12_backups_precede_replacement]"
}

R7_consented_upgrade_runs_installer() {
  _u="$(remote_url newer)"
  # a distinctive selection and distinctive values: the upgrade must not reset them
  mk_template "$T/r7-tpl" claude,opencode
  [ "$(tr '\n' ' ' < "$T/r7-tpl/.harness/.agents")" = "claude opencode " ] || fail "R7 precondition: selection was not recorded as claude+opencode"
  cp -R "$T/r7-tpl" "$T/r7"
  sed 's/^    backend: in-session/    backend: delegate/; /^pr_loop:/,/^[^ #]/s/^  enabled: false/  enabled: true/' \
    "$T/r7/.harness/harness.config.yaml" > "$T/r7.yaml"
  cat "$T/r7.yaml" > "$T/r7/.harness/harness.config.yaml"
  grep -q '^    backend: delegate' "$T/r7/.harness/harness.config.yaml" && grep -q '^  enabled: true  *# *\|^  enabled: true' "$T/r7/.harness/harness.config.yaml" \
    || fail "R7 precondition: the value edits did not apply"
  commit_all "$T/r7" "non-default backend + pr_loop"
  cp "$T/r7/.harness/.agents" "$T/r7.agents"
  run_gate "$T/r7" "y\ny\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 3 ] || fail "R7 C14: want rc 3, got $GATE_RC: $GATE_OUT"
  [ "$(stamp "$T/r7")" = "$NEXT" ] || fail "R7 C14: stamp is '$(stamp "$T/r7")', want $NEXT"
  grep -q '# E38 marker' "$T/r7/.harness/agents/scout.md" || fail "R7 C14: the incoming tag's body was not installed"
  cmp -s "$T/r7.agents" "$T/r7/.harness/.agents" || fail "R7 C14: the recorded front-end selection changed"
  grep -q '^    backend: delegate' "$T/r7/.harness/harness.config.yaml" || fail "R7 C14: execution.builder.backend was reset"
  sed -n '/^pr_loop:/,/^[^ #]/p' "$T/r7/.harness/harness.config.yaml" | grep -q '^  enabled: true' || fail "R7 C14: pr_loop.enabled was reset"
  [ "$(git -C "$T/r7/.harness/progress/update-check/repo" describe --tags --exact-match HEAD)" = "v$NEXT" ] \
    || fail "R7 C14: update-check/repo is not a checkout of v$NEXT"
  has "$GATE_OUT" "v$CUR → v$NEXT" || fail "R7 C14: the report does not name both versions: $GATE_OUT"
  has "$GATE_OUT" "progress/upgrade-backup/$CUR" || fail "R7 C14: the report does not name the backup directory"
  printf '%s\n' "$GATE_OUT" | grep -qi 'commit' || fail "R7 C14: the report does not say the upgrade must be committed"
  printf '%s\n' "$GATE_OUT" | grep -qi 're-run init.sh' || fail "R7 C14: the report does not say to re-run init.sh"
  # C14b — fetch failure: rc 5, message, nothing changed
  mk_target "$T/r7b"
  SHIM_MODE=fail-fetch run_gate "$T/r7b" "y\ny\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 5 ] || fail "R7 C14b: a failed fetch must exit 5, got $GATE_RC: $GATE_OUT"
  has "$GATE_OUT" "could not fetch v$NEXT" || fail "R7 C14b: no message naming the fetch failure: $GATE_OUT"
  has "$GATE_OUT" "upgrade-backup/$CUR" || fail "R7 C14b: the message does not name the backup directory"
  [ "$(stamp "$T/r7b")" = "$CUR" ] || fail "R7 C14b: a failed fetch changed the stamp"
  [ -z "$(git -C "$T/r7b" status --porcelain)" ] || fail "R7 C14b: a failed fetch changed the tree"
  pass "y+y fetches the tag, runs ITS installer, keeps selection/backend/pr_loop, reports, exits 3; fetch failure exits 5 (R7) [R7_consented_upgrade_runs_installer]"
}

# ═════════════════════════════════════════════════════════════════════════════════════
# R8 / R9 — the preservation proofs
# ═════════════════════════════════════════════════════════════════════════════════════
strip_update_block() { # <config> — what a pre-E38 config looks like
  awk '/^# Harness self-update check \(E38-F01\)/ { skip = 1 } skip && /^  remote:/ { skip = 0; next } !skip' "$1" > "$1.stripped"
  cat "$1.stripped" > "$1"; rm -f "$1.stripped"
  ! grep -Eq '^update:' "$1" || fail "setup failed — the update: block was not stripped from $1"
}

R8_config_preserved_proof() {
  _u="$(remote_url newer)"
  # C15 — hand-edited value + a comment line survive, in order; the block is appended
  mk_target "$T/r8"
  strip_update_block "$T/r8/.harness/harness.config.yaml"
  sed 's|^  test_command: ""|  test_command: "pytest -q"|' "$T/r8/.harness/harness.config.yaml" > "$T/r8.yaml"
  cat "$T/r8.yaml" > "$T/r8/.harness/harness.config.yaml"
  printf '\n# my note\n' >> "$T/r8/.harness/harness.config.yaml"
  grep -q 'test_command: "pytest -q"' "$T/r8/.harness/harness.config.yaml" || fail "R8 precondition: test_command edit did not apply"
  commit_all "$T/r8" "hand-edited config"
  run_gate "$T/r8" "y\ny\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 3 ] || fail "R8 C15: rc $GATE_RC: $GATE_OUT"
  printf '%s\n' "$GATE_OUT" | grep -qxF "✅ preserved root harness.config.yaml" || fail "R8 C15: no preserved line: $GATE_OUT"
  _a="$(grep -n 'test_command: "pytest -q"' "$T/r8/.harness/harness.config.yaml" | head -n1 | cut -d: -f1)"
  _b="$(grep -n '^# my note$' "$T/r8/.harness/harness.config.yaml" | head -n1 | cut -d: -f1)"
  [ -n "$_a" ] && [ -n "$_b" ] && [ "$_a" -lt "$_b" ] || fail "R8 C15: the edited lines are missing or out of order"
  grep -q '^update:' "$T/r8/.harness/harness.config.yaml" || fail "R8 C15: the update: block was not appended (the subsequence rule was never exercised)"
  # C15b — an installer that rewrites a value: ❌, snapshot named, rc 4
  mk_target "$T/r8b"
  run_gate "$T/r8b" "y\ny\n" HARNESS_UPDATE_REMOTE="$(remote_url newer-badinstaller-config)" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 4 ] || fail "R8 C15b: a violated config must exit 4, got $GATE_RC: $GATE_OUT"
  printf '%s\n' "$GATE_OUT" | grep -q '^❌ changed root harness.config.yaml' || fail "R8 C15b: no changed line: $GATE_OUT"
  _snap="$T/r8b/.harness/progress/upgrade-backup/$CUR/preservation/root/harness.config.yaml"
  has "$GATE_OUT" "$_snap" || fail "R8 C15b: the snapshot path is not named"
  [ -f "$_snap" ] && grep -q 'test_command: ""' "$_snap" || fail "R8 C15b: the snapshot is missing or does not hold the original"
  pass "config lines proved preserved in order (appends allowed); a rewritten value reports changed + snapshot + rc 4 (R8) [R8_config_preserved_proof]"
}

R9_entrypoints_preserved_proof() {
  _u="$(remote_url newer)"
  mk_target "$T/r9"
  { echo "PROSE ABOVE the block"; cat "$T/r9/CLAUDE.md"; echo; echo "PROSE BELOW the block"; } > "$T/r9.claude"
  cat "$T/r9.claude" > "$T/r9/CLAUDE.md"
  printf 'agents prose, no block\n' > "$T/r9/AGENTS.md"
  commit_all "$T/r9" "entrypoint prose"
  run_gate "$T/r9" "y\ny\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 3 ] || fail "R9 C16: rc $GATE_RC: $GATE_OUT"
  printf '%s\n' "$GATE_OUT" | grep -qxF "✅ preserved root CLAUDE.md" || fail "R9 C16: no preserved CLAUDE.md line: $GATE_OUT"
  printf '%s\n' "$GATE_OUT" | grep -qxF "✅ preserved root AGENTS.md" || fail "R9 C16: no preserved AGENTS.md line: $GATE_OUT"
  grep -qxF 'PROSE ABOVE the block' "$T/r9/CLAUDE.md" && grep -qxF 'PROSE BELOW the block' "$T/r9/CLAUDE.md" \
    && grep -qxF 'agents prose, no block' "$T/r9/AGENTS.md" || fail "R9 C16: user prose is gone"
  [ "$(grep -c '<!-- harness:begin -->' "$T/r9/CLAUDE.md")" = 1 ] || fail "R9 C16: CLAUDE.md does not hold exactly one block"
  [ "$(grep -c '<!-- harness:begin -->' "$T/r9/AGENTS.md")" = 1 ] || fail "R9 C16: AGENTS.md was not given its block (control: the file did change)"
  # C16b — an installer that appends outside the block
  mk_target "$T/r9b"
  run_gate "$T/r9b" "y\ny\n" HARNESS_UPDATE_REMOTE="$(remote_url newer-badinstaller-claude)" HARNESS_UPDATE_ASSUME_TTY=1
  [ "$GATE_RC" = 4 ] || fail "R9 C16b: a violated entrypoint must exit 4, got $GATE_RC: $GATE_OUT"
  printf '%s\n' "$GATE_OUT" | grep -q '^❌ changed root CLAUDE.md' || fail "R9 C16b: no changed line: $GATE_OUT"
  has "$GATE_OUT" "$T/r9b/.harness/progress/upgrade-backup/$CUR/preservation/root/CLAUDE.md" || fail "R9 C16b: the snapshot path is not named"
  printf '%s\n' "$GATE_OUT" | grep -qxF "✅ preserved root AGENTS.md" || fail "R9 C16b: the untouched AGENTS.md should still be reported preserved"
  pass "bytes outside the harness block proved identical; tampering reports changed + rc 4 (R9) [R9_entrypoints_preserved_proof]"
}

# ═════════════════════════════════════════════════════════════════════════════════════
# R10 — a coordinator upgrade cascades
# ═════════════════════════════════════════════════════════════════════════════════════
R10_coordinator_cascades() {
  _u="$(remote_url newer-argvlog)"
  _c="$T/coord"
  mkdir -p "$_c"
  for _ch in api web; do
    mkdir -p "$_c/$_ch"
    git -C "$_c/$_ch" init -q .
    git -C "$_c/$_ch" config user.email "test@harness.local"
    git -C "$_c/$_ch" config user.name "harness test"
    echo seed > "$_c/$_ch/README.md"
    git -C "$_c/$_ch" add -A
    git -C "$_c/$_ch" commit -q -m init
  done
  sh "$SRC/harness-install.sh" --umbrella "$_c" --agents=claude >/dev/null 2>&1 || [ $? = 3 ] || fail "R10: could not build the coordinator fixture"
  # api: an explicit override that differs from the coordinator
  sed 's|^  test_command: ""|  test_command: "pytest -q"|' "$_c/api/.harness/harness.config.yaml" > "$T/api.yaml"
  cat "$T/api.yaml" > "$_c/api/.harness/harness.config.yaml"
  sed 's|^  builder: inherit|  builder: standard|' "$_c/api/.harness/harness.config.yaml" > "$T/api.yaml"
  cat "$T/api.yaml" > "$_c/api/.harness/harness.config.yaml"
  grep -q 'test_command: "pytest -q"' "$_c/api/.harness/harness.config.yaml" && grep -q '^  builder: standard' "$_c/api/.harness/harness.config.yaml" \
    || fail "R10 precondition: the api override did not apply"
  for _ch in api web; do head -n 1 "$_c/$_ch/.harness/AGENTS.md" | grep -qxF '<!-- harness:umbrella-stub -->' || fail "R10 precondition: $_ch is not thin"; done
  for _r in "$_c/api" "$_c/web"; do git -C "$_r" add -A && git -C "$_r" commit -q -m "land the harness"; done
  [ "$(stamp "$_c")" = "$CUR" ] && [ "$(stamp "$_c/api")" = "$CUR" ] || fail "R10 precondition: stamps are not $CUR"
  _udir="$(cd "$_c" && pwd)"
  : > "$T/argv"
  run_gate "$_c" "y\ny\n" HARNESS_UPDATE_REMOTE="$_u" HARNESS_UPDATE_ASSUME_TTY=1 E38_ARGV_LOG="$T/argv"
  [ "$GATE_RC" = 3 ] || fail "R10 C19: want rc 3, got $GATE_RC: $GATE_OUT"
  grep -qxF -- "--umbrella $_udir" "$T/argv" || fail "R10 C19: the installer was not invoked as '--umbrella $_udir' (argv: $(cat "$T/argv"))"
  [ "$(stamp "$_c")" = "$NEXT" ] && [ "$(stamp "$_c/api")" = "$NEXT" ] && [ "$(stamp "$_c/web")" = "$NEXT" ] \
    || fail "R10 C19: stamps after the cascade: coord=$(stamp "$_c") api=$(stamp "$_c/api") web=$(stamp "$_c/web"), want $NEXT"
  for _ch in api web; do head -n 1 "$_c/$_ch/.harness/AGENTS.md" | grep -qxF '<!-- harness:umbrella-stub -->' || fail "R10 C19: $_ch's prose tier is no longer stubs"; done
  printf '%s\n' "$GATE_OUT" | grep -qxF "✅ preserved root harness.config.yaml" || fail "R10 C19: no root config proof: $GATE_OUT"
  printf '%s\n' "$GATE_OUT" | grep -qxF "✅ preserved api harness.config.yaml" || fail "R10 C19: no api config proof: $GATE_OUT"
  printf '%s\n' "$GATE_OUT" | grep -qxF "✅ preserved web harness.config.yaml" || fail "R10 C19: no web config proof: $GATE_OUT"
  grep -q 'test_command: "pytest -q"' "$_c/api/.harness/harness.config.yaml" && grep -q '^  builder: standard' "$_c/api/.harness/harness.config.yaml" \
    || fail "R10 C19: api's explicit overrides were not kept"
  # C19b — the installer's exit 3 is the expected outcome and is reported as success
  has "$GATE_OUT" "NOT COMMITTED" || fail "R10 C19b: the cascade's own unlanded audit line is absent — exit 3 was not exercised"
  has "$GATE_OUT" "harness upgraded: v$CUR → v$NEXT" || fail "R10 C19b: exit 3 was not reported as a successful upgrade"
  printf '%s\n' "$GATE_OUT" | grep -qi 'commit' || fail "R10 C19b: the report does not say to commit"
  pass "coordinator => '--umbrella <dir>', every child stamped, thin stays thin, per-repo proofs, installer exit 3 = success (R10) [R10_coordinator_cascades]"
}

R1_notice_when_newer
R2_silent_skips_table
R4_same_older_junk_silent
R3_failure_silent_bounded_cached
R5_cache_ttl
R6_prompt_only_interactive
R11_preview_then_consent
R12_backups_precede_replacement
R7_consented_upgrade_runs_installer
R8_config_preserved_proof
R9_entrypoints_preserved_proof
R10_coordinator_cascades
echo "all update-check cases passed"
