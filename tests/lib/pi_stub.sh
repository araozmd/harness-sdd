#!/bin/sh
# tests/lib/pi_stub.sh -- the shared hermetic pi sandbox of the pi suites (E35-F04 and E35-F05).
#
# SOURCED by tests/test_pi_preflight.sh (PP) and tests/test_pi_integrity.sh (PI), never run. The
# caller sets SRC (the repo root) and INST ($SRC/harness-install.sh) first; this file provides:
#   T, fail, pass, SANDBOX_PATH, NOPY, STUBDIR (the stub `pi`), ptyrun.py, mkcell/ctl/inst/pty_inst
#   and their assertions, the parallel table runner, and the E35-F05 fixture installer:
#     SYN       a synthetic pi-subagents package (3 files), its tarball, integrity and tree digest
#     FXI       a COPY of the repo whose two PI_SUBAGENTS_INTEGRITY / PI_SUBAGENTS_TREE_SHA256
#               lines are rewritten to the synthetic values (no runtime knob exists, by design)
# One stub, one sandbox, sourced by both suites: a stub copied into two suites is the "body and
# its copy diverge" class (E35-F05 tests.md).

T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-ppf)"
trap '[ -n "${PI_KEEP_T:-}" ] || rm -rf "$T"' EXIT

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

# ── the synthetic pi-subagents package (E35-F05 fixture installer, step 1-2) ────────────────
# The real constants describe the real 2.4 MB tarball, which no test may fetch. So the suites
# use a 3-file SYNTHETIC package; the digest below comes from sha256sum, a deliberately
# DIFFERENT implementation from the installer's python (an independent check of the byte contract).
_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; }
# tree_digest <dir> -- plan "Tree digest": sha256 over the sorted `<sha256-hex>  <relpath>\n` lines
tree_digest() {
  ( cd "$1" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r _f; do _sha256 < "$_f" | sed "s|  -\$|  $_f|"; done ) | _sha256 | sed 's/ .*//'
}
SYN="$T/syn"; mkdir -p "$SYN/package/lib"
printf '{"name":"pi-subagents","version":"0.78.0","dependencies":{"dep":"1.0.0"}}' > "$SYN/package/package.json"
printf 'export default function () {}\n' > "$SYN/package/index.ts"
printf 'module.exports = 2;\n' > "$SYN/package/lib/a.js"
SYN_DIGEST="$(tree_digest "$SYN/package")"
# the digest sorts rows by RELPATH bytes, not by hash: the fixture is only able to tell the two orders
# apart when its hash order differs from its path order (E35-F05 round 1, B1) -- assert that here
_hord="$(cd "$SYN/package" && find . -type f | sed 's|^\./||' | while IFS= read -r _f; do printf '%s %s\n' "$(_sha256 < "$_f" | sed 's/ .*//')" "$_f"; done | LC_ALL=C sort | sed 's/^[^ ]* //' | tr '\n' ' ')"
_pord="$(cd "$SYN/package" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | tr '\n' ' ')"
[ "$_hord" != "$_pord" ] || fail "setup: the synthetic package's hash order equals its path order ($_pord): the digest sort order would be unpinned"
( cd "$SYN" && tar -czf pi-subagents-0.78.0.tgz package )
SYN_INTEGRITY="$(python3 -c 'import base64,hashlib,sys; print("sha512-" + base64.b64encode(hashlib.sha512(open(sys.argv[1],"rb").read()).digest()).decode())' "$SYN/pi-subagents-0.78.0.tgz")"
printf '%s\n' "$SYN_INTEGRITY" > "$SYN/integrity"
case "$SYN_DIGEST" in [0-9a-f]*) [ "${#SYN_DIGEST}" = 64 ] || fail "setup: synthetic tree digest is not 64 hex" ;; *) fail "setup: synthetic tree digest is not hex" ;; esac
# the fixture installer: a COPY of the repo, EXACTLY two lines rewritten (the two pin constants)
FXI_DIR="$T/fx"; mkdir -p "$FXI_DIR"
( cd "$SRC" && for _e in * .[!.]*; do
    case "$_e" in .git|scratchpad|node_modules|progress) continue ;; esac
    [ -e "$_e" ] || [ -L "$_e" ] || continue
    cp -R "$_e" "$FXI_DIR/"
  done )
FXI="$FXI_DIR/harness-install.sh"
sed "s|^PI_SUBAGENTS_INTEGRITY=.*|PI_SUBAGENTS_INTEGRITY=$SYN_INTEGRITY|;s|^PI_SUBAGENTS_TREE_SHA256=.*|PI_SUBAGENTS_TREE_SHA256=$SYN_DIGEST|" "$INST" > "$FXI"
# a void sed reads as a pass (lessons 2026-09): print the applied diff and require EXACTLY 2 changed lines
diff "$INST" "$FXI" > "$T/fxi.diff" || :
[ "$(grep -c '^< ' "$T/fxi.diff")" = 2 ] && [ "$(grep -c '^> ' "$T/fxi.diff")" = 2 ] \
  || fail "setup: the fixture installer differs from the installer in other than exactly 2 lines: $(cat "$T/fxi.diff")"
grep -q "^> PI_SUBAGENTS_INTEGRITY=$SYN_INTEGRITY\$" "$T/fxi.diff" && grep -q "^> PI_SUBAGENTS_TREE_SHA256=$SYN_DIGEST\$" "$T/fxi.diff" \
  || fail "setup: the fixture installer's two changed lines are not the synthetic constants"

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
  real|add-subagents|rc1-subagents|setsid-real|tamper|pnpm-like)
    if [ "$key" = list ]; then
      # real pi throws (or blocks) on a settings.json it cannot read: a FIFO or a directory
      { [ ! -e .pi/settings.json ] || [ -f .pi/settings.json ]; } || exit 1
      python3 - <<'PYLISTREAL'
import json, os
def pk(path):
    try:
        b = open(path, "rb").read()
        if b.startswith(b"\xef\xbb\xbf"):
            b = b[3:]
        d = json.loads(b.decode("utf-8", errors="replace"))
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
# a realistic .pi/npm as real npm leaves it (E35-F05 plan section 4): package.json recording the
# dependency, a v3 package-lock.json whose pi-subagents entry carries the canonical resolved URL
# and the integrity, and the package files. Only the pin's own version has a synthetic tree.
import shutil
ver = spec.rsplit("@", 1)[1]
syn = "@SYN@"
pkgdir = ".pi/npm/node_modules/pi-subagents"
if mode == "pnpm-like":
    real = ".pi/npm/node_modules/.pnpm/pi-subagents@%s/node_modules/pi-subagents" % ver
    shutil.copytree(syn + "/package", real)
    os.symlink(os.path.relpath(real, ".pi/npm/node_modules"), pkgdir)
    open(".pi/npm/pnpm-lock.yaml", "w").write("lockfileVersion: '9.0'\n")
elif ver == "0.78.0":
    shutil.copytree(syn + "/package", pkgdir, dirs_exist_ok=True)
    integ = open(syn + "/integrity").read().strip()
    lock = {"name": "pi-extensions", "lockfileVersion": 3, "requires": True, "packages": {
        "": {"name": "pi-extensions", "dependencies": {"pi-subagents": "^" + ver}},
        "node_modules/pi-subagents": {"version": ver, "resolved": "https://registry.npmjs.org/pi-subagents/-/pi-subagents-%s.tgz" % ver, "integrity": integ}}}
    with open(".pi/npm/package-lock.json", "w") as fh:
        fh.write(json.dumps(lock, indent=2) + "\n")
else:
    os.makedirs(pkgdir, exist_ok=True)
    with open(pkgdir + "/package.json", "w") as fh:
        fh.write(json.dumps({"name": "pi-subagents", "version": ver}))
with open(".pi/npm/package.json", "w") as fh:
    fh.write(json.dumps({"name": "pi-extensions", "private": True, "dependencies": {"pi-subagents": "^" + ver}}) + "\n")
if not os.path.lexists(".pi/npm/.gitignore"):
    with open(".pi/npm/.gitignore", "w") as fh:
        fh.write("*\n!.gitignore\n")
if mode == "tamper":
    with open(pkgdir + "/index.ts", "ab") as fh:
        fh.write(b"X")
with open(".pi/settings.json", "w") as fh:
    fh.write(json.dumps(d, indent=2))
PYINSTALLREAL
      [ "$mode" = setsid-real ] && { setsid sleep 9 & }
      [ "$mode" = rc1-subagents ] && exit 1
    fi ;;
esac
exit 0
STUB
# the stub names the synthetic package dir by absolute path (no env needed: several suites call the
# installer through their own `env -i`)
sed "s|@SYN@|$SYN|g" "$STUBDIR/pi" > "$STUBDIR/pi.new" && mv "$STUBDIR/pi.new" "$STUBDIR/pi"
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
# mk_syn_install <target> -- a realistic, VERIFIABLE project install of the synthetic package, as
# the stub's `install real` leaves it: package.json, a v3 package-lock.json with the canonical
# resolved URL and the synthetic integrity, and the 3 package files (E35-F05 plan section 4)
mk_syn_install() {
  mkdir -p "$1/.pi/npm/node_modules"
  cp -R "$SYN/package" "$1/.pi/npm/node_modules/pi-subagents"
  printf '{"name":"pi-extensions","private":true,"dependencies":{"pi-subagents":"^0.78.0"}}\n' > "$1/.pi/npm/package.json"
  printf '*\n!.gitignore\n' > "$1/.pi/npm/.gitignore"
  mk_lock "$1/.pi/npm/package-lock.json" "$SYN_INTEGRITY"
}
# mk_lock <file> <integrity|-> [version] -- a v3 lockfile with the pi-subagents entry (no integrity
# field for `-`)
mk_lock() {
  python3 - "$1" "$2" "${3:-0.78.0}" <<'PYLOCK'
import json, sys
f, integ, ver = sys.argv[1:4]
e = {"version": ver, "resolved": "https://registry.npmjs.org/pi-subagents/-/pi-subagents-%s.tgz" % ver}
if integ != "-":
    e["integrity"] = integ
json.dump({"name": "pi-extensions", "lockfileVersion": 3, "requires": True, "packages": {
    "": {"name": "pi-extensions", "dependencies": {"pi-subagents": "^" + ver}},
    "node_modules/pi-subagents": e}}, open(f, "w"), indent=2)
PYLOCK
  [ $? = 0 ] || fail "mk_lock: python failed"
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

# parallel table runner: rows on stdin, `ROWFN row` per row, as background jobs. ONE shared
# worker limit: the test groups run sequentially (run_all below), so at most PPF_JOBS installer
# jobs run at once suite-wide. Default: online CPUs clamped to [2, 8]; override with PPF_JOBS.
_ncpu="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 2)"
case "$_ncpu" in ''|*[!0-9]*) _ncpu=2 ;; esac
[ "$_ncpu" -ge 2 ] || _ncpu=2; [ "$_ncpu" -le 8 ] || _ncpu=8
PPF_JOBS="${PPF_JOBS:-$_ncpu}"
case "$PPF_JOBS" in ''|*[!0-9]*|0) fail "PPF_JOBS must be a positive integer, got '$PPF_JOBS'" ;; esac
PIDS=""
par_add() { ( "$@" ) & PIDS="$PIDS $!"; _n=$(( ${_n:-0} + 1 )); [ "$_n" -lt "$PPF_JOBS" ] || par_wait; }
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
