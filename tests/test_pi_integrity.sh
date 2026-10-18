#!/bin/sh
# test_pi_integrity.sh -- E35-F05, the integrity pin of the pi-subagents install: pre-install
# npm-steering guards (R1-R5, R7) and the post-install byte verification (R8-R10).
#
# Covers R1-R12 of specs/epics/E35-pi-first-class/F05-pi-subagents-integrity-pin/.
#
# HERMETIC, exactly as test_pi_preflight.sh: both suites source tests/lib/pi_stub.sh (the sandbox
# PATH without any real `pi`, `env -i` with an isolated HOME, the STUB_CTL/STUB_LOG stub). No case
# runs the real pi; the real-npm rows drive the real `npm` against a LOCAL registry on 127.0.0.1.
#
# FIXTURE INSTALLER. The real pin constants describe the real 2.4 MB tarball, which no test may
# fetch, so the suite runs a COPY of the repo whose two constant lines are rewritten to a
# synthetic 3-file package (INST = the real file, FXI = the copy; the lib asserts the copy differs
# in exactly 2 lines). One row runs the UNPATCHED installer to prove the shipped constants are not
# the synthetic ones.
#
# HOSTILE TABLES IN ROUND 1 (progress/lessons.md 2026-10-14/16/17). Every row that names a
# mutant in E35-F05.tests.md is listed with it in a `# kills:` comment.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INST="$SRC/harness-install.sh"
SRCINST="$INST"
. "$SRC/tests/lib/pi_stub.sh"
INST="$FXI"
ESC="$(printf '\033')"

# ── the lockfile generator: the empirical v3 lockfile (7 canonical entries) + hostile variants ──
cat > "$T/lockgen.py" <<'PYLOCKGEN'
import json, sys
out, var, synint = sys.argv[1], sys.argv[2], sys.argv[3]
EVIL = "http://127.0.0.1:1/evil/jiti-2.7.0.tgz"
DEPS = [("jiti", "2.7.0"), ("yaml", "2.8.3"), ("acorn", "8.18.0"), ("undici", "8.10.2"), ("@js-temporal/polyfill", "0.5.1"), ("jsbi", "4.3.2")]
def url(name, ver):
    return "https://registry.npmjs.org/%s/-/%s-%s.tgz" % (name, name.split("/")[-1], ver)
def ent(name, ver, **kw):
    d = {"version": ver, "resolved": url(name, ver), "integrity": "sha512-AAAA"}
    d.update(kw)
    return d
def base():
    pk = [("", {"name": "pi-extensions", "dependencies": {"pi-subagents": "^0.78.0"}}),
          ("node_modules/pi-subagents", ent("pi-subagents", "0.78.0", integrity=synint))]
    for n, v in DEPS:
        pk.append(("node_modules/" + n, ent(n, v)))
    return pk
def setk(pk, k, v):
    return [(a, v if a == k else b) for a, b in pk]
def raw(pk, name="pi-extensions"):
    body = ",\n".join('%s: %s' % (json.dumps(k), json.dumps(v)) for k, v in pk)
    return '{"name": %s, "lockfileVersion": 3, "requires": true, "packages": {\n%s\n}}\n' % (json.dumps(name), body)
pk = base()
data = None
if var == "base":
    pass
elif var == "dep-url":
    pk = setk(pk, "node_modules/jiti", ent("jiti", "2.7.0", resolved=EVIL))
elif var == "v1":
    data = json.dumps({"lockfileVersion": 1, "dependencies": {"jiti": {"version": "2.7.0", "resolved": EVIL}}})
elif var == "dup-last":
    pk = pk + [("node_modules/jiti", ent("jiti", "2.7.0", resolved=EVIL))]
elif var == "dup-first":
    pk = [("node_modules/jiti", ent("jiti", "2.7.0", resolved=EVIL))] + pk
elif var == "bom-evil":
    pk = setk(pk, "node_modules/jiti", ent("jiti", "2.7.0", resolved=EVIL))
    data = b"\xef\xbb\xbf" + raw(pk, name="pi-\udcff").encode("utf-8", "surrogateescape").replace(b"\\udcff", b"\xff")
elif var == "noresolved":
    pk = setk(pk, "node_modules/jiti", {"version": "2.7.0"})
elif var == "scoped-leaf":
    pk = setk(pk, "node_modules/@js-temporal/polyfill", ent("@js-temporal/polyfill", "0.5.1", resolved="https://registry.npmjs.org/@js-temporal/polyfill/-/@js-temporal/polyfill-0.5.1.tgz"))
elif var == "ver":
    pk = setk(pk, "node_modules/jiti", ent("jiti", "2.7.0", resolved=url("jiti", "2.6.0")))
elif var == "ver-traversal":
    v = "2.7.0/../../../evil/-/evil-1.0.0"
    pk = setk(pk, "node_modules/jiti", ent("jiti", v))
elif var == "nonobj-entry":
    pk = setk(pk, "node_modules/jiti", "x")
elif var == "http":
    pk = setk(pk, "node_modules/jiti", ent("jiti", "2.7.0", resolved="http://registry.npmjs.org/jiti/-/jiti-2.7.0.tgz"))
elif var == "query":
    pk = setk(pk, "node_modules/jiti", ent("jiti", "2.7.0", resolved=url("jiti", "2.7.0") + "?x"))
elif var == "mirror":
    pk = setk(pk, "node_modules/jiti", ent("jiti", "2.7.0", resolved="https://registry.yarnpkg.com/jiti/-/jiti-2.7.0.tgz"))
elif var == "link":
    pk = setk(pk, "node_modules/jiti", {"link": True, "resolved": "w1"})
elif var == "key":
    pk = pk + [("x/node_modules/jiti", ent("jiti", "2.7.0"))]
elif var == "key2":
    # a key that fails the grammar but whose URL (formula output, "../" included) passes the equality
    # and normalizes to the OFFICIAL jiti tarball: only the key grammar refuses it
    pk = [(a, b) for a, b in pk if a != "node_modules/jiti"] + [("node_modules/a/../jiti", ent("jiti", "2.7.0", resolved="https://registry.npmjs.org/a/../jiti/-/jiti-2.7.0.tgz"))]
elif var == "ctrl-other":
    pk = pk + [("node_modules/left-pad", ent("left-pad", "1.3.0"))]
elif var == "ctrl-nested":
    pk = pk + [("node_modules/yaml/node_modules/jiti", ent("jiti", "2.7.0"))]
elif var == "big":
    txt = raw(pk)
    data = txt.rstrip("\n") + " " * (4194304 + 1 - len(txt.rstrip("\n").encode()))
elif var == "bigok":
    txt = raw(pk)
    data = txt.rstrip("\n") + " " * (4194304 - len(txt.rstrip("\n").encode()))
elif var == "nan":
    data = '{"lockfileVersion": NaN, "packages": {}}'
elif var == "inf":
    data = '{"lockfileVersion": Infinity, "packages": {}}'
elif var == "ninf":
    data = '{"lockfileVersion": -Infinity, "packages": {}}'
else:
    raise SystemExit("unknown variant " + var)
if data is None:
    data = raw(pk)
with open(out, "wb") as fh:
    fh.write(data if isinstance(data, bytes) else data.encode("utf-8"))
PYLOCKGEN
lockgen() { python3 "$T/lockgen.py" "$1" "$2" "$SYN_INTEGRITY" || fail "setup: lockgen $2"; }

# ── cell + assertions ──────────────────────────────────────────────────────────────────────
NMFIX="fix: npm keeps whatever is already in .pi/npm/node_modules; remove that directory and re-run, and npm reinstalls every listed package from the registry"
cellprep() { # <name> -- a trusted target with the stub: pi 1.2.0, backend absent, `install real`
  CELL="$1"; mkcell "$CELL"; mkdir -p "$TGT/.pi" "$CD/home/.pi/agent"
  printf '{"%s":true}' "$RT" > "$CD/home/.pi/agent/trust.json"
  NPM="$TGT/.pi/npm"
  ctl "version ok:1.2.0\n" "install real"
}
run_flag() { inst "$CTL" - null $ARGS --pi-deps=install "$TGT"; }
last_verb() { tail -n 1 "$LOG" | sed 's/^argv=\[\([^]]*\)\].*/\1/'; }
no_esc() { ! grep -q "$ESC" "$OUT" || fail "$CELL: an ESC byte reached stdout"; }
# A refusal (common assertions): the exact reason, nothing run after the `list -a` probe, exit 5,
# the run finished its remaining steps, no ESC
refused() { # <reason> [fixline]
  want_rc 5; no_install
  hasl "install: not attempted: $1"
  [ "$(last_verb)" = list ] || fail "$CELL: a pi record follows the list probe: $(cat "$LOG")"
  [ "$(grep -c . "$LOG")" = 2 ] || fail "$CELL: expected exactly the version + list records: $(cat "$LOG")"
  [ -f "$TGT/.harness/.agents" ] && [ -f "$TGT/.harness/.harness-version" ] || fail "$CELL: the run did not finish its remaining steps before exit 5"
  if [ -n "${2:-}" ]; then hasl "$2"; else nof "pi preflight: fix: npm keeps"; fi
  no_esc
}
installed() { # a control: the install ran and verified
  want_rc 0; [ "$(ncalls install)" = 1 ] || fail "$CELL: the control did not install: $(grep 'pi preflight' "$OUT" | cut -c1-200)"
  hasl "install: installed and verified"; no_esc
}
GOODPKG='{"name":"pi-extensions","private":true,"dependencies":{"pi-subagents":"^0.78.0"}}'

# ══ R1: project npmCommand / __proto__ ═════════════════════════════════════════════════════
row_npmcmd() {
  _id="$1"; cellprep "npmcmd-$_id"
  case "$_id" in
    p-plain)   printf '{"npmCommand":["x"]}' > "$TGT/.pi/settings.json" ;;
    p-proto)   printf '{"__proto__":{"npmCommand":["x"]}}' > "$TGT/.pi/settings.json" ;;
    p-protoempty) printf '{"__proto__":{}}' > "$TGT/.pi/settings.json" ;;
    p-nested)  printf '{"a":{"npmCommand":1}}' > "$TGT/.pi/settings.json" ;;
    p-inarray) printf '{"a":[{"b":{"npmCommand":1}}]}' > "$TGT/.pi/settings.json" ;;
    p-null)    printf '{"npmCommand":null}' > "$TGT/.pi/settings.json" ;;
    p-emptyarr) printf '{"npmCommand":[]}' > "$TGT/.pi/settings.json" ;;
    p-emptystr) printf '{"npmCommand":""}' > "$TGT/.pi/settings.json" ;;
    p-dupnest) printf '{"a":{"npmCommand":1},"a":{}}' > "$TGT/.pi/settings.json" ;;
    p-dupfirst) printf '{"npmCommand":["x"],"npmCommand":null}' > "$TGT/.pi/settings.json" ;;
    p-esc)     printf '{"npm\\u0043ommand":["x"]}' > "$TGT/.pi/settings.json" ;;
    p-esc2)    printf '{"\\u005f_proto__":{}}' > "$TGT/.pi/settings.json" ;;
    u-allowed) printf '{"npmCommand":["npm"]}' > "$CD/home/.pi/agent/settings.json" ;;
    u-proto)   printf '{"__proto__":{"npmCommand":["x"]}}' > "$CD/home/.pi/agent/settings.json" ;;
    u-unreadable) printf '{"npmCommand":["x"],' > "$CD/home/.pi/agent/settings.json" ;;
    u-pnpm)    printf '{"npmCommand":["pnpm"]}' > "$CD/home/.pi/agent/settings.json"; ctl "version ok:1.2.0\n" "install pnpm-like" ;;
    ctrl)      printf '{"packages":[]}' > "$TGT/.pi/settings.json" ;;
    *) fail "unknown R1 row $_id" ;;
  esac
  _us="$(snap "$CD/home/.pi/agent/settings.json")"
  run_flag
  [ "$(snap "$CD/home/.pi/agent/settings.json")" = "$_us" ] || fail "$CELL: the user settings file changed"
  case "$_id" in
    p-*) refused "npm command override (project settings)" ;;
    u-unreadable) want_rc 5; no_install; hasl "install: not attempted: backend status unknown"
                  ! grep -qE 'npm command override|existing .pi|unexpected entry|unsafe .pi/npm|lockfile' "$OUT" || fail "$CELL: an F05 reason replaced F04's (the user file must not be read by F05)" ;;
    u-pnpm) want_rc 5; [ "$(ncalls install)" = 1 ] || fail "$CELL: the non-npm install did not run (R1 must not refuse a user-scope npmCommand)"
            hasl "install: failed: not verified"; no_esc ;;
    *) installed ;;
  esac
}
test_npm_command() {
  # kills: M1a (R1 removed / project file not read) p-plain; M1c (only npmCommand matched) p-proto;
  # M1d (top level only) p-nested/p-inarray; M1e (value truthiness) p-null/p-emptyarr/p-emptystr;
  # M1f (final dict only) p-dupnest/p-dupfirst; M1g (raw-byte search) p-esc/p-esc2;
  # M1b (user file checked too) u-allowed/u-proto/u-pnpm; u-unreadable pins no F05 user read
  for r in p-plain p-proto p-protoempty p-nested p-inarray p-null p-emptyarr p-emptystr p-dupnest p-dupfirst p-esc p-esc2 u-allowed u-proto u-unreadable u-pnpm ctrl; do par_add row_npmcmd "$r"; done
  par_wait
  pass "R1: a project npmCommand/__proto__ key at any depth refuses; the user scope never does and is never read by F05"
}

# ══ R2: an existing .pi/npm/node_modules ════════════════════════════════════════════════
row_nm() {
  _id="$1"; cellprep "nm-$_id"
  case "$_id" in
    empty) mkdir -p "$NPM/node_modules" ;;
    prior) mk_pkg "$NPM/node_modules/pi-subagents" 0.77.0; mk_pkg "$NPM/node_modules/jiti" 2.7.0
           printf '{"packages":["npm:pi-subagents@0.77.0"]}' > "$TGT/.pi/settings.json"
           printf '{"name":"pi-extensions","private":true,"dependencies":{"pi-subagents":"^0.77.0"}}\n' > "$NPM/package.json"
           mk_lock "$NPM/package-lock.json" - 0.77.0; mk_lock "$NPM/npm-shrinkwrap.json" - 0.77.0 ;;
    bin-inside) mkdir -p "$NPM/node_modules/.bin"; ln -s ../pi-subagents/y "$NPM/node_modules/.bin/x" ;;
    nm-file) mkdir -p "$NPM"; : > "$NPM/node_modules" ;;
    nm-link) mkdir -p "$NPM" "$CD/elsewhere"; ln -s "$CD/elsewhere" "$NPM/node_modules" ;;
    *) fail "unknown R2 row $_id" ;;
  esac
  run_flag
  case "$_id" in
    nm-file|nm-link) want_rc 5; no_install; hasl "install: not attempted: unsafe path .pi/npm/node_modules"; nof "pi preflight: fix: npm keeps" ;;
    *) refused "existing .pi/npm/node_modules" "$NMFIX" ;;
  esac
  [ "$_id" != prior ] || hasl "pi-subagents: mismatch"
}
test_node_modules() {
  # kills: M2a (R2 removed) empty/prior; M2b (F04's .bin exception removed) bin-inside reds with
  # F04's reason instead of R2's; nm-file/nm-link pin the F04-first precedence
  for r in empty prior bin-inside nm-file nm-link; do par_add row_nm "$r"; done
  par_wait
  pass "R2: any existing .pi/npm/node_modules refuses with the fix line; F04's link/type refusals keep precedence"
}

# ══ R3: the .pi/npm entry allow-list ════════════════════════════════════════════════════
row_entries() {
  _id="$1"; cellprep "entries-$_id"; mkdir -p "$NPM"
  case "$_id" in
    yarn) printf '# yarn lockfile v1\n' > "$NPM/yarn.lock" ;;
    etc-npmrc) mkdir -p "$NPM/etc"; printf 'loglevel=silly\n' > "$NPM/etc/npmrc" ;;
    pnpm) printf "lockfileVersion: '9.0'\n" > "$NPM/pnpm-lock.yaml" ;;
    ws) mkdir -p "$NPM/w1"; printf '{}' > "$NPM/w1/package.json" ;;
    readme) printf 'x\n' > "$NPM/README" ;;
    escname) : > "$NPM/x$(printf '\033')[31m" ;;
    npmrc) printf 'registry=x\n' > "$NPM/.npmrc" ;;
    ctrl-all4) printf '%s\n' "$GOODPKG" > "$NPM/package.json"; printf '*\n!.gitignore\n' > "$NPM/.gitignore"
               mk_lock "$NPM/package-lock.json" "$SYN_INTEGRITY"; mk_lock "$NPM/npm-shrinkwrap.json" "$SYN_INTEGRITY" ;;
    *) fail "unknown R3 row $_id" ;;
  esac
  run_flag
  case "$_id" in
    npmrc) want_rc 5; no_install; hasl "install: not attempted: unsafe path .pi/npm/.npmrc" ;;
    ctrl-all4) installed ;;
    *) refused "unexpected entry in .pi/npm" ;;
  esac
}
test_prefix_entries() {
  # kills: M3a (R3 removed) yarn/pnpm/ws; M3b (deny-list of lockfile names) readme/escname;
  # M3c (the name echoed) escname; M3d (an allowed name missing from the allow-list) ctrl-all4
  for r in yarn etc-npmrc pnpm ws readme escname npmrc ctrl-all4; do par_add row_entries "$r"; done
  par_wait
  pass "R3: the .pi/npm direct children are an allow-list; the refusal text never echoes a name"
}

# ══ R4: .pi/npm/package.json ═══════════════════════════════════════════════════════════
R4W="unsafe .pi/npm/package.json content"
row_pkgjson() {
  _id="$1"; cellprep "pkgjson-$_id"; mkdir -p "$NPM"; _f="$NPM/package.json"; _want=refuse
  case "$_id" in
    overrides) printf '{"overrides":{"jiti":"https://x/j.tgz"}}' > "$_f" ;;
    workspaces) printf '{"workspaces":["w1"]}' > "$_f" ;;
    devdeps) printf '{"devDependencies":{"jiti":"1.0.0"}}' > "$_f" ;;
    optdeps) printf '{"optionalDependencies":{"jiti":"1.0.0"}}' > "$_f" ;;
    scripts) printf '{"scripts":{"postinstall":"x"}}' > "$_f" ;;
    version) printf '{"name":"x","version":"1.0.0"}' > "$_f" ;;
    url) printf '{"dependencies":{"jiti":"https://x/j.tgz"}}' > "$_f" ;;
    file) printf '{"dependencies":{"jiti":"file:../x"}}' > "$_f" ;;
    git) printf '{"dependencies":{"jiti":"git+https://x"}}' > "$_f" ;;
    alias) printf '{"dependencies":{"jiti":"npm:evil@1.0.0"}}' > "$_f" ;;
    tag) printf '{"dependencies":{"jiti":"latest"}}' > "$_f" ;;
    range) printf '{"dependencies":{"jiti":">=1.0.0 <2"}}' > "$_f" ;;
    or) printf '{"dependencies":{"jiti":"1.0.0 || 2.0.0"}}' > "$_f" ;;
    nonstr) printf '{"dependencies":{"jiti":1}}' > "$_f" ;;
    depsarray) printf '{"dependencies":[]}' > "$_f" ;;
    nl) printf '{"dependencies":{"jiti":"^1.0.0\\n"}}' > "$_f" ;;
    nonobj) printf '[]' > "$_f" ;;
    dup) printf '{"dependencies":{"x":"^1.0.0"},"dependencies":{}}' > "$_f" ;;
    dupdeep) printf '{"dependencies":{"x":"^1.0.0","x":"^1.0.0"}}' > "$_f" ;;
    nan) printf '{"name":NaN}' > "$_f" ;;
    inf) printf '{"name":Infinity}' > "$_f" ;;
    ninf) printf '{"name":-Infinity}' > "$_f" ;;
    unparsable) printf '{' > "$_f" ;;
    ctrl-pi) printf '{"name":"pi-extensions","private":true}' > "$_f"; _want=ok ;;
    ctrl-npm) printf '{"name":"pi-extensions","private":true,"dependencies":{"pi-subagents":"^0.78.0","other":"1.2.3"}}' > "$_f"; _want=ok ;;
    ctrl-forms) printf '{"dependencies":{"a":"1.2.3","b":"~1.2.3","c":"^1.2.3-rc.1+build.5","d":"0.0.0"}}' > "$_f"; _want=ok ;;
    ctrl-bom) printf '\357\273\277%s' "$GOODPKG" > "$_f"; _want=ok ;;
    ctrl-ff) printf '{"name":"pi-\377","private":true}' > "$_f"; _want=ok ;;
    *) fail "unknown R4 row $_id" ;;
  esac
  run_flag
  if [ "$_want" = ok ]; then installed; else refused "$R4W"; fi
}
test_package_json() {
  # kills: M4a (top-level key allow-list removed) overrides..scripts/version; M4b (value grammar
  # removed) url..depsarray; M4c (re.match with $) nl; M4d (duplicate keys accepted) dup/dupdeep;
  # nonobj (fail-closed: [] has no keys to check); M4e (dependencies missing from the allow-list)
  # ctrl-npm; M6a (strict decode, no BOM strip) ctrl-bom; M6b (strict UTF-8) ctrl-ff
  for r in overrides workspaces devdeps optdeps scripts version url file git alias tag range or nonstr depsarray nl nonobj dup dupdeep nan inf ninf unparsable ctrl-pi ctrl-npm ctrl-forms ctrl-bom ctrl-ff; do par_add row_pkgjson "$r"; done
  par_wait
  pass "R4: .pi/npm/package.json keys and dependency specs are allow-listed, duplicates and unreadable forms refuse"
}

# ══ R5 + R6: lockfiles ═════════════════════════════════════════════════════════════════════
row_lock() {
  _id="$1"; _file="$2"; _want="$3"; cellprep "lock-$_id-$_file"; mkdir -p "$NPM"
  case "$_id" in
    sw-url) lockgen "$NPM/npm-shrinkwrap.json" dep-url; _file=npm-shrinkwrap.json ;;
    order) lockgen "$NPM/package-lock.json" dep-url; lockgen "$NPM/npm-shrinkwrap.json" dep-url; _file=package-lock.json ;;
    *) lockgen "$NPM/$_file" "$_id" ;;
  esac
  run_flag
  case "$_want" in
    ok) installed ;;
    *) refused "lockfile $_file $_want" ;;
  esac
}
test_lockfiles() {
  # kills: M5a (resolved not checked) dep-url; M5b (only package-lock.json checked) sw-url;
  # M5c (missing packages treated as empty) v1; M5d (no duplicate rule) dup-last/dup-first;
  # M6a/M6b (strict decode: reads `unreadable`) bom-evil; M5e (missing resolved accepted)
  # noresolved; M5f (leaf = the full scoped name) scoped-leaf; M5f' (a wrong leaf for the scoped
  # control) ctrl-scoped = base; M5g (version not part of the URL) ver; M5k (version grammar
  # missing, or after the URL equality) ver-traversal; M5h (prefix match) http/query/mirror;
  # M5i (key grammar removed) key2 (key: the URL check alone already refuses it); M5j (order swapped) order; M6e (no size cap) big; M6c nan
  while IFS='|' read -r id file want; do
    [ -n "$id" ] || continue; par_add row_lock "$id" "$file" "$want"
  done <<'EOF'
base|package-lock.json|ok
base|npm-shrinkwrap.json|ok
ctrl-other|package-lock.json|ok
ctrl-nested|package-lock.json|ok
dep-url|package-lock.json|not canonical
sw-url|npm-shrinkwrap.json|not canonical
v1|package-lock.json|unreadable
v1|npm-shrinkwrap.json|unreadable
dup-last|package-lock.json|ambiguous
dup-first|package-lock.json|ambiguous
dup-last|npm-shrinkwrap.json|ambiguous
bom-evil|package-lock.json|not canonical
noresolved|package-lock.json|not canonical
scoped-leaf|package-lock.json|not canonical
ver|package-lock.json|not canonical
ver-traversal|package-lock.json|not canonical
nonobj-entry|package-lock.json|not canonical
http|package-lock.json|not canonical
query|package-lock.json|not canonical
mirror|package-lock.json|not canonical
link|package-lock.json|not canonical
key|package-lock.json|not canonical
key2|package-lock.json|not canonical
order|package-lock.json|not canonical
big|package-lock.json|unreadable
bigok|package-lock.json|ok
nan|package-lock.json|unreadable
inf|package-lock.json|unreadable
ninf|package-lock.json|unreadable
EOF
  par_wait
  pass "R5/R6: lockfiles need packages, no duplicate keys and exact canonical registry URLs; unreadable forms refuse"
}

row_lock_raw() { # <id>
  _id="$1"; cellprep "lockraw-$_id"; mkdir -p "$NPM"
  case "$_id" in
    notjson) printf 'not json' > "$NPM/package-lock.json" ;;
    emptypk) printf '{"packages":{}}' > "$NPM/package-lock.json" ;;
    pkarray) printf '{"packages":[]}' > "$NPM/package-lock.json" ;;
    toparray) printf '[]' > "$NPM/package-lock.json" ;;
    fifo) mkfifo "$NPM/package-lock.json" ;;
    empty) : > "$NPM/package-lock.json" ;;
    ctrlbom) printf '\357\273\277' > "$NPM/package-lock.json"; lockgen "$NPM/tmp.json" base; cat "$NPM/tmp.json" >> "$NPM/package-lock.json"; rm -f "$NPM/tmp.json" ;;
    ctrlff) lockgen "$NPM/package-lock.json" base; python3 - "$NPM/package-lock.json" <<'PYFF'
import sys
b = open(sys.argv[1], "rb").read().replace(b'"name": "pi-extensions"', b'"name": "pi-\xff"', 1)
open(sys.argv[1], "wb").write(b)
PYFF
      ;;
  esac
  run_flag
  case "$_id" in
    notjson|empty|pkarray|toparray) refused "lockfile package-lock.json unreadable" ;;
    emptypk) installed ;;
    fifo) want_rc 5; no_install; hasl "install: not attempted: unsafe path .pi/npm/package-lock.json" ;;
    ctrlbom|ctrlff) installed ;;
  esac
}
test_lock_reader() {
  # kills: M6a (strict decode) ctrlbom: a BOM'd canonical lockfile must still be accepted;
  # M6b (strict UTF-8) ctrlff; pkarray/toparray pin the non-dict fail-closed arms
  for r in notjson empty pkarray toparray emptypk fifo ctrlbom ctrlff; do par_add row_lock_raw "$r"; done
  par_wait
  pass "R6: the lock reader accepts a BOM and invalid UTF-8 as pi/npm do, and refuses every other non-object form"
}

# ══ R7: order, install moment, exit mapping ════════════════════════════════════════════════
row_order() {
  _id="$1"; cellprep "order-$_id"; mkdir -p "$NPM"
  _fix=""
  case "$_id" in
    npmrc-yarn) printf 'registry=x\n' > "$NPM/.npmrc"; : > "$NPM/yarn.lock"; _want="unsafe path .pi/npm/.npmrc" ;;
    pbom-npmcmd) printf '\357\273\277{"npmCommand":["x"]}' > "$TGT/.pi/settings.json"; _want="unsafe .pi/settings.json content" ;;
    distrust-npmcmd) printf '{"%s":false}' "$RT" > "$CD/home/.pi/agent/trust.json"; printf '{"npmCommand":["x"]}' > "$TGT/.pi/settings.json"; _want="project distrusted" ;;
    npmcmd-nm) printf '{"npmCommand":["x"]}' > "$TGT/.pi/settings.json"; mkdir -p "$NPM/node_modules"; _want="npm command override (project settings)" ;;
    nm-yarn) mkdir -p "$NPM/node_modules"; : > "$NPM/yarn.lock"; _want="existing .pi/npm/node_modules"; _fix="$NMFIX" ;;
    yarn-pkgjson) : > "$NPM/yarn.lock"; printf '{"overrides":{}}' > "$NPM/package.json"; _want="unexpected entry in .pi/npm" ;;
    pkgjson-lock) printf '{"overrides":{}}' > "$NPM/package.json"; lockgen "$NPM/package-lock.json" dep-url; _want="$R4W" ;;
    *) fail "unknown R7 row $_id" ;;
  esac
  run_flag
  case "$_id" in
    npmrc-yarn|pbom-npmcmd|distrust-npmcmd) want_rc 5; no_install; hasl "install: not attempted: $_want" ;;
    *) refused "$_want" "$_fix" ;;
  esac
}
test_order_and_exit() {
  # kills: M7a (pi_install_npm_safe before pi_install_paths_safe) npmrc-yarn/pbom-npmcmd;
  # distrust-npmcmd (trust precedes); M7b (R2 before R1) npmcmd-nm; M7c (R3 before R2) nm-yarn;
  # M7d (R4 before R3) yarn-pkgjson; M7e (R5 before R4) pkgjson-lock; M7f (refusal in a subshell /
  # pi_preflight_flag_fail not called): every refusal row asserts exit 5 AND a finished run
  for r in npmrc-yarn pbom-npmcmd distrust-npmcmd npmcmd-nm nm-yarn yarn-pkgjson pkgjson-lock; do par_add row_order "$r"; done
  par_wait
  # the run finishes through the arming verdict (the escalation file is written after a refusal)
  CELL=order-arming; cellprep "$CELL"; tier_target; mkdir -p "$NPM"; : > "$NPM/yarn.lock"
  : > "$LOG"; ctl "version ok:1.2.0\n" "install real"
  inst "$CTL" - null $ARGS --pr-loop=false --pi-deps=install "$TGT"
  refused "unexpected entry in .pi/npm"
  [ "$(arming_pi)" = raise ] || fail "$CELL: the arming verdict was not written after the refusal (pi=$(arming_pi))"
  # M7g: outside the flag a refusal leaves the exit status unchanged (PTY, `y` typed)
  CELL=order-check-pty; cellprep "$CELL"; mkdir -p "$NPM"; : > "$NPM/yarn.lock"
  pty_inst "$CTL" - ie 'y\n' $PTYARGS "$TGT"; want_rc 0; no_install
  hasl "install: not attempted: unexpected entry in .pi/npm"
  # the guards run only at the install moment: no approval => the printed command, no refusal
  CELL=order-check-pipe; cellprep "$CELL"; mkdir -p "$NPM"; : > "$NPM/yarn.lock"
  inst "$CTL" - null $ARGS --pi-deps=check "$TGT"; want_rc 0; no_install
  hasf "install: not approved — run: "; nof "install: not attempted"
  # M7h: a pinned install (node_modules exists, a stray yarn.lock) is `not needed`, never refused
  CELL=order-status-moment; cellprep "$CELL"; mk_syn_install "$TGT"; : > "$NPM/yarn.lock"
  printf '{"packages":["npm:pi-subagents@0.78.0"]}' > "$TGT/.pi/settings.json"
  run_flag; want_rc 0; no_install; hasl "pi-subagents: pinned 0.78.0 (project)"; hasl "install: not needed"; nof "install: not attempted"
  # the F04 "backend status unknown" branch names F04's reason only (the new function is not called)
  CELL=order-unknown; cellprep "$CELL"; mkdir -p "$NPM"; : > "$NPM/yarn.lock"; ctl "version ok:1.2.0\n" "list rc:1"
  run_flag; want_rc 5; no_install; hasl "install: not attempted: backend status unknown"
  # fail closed by structure: a guard that crashes (no output) still refuses, with the default
  # reason -- a python3 shim fails only the npm guard's program (M7i: the default reason removed)
  CELL=order-crash; cellprep "$CELL"
  mkdir -p "$CD/shim"; REALPY="$(command -v python3)"
  { printf '#!/bin/sh\ncat > "%s/prog"\n' "$CD"
    printf 'if grep -q "def refuse(why)" "%s/prog"; then exit 3; fi\n' "$CD"
    printf 'exec "%s" "$@" < "%s/prog"\n' "$REALPY" "$CD"; } > "$CD/shim/python3"
  chmod +x "$CD/shim/python3"; SBPATH="$CD/shim:$SANDBOX_PATH"
  run_flag; refused "npm guard failed"
  pass "R7: F04's checks first, then R1..R5 in order; refusals exit 5 under the flag only; install moment only; a crashed guard refuses"
}

# ══ R8 / R9: byte verification of pinned (project) ═══════════════════════════════════════
PKGDIR_REL=".pi/npm/node_modules/pi-subagents"
vcell() { # <name> -- a verifiable synthetic project install + its settings entry, probed with `check`
  cellprep "$1"; mk_syn_install "$TGT"; P="$TGT/$PKGDIR_REL"; NPM="$TGT/.pi/npm"
  printf '{"packages":["npm:pi-subagents@0.78.0"]}' > "$TGT/.pi/settings.json"
  ctl "version ok:1.2.0\n" "list real"
}
probe() { inst "$CTL" - null $ARGS --pi-deps=check "$TGT"; want_rc 0; no_install; no_esc; }
GOODENT='"version":"0.78.0","integrity":"@I@"'
row_vl() {
  _id="$1"; vcell "vl-$_id"; _want=unverified
  case "$_id" in
    ok) _want=pinned ;;
    noint) mk_lock "$NPM/package-lock.json" - ;;
    wrongint) mk_lock "$NPM/package-lock.json" "sha512-ZZZZ" ;;
    wrongver) mk_lock "$NPM/package-lock.json" "$SYN_INTEGRITY" 0.77.0 ;;
    nolock) rm -f "$NPM/package-lock.json" ;;
    sw-good) mk_lock "$NPM/npm-shrinkwrap.json" "$SYN_INTEGRITY"; mk_lock "$NPM/package-lock.json" - ; _want=pinned ;;
    sw-bad) mk_lock "$NPM/npm-shrinkwrap.json" -; _want=unverified ;;
    dup-badlast) printf '{"packages":{"node_modules/pi-subagents":{"version":"0.78.0","integrity":"%s"},"node_modules/pi-subagents":{"version":"0.78.0"}}}' "$SYN_INTEGRITY" > "$NPM/package-lock.json" ;;
    dup-badfirst) printf '{"packages":{"node_modules/pi-subagents":{"version":"0.78.0"},"node_modules/pi-subagents":{"version":"0.78.0","integrity":"%s"}}}' "$SYN_INTEGRITY" > "$NPM/package-lock.json" ;;
    dup-other) printf '{"packages":{"node_modules/pi-subagents":{"version":"0.78.0","integrity":"%s"}},"x":1,"x":2}' "$SYN_INTEGRITY" > "$NPM/package-lock.json" ;;
    bom) { printf '\357\273\277'; cat "$NPM/package-lock.json"; } > "$NPM/l.t" && mv "$NPM/l.t" "$NPM/package-lock.json"; _want=pinned ;;
    ff) python3 -c 'import sys; b = open(sys.argv[1], "rb").read().replace(b"pi-extensions", b"pi-\xff", 1); open(sys.argv[1], "wb").write(b)' "$NPM/package-lock.json" || fail "$CELL: setup"; _want=pinned ;;
    nan) printf '{"packages":{"node_modules/pi-subagents":{"version":"0.78.0","integrity":"%s"}},"n":NaN}' "$SYN_INTEGRITY" > "$NPM/package-lock.json" ;;
    inf) printf '{"packages":{"node_modules/pi-subagents":{"version":"0.78.0","integrity":"%s"}},"n":Infinity}' "$SYN_INTEGRITY" > "$NPM/package-lock.json" ;;
    ninf) printf '{"packages":{"node_modules/pi-subagents":{"version":"0.78.0","integrity":"%s"}},"n":-Infinity}' "$SYN_INTEGRITY" > "$NPM/package-lock.json" ;;
    noentry) printf '{"packages":{}}' > "$NPM/package-lock.json" ;;
    nopackages) printf '{"lockfileVersion":1}' > "$NPM/package-lock.json" ;;
    entrystr) printf '{"packages":{"node_modules/pi-subagents":"x"}}' > "$NPM/package-lock.json" ;;
    linklock) mkdir -p "$CD/outside"; cp "$NPM/package-lock.json" "$CD/outside/lock.json"; rm "$NPM/package-lock.json"; ln -s "$CD/outside/lock.json" "$NPM/package-lock.json" ;;
    fifo) rm "$NPM/package-lock.json"; mkfifo "$NPM/package-lock.json" ;;
    *) fail "unknown R8 row $_id" ;;
  esac
  probe
  if [ "$_want" = pinned ]; then hasl "pi-subagents: pinned 0.78.0 (project)"; hasl "install: not needed"
  else hasl "pi-subagents: unverified (lockfile)"; nof "pinned 0.78.0"; hasl "install: not attempted: backend unverified"; fi
}
test_verify_lockfile() {
  # kills: M8a (R8 removed) noint/wrongint/nolock; M8b (version not compared) wrongver;
  # M8c (always package-lock.json) sw-good; M8d (either file suffices) sw-bad; M8e (no duplicate
  # check) dup-badlast/dup-badfirst; M6a (strict decode) bom; M6b ff; M6c (NaN accepted) nan;
  # M8f (the read follows links) linklock; M8g (S_ISREG check removed -> the fifo hangs, the
  # per-case watchdog reds the row) fifo
  for r in ok noint wrongint wrongver nolock sw-good sw-bad dup-badlast dup-badfirst dup-other bom ff nan inf ninf noentry nopackages entrystr linklock fifo; do par_add row_vl "$r"; done
  par_wait
  pass "R8: pinned (project) needs the effective lockfile's version and registry integrity"
}

# open_log -- run the installer's python under an audit hook that logs every path it opens inside
# the package dir to $OPENLOG, and an os.scandir wrapper that logs one line per entry it yields from
# <pkg>/many to $SCANLOG (only the program holding tree_ok is instrumented)
open_log() {
  OPENLOG="$CD/opens.log"; : > "$OPENLOG"; SCANLOG="$CD/scans.log"; : > "$SCANLOG"; mkdir -p "$CD/shim"; REALPY="$(command -v python3)"
  cat > "$CD/hook.py" <<PYHOOK
import sys as _s
_lf = open("$OPENLOG", "a", buffering=1)
_s.addaudithook(lambda e, a: _lf.write(a[0] + "\\n") if e == "open" and isinstance(a[0], str) and "/pi-subagents/" in a[0] else None)
import os as _o
_sc = open("$SCANLOG", "a", buffering=1); _rsd = _o.scandir
class _SD:
    def __init__(s, p): s.m = str(p).endswith("/pi-subagents/many"); s.it = _rsd(p)
    def __enter__(s): return s
    def __exit__(s, *a): s.it.close()
    def __iter__(s): return s
    def __next__(s):
        e = next(s.it)
        if s.m: _sc.write("e\\n")
        return e
    def close(s): s.it.close()
_o.scandir = lambda p=".": _SD(p)
PYHOOK
  { printf '#!/bin/sh\ncat > "%s/prog"\n' "$CD"
    printf 'grep -q "def tree_ok(" "%s/prog" && cat "%s/hook.py" "%s/prog" > "%s/prog2" && mv "%s/prog2" "%s/prog"\n' "$CD" "$CD" "$CD" "$CD" "$CD" "$CD"
    printf 'exec "%s" "$@" < "%s/prog"\n' "$REALPY" "$CD"; } > "$CD/shim/python3"
  chmod +x "$CD/shim/python3"; SBPATH="$CD/shim:$SANDBOX_PATH"
}
row_vt() {
  _id="$1"; vcell "vt-$_id"; _want=files; OPENLOG=""
  case "$_id" in
    ok) _want=pinned ;;
    extra) printf 'x' > "$P/EVIL.js" ;;
    missing) rm "$P/lib/a.js" ;;
    changed) printf 'Y' >> "$P/index.ts" ;;
    symlink) mkdir -p "$CD/outside"; cp "$P/index.ts" "$CD/outside/index.ts"; rm "$P/index.ts"; ln -s "$CD/outside/index.ts" "$P/index.ts" ;;
    hardlink) mkdir -p "$CD/outside"; cp "$P/lib/a.js" "$CD/outside/a.js"; rm "$P/lib/a.js"; ln "$CD/outside/a.js" "$P/lib/a.js" ;;
    nested) mkdir -p "$P/node_modules/jiti"; printf 'x' > "$P/node_modules/jiti/index.js" ;;
    fifo) mkfifo "$P/f" ;;
    unreadable) [ "$(id -u)" != 0 ] || return 0; chmod 000 "$P/index.ts" ;;
    forge-nl)
      # a reduced tree whose line stream equals the official one: package.json + ONE file whose
      # relpath is `index.ts\n<sha256 of lib/a.js>  lib/a.js` (a directory named
      # `index.ts\n<sha256>  lib` holding `a.js` with index.ts's bytes)
      _ha="$(_sha256 < "$P/lib/a.js" | sed 's/ .*//')"
      python3 - "$P" "$_ha" "$SYN_DIGEST" <<'PYFORGE'
import hashlib, os, shutil, sys
p, ha, want = sys.argv[1:4]
idx = open(p + "/index.ts", "rb").read()
pj = open(p + "/package.json", "rb").read()
shutil.rmtree(p); os.makedirs(p)
open(p + "/package.json", "wb").write(pj)
d = os.path.join(p, "index.ts\n%s  lib" % ha)
os.makedirs(d)
open(os.path.join(d, "a.js"), "wb").write(idx)
# the PRECONDITION: without a control-character rule this tree reproduces the official digest
rows = []
for root, _dirs, files in os.walk(p):
    for n in files:
        f = os.path.join(root, n)
        rows.append((os.path.relpath(f, p).encode(), hashlib.sha256(open(f, "rb").read()).hexdigest()))
rows.sort()
got = hashlib.sha256(b"".join(h.encode() + b"  " + n + b"\n" for n, h in rows)).hexdigest()
if got != want:
    sys.exit("forge precondition failed: %s != %s" % (got, want))
PYFORGE
      [ $? = 0 ] || fail "$CELL: the forge setup/precondition failed"
      ;;
    emptydir) mkdir -p "$P/empty-dir"; _want=pinned ;;
    rootlink) mv "$P" "$CD/real-copy"; ln -s "$CD/real-copy" "$P" ;;
    nmlink) mv "$NPM/node_modules" "$CD/nm-copy"; ln -s "$CD/nm-copy" "$NPM/node_modules" ;;
    noR8) printf 'x' >> "$P/index.ts"; mk_lock "$NPM/package-lock.json" -; _want=lockfile ;;
    manyfiles) mkdir -p "$P/many"; python3 -c 'import sys
for i in range(10100): open("%s/f%d" % (sys.argv[1], i), "w").close()' "$P/many" || fail "$CELL: setup"; open_log ;;
    bigfile) truncate -s 67108865 "$P/big" || fail "$CELL: setup"; open_log ;;
    *) fail "unknown R9 row $_id" ;;
  esac
  probe
  if [ -n "${OPENLOG:-}" ]; then
    # precondition: the hook saw the package.json read, so an empty match below is not vacuous
    grep -q '/pi-subagents/package.json$' "$OPENLOG" || fail "$CELL: the open hook logged nothing"
    case "$_id" in
      manyfiles) grep -q '/pi-subagents/many/' "$OPENLOG" && fail "$CELL: a file of an over-count tree was opened"
        # the cap aborts mid-stream: a 10100-name directory yields at most TREE_MAX_ENTRIES+1 names
        # (>0 also proves the walk streamed it through os.scandir, not os.listdir)
        _n=$(wc -l < "$SCANLOG"); [ "$_n" -gt 0 ] || fail "$CELL: the scandir hook saw no entry of many/"
        [ "$_n" -le 10001 ] || fail "$CELL: many/ enumerated in full ($_n entries) before the cap" ;;
      bigfile) grep -q '/pi-subagents/big$' "$OPENLOG" && fail "$CELL: a file over the byte cap was opened" ;;
    esac
  fi
  case "$_want" in
    pinned) hasl "pi-subagents: pinned 0.78.0 (project)" ;;
    files) hasl "pi-subagents: unverified (files)"; nof "pinned 0.78.0" ;;
    lockfile) hasl "pi-subagents: unverified (lockfile)"; nof "unverified (files)" ;;
  esac
}
test_verify_tree() {
  # kills: M9a (R9 removed) extra/missing/changed; M9b (the walk follows links) symlink/rootlink/
  # nmlink; M9c (nlink not checked) hardlink; M9d (control-character rule removed) forge-nl;
  # M9e (directories hashed) emptydir; M9f (R9 run regardless of R8, or files ranked above
  # lockfile) noR8; fifo (a non-regular node is never opened); M9g (no entry-count cap: the
  # over-count tree is opened) manyfiles; M9h (no byte cap: the 64 MiB + 1 sparse file is opened)
  # bigfile
  for r in ok extra missing changed symlink hardlink nested fifo unreadable forge-nl emptydir rootlink nmlink noR8 manyfiles bigfile; do par_add row_vt "$r"; done
  par_wait
  pass "R9: pinned (project) needs the exact tree digest; links, hard links, control-character names and extra files fail"
}

# ══ R10: unverified neither prompts nor installs ═══════════════════════════════════════════
row_unv() {
  _id="$1"; vcell "unv-$_id"
  case "$_id" in
    status-flag) printf 'Y' >> "$P/index.ts"; run_flag
      want_rc 5; no_install; hasl "pi-subagents: unverified (files)"; hasl "install: not attempted: backend unverified"; hasl "$NMFIX"
      [ -f "$TGT/.harness/.agents" ] || fail "$CELL: the run did not finish"; nof "[y/N]" ;;
    status-lock) mk_lock "$NPM/package-lock.json" -; run_flag
      want_rc 5; no_install; hasl "pi-subagents: unverified (lockfile)"; hasl "install: not attempted: backend unverified"; hasl "$NMFIX" ;;
    status-pty) printf 'Y' >> "$P/index.ts"
      pty_inst "$CTL" - ie 'y\n' $PTYARGS --pi-deps=check "$TGT"
      want_rc 0; no_install; nof "[y/N]"; hasl "pi-subagents: unverified (files)"; hasl "install: not attempted: backend unverified" ;;
    verify) rm -rf "$TGT/.pi/npm" "$TGT/.pi/settings.json"; ctl "version ok:1.2.0\n" "install tamper"; run_flag
      want_rc 5; [ "$(ncalls install)" = 1 ] || fail "$CELL: the install did not run"
      hasl "install: failed: not verified" ;;
    user) rm -rf "$TGT/.pi/npm" "$TGT/.pi/settings.json"
      mk_pkg "$CD/home/.pi/agent/npm/node_modules/pi-subagents" 0.78.0; printf '{"packages":["npm:pi-subagents@0.78.0"]}' > "$CD/home/.pi/agent/settings.json"
      probe; hasl "pi-subagents: pinned 0.78.0 (user)"; hasl "install: not needed"
      ! grep 'pinned 0.78.0 (user)' "$OUT" | grep -qi 'verified' || fail "$CELL: the user-scope line claims byte-verification" ;;
    mix) printf 'Y' >> "$P/index.ts"
      mk_pkg "$CD/home/.pi/agent/npm/node_modules/pi-subagents" 0.78.0; printf '{"packages":["npm:pi-subagents@0.78.0"]}' > "$CD/home/.pi/agent/settings.json"
      probe; hasl "pi-subagents: unverified (files)"; nof "pinned 0.78.0" ;;
    unpatched-lock) INST="$SRCINST"; probe; hasl "pi-subagents: unverified (lockfile)"; nof "pinned 0.78.0" ;;
    unpatched-files) INST="$SRCINST"
      _real="$(sed -n 's/^PI_SUBAGENTS_INTEGRITY=//p' "$SRCINST")"; mk_lock "$NPM/package-lock.json" "$_real"
      probe; hasl "pi-subagents: unverified (files)"; nof "pinned 0.78.0" ;;
    *) fail "unknown R10 row $_id" ;;
  esac
}
test_unverified_flow() {
  # kills: M10a (unverified handled like mismatch: R2's reason missing) status-flag; M10b (no
  # pi_preflight_flag_fail) status-flag/-lock exit 5; M10c (unverified reaches the prompt)
  # status-pty; M10d (the verify probe accepts unverified-*) verify; M10f (the user line claims
  # byte-verification) user; M10g (R8/R9 applied to the user scope) user; M10e (pinned-user ranked
  # above unverified) mix; M11b (the shipped integrity/tree replaced by the synthetic one)
  # unpatched-lock / unpatched-files
  for r in status-flag status-lock status-pty verify user mix unpatched-lock unpatched-files; do par_add row_unv "$r"; done
  par_wait
  pass "R10: unverified neither prompts nor installs and exits 5 under the flag; pinned (user) is unchanged and not byte-verified"
}

# ══ R11: constants ═════════════════════════════════════════════════════════════════════════
test_constants() {
  _int='sha512-AsOvPL1xaVFV4bqIlheQKNI2LmAoiAKTPXXxi39/BsWJTdMJIqAkZJ3iLi6bTsh2PZHG7Ur08b7VJOtgAMIAig=='
  _dig='ca6eb868eaf496af797e4ad17485c37d7e97199c30deb50072217d95b724fc87'
  [ "$(grep -c "^PI_SUBAGENTS_INTEGRITY=$_int\$" "$SRCINST")" = 1 ] || fail "R11: PI_SUBAGENTS_INTEGRITY is not exactly one NAME=value line"
  [ "$(grep -c "^PI_SUBAGENTS_TREE_SHA256=$_dig\$" "$SRCINST")" = 1 ] || fail "R11: PI_SUBAGENTS_TREE_SHA256 is not exactly one NAME=value line"
  for _lit in "$_int" "$_dig"; do
    _n="$(grep -nF -- "$_lit" "$SRCINST" | grep -vE '^[0-9]+:[[:space:]]*#' | wc -l | tr -d ' ')"
    [ "$_n" = 1 ] || fail "R11: the literal $_lit appears $_n times outside comments (want 1)"
  done
  # the byte contract: the suite's own implementation over a fixed tree equals a hard-coded digest
  # (2 files: `a` = A, `b/c` = C; lines `<sha256>  <relpath>` sorted by path, one trailing newline)
  mkdir -p "$T/kat/b"; printf 'A' > "$T/kat/a"; printf 'D' > "$T/kat/b/c"
  # precondition (B1): the hash order (b/c, then a) differs from the path order (a, then b/c), so a
  # digest sorted by hash or by the whole line cannot equal the relpath-sorted one
  [ "$(printf '%s b/c\n%s a\n' "$(printf 'D' | _sha256 | sed 's/ .*//')" "$(printf 'A' | _sha256 | sed 's/ .*//')" | LC_ALL=C sort | head -n 1 | sed 's/^[^ ]* //')" = b/c ] || fail "R11 kat: setup: the hash order equals the path order"
  [ "$(tree_digest "$T/kat")" = 64254b8d343dd5efae96192cf9c5eca18854d22f5cd14b6ee351a9211b44b17d ] || fail "R11 kat: the suite's tree digest of the fixed tree is $(tree_digest "$T/kat"), want the hard-coded 64254b8d343dd5efae96192cf9c5eca18854d22f5cd14b6ee351a9211b44b17d"
  pass "R11: the two pin constants are single NAME=value lines holding the exact registry integrity and tree digest"
}

# ══ R12: docs, changelog, version ═════════════════════════════════════════════════════════
test_docs() {
  [ "$(cat "$SRC/VERSION")" = 0.96.0 ] || fail "R12: VERSION is not 0.96.0"
  [ "$(grep -m1 '^## \[' "$SRC/CHANGELOG.md" | sed 's/ —.*//')" = '## [0.96.0]' ] || fail "R12: the newest CHANGELOG heading is not ## [0.96.0]"
  awk '/^## \[0.96.0\]/{k=1;next} /^## \[/{k=0} k' "$SRC/CHANGELOG.md" | grep -q 'E35-F05' || fail "R12: the 0.96.0 changelog entry does not name E35-F05"
  # F04's entry still exists and still names E35-F04 (PP's R12 relies on it)
  awk '/^## \[0.95.0\]/{k=1;next} /^## \[/{k=0} k' "$SRC/CHANGELOG.md" | grep -q 'E35-F04' || fail "R12: the 0.95.0 changelog entry no longer names E35-F04"
  _sec="$(awk '/^### pi$/{k=1;next} /^#{1,3} /{k=0} k' "$SRC/docs/INSTALL.md")"
  ! printf '%s\n' "$_sec" | tr '\n' ' ' | grep -qF 'not an integrity pin' || fail "R12: the INSTALL.md pi section still says 'not an integrity pin'"
  for w in 'byte-verified' 'npm command override' 'existing .pi/npm/node_modules' 'unexpected entry in .pi/npm' 'not canonical' 'unverified' 'pinned (user)' 'mirror' 'not re-verified' 'cache' 'other registry packages' 'remove'; do
    printf '%s\n' "$_sec" | tr '\n' ' ' | grep -qF -- "$w" || fail "R12: the INSTALL.md pi section does not mention '$w'"
  done
  printf '%s\n' "$_sec" | tr '\n' ' ' | grep -qiE 'pinned \(user\)[^.]{0,40}not byte-verified|not byte-verified[^.]{0,80}pinned \(user\)|`pinned \(user\)` is NOT byte-verified' || fail "R12: the docs do not say pinned (user) is not byte-verified"
  sh -n "$SRCINST" || fail "sh -n harness-install.sh"
  if command -v dash >/dev/null 2>&1; then dash -n "$SRCINST" || fail "dash -n harness-install.sh"; fi
  _pre="$(awk '/pi environment preflight \(E35-F04\) ──/{k=1} /write_escalation_arming — record/{k=0} k' "$SRCINST")"
  printf '%s\n' "$_pre" | grep -vE '^[[:space:]]*#' | grep -qE '(^|[^a-z_-])timeout [0-9]|stat -c|readlink -f' && fail "the preflight uses timeout(1), stat -c or readlink -f"
  pass "R12: VERSION 0.96.0, CHANGELOG names E35-F05, docs replace the 'not an integrity pin' sentence and state the residual"
}

# ══ real npm, offline: the guards against the real installer, a LOCAL registry ═════════════
cat > "$T/regsetup.py" <<'PYREGSETUP'
# regsetup.py <dir> <syn tarball> <syn integrity> -- build the local registry's static files
import base64, hashlib, io, json, os, sys, tarfile
d, syn_tgz, syn_int = sys.argv[1:4]
def tgz(files):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as t:
        for n, c in files.items():
            ti = tarfile.TarInfo("package/" + n); ti.size = len(c); ti.mode = 0o644
            t.addfile(ti, io.BytesIO(c))
    return buf.getvalue()
def integ(b):
    return "sha512-" + base64.b64encode(hashlib.sha512(b).digest()).decode()
clean = tgz({"package.json": b'{"name":"dep","version":"1.0.0"}', "index.js": b"module.exports = 1;\n"})
evil = tgz({"package.json": json.dumps({"name": "dep", "version": "1.0.0", "scripts": {"postinstall": "node -e \"require('fs').writeFileSync(process.env.CANARY, 'ran')\""}}).encode(),
            "index.js": b"module.exports = 'evil';\n", "EVIL.txt": b"evil\n"})
syn = open(syn_tgz, "rb").read()
assert integ(syn) == syn_int, "synthetic integrity mismatch"
def packument(name, ver, b, deps):
    # the tarball URL is the OFFICIAL host: npm's default replace-registry-host maps it to the
    # configured registry, so the lockfile it writes holds the canonical https://registry.npmjs.org URL
    return {"name": name, "dist-tags": {"latest": ver}, "versions": {ver: {
        "name": name, "version": ver, "dependencies": deps,
        "dist": {"tarball": "https://registry.npmjs.org/%s/-/%s-%s.tgz" % (name, name, ver), "integrity": integ(b)}}}}
files = {"pi-subagents.json": json.dumps(packument("pi-subagents", "0.78.0", syn, {"dep": "1.0.0"})),
         "dep.json": json.dumps(packument("dep", "1.0.0", clean, {}))}
for n, c in files.items():
    open(os.path.join(d, n), "w").write(c)
open(os.path.join(d, "pi-subagents-0.78.0.tgz"), "wb").write(syn)
open(os.path.join(d, "dep-1.0.0.tgz"), "wb").write(clean)
open(os.path.join(d, "evil-dep-1.0.0.tgz"), "wb").write(evil)
PYREGSETUP
cat > "$T/regsrv.py" <<'PYREGSRV'
# regsrv.py <dir> <portfile> <logfile> -- a tiny local npm registry on 127.0.0.1, port 0
import http.server, os, sys
d, portfile, logfile = sys.argv[1:4]
ROUTES = {"/pi-subagents": ("pi-subagents.json", "application/json"), "/dep": ("dep.json", "application/json"),
          "/pi-subagents/-/pi-subagents-0.78.0.tgz": ("pi-subagents-0.78.0.tgz", "application/octet-stream"),
          "/dep/-/dep-1.0.0.tgz": ("dep-1.0.0.tgz", "application/octet-stream"),
          "/evil/dep/-/dep-1.0.0.tgz": ("evil-dep-1.0.0.tgz", "application/octet-stream")}
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(logfile, "a") as fh:
            fh.write(self.path + "\n")
        r = ROUTES.get(self.path)
        if not r:
            self.send_response(404); self.end_headers(); return
        b = open(os.path.join(d, r[0]), "rb").read()
        self.send_response(200); self.send_header("Content-Type", r[1]); self.send_header("Content-Length", str(len(b))); self.end_headers()
        self.wfile.write(b)
    def log_message(self, *a):
        pass
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(portfile + ".t", "w").write(str(s.server_address[1]))
os.rename(portfile + ".t", portfile)
s.serve_forever()
PYREGSRV

# npm_env <cell dir> -- the hermetic npm environment words (fresh cache, empty userconfig, local registry)
npm_env() {
  : > "$CD/npmrc"
  echo "npm_config_registry=http://127.0.0.1:$REGPORT/ npm_config_cache=$CD/npmcache npm_config_userconfig=$CD/npmrc npm_config_audit=false npm_config_fund=false npm_config_update_notifier=false CANARY=$CD/canary"
}
# a shim `pi`: logs through the stub, answers like the stub, and runs the REAL npm argv pi runs
# (`npm install npm-spec --prefix <cwd>/.pi/npm --legacy-peer-deps`) for `install`
mk_shim() { # <dir>
  mkdir -p "$1"
  cat > "$1/pi" <<SHIM
#!/bin/sh
if [ "\$1" = install ]; then
  printf 'install noop\n' > "$1/ctl.noop"
  STUB_CTL="$1/ctl.noop" "$STUBDIR/pi" "\$@"
  spec="\${4}"
  mkdir -p .pi/npm
  [ -e .pi/npm/package.json ] || printf '{"name":"pi-extensions","private":true}\n' > .pi/npm/package.json
  [ -e .pi/npm/.gitignore ] || printf '*\n!.gitignore\n' > .pi/npm/.gitignore
  npm install "\${spec#npm:}" --prefix "\$PWD/.pi/npm" --legacy-peer-deps >> "\$STUB_LOG.npm" 2>&1 || exit 1
  python3 - "\$spec" <<'PYSET'
import json, os, sys
d = json.load(open(".pi/settings.json")) if os.path.exists(".pi/settings.json") else {}
pk = d.setdefault("packages", [])
if sys.argv[1] not in pk:
    pk.append(sys.argv[1])
json.dump(d, open(".pi/settings.json", "w"), indent=2)
PYSET
  exit 0
fi
exec "$STUBDIR/pi" "\$@"
SHIM
  chmod +x "$1/pi"
}
YARNSTEER() { printf '# yarn lockfile v1\n\n\ndep@1.0.0:\n  version "1.0.0"\n  resolved "http://127.0.0.1:%s/evil/dep/-/dep-1.0.0.tgz"\n' "$REGPORT"; }
rn_direct() { # the shim (real npm) run directly in the target, WITHOUT the installer's guards
  ( cd "$TGT" && env -i PATH="$SANDBOX_PATH" HOME="$CD/home" STUB_CTL="$CTL" STUB_LOG="$LOG" $(npm_env) sh "$CD/shimbin/pi" install -l -a npm:pi-subagents@0.78.0 ) </dev/null >/dev/null 2>&1 || :
}
rn_run() { # run the installer with the shim and the npm env; $RC, $OUT
  : > "$RLOG"
  # inst puts $STUBDIR first on PATH: point it at the shim (which delegates to the real stub)
  _sd="$STUBDIR"; STUBDIR="$CD/shimbin"
  inst "$CTL" "$(npm_env)" null $ARGS --pi-deps=install "$TGT"
  STUBDIR="$_sd"
}
rn_cell() { # <name>
  cellprep "$1"; mk_shim "$CD/shimbin"; RLOG="$REGDIR/log"; ctl "version ok:1.2.0\n" "list real"
}
test_real_npm() {
  # npm usually lives in a directory that also holds `pi` (which the sandbox PATH drops): wrap just
  # `npm` and `node` in a private dir so the sandbox still has no `pi`
  _nb="$T/npmbin"; mkdir -p "$_nb"
  for _x in npm node; do
    _xp="$(command -v "$_x" 2>/dev/null || :)"
    if [ -n "$_xp" ] && [ ! -e "$_nb/$_x" ]; then printf '#!/bin/sh\nexec "%s" "$@"\n' "$_xp" > "$_nb/$_x"; chmod +x "$_nb/$_x"; fi
  done
  SANDBOX_PATH="$_nb:$SANDBOX_PATH"
  if ! env -i PATH="$SANDBOX_PATH" sh -c 'command -v npm && command -v node' >/dev/null 2>&1; then echo "SKIP - real npm: npm or node is not on PATH"; return 0; fi
  env -i PATH="$SANDBOX_PATH" sh -c 'command -v pi' >/dev/null 2>&1 && fail "real npm: pi resolves on the sandbox PATH"
  REGDIR="$T/reg"; mkdir -p "$REGDIR"
  python3 "$T/regsetup.py" "$REGDIR" "$SYN/pi-subagents-0.78.0.tgz" "$SYN_INTEGRITY" || fail "real npm: registry setup"
  python3 "$T/regsrv.py" "$REGDIR" "$REGDIR/port" "$REGDIR/log" &
  _srv=$!
  trap 'kill "$_srv" 2>/dev/null || :' EXIT
  _w=0; while [ ! -s "$REGDIR/port" ] && [ "$_w" -lt 50 ]; do sleep 0.1; _w=$((_w + 1)); done
  REGPORT="$(cat "$REGDIR/port")"; [ -n "$REGPORT" ] || fail "real npm: the local registry did not start"
  # (a) a clean target: the REAL npm-written lockfile and tree satisfy R8 and R9
  rn_cell rn-a; rn_run
  installed; [ ! -e "$CD/canary" ] || fail "rn-a: the canary exists"
  grep -q '^/pi-subagents' "$RLOG" && grep -q '^/dep' "$RLOG" || fail "rn-a: npm did not fetch from the local registry: $(cat "$RLOG")"
  ! grep -q '/evil/' "$RLOG" || fail "rn-a: the evil URL was requested"
  # (c) a second run: nothing to do
  : > "$LOG"; rn_run; want_rc 0; no_install; hasl "pi-subagents: pinned 0.78.0 (project)"; hasl "install: not needed"
  # (g) the package files REAL npm wrote are what the digest covers: one appended byte reads
  # `unverified (files)` and the install is refused (npm would keep the tampered file, fact 8)
  CELL=rn-g; printf 'X' >> "$NPM/node_modules/pi-subagents/index.ts"; : > "$LOG"; rn_run
  want_rc 5; no_install; hasl "pi-subagents: unverified (files)"; hasl "install: not attempted: backend unverified"
  python3 - "$NPM/node_modules/pi-subagents/index.ts" <<'PYUNDO'
import sys
b = open(sys.argv[1], "rb").read()
open(sys.argv[1], "wb").write(b[:-1])
PYUNDO
  # the documented residual (R12): a tampered DEPENDENCY of an install the harness did not run is not
  # re-verified, so the pin still reads pinned
  CELL=rn-h; printf 'tampered\n' >> "$NPM/node_modules/dep/index.js"; : > "$LOG"; rn_run
  want_rc 0; no_install; hasl "pi-subagents: pinned 0.78.0 (project)"; hasl "install: not needed"
  # (d) node_modules left from (a), settings moved to @0.77.0: the R2 refusal, no npm
  CELL=rn-d; printf '{"packages":["npm:pi-subagents@0.77.0"]}' > "$TGT/.pi/settings.json"; : > "$LOG"; rn_run
  want_rc 5; no_install; hasl "pi-subagents: mismatch"; hasl "install: not attempted: existing .pi/npm/node_modules"; hasl "$NMFIX"
  # (e) the lockfile REAL npm wrote passes R5 (canonical registry URLs) once node_modules is gone
  CELL=rn-e; rm -rf "$NPM/node_modules" "$TGT/.pi/settings.json"; : > "$LOG"; rn_run; installed
  # (b) a yarn.lock steering dep to /evil/: the guard refuses BEFORE npm runs (no registry request,
  # no canary) ...
  rn_cell rn-b; mkdir -p "$NPM"; YARNSTEER > "$NPM/yarn.lock"; rn_run
  want_rc 5; no_install; hasl "install: not attempted: unexpected entry in .pi/npm"
  [ ! -s "$RLOG" ] || fail "rn-b: npm reached the registry despite the refusal: $(cat "$RLOG")"
  [ ! -e "$CD/canary" ] || fail "rn-b: the steered postinstall ran"
  # ... and the control: WITHOUT the guard (the shim run directly) the same setup fires the canary,
  # so the row above is live (the real npm still honours yarn.lock)
  rn_cell rn-b-live; mkdir -p "$NPM"; YARNSTEER > "$NPM/yarn.lock"
  rn_direct
  [ -e "$CD/canary" ] || fail "rn-b-live: the unguarded real npm did not run the steered postinstall: the row above proves nothing ($(tail -n 5 "$LOG.npm" 2>/dev/null))"
  # (f) a canonical-looking package-lock.json whose dep is steered: R5 refuses; the control fires
  rn_cell rn-f; mkdir -p "$NPM"
  python3 - "$NPM/package-lock.json" "$REGPORT" "$SYN_INTEGRITY" <<'PYLF'
import json, sys
f, port, si = sys.argv[1:4]
json.dump({"name": "pi-extensions", "lockfileVersion": 3, "requires": True, "packages": {
    "": {"name": "pi-extensions", "dependencies": {"pi-subagents": "^0.78.0"}},
    "node_modules/dep": {"version": "1.0.0", "resolved": "http://127.0.0.1:%s/evil/dep/-/dep-1.0.0.tgz" % port, "hasInstallScript": True}}}, open(f, "w"))
PYLF
  cp "$NPM/package-lock.json" "$T/lock.steer"
  rn_run; want_rc 5; no_install; hasl "install: not attempted: lockfile package-lock.json not canonical"
  [ ! -s "$RLOG" ] && [ ! -e "$CD/canary" ] || fail "rn-f: npm ran despite the refusal"
  rn_cell rn-f-live; mkdir -p "$NPM"; cp "$T/lock.steer" "$NPM/package-lock.json"
  rn_direct
  [ -e "$CD/canary" ] || fail "rn-f-live: the unguarded real npm did not honour the steered lockfile: the row above proves nothing ($(tail -n 5 "$LOG.npm" 2>/dev/null))"
  kill "$_srv" 2>/dev/null || :; trap - EXIT
  pass "real npm: a clean install verifies end to end; yarn.lock and steered lockfiles are refused before any registry request, and the unguarded control fires"
}

run_all() {
  for _ra_f in "$@"; do
    ( "$_ra_f" ) || exit 1
  done
}
# PI_ONLY="test_a test_b" runs just those (development aid); PI_KEEP_T=1 keeps the temp dir
if [ -n "${PI_ONLY:-}" ]; then echo "!!! PI_ONLY is set: running ONLY: $PI_ONLY -- this is NOT the whole suite !!!" >&2; run_all $PI_ONLY; echo "All selected pi integrity tests passed."; exit 0; fi
run_all test_npm_command test_node_modules test_prefix_entries test_package_json test_lockfiles test_lock_reader \
  test_order_and_exit test_verify_lockfile test_verify_tree test_unverified_flow test_constants test_docs test_real_npm
echo "All pi integrity tests passed."
