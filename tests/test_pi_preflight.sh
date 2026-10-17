#!/bin/sh
# test_pi_preflight.sh — E35-F04, the pi environment preflight + approval-gated pinned
# pi-subagents install (harness-install.sh §6a-pi).
#
# Covers R1–R12 of specs/epics/E35-pi-first-class/F04-pi-preflight-deps/.
#
# HERMETIC. This host may have a real `pi` on PATH (and a real ~/.pi/agent). Every installer
# run goes through `env -i` with a sandbox PATH (the real PATH minus every directory holding
# a `pi` executable), an isolated HOME and CODEX_HOME, and PI_CODING_AGENT_DIR unset. The only
# `pi` that ever runs is the STUB written below. No case runs the real pi, npm or the network.
#
# HOSTILE TABLES IN ROUND 1 (progress/lessons.md 2026-10-14, 2026-10-16): every table below is
# the full matrix — version/trust/list/conflict/shape — not a sample. Table rows are
# independent targets run as parallel background jobs (joined with `wait`).
#
# The stub logs one tab-separated record per invocation to $STUB_LOG:
#   argv=[a] [b] …  cwd=<pwd -P>  stdin=devnull|other  offline=<PI_OFFLINE>
#   arming=yes|no (.harness/.escalation-arming present AT CALL TIME)  agents=<n .pi/agents/*.md>

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INST="$SRC/harness-install.sh"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-ppf)"
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
  && fail "sandbox setup: 'pi' still resolves on the sandbox PATH"
for _c in awk sed grep sort tr cp mv rm mkdir cat cmp mktemp find python3 git readlink cksum ln xargs head wc date; do
  env -i PATH="$SANDBOX_PATH" sh -c "command -v $_c" >/dev/null 2>&1 \
    || fail "sandbox setup: '$_c' is missing from the sandbox PATH"
done

# A PATH with every sandbox executable EXCEPT python3 (a symlink mirror), for R7(d)/R11.
NOPY="$T/nopy"; mkdir -p "$NOPY"
python3 - "$NOPY" "$SANDBOX_PATH" <<'PYMIRROR'
import os, sys
d = sys.argv[1]
for p in sys.argv[2].split(":"):
    try:
        names = os.listdir(p)
    except OSError:
        continue
    for n in names:
        if n.startswith("python"):
            continue
        src, dst = os.path.join(p, n), os.path.join(d, n)
        if os.path.lexists(dst):
            continue
        if os.path.isfile(src) and os.access(src, os.X_OK):
            os.symlink(src, dst)
PYMIRROR
env -i PATH="$NOPY" sh -c 'command -v python3' >/dev/null 2>&1 && fail "setup: python3 still resolves on the no-python PATH"

# ── the stub `pi` ────────────────────────────────────────────────────────────────────────
STUBDIR="$T/stubbin"; mkdir -p "$STUBDIR"
cat > "$STUBDIR/pi" <<'STUB'
#!/bin/sh
# hermetic stub pi — behaviour per verb from $STUB_CTL ("<verb> <mode>" lines).
verb="$1"
dev=other
[ "$(readlink /proc/self/fd/0 2>/dev/null)" = /dev/null ] && dev=devnull
args=""
for a in "$@"; do args="$args[$a] "; done
arming=no; [ -e .harness/.escalation-arming ] && arming=yes
nag=0; for f in .pi/agents/*.md; do [ -e "$f" ] && nag=$((nag + 1)); done
printf 'argv=%s\tcwd=%s\tstdin=%s\toffline=%s\tarming=%s\tagents=%s\n' "$args" "$(pwd -P)" "$dev" "${PI_OFFLINE:-}" "$arming" "$nag" >> "$STUB_LOG"
case "$verb" in
  --version) key=version; def='ok:1.2.0\n' ;;
  list) key=list; def=real ;;
  install) key=install; def=real ;;
  *) exit 0 ;;
esac
mode=""
[ -r "${STUB_CTL:-/nonexistent}" ] && mode="$(sed -n "s/^$key //p" "$STUB_CTL" | head -n 1)"
[ -n "$mode" ] || mode="$def"
if [ "${STUB_CANARY:-}" = 1 ] && [ "$key" = install ]; then
  printf 'CANARY-OUT\n'; printf 'CANARY-ERR\n' >&2
fi
case "$mode" in
  ok:*) printf '%b' "${mode#ok:}" ;;
  rc:*) rest="${mode#rc:}"; rc="${rest%%:*}"; txt="${rest#*:}"; [ "$txt" != "$rest" ] && printf '%b' "$txt"; exit "$rc" ;;
  text:*) printf '%b' "${mode#text:}" ;;
  huge) head -c 66000 /dev/zero | tr '\0' x; echo ;;
  hugeok) head -c 66000 /dev/zero | tr '\0' '\n'; printf 'No packages installed.\n' ;;
  sleep) sleep 30 & echo $! > "$STUB_LOG.gc"; sleep 30 ;;
  noop) ;;
  real|add-subagents|rc1-subagents|setsid-real)
    if [ "$key" = list ]; then
      # real pi throws (or blocks) on a settings.json it cannot read: a FIFO or a directory
      { [ ! -e .pi/settings.json ] || [ -f .pi/settings.json ]; } || exit 1
      python3 - <<'PYLISTREAL'
import json, os
def pk(path):
    try:
        with open(path) as fh:
            d = json.load(fh)
        return d.get("packages", []) if isinstance(d, dict) else []
    except Exception:
        return []
def name(e):
    s = e if isinstance(e, str) else e.get("source", "")
    s = s.split(":", 1)[-1]
    if s.startswith("@"):
        return "@" + s[1:].split("@")[0]
    return s.split("@")[0]
def render(title, ents, base):
    out = [title]
    for e in ents:
        s = e if isinstance(e, str) else e.get("source", "") + " (filtered)"
        out.append("  " + s)
        p = os.path.join(base, "node_modules", name(e))
        if os.path.exists(p):
            out.append("    " + p)
    return out
user = pk(os.environ["HOME"] + "/.pi/agent/settings.json")
proj = pk(".pi/settings.json")
if not user and not proj:
    print("No packages installed.")
else:
    lines = []
    if user:
        lines += render("User packages:", user, os.environ["HOME"] + "/.pi/agent/npm")
    if user and proj:
        lines.append("")
    if proj:
        lines += render("Project packages:", proj, os.path.abspath(".pi/npm"))
    print("\n".join(lines))
PYLISTREAL
    else
      python3 - "$mode" "$@" <<'PYINSTALLREAL'
import json, os, sys
mode, spec = sys.argv[1], sys.argv[-1]
d = {}
if os.path.exists(".pi/settings.json"):
    with open(".pi/settings.json") as fh:
        d = json.load(fh)
ident = spec.rsplit("@", 1)[0]
pk = d.setdefault("packages", [])
for i, e in enumerate(pk):
    if isinstance(e, str) and e.rsplit("@", 1)[0] == ident:
        pk[i] = spec
        break
else:
    pk.append(spec)
if mode in ("add-subagents", "rc1-subagents"):
    d["subagents"] = {}
os.makedirs(".pi/npm/node_modules/pi-subagents", exist_ok=True)
with open(".pi/npm/node_modules/pi-subagents/package.json", "w") as fh:
    fh.write(json.dumps({"name": "pi-subagents", "version": spec.rsplit("@", 1)[1]}))
for f, c in ((".pi/npm/package.json", "{}\n"), (".pi/npm/.gitignore", "*\n!.gitignore\n")):
    if not os.path.lexists(f):
        with open(f, "w") as fh:
            fh.write(c)
with open(".pi/settings.json", "w") as fh:
    fh.write(json.dumps(d, indent=2))
PYINSTALLREAL
      [ "$mode" = setsid-real ] && { setsid sleep 9 & }
      [ "$mode" = rc1-subagents ] && exit 1
    fi ;;
esac
exit 0
STUB
chmod +x "$STUBDIR/pi"
# a NON-executable `pi` on PATH
NOXDIR="$T/noxbin"; mkdir -p "$NOXDIR"; printf '#!/bin/sh\nexit 0\n' > "$NOXDIR/pi"; chmod 644 "$NOXDIR/pi"

# ── the PTY runner: stdin/stdout/stderr each a terminal or not, typed input ──────────────
cat > "$T/ptyrun.py" <<'PYPTY'
# usage: ptyrun.py <modeflags subset of i,o,e> <typed (python escapes)> <outbase> -- cmd…
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

# ── fixture helpers ──────────────────────────────────────────────────────────────────────
SBPATH="$SANDBOX_PATH"
L="   pi preflight: "
mkcell() { # <name> — a fresh cell: $CD, $TGT, $RT, $OUT, $ERR, $LOG, $CTL; stub log reset
  CD="$T/c/$1"; rm -rf "$CD"; mkdir -p "$CD/home" "$CD/ch" "$CD/t"
  TGT="$CD/t"; RT="$(cd "$TGT" && pwd -P)"; OUT="$CD/out"; ERR="$CD/err"; LOG="$CD/stub.log"; CTL="$CD/ctl"
  : > "$LOG"; : > "$CTL"; SBPATH="$SANDBOX_PATH"
}
ctl() { : > "$CTL"; for _l in "$@"; do printf '%s\n' "$_l" >> "$CTL"; done; }

# snapshot of an agent dir: every entry, every link target, every regular file's cksum
agsnap() {
  [ -e "$1" ] || [ -L "$1" ] || { echo absent; return 0; }
  ( find "$1" | sort
    find "$1" -type l | sort | while IFS= read -r _l; do printf 'L %s -> %s\n' "$_l" "$(readlink "$_l")"; done
    find "$1" -type f -exec cksum {} + 2>&1 ) || :
}
# victim snapshots: a node's whole identity
snap() {
  if [ -L "$1" ]; then printf 'L %s\n' "$(readlink "$1")"
  elif [ -f "$1" ]; then printf 'F %s\n' "$(cksum < "$1")"
  elif [ -d "$1" ]; then ( cd "$1" && find . | sort && find . -type f -exec cksum {} + 2>&1 )
  elif [ -e "$1" ]; then echo X
  else echo absent; fi
}

# inst <ctl-file|-> <extra env words|-> <stdin: null|closed|yes> <installer args…>
# Runs the installer hermetically (stdout → $OUT, stderr → $ERR, rc → $RC) under a 90 s
# watchdog, then asserts the two invariants every run owes: the agent dir is byte-identical,
# and every stub record has cwd = target and stdin = /dev/null (R7a).
inst() {
  _i_ctl="$1"; _i_env="$2"; _i_in="$3"; shift 3
  [ "$_i_env" != - ] || _i_env=""
  _i_path="$SBPATH"
  _i_stub=""
  if [ "$_i_ctl" != - ]; then _i_path="$STUBDIR:$SBPATH"; _i_stub="STUB_CTL=$_i_ctl STUB_LOG=$LOG"; fi
  agsnap "$CD/home/.pi/agent" > "$CD/snap.0" 2>&1
  RC=0
  case "$_i_in" in
    null)   env -i PATH="$_i_path" HOME="$CD/home" CODEX_HOME="$CD/ch" $_i_stub $_i_env sh "$INST" "$@" </dev/null >"$OUT" 2>"$ERR" & ;;
    closed) env -i PATH="$_i_path" HOME="$CD/home" CODEX_HOME="$CD/ch" $_i_stub $_i_env sh "$INST" "$@" <&- >"$OUT" 2>"$ERR" & ;;
    yes)    { yes | env -i PATH="$_i_path" HOME="$CD/home" CODEX_HOME="$CD/ch" $_i_stub $_i_env sh "$INST" "$@" >"$OUT" 2>"$ERR"; } & ;;
    *) fail "inst: bad stdin spec $_i_in" ;;
  esac
  _i_p=$!
  ( sleep 90; kill -9 "$_i_p" 2>/dev/null ) >/dev/null 2>&1 &
  _i_w=$!
  wait "$_i_p" || RC=$?
  kill "$_i_w" 2>/dev/null || :
  wait "$_i_w" 2>/dev/null || :
  post_checks
}
post_checks() {
  agsnap "$CD/home/.pi/agent" > "$CD/snap.1" 2>&1
  cmp -s "$CD/snap.0" "$CD/snap.1" || fail "${CELL:-cell}: the pi agent dir changed during the run (R6/R7)"
  if [ -s "$LOG" ] && [ -d "$TGT" ]; then
    _pc_rt="$(cd "$TGT" && pwd -P)"
    awk -F'\t' -v rt="$_pc_rt" '{ if ($2 != "cwd=" rt && index($2, "cwd=" rt "/") != 1) bad=1; if ($3 != "stdin=devnull") bad=1 } END { exit bad }' "$LOG" \
      || fail "${CELL:-cell}: a pi invocation had the wrong cwd or stdin (R7a): $(cat "$LOG")"
  fi
}
# pty_inst <ctl|-> <env words|-> <tty flags i/o/e> <typed> <installer args…>  → rc in $RC,
# $OUT = stdout file + terminal capture, $ERR = stderr file.
pty_inst() {
  _p_ctl="$1"; _p_env="$2"; _p_mode="$3"; _p_typed="$4"; shift 4
  [ "$_p_env" != - ] || _p_env=""
  _p_path="$SBPATH"; _p_stub=""
  if [ "$_p_ctl" != - ]; then _p_path="$STUBDIR:$SBPATH"; _p_stub="STUB_CTL=$_p_ctl STUB_LOG=$LOG"; fi
  agsnap "$CD/home/.pi/agent" > "$CD/snap.0" 2>&1
  python3 "$T/ptyrun.py" "$_p_mode" "$_p_typed" "$CD/pty" -- \
    env -i PATH="$_p_path" HOME="$CD/home" CODEX_HOME="$CD/ch" $_p_stub $_p_env sh "$INST" "$@" \
    || fail "${CELL:-cell}: pty runner failed"
  RC="$(cat "$CD/pty.rc")"
  cat "$CD/pty.out" "$CD/pty.tty" | tr -d '\r' > "$OUT"; tr -d '\r' < "$CD/pty.err" > "$ERR"
  post_checks
}

# mk_pkg <dir> <version|none|bad> — an installed pi-subagents package dir with its package.json
mk_pkg() {
  mkdir -p "$1"
  case "$2" in none) ;; bad) printf '{' > "$1/package.json" ;; *) printf '{"name":"pi-subagents","version":"%s"}' "$2" > "$1/package.json" ;; esac
}
CLBL="conflict: a subagent extension (pi example or legacy pi-subagents clone) that registers a conflicting subagent tool at"
hasl() { grep -qxF "${L}$1" "$OUT" || fail "${CELL:-cell}: missing report line '${L}$1' in: $(grep 'pi preflight' "$OUT" | cut -c1-200)"; }
nol()  { ! grep -qxF "${L}$1" "$OUT" || fail "${CELL:-cell}: unexpected report line '${L}$1'"; }
hasf() { grep -qF "$1" "$OUT" || fail "${CELL:-cell}: output lacks '$1': $(grep 'pi preflight' "$OUT" | cut -c1-200)"; }
nof()  { ! grep -qF "$1" "$OUT" || fail "${CELL:-cell}: output unexpectedly contains '$1'"; }
ncalls() { grep -c "^argv=\[$1\]" "$LOG" || :; }
no_pi_calls() { [ ! -s "$LOG" ] || fail "${CELL:-cell}: the stub pi was called: $(cat "$LOG")"; }
no_install() { [ "$(ncalls install)" = 0 ] || fail "${CELL:-cell}: pi install was called: $(cat "$LOG")"; }
want_rc() { [ "$RC" = "$1" ] || fail "${CELL:-cell}: exit $RC, want $1: $(grep 'pi preflight' "$OUT" | cut -c1-200) $(tail -n 5 "$ERR" | cut -c1-200)"; }
fld() { printf '%s\n' "$2" | awk -F'|' -v n="$1" '{ print $n }'; }
ARGS="--agents=pi"
PTYARGS="--agents=pi --builder-backend=in-session --pr-loop=false"

# parallel table runner: rows on stdin, `ROWFN row` per row, as background jobs
PIDS=""
par_add() { ( "$@" ) & PIDS="$PIDS $!"; _n=$(( ${_n:-0} + 1 )); [ "$_n" -lt 14 ] || par_wait; }
par_wait() {
  _bad=0
  for _p in $PIDS; do wait "$_p" || _bad=1; done
  PIDS=""; _n=0
  [ "$_bad" = 0 ] || fail "a table cell failed (see above)"
}

# ── helpers for seeded targets ───────────────────────────────────────────────────────────
# tier_target: an installed pi target whose tiers make pi raise (builder standard, heavy reasoning)
tier_target() {
  inst - "HARNESS_PI_DEPS=skip" null $ARGS --pr-loop=false "$TGT"; want_rc 0
  _cfg="$TGT/.harness/harness.config.yaml"
  sed 's/^  builder: .*/  builder: standard/;s/^  builder-heavy: .*/  builder-heavy: reasoning/' "$_cfg" > "$_cfg.t" && mv "$_cfg.t" "$_cfg"
  grep -q '^  builder-heavy: reasoning$' "$_cfg" || fail "setup: could not seed tiers"
}
arming_pi() { sed -n 's/^pi=//p' "$TGT/.harness/.escalation-arming"; }

# ══ R12-adjacent pure functions ═══════════════════════════════════════════════════════════
sed -n '/^pi_deps_decision() {$/,/^}$/p' "$INST" > "$T/dec.sh"
sed -n '/^pi_deps_answer() {$/,/^}$/p' "$INST" >> "$T/dec.sh"
grep -q '^pi_deps_decision() {$' "$T/dec.sh" && grep -q '^pi_deps_answer() {$' "$T/dec.sh" \
  || fail "SHAPE CONTRACT: pi_deps_decision / pi_deps_answer cannot be extracted with sed"
[ "$(grep -c '^}$' "$T/dec.sh")" = 2 ] || fail "SHAPE CONTRACT: an inner line is exactly '}'"
. "$T/dec.sh"

test_decision_pure() {
  # literal rows: mode source stdin_tty stderr_tty umbrella answer → decision
  while IFS=' ' read -r m s i e u a want; do
    [ -n "$m" ] || continue
    [ "$a" != - ] || a=""
    got="$(pi_deps_decision "$m" "$s" "$i" "$e" "$u" "$a")"
    [ "$got" = "$want" ] || fail "R8 pure: decision($m $s $i $e $u '$a') = '$got', want '$want'"
  done <<'EOF'
install flag 0 0 0 - install
install flag 1 1 1 - install
install env 1 1 0 - print-command
install env 0 0 0 - print-command
install env 1 1 0 yes print-command
install default 1 1 0 yes print-command
check flag 1 1 0 - prompt
check env 1 1 0 - prompt
check default 1 1 0 - prompt
check default 1 1 0 yes install
check default 1 1 0 no print-command
check default 0 1 0 - print-command
check default 1 0 0 - print-command
check default 0 0 0 yes print-command
check default 1 1 1 - print-command
check default 1 1 1 yes print-command
skip flag 1 1 0 - print-command
skip flag 0 0 0 yes print-command
EOF
  # exhaustive: an independently written model of the rules over EVERY input combination
  for m in check install skip bogus; do for s in flag env default; do for i in 0 1; do for e in 0 1; do for u in 0 1; do for a in '' yes no; do
    want=print-command
    if [ "$m" = install ] && [ "$s" = flag ]; then want=install
    elif [ "$m" = check ] && [ "$i$e$u" = 110 ]; then
      case "$a" in '') want=prompt ;; yes) want=install ;; esac
    fi
    got="$(pi_deps_decision "$m" "$s" "$i" "$e" "$u" "$a")"
    [ "$got" = "$want" ] || fail "R8 pure: decision($m $s $i $e $u '$a') = '$got', want '$want'"
  done; done; done; done; done; done
  # the timeout override rule: a positive integer <= 3600, anything else ignored
  sed -n '/^pi_bound() {$/,/^}$/p' "$INST" > "$T/bound.sh"; . "$T/bound.sh"
  while IFS=' ' read -r v want; do
    [ -n "$v" ] || continue; [ "$v" != - ] || v=""
    [ "$(pi_bound "$v" 15)" = "$want" ] || fail "R7: pi_bound('$v') = '$(pi_bound "$v" 15)', want $want"
  done <<'BOUNDS'
- 15
0 15
00 15
-1 15
+5 15
abc 15
1.5 15
3601 15
99999 15
123456789012345678901234567890 15
1 1
5 5
60 60
3600 3600
BOUNDS
  for y in y Y yes YES Yes yEs ' y ' '  yes' 'yes  ' "$(printf '\ty\t')"; do
    [ "$(pi_deps_answer "$y")" = yes ] || fail "R8 pure: answer('$y') is not yes"
  done
  for n in '' ' ' n N no NO yep yeah 'yes!' 'y y' ye 1 true ok yess 'yes please' "$(printf 'y\nn')"; do
    [ "$(pi_deps_answer "$n")" = no ] || fail "R8 pure: answer('$n') is not no"
  done
  pass "pi_deps_decision / pi_deps_answer: every input combination, SHAPE CONTRACT (R8)"
}

# ══ R1: mode parse ════════════════════════════════════════════════════════════════════════
row_mode() {
  CELL="mode-$(fld 1 "$1")"; mkcell "$CELL"
  _args="$(fld 2 "$1")"; _env="$(fld 3 "$1")"; _want="$(fld 4 "$1")"
  [ "$_args" != - ] || _args=""; [ -n "$_env" ] || _env=-
  _args="$(printf '%b' "$_args")"; _env="$(printf '%b' "$_env")"
  if [ "$_want" = abort ]; then
    case "$_args" in *--umbrella*) mkdir -p "$CD/u"; _args="$_args $CD/u" ;; esac
    ctl "version ok:1.2.0\n"
    inst "$CTL" "$_env" null $_args $ARGS $( case "$_args" in *--umbrella*) ;; *) echo "$TGT" ;; esac )
    [ "$RC" != 0 ] || fail "$CELL: expected a non-zero abort"
    cat "$OUT" "$ERR" > "$CD/all"
    for w in check install skip; do grep -qF "'$w'" "$CD/all" || fail "$CELL: the abort message does not name '$w': $(cat "$CD/all")"; done
    [ ! -e "$TGT/.harness" ] || fail "$CELL: the aborting run wrote .harness/"
    ! grep -q "$(printf '\033')" "$CD/all" || fail "$CELL: the abort message echoed an ESC byte raw"
    no_pi_calls
    return 0
  fi
  ctl "version ok:1.2.0\n"
  inst "$CTL" "$_env" null $_args $ARGS "$TGT"; want_rc 0
  case "$_want" in
    skip) hasl "skipped (--pi-deps=skip)"; no_pi_calls ;;
    check) hasl "pi 1.2.0 (>= 1.0.0)"; no_install ;;
    install) [ "$(ncalls install)" = 1 ] || fail "$CELL: the flag install did not run pi install: $(cat "$LOG")" ;;
  esac
}
test_mode_parse() {
  while IFS= read -r r; do [ -n "$r" ] || continue; par_add row_mode "$r"; done <<'EOF'
c1|--pi-deps=check||check
c2|--pi-deps=install||install
c3|--pi-deps=skip||skip
c4|--pi-deps skip||skip
c5|--pi-deps=||check
c6|--pi-deps=install|HARNESS_PI_DEPS=skip|install
c7|-|HARNESS_PI_DEPS=skip|skip
c8|--pi-deps=skip|HARNESS_PI_DEPS=install|skip
c9|-|HARNESS_PI_DEPS=check|check
a1|--pi-deps=bogus||abort
a2|-|HARNESS_PI_DEPS=Install|abort
a3|--pi-deps=install --umbrella||abort
a4|--pi-deps=INSTALL||abort
a5|--pi-deps=check,install||abort
a6|-|HARNESS_PI_DEPS=bogus|abort
a7|--pi-deps=\033red||abort
a8|-|HARNESS_PI_DEPS=x\033y|abort
EOF
  par_wait
  # a trailing `--pi-deps` with no value is a usage error
  CELL=mode-trail; mkcell "$CELL"
  inst - - null "$TGT" --pi-deps; [ "$RC" != 0 ] || fail "R1: a trailing --pi-deps did not abort"
  [ ! -e "$TGT/.harness" ] || fail "R1: a trailing --pi-deps wrote .harness/"
  pass "mode parse: flag/env precedence, empty = default, illegal and umbrella+install abort before any write (R1)"
}

# ══ R2: gating and placement ══════════════════════════════════════════════════════════════
test_gating() {
  CELL=gate-a; mkcell "$CELL"; ctl "version ok:1.2.0\n"
  inst "$CTL" - null --agents=claude "$TGT"; want_rc 0
  no_pi_calls; nof "pi preflight"
  mkcell gate-a2; CELL=gate-a2; ctl "version ok:1.2.0\n"
  inst "$CTL" HARNESS_PI_DEPS=install null --agents=claude "$TGT"; want_rc 0
  no_pi_calls; nof "pi preflight"; nof "cannot approve"
  mkcell gate-a3; CELL=gate-a3; ctl "version ok:1.2.0\n"
  inst "$CTL" - null --agents=claude --pi-deps=install "$TGT"; want_rc 0
  no_pi_calls; nof "pi preflight"
  hasf "note: --pi-deps=install has no effect"
  mkcell gate-a4; CELL=gate-a4; ctl "version ok:1.2.0\n"
  inst "$CTL" - null --agents=claude --pi-deps=check "$TGT"; want_rc 0
  nof "has no effect"
  # (b) skip: exactly one skip line, nothing executed
  mkcell gate-b; CELL=gate-b; ctl "version ok:1.2.0\n"
  inst "$CTL" - null $ARGS --pi-deps=skip "$TGT"; want_rc 0
  no_pi_calls; hasl "skipped (--pi-deps=skip)"
  [ "$(grep -c 'pi preflight:' "$OUT")" = 1 ] || fail "R2b: --pi-deps=skip printed more than one preflight line: $(cat "$OUT")"
  # (d) placement: the preflight runs after the .pi/ files exist and before the arming file
  mkcell gate-d; CELL=gate-d; tier_target
  rm -f "$TGT/.harness/.escalation-arming"; : > "$LOG"; ctl "version ok:1.2.0\n"
  inst "$CTL" - null $ARGS --pr-loop=false "$TGT"; want_rc 0
  [ "$(ncalls list)" = 1 ] || fail "R2d: no list probe: $(cat "$LOG")"
  grep '^argv=\[list\]' "$LOG" | grep -q "arming=no" || fail "R2d: the arming file existed when pi list ran: $(cat "$LOG")"
  grep '^argv=\[list\]' "$LOG" | grep -Eq "agents=7" || fail "R2d: the .pi/agents files were not all written when pi list ran: $(cat "$LOG")"
  [ -f "$TGT/.harness/.escalation-arming" ] || fail "R2d: the arming file was not written after the preflight"
  pass "gating: no pi => no preflight and no pi call; skip => one line; placement before the arming verdict (R2)"
}

# ══ R3: version probe ═════════════════════════════════════════════════════════════════════
row_version() {
  _id="$(fld 1 "$1")"; CELL="ver-$_id"; mkcell "$CELL"
  _mode="$(fld 2 "$1")"; _want="$(fld 3 "$1")"
  case "$_mode" in
    @missing) inst - - null $ARGS --pi-deps=check "$TGT" ;;
    @nonexec) SBPATH="$NOXDIR:$SANDBOX_PATH"; inst - - null $ARGS --pi-deps=check "$TGT" ;;
    *) ctl "version $_mode"; inst "$CTL" HARNESS_PI_PROBE_TIMEOUT=1 null $ARGS --pi-deps=check "$TGT" ;;
  esac
  want_rc 0
  [ -z "$(printf '%s' "$_mode" | grep -F 'sleep')" ] || :
  case "$_want" in
    ok:*) hasl "pi ${_want#ok:} (>= 1.0.0)"; [ "$(ncalls list)" = 1 ] || fail "$CELL: no list probe after an ok version" ;;
    below:*) hasl "pi ${_want#below:} is below the 1.0.0 floor"; [ "$(ncalls list)" = 0 ] || fail "$CELL: list probed below the floor" ;;
    unknown) hasl "pi version: unknown"; [ "$(ncalls list)" = 0 ] || fail "$CELL: list probed with an unknown version" ;;
    missing) hasl "pi: not found on PATH"; no_pi_calls ;;
    nonexec) if grep -qxF "${L}pi: not found on PATH" "$OUT" || grep -qxF "${L}pi version: unknown" "$OUT"; then :; else fail "$CELL: non-executable pi not reported"; fi
             [ "$(ncalls list)" = 0 ] || fail "$CELL: list probed for a non-executable pi" ;;
  esac
  ESC="$(printf '\033')"
  ! grep -q "$ESC" "$OUT" || fail "$CELL: stdout holds an ESC byte"
  ! grep 'pi preflight' "$OUT" | grep -qF "XTRAJUNK" || fail "$CELL: the report echoes the stub's raw text"
  nof "CANARY"
  [ "$_want" != unknown ] || { ! grep 'pi preflight' "$OUT" | grep -qF "v1.2.0" || fail "$CELL: the report echoes a rejected version"; }
}
test_version_table() {
  while IFS= read -r r; do [ -n "$r" ] || continue; par_add row_version "$r"; done <<'EOF'
missing|@missing|missing
nonexec|@nonexec|nonexec
ok120|ok:1.2.0\n|ok:1.2.0
ok100|ok:1.0.0\n|ok:1.0.0
ok110|ok:1.10.0\n|ok:1.10.0
ok200|ok:2.0.0\n|ok:2.0.0
ok1000|ok:10.0.0\n|ok:10.0.0
rc|ok:1.2.0-rc.1\n|ok:1.2.0-rc.1
plus|ok:1.2.0+b.5\n|ok:1.2.0+b.5
below|ok:0.99.9\n|below:0.99.9
below2|ok:0.100.0\n|below:0.100.0
vpre|ok:v1.2.0\n|unknown
short|ok:1.2\n|unknown
empty|ok:|unknown
nl|ok:\n|unknown
extra|ok:1.2.0\nXTRAJUNK\n|unknown
extra2|ok:XTRAJUNK\n1.2.0\n|unknown
dblnl|ok:1.2.0\n\n|unknown
esc|ok:\0033 1.2.0\n|unknown
esc2|ok:\00331.2.0\n|unknown
trail|ok:1.2.0 \n|unknown
lead|ok: 1.2.0\n|unknown
nul|ok:1.2.0\0\n|unknown
dash|ok:1.2.0-\n|unknown
sufesc|ok:1.2.0-rc\0033[31m\n|unknown
sufnl|ok:1.2.0-rc\nXTRAJUNK\n|unknown
sufsp|ok:1.2.0-rc 1\n|unknown
hugever|ok:1.2.99999999999\n|unknown
four|ok:1.2.0.0\n|unknown
alpha|ok:1.x.0\n|unknown
neg|ok:-1.2.0\n|unknown
rc1|rc:1:1.2.0\n|unknown
sleep|sleep|unknown
huge|huge|unknown
EOF
  par_wait
  pass "version probe: ok/below/unknown/missing over the full grammar table, no list call unless ok (R3)"
}

# ══ R4: trust classification ══════════════════════════════════════════════════════════════
row_trust() {
  _id="$(fld 1 "$1")"; CELL="trust-$_id"; mkcell "$CELL"
  _kind="$(fld 2 "$1")"; _body="$(fld 3 "$1")"; _want="$(fld 4 "$1")"; _reason="$(fld 5 "$1")"
  AD="$CD/home/.pi/agent"; mkdir -p "$AD"
  P="$(dirname "$RT")"
  _body="$(printf '%s' "$_body" | sed "s|@T@|$RT|g;s|@P@|$P|g;s|@L@|$CD/lnk|g")"
  _tgtarg="$TGT"; _env=-
  case "$_kind" in
    none) ;;
    file) printf '%s' "$_body" > "$AD/trust.json" ;;
    bom) printf '\357\273\277%s' "$_body" > "$AD/trust.json" ;;
    dir) mkdir "$AD/trust.json" ;;
    fifo) mkfifo "$AD/trust.json" ;;
    dangling) ln -s "$CD/does-not-exist.json" "$AD/trust.json" ;;
    symlink) printf '%s' "$_body" > "$CD/real-trust.json"; ln -s "$CD/real-trust.json" "$AD/trust.json" ;;
    mode0) [ "$(id -u)" != 0 ] || return 0; printf '%s' "$_body" > "$AD/trust.json"; chmod 000 "$AD/trust.json" ;;
    big) python3 - "$AD/trust.json" "$RT" <<'PYBIG'
import json, sys
d = {"/pad/%d" % i: None for i in range(60000)}
d[sys.argv[2]] = True
open(sys.argv[1], "w").write(json.dumps(d))
PYBIG
         ;;
    link) ln -s "$RT" "$CD/lnk"; printf '%s' "$_body" > "$AD/trust.json"; _tgtarg="$CD/lnk" ;;
    relenv) _env="PI_CODING_AGENT_DIR=rel/dir" ;;
    tilde) mkdir -p "$CD/home/alt"; printf '%s' "$_body" > "$CD/home/alt/trust.json"; _env="PI_CODING_AGENT_DIR=~/alt" ;;
  esac
  ctl "version ok:1.2.0\n"
  inst "$CTL" "$_env" null $ARGS --pi-deps=check "$_tgtarg"; want_rc 0
  case "$_want" in
    unknown) grep -q "^${L}trust: unknown (${_reason:-[a-z-]*})\$" "$OUT" || fail "$CELL: trust not unknown(${_reason:-<reason>}): $(grep 'trust:' "$OUT")" ;;
    *) hasl "trust: $_want" ;;
  esac
  if [ "$_want" = trusted ]; then nof "pi preflight: fix:"; else hasf "pi preflight: fix: run /trust in an interactive pi session"; fi
  if [ "$_want" = undecided ]; then hasf "defaultProjectTrust"; else nof "defaultProjectTrust"; fi
  [ "$_kind" != mode0 ] || chmod 600 "$AD/trust.json"
}
test_trust_table() {
  while IFS= read -r r; do [ -n "$r" ] || continue; par_add row_trust "$r"; done <<'EOF'
absent|none||undecided
empty|file|{}|undecided
exact|file|{"@T@":true}|trusted
exactf|file|{"@T@":false}|distrusted
anc|file|{"@P@":true}|trusted
ancf|file|{"@P@":false}|distrusted
nearest|file|{"@P@":true,"@T@":false}|distrusted
nearest2|file|{"@T@":false,"@P@":true}|distrusted
nullskip|file|{"@P@":true,"@T@":null}|trusted
nullonly|file|{"@T@":null}|undecided
rootkey|file|{"/":true}|trusted
other|file|{"/nowhere":true}|undecided
link|link|{"@L@":true}|undecided
linkreal|link|{"@T@":true}|trusted
bom|bom|{"@T@":true}|trusted
badjson|file|{|unknown|invalid
arr|file|[]|unknown|invalid
yes|file|{"@T@":"yes"}|unknown|invalid
num|file|{"@T@":1}|unknown|invalid
badother|file|{"@T@":true,"x":"y"}|unknown|invalid
nan|file|{"@T@":NaN}|unknown|invalid
str|file|"x"|unknown|invalid
dir|dir||unknown|not-a-file
fifo|fifo||unknown|not-a-file
dangling|dangling||undecided
symlink|symlink|{"@T@":true}|trusted
mode0|mode0|{"@T@":true}|unknown|unreadable
big|big||unknown|too-large
rel|relenv||unknown|agent-dir
tilde|tilde|{"@T@":true}|trusted
EOF
  par_wait
  pass "trust: nearest decided key wins, null skipped, realpath only, every hostile trust.json fails closed (R4)"
}

# ══ R5: pi list -a ════════════════════════════════════════════════════════════════════════
row_list() {
  _id="$(fld 1 "$1")"; CELL="list-$_id"; mkcell "$CELL"
  _mode="$(fld 2 "$1")"; _want="$(fld 3 "$1")"; _pv="$(fld 4 "$1")"; [ -n "$_pv" ] || _pv=0.78.0
  mk_pkg "$RT/.pi/npm/node_modules/pi-subagents" "$_pv"
  mk_pkg "$CD/home/.pi/agent/npm/node_modules/pi-subagents" "$_pv"
  _mode="$(printf '%s' "$_mode" | sed "s|@PP@|$RT/.pi/npm/node_modules/pi-subagents|g;s|@UP@|$CD/home/.pi/agent/npm/node_modules/pi-subagents|g")"
  ctl "version ok:1.2.0\n" "list $_mode"
  inst "$CTL" HARNESS_PI_PROBE_TIMEOUT=1 null $ARGS --pi-deps=check "$TGT"; want_rc 0
  case "$_want" in
    pinned-project) hasl "pi-subagents: pinned 0.78.0 (project)"; hasl "install: not needed" ;;
    pinned-user) hasl "pi-subagents: pinned 0.78.0 (user)"; hasl "install: not needed" ;;
    mismatch-user) hasl "pi-subagents: mismatch (user scope)"; hasl "install: not attempted: user-scope mismatch" ;;
    *) hasl "pi-subagents: $_want" ;;
  esac
  [ "$(ncalls list)" = 1 ] || fail "$CELL: expected exactly one list call"
  grep '^argv=\[list\]' "$LOG" | grep -q '^argv=\[list\] \[-a\] 	' || fail "$CELL: list argv is not exactly 'list -a': $(cat "$LOG")"
  grep '^argv=\[list\]' "$LOG" | grep -q "offline=1" || fail "$CELL: list ran without PI_OFFLINE=1"
  grep '^argv=\[list\]' "$LOG" | grep -q "cwd=$RT" || fail "$CELL: list did not run in the target"
  case "$_want" in pinned-*) nol "install: not approved — run: " ;; esac
}
test_list_table() {
  P='npm:pi-subagents@0.78.0'
  while IFS= read -r r; do [ -n "$r" ] || continue; par_add row_list "$r"; done <<'EOF'
none|text:No packages installed.\n|absent
pproj|text:Project packages:\n  npm:pi-subagents@0.78.0\n    @PP@\n|pinned-project
puser|text:User packages:\n  npm:pi-subagents@0.78.0\n    @UP@\n|pinned-user
both|text:User packages:\n  npm:pi-subagents@0.78.0\n    @UP@\n\nProject packages:\n  npm:pi-subagents@0.78.0\n    @PP@\n|pinned-project
mix1|text:User packages:\n  npm:pi-subagents@0.78.0\n    @UP@\n\nProject packages:\n  npm:pi-subagents@0.77.0\n    /p\n|mismatch
mix2|text:User packages:\n  npm:pi-subagents@0.77.0\n    /u\n\nProject packages:\n  npm:pi-subagents@0.78.0\n    @PP@\n|mismatch-user
mix3|text:Project packages:\n  npm:pi-subagents@0.78.0\n    @PP@\n  npm:pi-subagents@0.77.0\n    /q\n|mismatch
useronly|text:User packages:\n  npm:pi-subagents@0.77.0\n    /u\n|mismatch-user
userpin-fakepath|text:User packages:\n  npm:pi-subagents@0.78.0\n    /fake/path\n|mismatch-user
fakepath|text:Project packages:\n  npm:pi-subagents@0.78.0\n    /fake/path\n|mismatch
wrongscope|text:User packages:\n  npm:pi-subagents@0.78.0\n    @PP@\n|mismatch-user
verother|text:Project packages:\n  npm:pi-subagents@0.78.0\n    @PP@\n|mismatch|0.77.0
vermissing|text:Project packages:\n  npm:pi-subagents@0.78.0\n    @PP@\n|unknown|none
verbad|text:Project packages:\n  npm:pi-subagents@0.78.0\n    @PP@\n|unknown|bad
nopath|text:Project packages:\n  npm:pi-subagents@0.78.0\n|mismatch
filtered|text:Project packages:\n  npm:pi-subagents@0.78.0 (filtered)\n    /p\n|mismatch
old|text:Project packages:\n  npm:pi-subagents@0.77.0\n    /p\n|mismatch
unpinned|text:Project packages:\n  npm:pi-subagents\n    /p\n|mismatch
git|text:Project packages:\n  git:github.com/x/pi-subagents\n    /p\n|mismatch
upper|text:Project packages:\n  npm:Pi-Subagents@0.78.0\n    /p\n|mismatch
trailsp|text:Project packages:\n  npm:pi-subagents@0.78.0 \n    /p\n|mismatch
other|text:Project packages:\n  npm:other-thing@1.0.0\n    /p\n|absent
sgr|text:\0033[1mProject packages:\0033[22m\n  \0033[32mnpm:pi-subagents@0.78.0\0033[39m\n    @PP@\n|pinned-project
garbage|text:hello world\n|unknown
esc|text:Project packages:\n  npm:other\0033[?25h\n    /p\n|unknown
oscesc|text:Project packages:\n  npm:other\0033]0;x\0007\n|unknown
tab|text:Project packages:\n\tnpm:pi-subagents@0.78.0\n|unknown
three|text:Project packages:\n   npm:pi-subagents@0.78.0\n|unknown
nohdr|text:  npm:pi-subagents@0.78.0\n    /p\n|unknown
pathpath|text:Project packages:\n  npm:other\n    /p\n    /q\n|unknown
orphpath|text:Project packages:\n    /p\n|unknown
nopk|text:No packages installed.\nProject packages:\n|unknown
emptyout|text:|unknown
blankonly|text:\n\n|unknown
cr|text:Project packages:\r\n|unknown
rc1|rc:1|unknown
rc1out|rc:1:No packages installed.\n|unknown
sleep|sleep|unknown
huge|huge|unknown
hugeok|hugeok|unknown
EOF
  par_wait
  # `real` rendering drives the same parser from settings files (project and user scope)
  CELL=list-real-p; mkcell "$CELL"; ctl "version ok:1.2.0\n" "list real"
  mk_pkg "$TGT/.pi/npm/node_modules/pi-subagents" 0.78.0; printf '{"packages":["npm:pi-subagents@0.78.0"]}' > "$TGT/.pi/settings.json"
  inst "$CTL" - null $ARGS --pi-deps=check "$TGT"; want_rc 0; hasl "pi-subagents: pinned 0.78.0 (project)"
  CELL=list-real-u; mkcell "$CELL"; ctl "version ok:1.2.0\n" "list real"
  mk_pkg "$CD/home/.pi/agent/npm/node_modules/pi-subagents" 0.78.0; printf '{"packages":["npm:pi-subagents@0.78.0"]}' > "$CD/home/.pi/agent/settings.json"
  inst "$CTL" - null $ARGS --pi-deps=check "$TGT"; want_rc 0; hasl "pi-subagents: pinned 0.78.0 (user)"
  CELL=list-real-m; mkcell "$CELL"; ctl "version ok:1.2.0\n" "list real"
  mk_pkg "$TGT/.pi/npm/node_modules/pi-subagents" 0.77.0; printf '{"packages":["npm:pi-subagents@0.77.0"]}' > "$TGT/.pi/settings.json"
  inst "$CTL" - null $ARGS --pi-deps=check "$TGT"; want_rc 0; hasl "pi-subagents: mismatch"
  # N1: a newline inside a settings source string forges an entry plus a path line; real pi
  # prints the source verbatim. The forged path is not pi's computed location => not pinned.
  CELL=list-real-forge; mkcell "$CELL"; ctl "version ok:1.2.0\n" "list real"
  mkdir -p "$TGT/.pi"; printf '{"packages":["npm:pi-subagents@0.78.0\\n    /fake/path"]}' > "$TGT/.pi/settings.json"
  inst "$CTL" - null $ARGS --pi-deps=check "$TGT"; want_rc 0; hasl "pi-subagents: mismatch"; nof "pinned 0.78.0"
  # N6: the installed package must really be the pin (an on-disk 0.77.0 under a 0.78.0 config)
  CELL=list-real-ver; mkcell "$CELL"; ctl "version ok:1.2.0\n" "list real"
  mk_pkg "$TGT/.pi/npm/node_modules/pi-subagents" 0.77.0; printf '{"packages":["npm:pi-subagents@0.78.0"]}' > "$TGT/.pi/settings.json"
  inst "$CTL" - null $ARGS --pi-deps=check "$TGT"; want_rc 0; hasl "pi-subagents: mismatch"; nof "pinned 0.78.0"
  pass "pi list -a: strict line-shape parse, fail-closed mismatch, argv/cwd/stdin/offline pinned (R5)"
}

# ══ R6: conflicts and dangling agents ═════════════════════════════════════════════════════
row_conflict() {
  _id="$(fld 1 "$1")"; CELL="conf-$_id"; mkcell "$CELL"
  AD="$CD/home/.pi/agent"; mkdir -p "$AD/extensions/subagent" "$AD/agents"
  _ext="$AD/extensions"; _gone=/nonexistent/packages/coding-agent
  _env=-; _wantc=""; _dang=0; _live=0; _dangdir="$AD/agents"
  case "$_id" in
    none) ;;
    regular) : > "$_ext/subagent/index.ts"; _wantc="$_ext/subagent/index.ts" ;;
    dangling) ln -s "$_gone/index.ts" "$_ext/subagent/index.ts"; _wantc="$_ext/subagent/index.ts (dangling symlink)" ;;
    livelink) : > "$CD/real.ts"; ln -s "$CD/real.ts" "$_ext/subagent/index.ts"; _wantc="$_ext/subagent/index.ts" ;;
    indexjs) : > "$_ext/subagent/index.js"; _wantc="$_ext/subagent/index.js" ;;
    pkgjson) : > "$_ext/subagent/package.json"; _wantc="$_ext/subagent/package.json" ;;
    flatts) : > "$_ext/subagent.ts"; _wantc="$_ext/subagent.ts" ;;
    flatjs) ln -s "$_gone/x.js" "$_ext/subagent.js"; _wantc="$_ext/subagent.js (dangling symlink)" ;;
    configonly) : > "$_ext/subagent/config.json" ;;
    agentsts) : > "$_ext/subagent/agents.ts" ;;
    asfile) rm -rf "$_ext/subagent"; : > "$_ext/subagent" ;;
    agents) ln -s "$_gone/a.md" "$AD/agents/a.md"; ln -s "$_gone/b.md" "$AD/agents/b.md"; : > "$AD/agents/live.md"; _dang=2 ;;
    hidden) ln -s "$_gone/.h.md" "$AD/agents/.h.md"; _dang=1 ;;
    unresolvable) : > "$_ext/subagent/index.ts"; _env="PI_CODING_AGENT_DIR=rel/dir" ;;
    projext) mkdir -p "$TGT/.pi/extensions/subagent"; : > "$TGT/.pi/extensions/subagent/index.ts"; _wantc="$TGT/.pi/extensions/subagent/index.ts" ;;
    projdangling) mkdir -p "$TGT/.pi/extensions"; ln -s "$_gone/subagent.ts" "$TGT/.pi/extensions/subagent.ts"; _wantc="$TGT/.pi/extensions/subagent.ts (dangling symlink)" ;;
    homeagents) mkdir -p "$CD/home/.agents"; ln -s "$_gone/a.md" "$CD/home/.agents/a.md"; : > "$CD/home/.agents/live.md"; _dang=1; _dangdir="$CD/home/.agents" ;;
    eschome) _hm="$CD/h$(printf '\033')x"; mkdir -p "$_hm/.agents"; ln -s "$_gone/a.md" "$_hm/.agents/a.md"; _env="HOME=$_hm" ;;
    escdir) _env="PI_CODING_AGENT_DIR=/nonexistent/$(printf '\033')[31mx"; : > "$_ext/subagent/index.ts" ;;
  esac
  ctl "version ok:1.2.0\n"
  inst "$CTL" "$_env" null $ARGS --pi-deps=check "$TGT"; want_rc 0
  if [ -n "$_wantc" ]; then hasl "$CLBL $_wantc"
  else ! grep -q "conflict: a subagent extension" "$OUT" || fail "$CELL: a conflict was reported: $(grep 'pi preflight' "$OUT")"; fi
  if [ "$_dang" -gt 0 ]; then hasf "$_dang dangling symlink(s) under $_dangdir/ (left untouched)"
  else nof "dangling symlink(s)"; fi
  # N5: an agent dir with a control character is unresolvable and never echoed
  if [ "$_id" = eschome ]; then
    ! grep -q "$(printf '\033')" "$OUT" || fail "$CELL: an ESC byte from HOME reached stdout"
  fi
  if [ "$_id" = escdir ]; then
    ! grep -q "$(printf '\033')" "$OUT" || fail "$CELL: an ESC byte reached stdout"
    hasl "trust: unknown (agent-dir)"
  fi
  [ "$_id" != dangling ] || { [ -L "$_ext/subagent/index.ts" ] || fail "$CELL: the dangling link was removed"; }
}
test_conflict_table() {
  for r in none regular dangling livelink indexjs pkgjson flatts flatjs configonly agentsts asfile agents hidden unresolvable projext projdangling homeagents escdir eschome; do
    par_add row_conflict "$r"
  done
  par_wait
  pass "conflict scan: five paths, dangling label, config.json is no conflict, agents dangling count, agent dir untouched (R6)"
}

# ══ R7: bounded, quiet, non-echoing, no python3 ═══════════════════════════════════════════
row_hygiene_sleep() { # <verb> — sleep on one verb with 1 s bounds; the grandchild must die
  CELL="hyg-$1"; mkcell "$CELL"
  case "$1" in
    version) ctl "version sleep" ;;
    list) ctl "version ok:1.2.0\n" "list sleep" ;;
    install) ctl "version ok:1.2.0\n" "install sleep" ;;
  esac
  _t0="$(date +%s)"
  inst "$CTL" "HARNESS_PI_PROBE_TIMEOUT=1 HARNESS_PI_INSTALL_TIMEOUT=1" null $ARGS --pi-deps=install "$TGT"
  _t1="$(date +%s)"
  [ $((_t1 - _t0)) -lt 25 ] || fail "$CELL: the run took $((_t1 - _t0)) s with 1 s bounds"
  [ -s "$LOG.gc" ] || fail "$CELL: the stub did not record its grandchild"
  _gc="$(cat "$LOG.gc")"; _n=0
  while kill -0 "$_gc" 2>/dev/null && [ "$_n" -lt 20 ]; do sleep 0.2; _n=$((_n + 1)); done
  ! kill -0 "$_gc" 2>/dev/null || { kill -9 "$_gc" 2>/dev/null || :; fail "$CELL: the stub's grandchild survived (no process-group kill)"; }
}
test_runner_hygiene() {
  for v in version list install; do par_add row_hygiene_sleep "$v"; done
  # (c) canary: pi's stdout/stderr never reach the installer's stdout
  CELL=hyg-canary; mkcell "$CELL"; ctl "version ok:1.2.0\n" "list text:CANARY-OUT\n"
  inst "$CTL" - null $ARGS --pi-deps=check "$TGT"; want_rc 0
  nof CANARY; ! grep -q CANARY "$ERR" || fail "R7c: a probe's output was echoed to stderr"; hasl "pi-subagents: unknown"
  mkcell hyg-canary2; CELL=hyg-canary2; tier_target; : > "$LOG"; ctl "version ok:1.2.0\n" "install real"
  inst "$CTL" STUB_CANARY=1 null $ARGS --pr-loop=false --pi-deps=install "$TGT"
  nof CANARY; ! grep -q CANARY "$ERR" || fail "R7c/N9: the install's output reached the installer's stderr"
  # a FAILED install keeps its output in a private log and says where (installer-authored line)
  mkcell hyg-canary4; CELL=hyg-canary4; ctl "version ok:1.2.0\n" "install rc:1"
  inst "$CTL" STUB_CANARY=1 null $ARGS --pi-deps=install "$TGT"; want_rc 5
  nof CANARY; ! grep -q CANARY "$ERR" || fail "N9: a failed install's output reached stderr"
  _lg="$(sed -n 's/^   pi preflight: install output kept in //p' "$OUT")"
  [ -n "$_lg" ] && grep -q CANARY-ERR "$_lg" || fail "N9: the failed install's private log is missing or empty ($_lg)"
  rm -f "$_lg"
  # N9: a setsid grandchild of the install must not hold the installer's fds open
  if command -v setsid >/dev/null 2>&1; then
    mkcell hyg-setsid; CELL=hyg-setsid; ctl "version ok:1.2.0\n" "install setsid-real"
    _t0="$(date +%s)"
    { env -i PATH="$STUBDIR:$SBPATH" HOME="$CD/home" CODEX_HOME="$CD/ch" STUB_CTL="$CTL" STUB_LOG="$LOG" sh "$INST" $ARGS --pi-deps=install "$TGT" </dev/null 2>&1; } | cat > "$OUT"
    _t1="$(date +%s)"
    [ $((_t1 - _t0)) -lt 8 ] || fail "N9: a setsid grandchild held the installer's output open for $((_t1 - _t0)) s"
    hasl "install: installed and verified"
  fi
  # canary on the version verb alone (stdout is not a version)
  mkcell hyg-canary3; CELL=hyg-canary3; ctl "version text:CANARY-OUT\n"
  inst "$CTL" - null $ARGS --pi-deps=check "$TGT"; nof CANARY; hasl "pi version: unknown"
  # (d) no python3 on PATH: one skip line, no pi call
  mkcell hyg-nopy; CELL=hyg-nopy; ctl "version ok:1.2.0\n"; SBPATH="$NOPY"
  inst "$CTL" - null $ARGS --pi-deps=check "$TGT"; want_rc 0
  hasl "skipped (python3 not on PATH)"; no_pi_calls
  [ "$(grep -c 'pi preflight:' "$OUT")" = 1 ] || fail "R7d: more than one preflight line without python3: $(cat "$OUT")"
  mkcell hyg-nopy2; CELL=hyg-nopy2; ctl "version ok:1.2.0\n"; SBPATH="$NOPY"
  inst "$CTL" - null $ARGS --pi-deps=install "$TGT"; want_rc 5
  hasl "skipped (python3 not on PATH)"; hasl "install: not attempted: python3 missing"; no_pi_calls
  [ -f "$TGT/.harness/.agents" ] || fail "R11: the run did not finish before exiting 5"
  par_wait
  pass "runner hygiene: process-group kill on every verb, no echo, python3 missing degrades to one line (R7)"
}

# ══ R8: approval semantics ════════════════════════════════════════════════════════════════
row_approval() {
  _id="$(fld 1 "$1")"; CELL="appr-$_id"; mkcell "$CELL"
  _kind="$(fld 2 "$1")"; _env="$(fld 3 "$1")"; _tty="$(fld 4 "$1")"; _typed="$(fld 5 "$1")"; _want="$(fld 6 "$1")"
  [ -n "$_env" ] || _env=-
  ctl "version ok:1.2.0\n"
  case "$_kind" in
    null)   inst "$CTL" "$_env" null $ARGS --pi-deps=check "$TGT" ;;
    nullflag) inst "$CTL" "$_env" null $ARGS --pi-deps=install "$TGT" ;;
    yes)    inst "$CTL" "$_env" yes $ARGS "$TGT" ;;
    yescheck) inst "$CTL" "$_env" yes $ARGS --pi-deps=check "$TGT" ;;
    closed) inst "$CTL" "$_env" closed $ARGS --pi-deps=check "$TGT" ;;
    envonly) inst "$CTL" "$_env" yes "$TGT" ;;
    pty)    pty_inst "$CTL" "$_env" "$_tty" "$_typed" $PTYARGS "$TGT" ;;
    ptyflag) pty_inst "$CTL" "$_env" "$_tty" "$_typed" $PTYARGS --pi-deps=check "$TGT" ;;
  esac
  [ "$RC" = 0 ] || fail "$CELL: exit $RC: $(cat "$OUT") $(cat "$ERR")"
  if [ "$_want" = install ]; then
    [ "$(ncalls install)" = 1 ] || fail "$CELL: expected one pi install: $(cat "$LOG")"
    hasl "install: installed and verified"
  else
    no_install
    hasl "install: not approved — run: (cd '$TGT' && pi install -l -a npm:pi-subagents@0.78.0)"
  fi
}
test_approval() {
  # id|kind|env|tty|typed|want
  while IFS= read -r r; do [ -n "$r" ] || continue; par_add row_approval "$r"; done <<'EOF'
ci|nullflag|CI=true|||install
yespipe|yescheck||||none
yesenv|yes|HARNESS_PI_DEPS=install|||none
closed|closed||||none
null|null||||none
envonly|envonly|HARNESS_AGENTS=pi HARNESS_BUILDER_BACKEND=in-session||||none
ptyy|ptyflag||ie|y\n|install
ptyYES|ptyflag||ie|YES\n|install
ptyyes|ptyflag||ie|yes\n|install
ptysp|ptyflag||ie| y \n|install
ptyenter|ptyflag||ie|\n|none
ptyn|ptyflag||ie|n\n|none
ptyyep|ptyflag||ie|yep\n|none
ptyeof|ptyflag||ie|\x04|none
ptyenvy|pty|HARNESS_PI_DEPS=install|ie|y\n|install
ptyenvn|pty|HARNESS_PI_DEPS=install|ie|\n|none
ptyoutonly|ptyflag||oe||none
ptyoutonly2|ptyflag||o|y\n|none
ptyin_out_errfile|ptyflag||io|y\n|none
ptyinonly|ptyflag||i|y\n|none
ptyerronly|ptyflag||e|y\n|none
EOF
  par_wait
  # the downgrade notice is printed (inside the preflight), exactly once, with the env
  CELL=appr-notice; mkcell "$CELL"; ctl "version ok:1.2.0\n"
  inst "$CTL" HARNESS_PI_DEPS=install yes $ARGS "$TGT"; want_rc 0
  hasl "HARNESS_PI_DEPS=install cannot approve an install — pass --pi-deps=install"
  [ "$(grep -c 'cannot approve' "$OUT")" = 1 ] || fail "R8: the downgrade notice is not printed exactly once"
  # a status of unknown never prompts and never installs, even on a terminal
  CELL=appr-unknown; mkcell "$CELL"; ctl "version ok:1.2.0\n" "list rc:1"
  pty_inst "$CTL" - ie 'y\n' $PTYARGS "$TGT"; want_rc 0
  no_install; hasl "install: not attempted: backend status unknown"; nof "[y/N]"
  CELL=appr-unknown2; mkcell "$CELL"; ctl "version ok:1.2.0\n" "list rc:1"
  inst "$CTL" - null $ARGS --pi-deps=install "$TGT"; want_rc 5
  no_install; hasl "install: not attempted: backend status unknown"
  # a prompt is shown (stderr) naming the package, pin, target and command
  CELL=appr-prompt; mkcell "$CELL"; ctl "version ok:1.2.0\n"
  pty_inst "$CTL" - ie 'n\n' $PTYARGS --pi-deps=check "$TGT"
  hasf "[y/N]"; hasf "pi-subagents 0.78.0"; hasf "$TGT"
  # an umbrella cascade never prompts and never installs, even on a terminal with a typed y
  CELL=appr-umbrella; mkcell "$CELL"; ctl "version ok:1.2.0\n"
  mkdir -p "$CD/u/child"; git init -q "$CD/u/child"; TGT="$CD/u"
  pty_inst "$CTL" - ie 'y\ny\ny\n' --agents=pi --builder-backend=in-session --pr-loop=false --umbrella "$CD/u"
  # exit 3 is the cascade's own uncommitted-upgrade audit (the child is a bare git init), not pi
  case "$RC" in 0|3) ;; *) fail "R8: the cascade exited $RC" ;; esac
  [ "$(grep -c '^argv=\[--version\]' "$LOG")" -ge 1 ] || fail "R8: the cascade never ran the preflight: $(cat "$LOG")"
  no_install; nof "[y/N]"; hasf "install: not approved — run: "
  # a target path containing a single quote: the printed command round-trips through sh -c
  CELL=appr-quote; mkcell "$CELL"; TGT="$CD/it's here"; mkdir -p "$TGT"; ctl "version ok:1.2.0\n"
  inst "$CTL" - null $ARGS --pi-deps=check "$TGT"; want_rc 0; no_install
  _cmd="$(sed -n 's/^   pi preflight: install: not approved — run: //p' "$OUT")"
  [ -n "$_cmd" ] || fail "R8: no printed command for a quoted path"
  : > "$LOG"
  env -i PATH="$STUBDIR:$SANDBOX_PATH" HOME="$CD/home" STUB_CTL="$CTL" STUB_LOG="$LOG" sh -c "$_cmd" >/dev/null 2>&1 \
    || fail "R8: the printed command does not run under sh -c"
  [ "$(ncalls install)" = 1 ] || fail "R8: the printed command did not call pi install once: $(cat "$LOG")"
  grep -q "^argv=\[install\] \[-l\] \[-a\] \[npm:pi-subagents@0.78.0\] 	cwd=$(cd "$TGT" && pwd -P)	" "$LOG" || fail "R8: the printed command ran with the wrong argv/cwd: $(cat "$LOG")"
  pass "approval: only the flag or a typed y/yes at stdin+stderr terminals installs; the env, pipes, closed stdin, stdout-only ttys never do (R8)"
}

# ══ R9 + R11: preconditions, shape matrix, exit status ════════════════════════════════════
# row: id|setup|reason
shape_setup() { # <setup id>  — builds the hostile state inside $TGT; victims live in $CD/v*
  V="$CD/victim"; VD="$CD/victimdir"; MISS="$CD/missing-target"
  printf 'PRISTINE-VICTIM\n' > "$V"; mkdir -p "$VD"; printf 'PRISTINE\n' > "$VD/keep"
  case "$1" in
    pi-symlink) ln -s "$VD" "$TGT/.pi" ;;
    pi-dangling) ln -s "$MISS" "$TGT/.pi" ;;
    pi-file) : > "$TGT/.pi" ;;
    set-symlink) mkdir -p "$TGT/.pi"; ln -s "$V" "$TGT/.pi/settings.json" ;;
    set-dangling) mkdir -p "$TGT/.pi"; ln -s "$MISS" "$TGT/.pi/settings.json" ;;
    set-dir) mkdir -p "$TGT/.pi/settings.json" ;;
    set-fifo) mkdir -p "$TGT/.pi"; mkfifo "$TGT/.pi/settings.json" ;;
    set-hardlink) mkdir -p "$TGT/.pi"; ln "$V" "$TGT/.pi/settings.json" ;;
    set-bom) mkdir -p "$TGT/.pi"; printf '\357\273\277{}' > "$TGT/.pi/settings.json" ;;
    set-nan) mkdir -p "$TGT/.pi"; printf '{"a":NaN}' > "$TGT/.pi/settings.json" ;;
    set-badutf8) mkdir -p "$TGT/.pi"; printf '{"a":"\377"}' > "$TGT/.pi/settings.json" ;;
    set-array) mkdir -p "$TGT/.pi"; printf '[]' > "$TGT/.pi/settings.json" ;;
    set-string) mkdir -p "$TGT/.pi"; printf '"x"' > "$TGT/.pi/settings.json" ;;
    set-pkgstr) mkdir -p "$TGT/.pi"; printf '{"packages":"abc"}' > "$TGT/.pi/settings.json" ;;
    set-pkgobj) mkdir -p "$TGT/.pi"; printf '{"packages":{}}' > "$TGT/.pi/settings.json" ;;
    set-pkgnull) mkdir -p "$TGT/.pi"; printf '{"packages":null}' > "$TGT/.pi/settings.json" ;;
    set-empty) mkdir -p "$TGT/.pi"; : > "$TGT/.pi/settings.json" ;;
    npm-symlink) mkdir -p "$TGT/.pi"; ln -s "$VD" "$TGT/.pi/npm" ;;
    npm-dangling) mkdir -p "$TGT/.pi"; ln -s "$MISS" "$TGT/.pi/npm" ;;
    npm-file) mkdir -p "$TGT/.pi"; : > "$TGT/.pi/npm" ;;
    pkg-symlink) mkdir -p "$TGT/.pi/npm"; ln -s "$V" "$TGT/.pi/npm/package.json" ;;
    pkg-dangling) mkdir -p "$TGT/.pi/npm"; ln -s "$MISS" "$TGT/.pi/npm/package.json" ;;
    pkg-dir) mkdir -p "$TGT/.pi/npm/package.json" ;;
    pkg-hardlink) mkdir -p "$TGT/.pi/npm"; ln "$V" "$TGT/.pi/npm/package.json" ;;
    gi-symlink) mkdir -p "$TGT/.pi/npm"; ln -s "$V" "$TGT/.pi/npm/.gitignore" ;;
    gi-dangling) mkdir -p "$TGT/.pi/npm"; ln -s "$MISS" "$TGT/.pi/npm/.gitignore" ;;
    gi-dir) mkdir -p "$TGT/.pi/npm/.gitignore" ;;
    gi-hardlink) mkdir -p "$TGT/.pi/npm"; ln "$V" "$TGT/.pi/npm/.gitignore" ;;
    nm-symlink) mkdir -p "$TGT/.pi/npm"; ln -s "$VD" "$TGT/.pi/npm/node_modules" ;;
    nm-dangling) mkdir -p "$TGT/.pi/npm"; ln -s "$MISS" "$TGT/.pi/npm/node_modules" ;;
    nm-file) mkdir -p "$TGT/.pi/npm"; : > "$TGT/.pi/npm/node_modules" ;;
    lock-symlink) mkdir -p "$TGT/.pi/npm"; ln -s "$V" "$TGT/.pi/npm/package-lock.json" ;;
    lock-dangling) mkdir -p "$TGT/.pi/npm"; ln -s "$MISS" "$TGT/.pi/npm/package-lock.json" ;;
    lock-dir) mkdir -p "$TGT/.pi/npm/package-lock.json" ;;
    lock-hardlink) mkdir -p "$TGT/.pi/npm"; ln "$V" "$TGT/.pi/npm/package-lock.json" ;;
    shr-symlink) mkdir -p "$TGT/.pi/npm"; ln -s "$V" "$TGT/.pi/npm/npm-shrinkwrap.json" ;;
    shr-dangling) mkdir -p "$TGT/.pi/npm"; ln -s "$MISS" "$TGT/.pi/npm/npm-shrinkwrap.json" ;;
    shr-dir) mkdir -p "$TGT/.pi/npm/npm-shrinkwrap.json" ;;
    shr-hardlink) mkdir -p "$TGT/.pi/npm"; ln "$V" "$TGT/.pi/npm/npm-shrinkwrap.json" ;;
    xtra-symlink) mkdir -p "$TGT/.pi/npm"; ln -s "$V" "$TGT/.pi/npm/extra.txt" ;;
    xtra-hardlink) mkdir -p "$TGT/.pi/npm"; ln "$V" "$TGT/.pi/npm/extra.txt" ;;
    xtra-dir) mkdir -p "$TGT/.pi/npm/extra-dir" ;;
    xtra-hidden) mkdir -p "$TGT/.pi/npm"; ln -s "$V" "$TGT/.pi/npm/.hidden-lock" ;;
    xtra-dotdot) mkdir -p "$TGT/.pi/npm"; ln -s "$V" "$TGT/.pi/npm/..odd" ;;
    ctrl-lockfile) mkdir -p "$TGT/.pi/npm"; printf '{}\n' > "$TGT/.pi/npm/package-lock.json"; printf '{}\n' > "$TGT/.pi/npm/extra.txt" ;;
    ctrl-absent) ;;
    ctrl-theme) mkdir -p "$TGT/.pi"; printf '{"theme":"x"}' > "$TGT/.pi/settings.json" ;;
    ctrl-subagents) mkdir -p "$TGT/.pi"; printf '{"subagents":{}}' > "$TGT/.pi/settings.json" ;;
    ctrl-pkglist) mkdir -p "$TGT/.pi"; printf '{"packages":["npm:other@1.0.0"]}' > "$TGT/.pi/settings.json" ;;
    ctrl-npm) mkdir -p "$TGT/.pi/npm/node_modules/.bin"; ln -s ../x/y "$TGT/.pi/npm/node_modules/.bin/x"
              printf '{}\n' > "$TGT/.pi/npm/package.json"; printf '*\n!.gitignore\n' > "$TGT/.pi/npm/.gitignore" ;;
    trust-false) mkdir -p "$CD/home/.pi/agent"; printf '{"%s":false}' "$RT" > "$CD/home/.pi/agent/trust.json" ;;
    trust-bad) mkdir -p "$CD/home/.pi/agent"; printf '{' > "$CD/home/.pi/agent/trust.json" ;;
    trust-true) mkdir -p "$CD/home/.pi/agent"; printf '{"%s":true}' "$RT" > "$CD/home/.pi/agent/trust.json" ;;
    *) fail "unknown shape setup $1" ;;
  esac
}
row_shape() {
  _id="$(fld 1 "$1")"; CELL="shape-$_id"; mkcell "$CELL"
  _setup="$(fld 2 "$1")"; _want="$(fld 3 "$1")"
  shape_setup "$_setup"
  _vs="$(snap "$CD/victim")|$(snap "$CD/victimdir")"
  ctl "version ok:1.2.0\n"
  inst "$CTL" - null $ARGS --pi-deps=install "$TGT"
  # the victims are byte-pristine, a dangling target still does not exist, the stub never installed
  [ "$(snap "$CD/victim")|$(snap "$CD/victimdir")" = "$_vs" ] || fail "$CELL: a victim outside the target changed"
  [ ! -e "$CD/missing-target" ] && [ ! -L "$CD/missing-target" ] || fail "$CELL: a dangling target was created"
  case "$_want" in
    ok)
      want_rc 0; [ "$(ncalls install)" = 1 ] || fail "$CELL: a safe shape was not installed: $(cat "$LOG")"
      hasl "install: installed and verified" ;;
    *)
      want_rc 5; no_install; hasl "install: not attempted: $_want"
      [ -f "$TGT/.harness/.agents" ] && [ -f "$TGT/.harness/.harness-version" ] || fail "$CELL: the run did not finish its remaining steps before exit 5" ;;
  esac
}
test_shape_matrix() {
  while IFS= read -r r; do [ -n "$r" ] || continue; par_add row_shape "$r"; done <<'EOF'
s01|pi-symlink|unsafe path .pi
s02|pi-dangling|unsafe path .pi
s02b|pi-file|unsafe path .pi
s03|set-symlink|unsafe path .pi/settings.json
s04|set-dangling|unsafe path .pi/settings.json
s05|set-dir|unsafe path .pi/settings.json
s06|set-fifo|unsafe path .pi/settings.json
s07|set-hardlink|unsafe path .pi/settings.json
s08|set-bom|unsafe .pi/settings.json content
s09|set-nan|unsafe .pi/settings.json content
s10|set-badutf8|unsafe .pi/settings.json content
s11|set-array|unsafe .pi/settings.json content
s12|set-string|unsafe .pi/settings.json content
s13|set-pkgstr|unsafe .pi/settings.json content
s14|set-pkgobj|unsafe .pi/settings.json content
s14b|set-pkgnull|unsafe .pi/settings.json content
s14c|set-empty|unsafe .pi/settings.json content
s15|npm-symlink|unsafe path .pi/npm
s16|npm-dangling|unsafe path .pi/npm
s17|npm-file|unsafe path .pi/npm
s18|pkg-symlink|unsafe path .pi/npm/package.json
s19|pkg-dangling|unsafe path .pi/npm/package.json
s20|pkg-dir|unsafe path .pi/npm/package.json
s21|pkg-hardlink|unsafe path .pi/npm/package.json
s22|gi-symlink|unsafe path .pi/npm/.gitignore
s23|gi-dangling|unsafe path .pi/npm/.gitignore
s24|gi-dir|unsafe path .pi/npm/.gitignore
s25|gi-hardlink|unsafe path .pi/npm/.gitignore
s26|nm-symlink|unsafe path .pi/npm/node_modules
s27|nm-dangling|unsafe path .pi/npm/node_modules
s28|nm-file|unsafe path .pi/npm/node_modules
l01|lock-symlink|unsafe path .pi/npm/package-lock.json
l02|lock-dangling|unsafe path .pi/npm/package-lock.json
l03|lock-dir|unsafe path .pi/npm/package-lock.json
l04|lock-hardlink|unsafe path .pi/npm/package-lock.json
l05|shr-symlink|unsafe path .pi/npm/npm-shrinkwrap.json
l06|shr-dangling|unsafe path .pi/npm/npm-shrinkwrap.json
l07|shr-dir|unsafe path .pi/npm/npm-shrinkwrap.json
l08|shr-hardlink|unsafe path .pi/npm/npm-shrinkwrap.json
l09|xtra-symlink|unsafe path .pi/npm/<other>
l10|xtra-hardlink|unsafe path .pi/npm/<other>
l11|xtra-dir|unsafe path .pi/npm/<other>
l12|xtra-hidden|unsafe path .pi/npm/<other>
l13|xtra-dotdot|unsafe path .pi/npm/<other>
c07|ctrl-lockfile|ok
t01|trust-false|project distrusted
t02|trust-bad|project trust unknown
c01|ctrl-absent|ok
c02|ctrl-theme|ok
c03|ctrl-subagents|ok
c04|ctrl-pkglist|ok
c05|ctrl-npm|ok
c06|trust-true|ok
EOF
  par_wait
  # non-path preconditions that come from the pi probe itself
  while IFS='|' read -r id mode want; do
    [ -n "$id" ] || continue
    CELL="pre-$id"; mkcell "$CELL"
    case "$mode" in
      @missing) inst - - null $ARGS --pi-deps=install "$TGT" ;;
      list-unknown) ctl "version ok:1.2.0\n" "list rc:1"; inst "$CTL" - null $ARGS --pi-deps=install "$TGT" ;;
      *) ctl "version $mode"; inst "$CTL" HARNESS_PI_PROBE_TIMEOUT=1 null $ARGS --pi-deps=install "$TGT" ;;
    esac
    want_rc 5; no_install; hasl "install: not attempted: $want"
  done <<'EOF'
missing|@missing|pi missing
below|ok:0.99.0\n|pi below floor
unknown|ok:garbage\n|pi version unknown
listunk|list-unknown|backend status unknown
EOF
  # interactive approval is refused by the same preconditions (and the run still exits 0)
  CELL=pre-ptydistrust; mkcell "$CELL"; shape_setup trust-false; ctl "version ok:1.2.0\n"
  pty_inst "$CTL" - ie 'y\n' $PTYARGS "$TGT"; want_rc 0
  no_install; hasl "install: not attempted: project distrusted"
  pass "preconditions: 28 path shapes x link/type/nlink, settings content, trust, pi state — refused before any pi install; safe controls install (R9, R11)"
}

# ══ R10: install, verify, F03 re-check ════════════════════════════════════════════════════
test_install_verify() {
  # (a) the happy path
  CELL=iv-a; mkcell "$CELL"; tier_target; mkdir -p "$TGT/.pi"; printf '{"theme":"x"}' > "$TGT/.pi/settings.json"
  : > "$LOG"; ctl "version ok:1.2.0\n" "install real"
  inst "$CTL" - null $ARGS --pr-loop=false --pi-deps=install "$TGT"; want_rc 0
  grep -q '^argv=\[install\] \[-l\] \[-a\] \[npm:pi-subagents@0.78.0\] 	' "$LOG" || fail "R10a: install argv is not exactly 'install -l -a npm:pi-subagents@0.78.0': $(cat "$LOG")"
  [ "$(ncalls list)" = 2 ] || fail "R10a: expected a list probe before and after the install: $(cat "$LOG")"
  [ "$(grep -n '^argv=\[' "$LOG" | sed -n 's/^[0-9]*:argv=\[\([^]]*\)\].*/\1/p' | tr '\n' ' ')" = "--version list install list " ] \
    || fail "R10a: probe order is wrong: $(cat "$LOG")"
  hasl "install: installed and verified"; hasl "pi-subagents: absent"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["theme"]=="x" and d["packages"]==["npm:pi-subagents@0.78.0"], d' "$TGT/.pi/settings.json" \
    || fail "R10a: .pi/settings.json lost a key or lacks the pin"
  [ "$(arming_pi)" = raise ] || fail "R10a: pi=$(arming_pi), want raise: $(cat "$TGT/.harness/.escalation-arming")"
  # the upgrade path: re-running with the pin present asks nothing and installs nothing
  : > "$LOG"; inst "$CTL" - null $ARGS --pr-loop=false --pi-deps=install "$TGT"; want_rc 0
  [ "$(ncalls install)" = 0 ] || fail "R11: a pinned backend was reinstalled: $(cat "$LOG")"
  hasl "pi-subagents: pinned 0.78.0 (project)"; hasl "install: not needed"
  # (a2) a mismatching pin is replaced in place
  CELL=iv-a2; mkcell "$CELL"; tier_target; mk_pkg "$TGT/.pi/npm/node_modules/pi-subagents" 0.77.0
  printf '{"packages":["npm:pi-subagents@0.77.0"]}' > "$TGT/.pi/settings.json"
  : > "$LOG"; ctl "version ok:1.2.0\n" "install real"
  inst "$CTL" - null $ARGS --pr-loop=false --pi-deps=install "$TGT"; want_rc 0
  hasl "pi-subagents: mismatch"; hasl "install: installed and verified"
  # (b) exit 0 but nothing landed
  CELL=iv-b; mkcell "$CELL"; ctl "version ok:1.2.0\n" "install noop"
  inst "$CTL" - null $ARGS --pi-deps=install "$TGT"; want_rc 5; hasl "install: failed: not verified"
  # (c) pi adds a subagents key: verified, and the F03 re-check marks pi unstamped
  CELL=iv-c; mkcell "$CELL"; tier_target; : > "$LOG"; ctl "version ok:1.2.0\n" "install add-subagents"
  inst "$CTL" - null $ARGS --pr-loop=false --pi-deps=install "$TGT"; want_rc 0
  hasl "install: installed and verified"
  [ "$(arming_pi)" = unstamped ] || fail "R10c: pi=$(arming_pi), want unstamped (the re-check after install)"
  # (d) the install fails after writing subagents: failed, and the re-check still ran
  CELL=iv-d; mkcell "$CELL"; tier_target; : > "$LOG"; ctl "version ok:1.2.0\n" "install rc1-subagents"
  inst "$CTL" - null $ARGS --pr-loop=false --pi-deps=install "$TGT"; want_rc 5
  hasl "install: failed: exit 1"
  [ "$(arming_pi)" = unstamped ] || fail "R10d: pi=$(arming_pi), want unstamped after a failed install"
  [ "$(ncalls list)" = 1 ] || fail "R10d: a failed install was still verified: $(cat "$LOG")"
  # (e) timeout
  CELL=iv-e; mkcell "$CELL"; ctl "version ok:1.2.0\n" "install sleep"
  inst "$CTL" HARNESS_PI_INSTALL_TIMEOUT=1 null $ARGS --pi-deps=install "$TGT"; want_rc 5
  hasl "install: failed: timed out"
  # (f) interactive y + a failing install: the failure line, but exit 0
  CELL=iv-f; mkcell "$CELL"; ctl "version ok:1.2.0\n" "install rc:1"
  pty_inst "$CTL" - ie 'y\n' $PTYARGS "$TGT"; want_rc 0
  hasl "install: failed: exit 1"
  # (g) the install bound is a real constant: the default is 600 s and 15 s for probes
  grep -q '^PI_PROBE_TIMEOUT="$(pi_bound "${HARNESS_PI_PROBE_TIMEOUT:-}" 15)"$' "$INST" || fail "R7: probe bound is not 15"
  grep -q '^PI_INSTALL_TIMEOUT="$(pi_bound "${HARNESS_PI_INSTALL_TIMEOUT:-}" 600)"$' "$INST" || fail "R7: install bound is not 600"
  pass "install: exact argv, verify probe, F03 re-check before arming, failure/timeout words (R10)"
}

# ══ R11: exit status ══════════════════════════════════════════════════════════════════════
row_exit0() { # pi problems never fail an install in check / skip / env-downgraded mode
  _id="$(fld 1 "$1")"; CELL="exit-$_id"; mkcell "$CELL"
  _mode="$(fld 2 "$1")"; _flags="$(fld 3 "$1")"; _env="$(fld 4 "$1")"; _env2="$_env"; [ -n "$_env" ] || _env=-
  case "$_mode" in
    @missing) inst - "$_env" null $ARGS $_flags "$TGT" ;;
    @distrust) mkdir -p "$CD/home/.pi/agent"; printf '{"%s":false}' "$RT" > "$CD/home/.pi/agent/trust.json"; ctl "version ok:1.2.0\n"; inst "$CTL" "$_env" null $ARGS $_flags "$TGT" ;;
    @badtrust) mkdir -p "$CD/home/.pi/agent"; printf '{' > "$CD/home/.pi/agent/trust.json"; ctl "version ok:1.2.0\n"; inst "$CTL" "$_env" null $ARGS $_flags "$TGT" ;;
    @conflict) mkdir -p "$CD/home/.pi/agent/extensions/subagent"; ln -s /nonexistent/x "$CD/home/.pi/agent/extensions/subagent/index.ts"; ctl "version ok:1.2.0\n"; inst "$CTL" "$_env" null $ARGS $_flags "$TGT" ;;
    *) ctl "version $_mode" "list rc:1"; inst "$CTL" "HARNESS_PI_PROBE_TIMEOUT=1 $_env2" null $ARGS $_flags "$TGT" ;;
  esac
  want_rc 0
}
test_exit_status() {
  while IFS= read -r r; do [ -n "$r" ] || continue; par_add row_exit0 "$r"; done <<'EOF'
chk-missing|@missing|--pi-deps=check|
skip-missing|@missing|--pi-deps=skip|
env-missing|@missing||HARNESS_PI_DEPS=install
chk-unknown|ok:junk\n|--pi-deps=check|
chk-listunk|ok:1.2.0\n|--pi-deps=check|
chk-below|ok:0.5.0\n|--pi-deps=check|
chk-distrust|@distrust|--pi-deps=check|
chk-badtrust|@badtrust|--pi-deps=check|
chk-conflict|@conflict|--pi-deps=check|
env-distrust|@distrust||HARNESS_PI_DEPS=install
env-listunk|ok:1.2.0\n||HARNESS_PI_DEPS=install
EOF
  par_wait
  # flag install with the backend already pinned: success, no install, exit 0
  CELL=exit-pinned; mkcell "$CELL"; ctl "version ok:1.2.0\n" "list real"
  mk_pkg "$TGT/.pi/npm/node_modules/pi-subagents" 0.78.0; printf '{"packages":["npm:pi-subagents@0.78.0"]}' > "$TGT/.pi/settings.json"
  inst "$CTL" - null $ARGS --pi-deps=install "$TGT"; want_rc 0; no_install; hasl "install: not needed"
  # N2: a mismatch in USER scope cannot be fixed by `pi install -l`: refuse up front, run no pi install
  CELL=exit-usermm; mkcell "$CELL"; ctl "version ok:1.2.0\n" "list real"
  mk_pkg "$CD/home/.pi/agent/npm/node_modules/pi-subagents" 0.77.0; printf '{"packages":["npm:pi-subagents@0.77.0"]}' > "$CD/home/.pi/agent/settings.json"
  inst "$CTL" - null $ARGS --pi-deps=install "$TGT"; want_rc 5; no_install
  hasl "pi-subagents: mismatch (user scope)"; hasl "install: not attempted: user-scope mismatch"; hasf "fix: pi install -l only changes the project"
  CELL=exit-usermm2; mkcell "$CELL"; ctl "version ok:1.2.0\n" "list real"
  mk_pkg "$CD/home/.pi/agent/npm/node_modules/pi-subagents" 0.77.0; printf '{"packages":["npm:pi-subagents@0.77.0"]}' > "$CD/home/.pi/agent/settings.json"
  pty_inst "$CTL" - ie 'y\n' $PTYARGS --pi-deps=check "$TGT"; want_rc 0; no_install; nof "[y/N]"
  # flag install, project distrusted: finishes everything, exits 5 with the full artifact set
  CELL=exit-5; mkcell "$CELL"; shape_setup trust-false; ctl "version ok:1.2.0\n"
  inst "$CTL" - null $ARGS --pi-deps=install "$TGT"; want_rc 5
  for f in .agents .harness-version; do [ -f "$TGT/.harness/$f" ] || fail "R11: .harness/$f missing after an exit-5 run"; done
  [ -f "$TGT/.pi/agents/builder.md" ] || fail "R11: the pi agent files were not written before exit 5"
  pass "exit status: 5 only for a flag-approved install that did not end verified; everything else exits 0 (R11)"
}

# ══ R12: docs, manifest, changelog, version ═══════════════════════════════════════════════
test_docs() {
  [ "$(cat "$SRC/VERSION")" = 0.95.0 ] || fail "R12: VERSION is not 0.95.0"
  [ "$(grep -m1 '^## \[' "$SRC/CHANGELOG.md" | sed 's/ —.*//')" = '## [0.95.0]' ] || fail "R12: the newest CHANGELOG heading is not ## [0.95.0]"
  awk '/^## \[0.95.0\]/{k=1;next} /^## \[/{k=0} k' "$SRC/CHANGELOG.md" | grep -q 'E35-F04' || fail "R12: the 0.95.0 changelog entry does not name E35-F04"
  awk '/^## \[0.95.0\]/{k=1;next} /^## \[/{k=0} k' "$SRC/CHANGELOG.md" | tr '\n' ' ' | grep -q 'package-lock.json' || fail "R12: the changelog does not name the npm lockfiles"
  _sec="$(awk '/^### pi$/{k=1;next} /^#{1,3} /{k=0} k' "$SRC/docs/INSTALL.md")"
  for w in '--pi-deps=check' '--pi-deps=install' '--pi-deps=skip' 'HARNESS_PI_DEPS' 'pi install -l -a npm:pi-subagents@0.78.0' 'cannot approve' 'package-lock.json' 'user-scope' 'has no effect' '~/.agents'; do
    printf '%s\n' "$_sec" | grep -qF -- "$w" || fail "R12: the INSTALL.md pi section does not mention '$w'"
  done
  printf '%s\n' "$_sec" | tr '\n' ' ' | grep -qiE 'exit(s)? (status )?5' || fail "R12: the INSTALL.md pi section does not document exit status 5"
  printf '%s\n' "$_sec" | tr '\n' ' ' | grep -qE 'never touches[^.]*\.pi/settings\.json' && fail "R12: the INSTALL.md pi section still claims it never touches .pi/settings.json"
  awk 'NR<40' "$INST" | grep -q -- '--pi-deps' || fail "R12: the installer header does not name --pi-deps"
  CELL=docs-man; mkcell "$CELL"; inst - - null $ARGS --pi-deps=skip "$TGT"; want_rc 0
  grep -q -- '--pi-deps' "$TGT/.harness/manifest.txt" || fail "R12: the installed manifest.txt does not name --pi-deps"
  grep -qF 'PI ENVIRONMENT PREFLIGHT (E35-F04)' "$TGT/.harness/manifest.txt" || fail "R12: manifest.txt lacks the PI ENVIRONMENT PREFLIGHT paragraph"
  # one pin constant: the literal appears exactly once in code (comments and heredoc text aside)
  _n="$(grep -n '0\.78\.0' "$INST" | grep -vE '^[0-9]+:[[:space:]]*#' | wc -l | tr -d ' ')"
  [ "$_n" = 1 ] || fail "R12: the pin literal 0.78.0 appears $_n times in installer code lines (want exactly 1): $(grep -n '0\.78\.0' "$INST" | grep -vE '^[0-9]+:[[:space:]]*#')"
  grep -q '^PI_SUBAGENTS_PIN=0.78.0$' "$INST" || fail "R12: PI_SUBAGENTS_PIN is not the single constant"
  grep -q '^PI_VERSION_FLOOR=1.0.0$' "$INST" || fail "R12: PI_VERSION_FLOOR is not the single constant"
  # non-functional: portable shell only in the pi preflight code
  sh -n "$INST" || fail "sh -n harness-install.sh"
  _pre="$(awk '/pi environment preflight \(E35-F04\) ──/{k=1} /write_escalation_arming — record/{k=0} k' "$INST")"
  printf '%s\n' "$_pre" | grep -vE '^[[:space:]]*#' | grep -qE '(^|[^a-z_-])timeout [0-9]|stat -c|readlink -f' && fail "the preflight uses timeout(1), stat -c or readlink -f"
  pass "docs/manifest/changelog/version name the feature; one pin constant; portable shell (R12)"
}

# The test functions are independent (own cells, own subshell): run them concurrently and print
# their output in order.
run_all() {
  _ra_i=0
  for _ra_f in "$@"; do
    _ra_i=$((_ra_i + 1))
    ( "$_ra_f" ) > "$T/res.$_ra_f" 2>&1 &
    eval "_ra_pid_$_ra_i=$!"
  done
  _ra_i=0; _ra_bad=0
  for _ra_f in "$@"; do
    _ra_i=$((_ra_i + 1))
    eval "_ra_p=\$_ra_pid_$_ra_i"
    wait "$_ra_p" || _ra_bad=1
    cat "$T/res.$_ra_f"
  done
  [ "$_ra_bad" = 0 ] || exit 1
}
run_all test_decision_pure test_mode_parse test_gating test_version_table test_trust_table \
  test_list_table test_conflict_table test_runner_hygiene test_approval test_shape_matrix \
  test_install_verify test_exit_status test_docs
echo "All pi preflight tests passed."
