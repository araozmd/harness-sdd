#!/bin/sh
# test_worker_roster.sh — E17-F04, the worker roster (.harness/workers.json).
#
# Covers R1–R12 of specs/epics/E17-model-routing/F04-worker-roster/ plus the unnumbered
# roster-JSON-validity row of that feature's test contract.
#
# THE SUITE CONTROLS `PATH`, and that is the whole fixture. Presence is the variable under
# test, so every case builds a `mktemp` bin directory holding stub executables for exactly
# the keys it wants present, and runs the installer with `PATH=<that dir>:$BASE_PATH`.
# $BASE_PATH is the developer's real PATH with every directory holding one of the five
# rostered command names REMOVED (see base_path_without_rostered_clis) — a case that
# inherited the raw developer PATH would be testing this machine, not the requirement, and
# would report `codex` present on a laptop that has codex installed no matter what the
# fixture said.
#
# STUBS EXIST TO BE FOUND, NEVER RUN (R8). Every stub appends its own name to a witness
# file and exits NON-ZERO, so an implementation that shelled out to `<cli> --version` both
# leaves a trace and takes a failing exit status. A stub that merely exited 0 would let
# such an implementation pass.
#
# ENVIRONMENT DISCIPLINE. Every installer invocation goes through `hrun`/`hrun_relative`,
# which both funnel into `sandbox_run` — the ONE place this suite spawns anything: `env -i`
# with nothing but the case's PATH, a sandboxed HOME and a sandboxed CODEX_HOME (never the
# developer's real ~/.codex), stdin from /dev/null. The two wrappers differ ONLY in how the
# installer is NAMED on the command line (absolute path vs `./harness-install.sh` from the
# source directory), which is what R9 needs to pin that `$0` is not a roster input.
# No check freezes the exact VERSION string or diffs a file against `main`.
#
# Depends on python3 (a hard prerequisite of the harness — init.sh fails without it), which
# is what parses the roster: `grep` cannot tell a valid JSON document from a plausible one.
# Zero other dependencies; self-cleaning temp dir.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-roster)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

ROSTERED_COMMANDS='claude gemini opencode agy codex'

# ── the sandbox PATH ─────────────────────────────────────────────────────────
#
# base_path_without_rostered_clis — the real PATH minus every component that holds one of
# the five rostered command names. Building the base from the real PATH (rather than a
# hard-coded /usr/bin:/bin) keeps the suite portable across machines and CI images; the
# subtraction is what makes presence a property of the FIXTURE rather than of the box.
base_path_without_rostered_clis() {
  _bp_out=""
  _bp_oifs="$IFS"
  IFS=:
  set -- $PATH
  IFS="$_bp_oifs"
  for _bp_d in "$@"; do
    [ -n "$_bp_d" ] || continue
    _bp_skip=0
    for _bp_c in $ROSTERED_COMMANDS; do
      if [ -x "$_bp_d/$_bp_c" ]; then _bp_skip=1; fi
    done
    [ "$_bp_skip" = 0 ] || continue
    if [ -z "$_bp_out" ]; then _bp_out="$_bp_d"; else _bp_out="$_bp_out:$_bp_d"; fi
  done
  printf '%s\n' "$_bp_out"
}

BASE_PATH="$(base_path_without_rostered_clis)"

# The subtraction above must actually have worked, and it must not have taken the tools the
# installer needs with it. Both are asserted rather than assumed: a silently over-broad
# subtraction would make every installer run fail for a reason no assertion below names,
# and a silently under-broad one would make R6's "absent from PATH" fixture a lie.
for _c in $ROSTERED_COMMANDS; do
  if env -i PATH="$BASE_PATH" sh -c "command -v $_c" >/dev/null 2>&1; then
    fail "sandbox setup: '$_c' still resolves on the reduced base PATH — presence would be a property of this machine, not of the fixture"
  fi
done
for _c in awk sed grep sort tr cp mv rm mkdir chmod cat cmp mktemp find python3; do
  if ! env -i PATH="$BASE_PATH" sh -c "command -v $_c" >/dev/null 2>&1; then
    fail "sandbox setup: '$_c' is missing from the reduced base PATH — a directory holding a rostered CLI also held a tool the installer or this suite needs"
  fi
done

WITNESS="$T/witness"

# stub_bin <name> <command…> — a fresh bin dir holding a stub per command; prints its path.
# Each stub RECORDS that it ran and then FAILS, per R8's test contract.
stub_bin() {
  _sb_d="$T/bin-$1"; shift
  rm -rf "$_sb_d"; mkdir -p "$_sb_d"
  for _sb_c in "$@"; do
    {
      printf '#!/bin/sh\n'
      printf '# E17-F04 test stub: exists to be FOUND on PATH, never to be RUN.\n'
      printf 'printf "%%s\\n" "%s" >> "%s"\n' "$_sb_c" "$WITNESS"
      printf 'exit 3\n'
    } > "$_sb_d/$_sb_c"
    chmod +x "$_sb_d/$_sb_c"
  done
  printf '%s\n' "$_sb_d"
}

# sandbox_run <invocation> <bindir> <script-dir> <script-name> <args…> — the ONE place this
# suite spawns a process. <invocation> selects how the script is NAMED on the command line,
# and nothing else:
#
#   abs — `sh <script-dir>/<script-name>`               ⇒ the script sees an absolute $0
#   rel — `cd <script-dir> && sh ./<script-name>`       ⇒ the script sees $0 = ./<name>
#
# Same file, same environment, same resolved source directory: harness-install.sh derives
# its own SRC as `cd "$(dirname "$0")" && pwd`, which is the same absolute path under both.
# The ONLY observable difference is the literal $0. That is deliberate — $0 is not one of
# R9's three roster inputs, so no byte of the roster may depend on it, and a fixture that
# only ever spelled the installer one way could not tell.
sandbox_run() {
  _sr_inv="$1"; _sr_bin="$2"; _sr_dir="$3"; _sr_name="$4"; shift 4
  mkdir -p "$T/home" "$T/ch"
  case "$_sr_inv" in
    abs)
      env -i PATH="$_sr_bin:$BASE_PATH" HOME="$T/home" CODEX_HOME="$T/ch" \
        sh "$_sr_dir/$_sr_name" "$@" </dev/null
      ;;
    rel)
      env -i PATH="$_sr_bin:$BASE_PATH" HOME="$T/home" CODEX_HOME="$T/ch" \
        sh -c 'cd "$1" || exit 1; _n="$2"; shift 2; exec sh "./$_n" "$@"' \
        _ "$_sr_dir" "$_sr_name" "$@" </dev/null
      ;;
    *) fail "sandbox_run: unknown invocation '$_sr_inv'" ;;
  esac
}

# hrun <target> <bindir> -- <extra installer args…> — the installer, named absolutely.
hrun() {
  _hr_target="$1"; _hr_bin="$2"; shift 2
  if [ "${1:-}" = "--" ]; then shift; fi
  sandbox_run abs "$_hr_bin" "$SRC" harness-install.sh "$_hr_target" "$@"
}

# hrun_relative — the SAME installer file, reached by a different invocation path. Used by
# R9 only, to hold every roster input fixed while varying something that is NOT an input.
hrun_relative() {
  _hr_target="$1"; _hr_bin="$2"; shift 2
  if [ "${1:-}" = "--" ]; then shift; fi
  sandbox_run rel "$_hr_bin" "$SRC" harness-install.sh "$_hr_target" "$@"
}

# ── the roster reader ────────────────────────────────────────────────────────
#
# A REAL PARSER, deliberately: `grep` is satisfied by a document that merely contains the
# right substrings, which is exactly the failure mode a hand-rolled printf emitter has
# (a trailing comma, a malformed empty array). Nothing here shares code with the emitter.
cat > "$T/rq.py" <<'PYEOF'
import json, sys

path, query = sys.argv[1], sys.argv[2]
with open(path) as fh:
    doc = json.load(fh)


def entry(key):
    for w in doc.get("workers", []):
        if w.get("key") == key:
            return w
    return None


if query == "schema":
    v = doc.get("schema")
    print("%s:%r" % (type(v).__name__, v))
elif query == "toplevel":
    print(",".join(sorted(doc.keys())))
elif query == "generated_by":
    print(doc.get("generated_by", "__ABSENT__"))
elif query == "vocab":
    print(",".join(doc.get("capability_vocabulary", [])))
elif query == "keys":
    for w in doc.get("workers", []):
        print(w.get("key"))
elif query == "nworkers":
    print(len(doc.get("workers", [])))
elif query == "allcaps":
    for w in doc.get("workers", []):
        for c in w.get("capabilities", []):
            print(c)
elif query in ("command", "caps", "fields"):
    e = entry(sys.argv[3])
    if e is None:
        print("__NOENTRY__")
    elif query == "command":
        print(e.get("command", "__NOCOMMAND__"))
    elif query == "caps":
        print(",".join(e.get("capabilities", [])))
    else:
        print(",".join(sorted(e.keys())))
else:
    sys.exit("unknown query: " + query)
PYEOF

rq() { python3 "$T/rq.py" "$@"; }

# has_cap <roster> <key> <tag> — true iff that entry carries that tag. Exact-token match on
# a comma-joined list, so `host-detectable` can never be matched by a superstring.
has_cap() {
  printf '%s\n' "$(rq "$1" caps "$2")" | tr ',' '\n' | grep -qx "$3"
}

# ── target fixtures ──────────────────────────────────────────────────────────
#
# One FRESH install is done at suite start; each case copies it. That is not just speed:
# it makes every case's roster-writing run an UPGRADE over an identical target, so the only
# thing that varies between cases is the gate, the selection and the sandbox PATH — the
# three roster inputs R9 names, and nothing else.
TPL="$T/template"
mkdir -p "$TPL"
_tpl_bin="$(stub_bin template)"
hrun "$TPL" "$_tpl_bin" >"$T/template-install.log" 2>&1 \
  || { cat "$T/template-install.log" >&2; fail "template install exited non-zero"; }
[ -f "$TPL/.harness/harness.config.yaml" ] || fail "template install produced no harness.config.yaml"

# target <name> — a fresh copy of the template; prints its path.
target() {
  _tg_d="$T/tgt-$1"
  rm -rf "$_tg_d"; mkdir -p "$_tg_d"
  cp -R "$TPL/." "$_tg_d/"
  printf '%s\n' "$_tg_d"
}

# set_gate <target> <true|false|…> — rewrite ONLY the `roster:` scalar in the workers block.
set_gate() {
  _sg_c="$1/.harness/harness.config.yaml"
  sed "s|^  roster: .*|  roster: $2|" "$_sg_c" > "$_sg_c.t" && mv "$_sg_c.t" "$_sg_c"
  grep -qxF "  roster: $2" "$_sg_c" \
    || fail "set_gate: the workers.roster line was not rewritten to '$2' — the fixture is not testing what it claims"
}

ROSTER_REL=".harness/workers.json"

# ── R1 ───────────────────────────────────────────────────────────────────────
test_R1_enabled_writes_roster() {
  _d="$(target r1)"
  set_gate "$_d" true
  _b="$(stub_bin r1 claude agy)"
  hrun "$_d" "$_b" >"$T/r1.log" 2>&1 || { cat "$T/r1.log" >&2; fail "R1: installer exited non-zero"; }
  [ -f "$_d/$ROSTER_REL" ] \
    || fail "R1: workers.roster is enabled but the installer wrote no $ROSTER_REL"
  [ ! -L "$_d/$ROSTER_REL" ] \
    || fail "R1: the roster was written as a symlink"
  [ "$(rq "$_d/$ROSTER_REL" nworkers)" = "2" ] \
    || fail "R1: the roster was written but holds $(rq "$_d/$ROSTER_REL" nworkers) entries, expected the 2 stubbed CLIs — the file exists for some other reason than detection"
}

# ── R2 ───────────────────────────────────────────────────────────────────────
#
# Two layers. The TRUTH TABLE exercises the gate function itself over the four values R2
# names plus decoys, which is the only way to tell "absent" from "false" — migrate_config
# appends the block before the roster is written, so an absent key can never survive a
# whole install run to be observed end to end.
#
# The E2E layer then enumerates the PERMITTED DELTAS rather than asserting "nothing
# changed": a gate-off target is NOT byte-identical to a pre-feature one and cannot be
# (the seeded `workers.roster: false` key and the unconditional `.gitignore` line are both
# documented as always-present), so a "nothing changed" assertion would fail a correct
# implementation. Two independent measurements carry "nothing else added", because neither
# is sufficient alone:
#   (i)  ON the gate-off target: no roster-NAMED path exists anywhere in it. Self-contained,
#        and the only one that can see an artifact written on BOTH gate paths.
#   (ii) BETWEEN the gate-off and gate-on targets: flipping the gate adds EXACTLY
#        `.harness/workers.json` and removes nothing. Sees any extra artifact the gate adds,
#        roster-named or not — but is blind to anything common to both runs.
test_R2_absent_key_writes_nothing() {
  # (a) the truth table, on the installer's own extracted gate.
  {
    sed -n '/^_cfg_workers_roster_is_true() {$/,/^}$/p' "$SRC/harness-install.sh"
    sed -n '/^worker_roster_enabled() {$/,/^}$/p' "$SRC/harness-install.sh"
  } > "$T/gatefns.sh"
  grep -q '^_cfg_workers_roster_is_true() {$'  "$T/gatefns.sh" || fail "R2: _cfg_workers_roster_is_true is not extractable at column 0"
  grep -q '^worker_roster_enabled() {$' "$T/gatefns.sh" || fail "R2: worker_roster_enabled is not extractable at column 0"
  cat > "$T/gate-probe.sh" <<'PEOF'
set -eu
. "$1"
H="$2"
if worker_roster_enabled; then echo enabled; else echo disabled; fi
PEOF

  # <config-body> uses `%b` so the `\n` escapes below become real newlines.
  _probe() {  # <label> <config-body> <expected>
    _pd="$T/gate-$1"; rm -rf "$_pd"; mkdir -p "$_pd"
    printf '%b' "$2" > "$_pd/harness.config.yaml"
    _got="$(sh "$T/gate-probe.sh" "$T/gatefns.sh" "$_pd")"
    [ "$_got" = "$3" ] \
      || fail "R2: gate case '$1' resolved '$_got', expected '$3' — the gate is a WHITELIST that fails closed: only a DIRECT child of top-level \`workers:\` named \`roster:\` whose value is one of the literals true / \"true\" / 'true' (plus an optional real trailing # comment) may enable the roster; every other shape, nested or malformed alike, stays OFF"
  }
  _probe absent_block    'telemetry:\n  enabled: true\n'            disabled
  _probe absent_key      'workers:\n'                               disabled
  _probe empty_value     'workers:\n  roster:\n'                    disabled
  _probe explicit_false  'workers:\n  roster: false\n'              disabled
  _probe unrecognized    'workers:\n  roster: yes\n'                disabled
  _probe wrong_case      'workers:\n  roster: True\n'               disabled
  _probe decoy_section   'ci:\n  roster: true\nworkers:\n  roster: false\n' disabled
  # A `#` inside a QUOTED scalar is part of the value, not a comment: `"true#disabled"` is a
  # valid YAML string and an unrecognized value, so R2 keeps the gate OFF. Comment-stripping
  # that ignores quoting truncates it to `true` and turns the roster ON.
  _probe quoted_hash     'workers:\n  roster: "true#disabled"\n'    disabled
  # …and the UNQUOTED forms, which reach a DIFFERENT branch. `quoted_hash` above is rejected
  # by the quote alternatives before the comment rule is ever consulted, so it pins nothing
  # about that rule. What the whitelist actually requires is that a `#` only opens a comment
  # when WHITESPACE precedes it: in `true#disabled` the `#` is part of a plain YAML scalar,
  # so the value is `true#disabled` — unrecognized, hence OFF. Relaxing the rule to allow
  # zero preceding whitespace lets both of these shed their suffix and read as `true`.
  _probe bare_hash        'workers:\n  roster: true#disabled\n'     disabled
  _probe quoted_then_hash 'workers:\n  roster: "true"#x\n'          disabled
  # TABS ARE NOT INDENTATION IN YAML — a tab-indented mapping key makes the whole document
  # malformed, so a real parser refuses the file rather than reading the key. An indent class
  # spanning the tab would enable the roster on a file nothing else can load. Both the indent
  # and the space after `roster:` are literal spaces, so both shapes stay OFF.
  _probe tab_indent       'workers:\n\troster: true\n'                disabled
  _probe tab_separator    'workers:\n  roster:\ttrue\n'               disabled
  # A tab ANYWHERE in the section's indentation makes the document unparseable, so the whole
  # section — including its space-indented lines — must stay OFF. This row pins HOW: the tab
  # line is measured, not skipped. Measured with spaces its indent is 0, which fixes the
  # direct-child indent at 0, so the following `  roster: true` reads as a descendant and never
  # decides. Skipping tab lines instead (as "malformed, never a key") lets `  roster: true` set
  # the child indent itself and ENABLE the roster on a file no parser will load — failing OPEN
  # on exactly the input the tab rule exists to reject.
  _probe tab_polluted     'workers:\n\tjunk: 1\n  roster: true\n'      disabled
  # SAME MALFORMED CLASS, OPPOSITE LINE ORDER, SAME ANSWER. A real parser refuses the file
  # whether the tab sits before or after the key, so the tab rule covers the WHOLE section,
  # not just the prefix the scan happens to read before it has a value. Answering at the
  # first `roster:` line and stopping there resolves this row ENABLED while `tab_polluted`
  # above resolves DISABLED — one document class with two answers, decided by line order.
  _probe tab_after_key    'workers:\n  roster: true\n\tjunk: 1\n'      disabled
  # …but the rule is SCOPED TO THE SECTION, not to the file: this gate reads one key, it does
  # not validate the document. A tab in an unrelated top-level block — on either side of
  # `workers:` — leaves a clean `workers:` section enabled, because vetoing on any tab
  # anywhere would make one stray tab elsewhere a silent global opt-out from the roster.
  _probe tab_other_after  'workers:\n  roster: true\nci:\n\tjunk: 1\n' enabled
  _probe tab_other_before 'ci:\n\tjunk: 1\nworkers:\n  roster: true\n' enabled
  # THE FIRST DIRECT `roster:` DECIDES, and finishing the section must not have changed that:
  # a later duplicate cannot promote a `false` first key into an enabled gate.
  _probe first_roster_wins 'workers:\n  roster: false\n  roster: true\n' disabled
  # …and the space-indented control still enables, so the rules above did not simply turn the
  # gate off for everyone.
  _probe space_indent_ctl 'workers:\n  roster: true\n'                enabled
  # ── the whitelist class ────────────────────────────────────────────────────────────
  # Every row below is a YAML shape that a decode-then-compare gate mis-decodes into the
  # literal `true` (or would, one variant at a time, as each new corner of YAML is taught to
  # it). The gate is instead a positive full-line match on three literal forms under the
  # DIRECT-child indent of `workers:`, so none of these match and all of them stay OFF.
  # `workers.options.roster` is a key of the `options` mapping, so `workers.roster` is ABSENT.
  _probe nested_mapping  'workers:\n  options:\n    roster: true\n' disabled
  # `'true''#disabled'` is a single YAML scalar: the doubled quote is an ESCAPED `'`, so the
  # value is the string `true'#disabled` — unrecognized, hence OFF. Closing the scalar at the
  # first inner quote instead reads `true` and turns the roster ON.
  _probe doubled_quote   "workers:\n  roster: 'true''#disabled'\n"  disabled
  # A folded block scalar, a tag and a trailing token: all unrecognized, none of them `true`.
  _probe block_scalar    'workers:\n  roster: >\n    true\n'        disabled
  _probe tagged_scalar   'workers:\n  roster: !!str true\n'         disabled
  _probe trailing_junk   'workers:\n  roster: true yes\n'           disabled
  _probe literal_true    'workers:\n  roster: true\n'               enabled
  # …and the enabling forms the whitelist must NOT regress: a genuine trailing comment (one
  # preceded by whitespace) is tolerated, and both quoted spellings of `true` still enable.
  _probe trailing_comment 'workers:\n  roster: true  # opt in\n'     enabled
  _probe quoted_true     'workers:\n  roster: "true"\n'             enabled
  _probe squoted_true    "workers:\n  roster: 'true'\n"             enabled
  # A comment line and a sibling key before `roster:` must not shift the direct-child indent
  # off the real one — otherwise rule 1 would disable a legitimately enabled roster.
  _probe comment_then_key 'workers:\n  # opt in below\n  roster: true\n' enabled
  _probe sibling_first   'workers:\n  other: 1\n  roster: true\n'   enabled
  # A config file that does not exist at all is the pre-install state; it must be OFF too.
  rm -rf "$T/gate-nofile"; mkdir -p "$T/gate-nofile"
  [ "$(sh "$T/gate-probe.sh" "$T/gatefns.sh" "$T/gate-nofile")" = "disabled" ] \
    || fail "R2: a target with no harness.config.yaml at all resolved the roster gate as enabled"

  # (b) end to end: the gate off adds no roster, and turning it on adds exactly one file.
  _off="$(target r2off)"
  set_gate "$_off" false
  _b="$(stub_bin r2 claude agy)"
  hrun "$_off" "$_b" >"$T/r2off.log" 2>&1 || { cat "$T/r2off.log" >&2; fail "R2: gate-off install exited non-zero"; }
  [ ! -e "$_off/$ROSTER_REL" ] \
    || fail "R2: the roster gate is off but $ROSTER_REL exists"

  # …AND NOTHING ELSE ROSTER-SHAPED, measured on the gate-off target ALONE. The gate-on/
  # gate-off inventory delta below is a comparison between two POST-feature targets, so it
  # can only ever see what the GATE adds: an artifact the roster code drops on BOTH paths
  # (say a stamp written before the gate is even consulted) appears in both inventories and
  # cancels out of the delta, leaving R2's "nothing else added" clause unenforced.
  # The direct comparison — a gate-off target against a pre-feature one — is not available:
  # it would mean diffing against `main`, which is banned here because it breaks on every
  # later legitimate change. So assert it positively and self-containedly instead: R2's two
  # permitted always-present items are a LINE INSIDE .harness/.gitignore and a KEY INSIDE
  # harness.config.yaml, neither of which is a roster-NAMED path, so a correct gate-off
  # install leaves no `*worker*` file or directory anywhere in the target.
  # The precondition is precisely "THE INSTALLER creates no worker-named path" — not "nothing
  # ever does". /sdd-pr-loop writes a `<round_dir>/worker` file into a target, but only at
  # AGENT RUNTIME, so it cannot reach a fixture that only ever runs the installer. Do not
  # relax this sweep on account of that path; a red here is the installer, and is real.
  _stray="$(find "$_off" -iname '*worker*' | LC_ALL=C sort | tr '\n' ' ')"
  [ -z "$_stray" ] \
    || fail "R2: the roster gate is off but the target carries roster-named artifacts: $_stray — with the gate off the installer may add exactly the workers.roster config key and the .gitignore line, both of which live INSIDE an existing file"

  # the two documented always-present items
  grep -qxF '  roster: false' "$_off/.harness/harness.config.yaml" \
    || fail "R2: the gate-off target has no documented \`workers.roster: false\` config key"
  grep -qxF 'workers.json' "$_off/.harness/.gitignore" \
    || fail "R2: the gate-off target has no workers.json entry in .harness/.gitignore (R11 is ubiquitous, not gated)"

  _on="$(target r2on)"
  set_gate "$_on" true
  hrun "$_on" "$_b" >"$T/r2on.log" 2>&1 || { cat "$T/r2on.log" >&2; fail "R2: gate-on install exited non-zero"; }
  ( cd "$_off" && find . -type f | LC_ALL=C sort ) > "$T/r2-off.txt"
  ( cd "$_on"  && find . -type f | LC_ALL=C sort ) > "$T/r2-on.txt"
  _delta="$(LC_ALL=C comm -13 "$T/r2-off.txt" "$T/r2-on.txt")"
  [ "$_delta" = "./$ROSTER_REL" ] \
    || fail "R2: flipping the roster gate on adds more (or less) than the roster file itself; delta was: $(printf '%s' "$_delta" | tr '\n' ' ')"
  _gone="$(LC_ALL=C comm -23 "$T/r2-off.txt" "$T/r2-on.txt")"
  [ -z "$_gone" ] \
    || fail "R2: flipping the roster gate on REMOVED files: $(printf '%s' "$_gone" | tr '\n' ' ')"
}

# ── R3 ───────────────────────────────────────────────────────────────────────
test_R3_ungated_reclaims_existing() {
  _d="$(target r3)"
  _b="$(stub_bin r3 claude agy)"
  set_gate "$_d" true
  hrun "$_d" "$_b" >"$T/r3a.log" 2>&1 || { cat "$T/r3a.log" >&2; fail "R3: setup install exited non-zero"; }
  [ -f "$_d/$ROSTER_REL" ] || fail "R3: setup failed — no roster to reclaim"

  set_gate "$_d" false
  hrun "$_d" "$_b" >"$T/r3b.log" 2>&1 || { cat "$T/r3b.log" >&2; fail "R3: reclaim install exited non-zero"; }
  [ ! -e "$_d/$ROSTER_REL" ] \
    || fail "R3: the roster gate went off but $ROSTER_REL was left behind"
  grep -qi 'roster reclaimed' "$T/r3b.log" \
    || fail "R3: the reclamation was not reported — an operator cannot tell a removed roster from one that was never written"
}

# ── R4 ───────────────────────────────────────────────────────────────────────
test_R4_schema_is_one() {
  _d="$(target r4)"
  set_gate "$_d" true
  _b="$(stub_bin r4 claude)"
  hrun "$_d" "$_b" >"$T/r4.log" 2>&1 || { cat "$T/r4.log" >&2; fail "R4: installer exited non-zero"; }
  # The TYPE matters as much as the value: `"schema": "1"` is a different contract, and a
  # grep for `1` could not tell them apart.
  [ "$(rq "$_d/$ROSTER_REL" schema)" = "int:1" ] \
    || fail "R4: top-level schema is $(rq "$_d/$ROSTER_REL" schema), expected the integer 1"
}

# ── R5 ───────────────────────────────────────────────────────────────────────
test_R5_one_entry_per_present_cli() {
  _d="$(target r5)"
  set_gate "$_d" true
  _b="$(stub_bin r5 claude codex agy)"
  hrun "$_d" "$_b" >"$T/r5.log" 2>&1 || { cat "$T/r5.log" >&2; fail "R5: installer exited non-zero"; }
  _r="$_d/$ROSTER_REL"

  # Exactly one entry per resolving key, in AGENT_KEYS order (claude gemini opencode
  # antigravity codex) — so the expected sequence is claude, antigravity, codex.
  [ "$(rq "$_r" keys | tr '\n' ' ')" = "claude antigravity codex " ] \
    || fail "R5: roster keys are '$(rq "$_r" keys | tr '\n' ' ')', expected 'claude antigravity codex ' (one per resolving key, in AGENT_KEYS order)"

  # Each entry names the key it describes and the invocation command that resolved. The
  # antigravity row is the discriminating one: its command is `agy`, not its key.
  [ "$(rq "$_r" command claude)" = "claude" ]      || fail "R5: the claude entry's command is '$(rq "$_r" command claude)'"
  [ "$(rq "$_r" command antigravity)" = "agy" ]    || fail "R5: the antigravity entry's command is '$(rq "$_r" command antigravity)', expected the invocation name 'agy'"
  [ "$(rq "$_r" command codex)" = "codex" ]        || fail "R5: the codex entry's command is '$(rq "$_r" command codex)'"

  # THE ENTRY SHAPE IS AN EQUALITY, NOT A PRESENCE CHECK. "An entry records no filesystem
  # path" is a recorded decision of the approval gate (spec → Recorded decision 4), and a
  # test that only checked `key`/`command` were present would pass an emitter that also
  # shipped `path`. `path` was in this spec until the gate removed it, so that emitter is a
  # live possibility rather than a hypothetical.
  for _k in claude antigravity codex; do
    [ "$(rq "$_r" fields "$_k")" = "capabilities,command,key" ] \
      || fail "R5: the '$_k' entry's field set is {$(rq "$_r" fields "$_k")}, expected exactly {capabilities,command,key} — an entry records the key and the command that resolved, and NO filesystem path (spec → Recorded decision 4)"
  done
}

test_R5_unselected_cli_is_still_rostered() {
  # THE ONE CASE STANDING BETWEEN THIS FEATURE AND A SILENT BUG. write_escalation_arming,
  # the precedent this code is modelled on, filters its AGENT_KEYS loop with
  # `agent_selected … || continue`. A roster that copied that filter is BYTE-IDENTICAL to a
  # correct one on any machine where everything is selected, so only a narrowed selection
  # with other CLIs installed can catch it.
  _d="$(target r5sel)"
  set_gate "$_d" true
  _b="$(stub_bin r5sel claude codex agy)"
  hrun "$_d" "$_b" -- --agents=claude >"$T/r5sel.log" 2>&1 \
    || { cat "$T/r5sel.log" >&2; fail "R5(sel): installer exited non-zero"; }
  _r="$_d/$ROSTER_REL"

  [ "$(rq "$_r" command codex)" != "__NOENTRY__" ] \
    || fail "R5(sel): 'codex' is installed but UNSELECTED and has no roster entry — the roster filtered by selection instead of recording it (plan → the agent_selected trap)"
  [ "$(rq "$_r" command antigravity)" != "__NOENTRY__" ] \
    || fail "R5(sel): 'antigravity' is installed but UNSELECTED and has no roster entry — the roster filtered by selection instead of recording it"

  # Selection is a FIELD, never a filter: the unselected entries exist and carry what they
  # earned, minus harness-selected.
  has_cap "$_r" claude harness-selected \
    || fail "R5(sel): the SELECTED 'claude' entry lacks harness-selected"
  ! has_cap "$_r" codex harness-selected \
    || fail "R5(sel): the UNSELECTED 'codex' entry carries harness-selected"
  ! has_cap "$_r" antigravity harness-selected \
    || fail "R5(sel): the UNSELECTED 'antigravity' entry carries harness-selected"
  has_cap "$_r" codex host-detectable \
    || fail "R5(sel): the unselected 'codex' entry lost host-detectable — deselection must not strip a capability it did not derive"
  has_cap "$_r" codex non-interactive \
    || fail "R5(sel): the unselected 'codex' entry lost non-interactive — deselection must not strip a capability it did not derive"
}

# ── R6 ───────────────────────────────────────────────────────────────────────
test_R6_absent_cli_has_no_entry() {
  # PAIRED WITH A CONTROL THAT FIRES. Silence on a fixture that could never have produced
  # an entry proves nothing, so the same fixture is re-run with the one stub added.
  _d="$(target r6)"
  set_gate "$_d" true
  _b1="$(stub_bin r6a claude)"
  hrun "$_d" "$_b1" >"$T/r6a.log" 2>&1 || { cat "$T/r6a.log" >&2; fail "R6: installer exited non-zero"; }
  [ "$(rq "$_d/$ROSTER_REL" command codex)" = "__NOENTRY__" ] \
    || fail "R6: 'codex' does not resolve on the sandbox PATH but the roster carries an entry for it"
  [ "$(rq "$_d/$ROSTER_REL" command gemini)" = "__NOENTRY__" ] \
    || fail "R6: 'gemini' does not resolve on the sandbox PATH but the roster carries an entry for it"

  _b2="$(stub_bin r6b claude codex)"
  hrun "$_d" "$_b2" >"$T/r6b.log" 2>&1 || { cat "$T/r6b.log" >&2; fail "R6: control install exited non-zero"; }
  [ "$(rq "$_d/$ROSTER_REL" command codex)" = "codex" ] \
    || fail "R6: the control fixture added a 'codex' stub to PATH and the roster STILL has no codex entry — the silence above proves nothing"
}

# ── R4 + R7: the vocabulary is closed AND fixed ──────────────────────────────
test_R7_capabilities_are_closed() {
  _d="$(target r7closed)"
  set_gate "$_d" true
  _b="$(stub_bin r7closed claude codex agy gemini)"
  hrun "$_d" "$_b" >"$T/r7c.log" 2>&1 || { cat "$T/r7c.log" >&2; fail "R7(closed): installer exited non-zero"; }
  _r="$_d/$ROSTER_REL"

  # The vocabulary EQUALS the sorted three-tag literal (R4). Honesty note, per the test
  # contract: this half is a trivially-passing regression guard — the vocabulary is a
  # hardcoded literal in the emitter, so comparing it against the same literal cannot fail
  # on any implementation that leaves that constant alone. It is kept because editing that
  # constant is precisely the silent format change R4 forbids. Read it as pinning the
  # contract, NOT as evidence the emitter works.
  [ "$(rq "$_r" vocab)" = "harness-selected,host-detectable,non-interactive" ] \
    || fail "R4/R7: capability_vocabulary is [$(rq "$_r" vocab)], expected exactly the sorted three-tag set harness-selected,host-detectable,non-interactive — growing, renaming or dropping a tag is a schema bump"

  # Every capability on every entry is one of those three. Compared against the LITERAL,
  # not against whatever the file declares — a self-consistent emitter satisfies the latter
  # for free. This half is NOT a trivial guard: it fails on any emitter that stamps a tag
  # outside the three, declared or not.
  rq "$_r" allcaps | LC_ALL=C sort -u > "$T/r7-seen.txt"
  while IFS= read -r _tag; do
    [ -n "$_tag" ] || continue
    case "$_tag" in
      harness-selected|host-detectable|non-interactive) : ;;
      *) fail "R4/R7: a roster entry carries the capability '$_tag', which is outside the closed schema-1 vocabulary" ;;
    esac
  done < "$T/r7-seen.txt"

  # …and the roster it was checked against was not vacuous.
  [ -s "$T/r7-seen.txt" ] \
    || fail "R4/R7: no entry carried ANY capability — the closure check above was vacuous"
}

# ── R7: each tag tracks its evidence, present AND absent ─────────────────────
test_R7_each_tag_tracks_its_evidence() {
  # One install pairs, for every tag, a key that HAS its evidence with a key that does not.
  #   harness-selected : claude (in --agents) vs codex (installed, not selected)
  #   host-detectable  : codex  (HOST_MARKERS row) vs gemini (no row)
  #   non-interactive  : codex  (WORKER_INVOKE claim) vs gemini (no claim)
  _d="$(target r7ev)"
  set_gate "$_d" true
  _b="$(stub_bin r7ev claude codex gemini)"
  hrun "$_d" "$_b" -- --agents=claude >"$T/r7ev.log" 2>&1 \
    || { cat "$T/r7ev.log" >&2; fail "R7(evidence): installer exited non-zero"; }
  _r="$_d/$ROSTER_REL"

  for _k in claude codex gemini; do
    [ "$(rq "$_r" command "$_k")" != "__NOENTRY__" ] \
      || fail "R7(evidence): setup failed — '$_k' was stubbed on PATH but has no roster entry, so its tags cannot be checked"
  done

  has_cap  "$_r" claude harness-selected  || fail "R7: 'claude' IS in the selection but its entry lacks harness-selected"
  ! has_cap "$_r" codex  harness-selected || fail "R7: 'codex' is NOT in the selection but its entry carries harness-selected"

  has_cap  "$_r" codex  host-detectable   || fail "R7: 'codex' HAS a HOST_MARKERS row but its entry lacks host-detectable"
  ! has_cap "$_r" gemini host-detectable  || fail "R7: 'gemini' has NO HOST_MARKERS row but its entry carries host-detectable"

  has_cap  "$_r" codex  non-interactive   || fail "R7: 'codex' HAS a verified WORKER_INVOKE entrypoint but its entry lacks non-interactive"
  ! has_cap "$_r" gemini non-interactive  || fail "R7: 'gemini' has NO verified entrypoint but its entry claims non-interactive — an unverified claim must never ship"

  # gemini earns nothing at all, and an empty capability list is a meaningful answer.
  [ "$(rq "$_r" caps gemini)" = "" ] \
    || fail "R7: the unselected, undetectable, unverified 'gemini' entry carries [$(rq "$_r" caps gemini)], expected an empty capability list"

  # The capability list is SORTED (R7/R9) — checked on the entry that earns more than one.
  [ "$(rq "$_r" caps claude)" = "harness-selected,host-detectable,non-interactive" ] \
    || fail "R7/R9: the claude entry's capabilities are [$(rq "$_r" caps claude)], expected them sorted"
}

# ── R7: harness-selected reports SELECTION, not a successful stamp ───────────
test_R7_selected_tag_survives_a_refused_write() {
  _d="$(target r7refuse)"
  set_gate "$_d" true
  # A hand-edited opencode.json the installer does not own: the documented refusal path
  # leaves it in place with a warning and applies no model routing.
  printf '{"$schema":"https://opencode.ai/config.json","hand":"edited"}\n' > "$_d/opencode.json"
  _b="$(stub_bin r7refuse opencode)"
  hrun "$_d" "$_b" -- --agents=opencode >"$T/r7refuse.log" 2>&1 \
    || { cat "$T/r7refuse.log" >&2; fail "R7(refused): installer exited non-zero"; }

  # ANCHOR: the refusal must actually have happened, or the assertion below is about
  # nothing. Both halves are checked — the warning, and the file surviving untouched.
  grep -q 'opencode.json differs from the generated stamp' "$T/r7refuse.log" \
    || fail "R7(refused): the installer did NOT refuse to overwrite the hand-edited opencode.json — the fixture is not exercising the refusal path"
  grep -q '"hand":"edited"' "$_d/opencode.json" \
    || fail "R7(refused): the hand-edited opencode.json was overwritten — the fixture is not exercising the refusal path"

  _r="$_d/$ROSTER_REL"
  [ "$(rq "$_r" command opencode)" != "__NOENTRY__" ] \
    || fail "R7(refused): 'opencode' resolves on PATH but has no roster entry"
  has_cap "$_r" opencode harness-selected \
    || fail "R7(refused): 'opencode' is in the selection but lost harness-selected after a REFUSED write — the tag's evidence is membership in SELECTED, not a write outcome; an implementation that reached for the stamp ledger made the tag mean harness-stamped by another name"
}

# ── R8 ───────────────────────────────────────────────────────────────────────
test_R8_never_executes_a_rostered_cli() {
  rm -f "$WITNESS"
  _d="$(target r8)"
  set_gate "$_d" true
  _b="$(stub_bin r8 claude codex agy)"
  hrun "$_d" "$_b" >"$T/r8.log" 2>&1 || { cat "$T/r8.log" >&2; fail "R8: installer exited non-zero"; }

  # ANCHOR FIRST. "The witness does not exist" is equally true when the sandbox PATH was
  # misconfigured, the gate was off, or the roster code never ran — an assertion satisfied
  # by a second path proves nothing about the first. So prove the detection path was
  # reached, on these very stubs, before reading the negative.
  [ -f "$_d/$ROSTER_REL" ] \
    || fail "R8: no roster was written, so the negative assertion below would be vacuous"
  for _k in claude codex antigravity; do
    [ "$(rq "$_d/$ROSTER_REL" command "$_k")" != "__NOENTRY__" ] \
      || fail "R8: the roster has no '$_k' entry, so the stubs were never looked up and the negative assertion below would be vacuous"
  done

  [ ! -e "$WITNESS" ] \
    || fail "R8: a rostered CLI was EXECUTED during the install (witness: $(tr '\n' ' ' < "$WITNESS")) — presence must be PATH resolution alone, and no rostered CLI may be run for any purpose including version detection"
}

# ── R9 ───────────────────────────────────────────────────────────────────────
test_R9_rerun_is_byte_identical() {
  _d="$(target r9)"
  set_gate "$_d" true
  _b="$(stub_bin r9 claude codex agy)"

  # All three roster inputs held fixed: same gate, same selection, same set of resolving
  # keys. BYTE identity (cmp), not field-by-field equivalence — ordering bugs (detection
  # order instead of AGENT_KEYS order, unsorted capabilities) are exactly what a semantic
  # comparison hides, and they are why R9 exists.
  #
  # THE TWO RUNS REACH THE SAME SCRIPT BY DIFFERENT INVOCATION PATHS (abs vs rel), so the
  # installer's own $0 differs between them while all three roster inputs stay fixed. Two
  # runs spelled identically cannot see an invocation-dependent value in the file at all —
  # and `generated_by` is exactly such a value if someone writes `"$0"` there instead of the
  # fixed literal (plan → Data model). That would be a *fourth* input to R9, and it is also
  # the invariant under the emitter's decision to ship NO JSON escaper: every value it
  # writes is a harness-authored literal, which an invocation path is not.
  #
  # ANCHOR: the two shapes must really produce different $0 values, or the cmp below is
  # between two identical command lines and pins nothing. Proven on a probe script through
  # the SAME sandbox_run machinery the installs go through, so a later "simplification" of
  # the rel branch back to an absolute path fails here instead of silently voiding R9.
  mkdir -p "$T/argv0"
  printf '#!/bin/sh\nprintf "%%s\\n" "$0"\n' > "$T/argv0/argv0-probe.sh"
  chmod +x "$T/argv0/argv0-probe.sh"
  _a0abs="$(sandbox_run abs "$_b" "$T/argv0" argv0-probe.sh)"
  _a0rel="$(sandbox_run rel "$_b" "$T/argv0" argv0-probe.sh)"
  [ "$_a0abs" != "$_a0rel" ] \
    || fail "R9: the abs and rel invocation shapes both gave \$0='$_a0abs' — the two installs below would differ in nothing, so the byte-identity check could not see an invocation-dependent value in the roster"
  [ "$_a0rel" = "./argv0-probe.sh" ] \
    || fail "R9: the rel invocation shape gave \$0='$_a0rel', expected './argv0-probe.sh'"

  hrun "$_d" "$_b" >"$T/r9a.log" 2>&1 || { cat "$T/r9a.log" >&2; fail "R9: first install exited non-zero"; }
  cp "$_d/$ROSTER_REL" "$T/r9-run1.json"
  hrun_relative "$_d" "$_b" >"$T/r9b.log" 2>&1 || { cat "$T/r9b.log" >&2; fail "R9: second (relatively-invoked) install exited non-zero"; }
  cp "$_d/$ROSTER_REL" "$T/r9-run2.json"
  cmp -s "$T/r9-run1.json" "$T/r9-run2.json" \
    || fail "R9: two runs with identical roster inputs produced different bytes — the only thing that differed was HOW the same installer was invoked (\`sh $SRC/harness-install.sh\` vs \`cd $SRC && sh ./harness-install.sh\`), which is not a roster input: $(diff "$T/r9-run1.json" "$T/r9-run2.json" | head -n 8)"

  # THE PATH-REORDERING CONTROL. With the resolved-path field dropped (spec → Recorded
  # decision 4), WHICH PATH component wins a lookup is no longer a roster input — input (c)
  # is a per-key boolean. So two runs over the same stub directories in a different PATH
  # order are BOUND to byte-identity, where the earlier resolved-path contract exempted
  # them. This is a REGRESSION GUARD, not a discriminator: a correct implementation
  # satisfies it by construction, because it records nothing derived from the winning
  # component. It fails exactly when someone reintroduces such a field.
  _d1="$(stub_bin r9x claude)"
  _d2="$(stub_bin r9y claude)"
  _e="$(target r9order)"
  set_gate "$_e" true
  hrun "$_e" "$_d1:$_d2" >"$T/r9c.log" 2>&1 || { cat "$T/r9c.log" >&2; fail "R9: PATH-order install (d1:d2) exited non-zero"; }
  cp "$_e/$ROSTER_REL" "$T/r9-order1.json"
  hrun "$_e" "$_d2:$_d1" >"$T/r9d.log" 2>&1 || { cat "$T/r9d.log" >&2; fail "R9: PATH-order install (d2:d1) exited non-zero"; }
  cp "$_e/$ROSTER_REL" "$T/r9-order2.json"
  cmp -s "$T/r9-order1.json" "$T/r9-order2.json" \
    || fail "R9: reordering two PATH components that BOTH hold a 'claude' stub changed the roster bytes — presence is a per-key boolean, so nothing in the file may depend on which component won: $(diff "$T/r9-order1.json" "$T/r9-order2.json" | head -n 8)"
  # …and the control was not vacuous: the reordered runs really did roster claude.
  [ "$(rq "$T/r9-order1.json" command claude)" = "claude" ] \
    || fail "R9: the PATH-order control produced no claude entry, so the comparison above was between two empty rosters"
}

# ── R10 ──────────────────────────────────────────────────────────────────────
test_R10_rerun_overwrites_from_fresh_state() {
  # THE FIRST ROSTER MUST BE DISTINGUISHABLE FROM A CORRECT ONE. Seeding a roster that
  # already matched the expected output would make the assertion pass whether or not
  # anything was overwritten. So seed one naming a key whose command is NOT on the sandbox
  # PATH, and require it to be gone.
  _d="$(target r10)"
  set_gate "$_d" true
  cat > "$_d/$ROSTER_REL" <<'STALE'
{
  "schema": 1,
  "generated_by": "harness-install.sh",
  "capability_vocabulary": ["harness-selected", "host-detectable", "non-interactive"],
  "workers": [
    {"key": "gemini", "command": "gemini", "capabilities": []}
  ]
}
STALE
  [ "$(rq "$_d/$ROSTER_REL" command gemini)" = "gemini" ] \
    || fail "R10: setup failed — the stale roster does not contain the gemini entry it is supposed to"

  _b="$(stub_bin r10 claude)"
  hrun "$_d" "$_b" >"$T/r10.log" 2>&1 || { cat "$T/r10.log" >&2; fail "R10: installer exited non-zero"; }
  [ "$(rq "$_d/$ROSTER_REL" command gemini)" = "__NOENTRY__" ] \
    || fail "R10: the stale 'gemini' entry survived a re-run on a PATH where gemini does not resolve — the roster was merged, not overwritten from freshly detected state"
  [ "$(rq "$_d/$ROSTER_REL" command claude)" = "claude" ] \
    || fail "R10: the freshly detected 'claude' entry is missing after the overwrite"

  # …and R10 still holds when the existing roster is NOT WRITABLE. A first install under a
  # restrictive umask leaves the file mode 0444, and a bare `>` cannot truncate it.
  #
  # ASSERT THE OUTCOME, NEVER THE SHELL'S REACTION. The bare redirection fails in two
  # different ways depending on the interpreter — dash/zsh abort on the `set -eu`
  # redirection error, bash/macOS `sh` carries on with the stale file — so a check written
  # against either one alone silently passes on the other half of the shells. Both are R10
  # violations, and both are caught by demanding the SAME end state as above: exit 0 and a
  # roster holding freshly detected content.
  #
  # ROOT CANNOT RUN THIS SCENARIO AT ALL, so it is skipped rather than adapted. Root bypasses
  # the permission bits: `test -w` reports a 0444 file writable, AND — the part that decides
  # the shape of this guard — the bare redirection SUCCEEDS against it. So under root there
  # is no failing write to observe, and the rows below would not be "mis-guarded", they would
  # be VACUOUS: they would pass identically with or without the `rm -f` they exist to pin.
  # Dropping the `test -w` guard would therefore make the suite green under root while
  # testing nothing, which is strictly worse than not running. Announce the skip instead —
  # a silently skipped case reads as a passing one. (CI and container images commonly run as
  # uid 0; that is the environment this exists for.)
  #
  # AND THE SKIP ITSELF IS PINNED, because the announcement below cannot be relied on to
  # surface it: tools/run-tests.sh — the configured verification.test_command — captures each
  # suite's stderr to a log and prints it ONLY on failure, so on a green run this message is
  # discarded. Unpinned, an always-taken skip would leave the suite green while the read-only
  # rows ran nowhere. R10RO_SKIPPED lets the driver assert that the skip was taken only as
  # uid 0. It re-reads `id -u`, so it is a control rather than an independent oracle — it
  # cannot catch a wholesale rewrite of the uid test, but it does kill the single-point
  # mutation (forcing the branch always-true) that is the realistic way this rots.
  if [ "$(id -u)" = "0" ]; then
    R10RO_SKIPPED=1
    echo "skip - R10 read-only rows: running as uid 0, which bypasses the 0444 bits — the failing write this pins cannot occur, so the rows would be vacuous rather than green" >&2
    return 0
  fi

  _d="$(target r10ro)"
  set_gate "$_d" true
  _b="$(stub_bin r10ro claude)"
  hrun "$_d" "$_b" >"$T/r10ro-first.log" 2>&1 \
    || { cat "$T/r10ro-first.log" >&2; fail "R10: setup failed — the first install exited non-zero"; }
  cat > "$_d/$ROSTER_REL" <<'STALE'
{
  "schema": 1,
  "generated_by": "harness-install.sh",
  "capability_vocabulary": ["harness-selected", "host-detectable", "non-interactive"],
  "workers": [
    {"key": "gemini", "command": "gemini", "capabilities": []}
  ]
}
STALE
  chmod 0444 "$_d/$ROSTER_REL"
  [ ! -w "$_d/$ROSTER_REL" ] \
    || fail "R10: setup failed — the roster is still writable after chmod 0444, so the read-only path is not under test"

  hrun "$_d" "$_b" >"$T/r10ro.log" 2>&1 \
    || { cat "$T/r10ro.log" >&2; fail "R10: the installer exited non-zero re-running against a READ-ONLY roster — a destination the installer owns outright must be replaced, not written through"; }
  [ "$(rq "$_d/$ROSTER_REL" command gemini)" = "__NOENTRY__" ] \
    || fail "R10: the stale entry survived a re-run against a READ-ONLY roster — the write silently failed and the roster was left as it was, while the installer reported success"
  [ "$(rq "$_d/$ROSTER_REL" command claude)" = "claude" ] \
    || fail "R10: the freshly detected 'claude' entry is missing after overwriting a READ-ONLY roster"
}

# ── R11 ──────────────────────────────────────────────────────────────────────
test_R11_roster_is_gitignored() {
  # Asserted on a GATE-OFF target on purpose: R11 is deliberately ubiquitous, not gated —
  # .harness/.gitignore is append-only on upgrade, so a gated line could never be removed
  # once the gate had been on.
  _d="$(target r11)"
  set_gate "$_d" false
  _b="$(stub_bin r11 claude)"
  hrun "$_d" "$_b" >"$T/r11.log" 2>&1 || { cat "$T/r11.log" >&2; fail "R11: installer exited non-zero"; }
  [ "$(grep -cxF 'workers.json' "$_d/.harness/.gitignore")" = "1" ] \
    || fail "R11: .harness/.gitignore carries $(grep -cxF 'workers.json' "$_d/.harness/.gitignore") 'workers.json' lines, expected exactly 1 (the ensure path is append-only and must not duplicate)"

  # …and as BEHAVIOR, not string presence: a line in the wrong place (e.g. after a
  # re-inclusion that shadows it) greps the same and ignores nothing.
  command -v git >/dev/null 2>&1 || return 0
  _g="$T/r11-probe"; rm -rf "$_g"; mkdir -p "$_g/.harness"
  git -C "$_g" init -q >/dev/null 2>&1 || { rm -rf "$_g"; return 0; }
  cp "$_d/.harness/.gitignore" "$_g/.harness/.gitignore"
  : > "$_g/.harness/workers.json"
  git -C "$_g" check-ignore -q .harness/workers.json \
    || fail "R11: .harness/workers.json is NOT ignored by the seeded .harness/.gitignore — one developer's local CLI set would be committed into a shared repo"
  rm -rf "$_g"
}

# ── R12 ──────────────────────────────────────────────────────────────────────
test_R12_symlink_is_refused() {
  _d="$(target r12)"
  set_gate "$_d" true
  _b="$(stub_bin r12 claude agy)"
  _outside="$T/r12-outside.json"
  printf 'not-a-roster\n' > "$_outside"
  ln -s "$_outside" "$_d/$ROSTER_REL"

  hrun "$_d" "$_b" >"$T/r12.log" 2>&1 || { cat "$T/r12.log" >&2; fail "R12: installer exited non-zero"; }
  [ -L "$_d/$ROSTER_REL" ] \
    || fail "R12: the symlinked roster was replaced — the link must be left entirely alone"
  [ "$(cat "$_outside")" = "not-a-roster" ] \
    || fail "R12: the installer wrote THROUGH the roster symlink and clobbered a file outside .harness/"
  grep -q 'workers.json is a symlink' "$T/r12.log" \
    || fail "R12: a symlinked roster was skipped silently — the refusal must warn"

  # R3 vs R12 MUST BE INDEPENDENTLY REACHABLE. The symlink guard runs BEFORE the gate, so a
  # symlinked roster with the gate OFF is left in place, never reclaimed. Without this
  # control an implementation that checked the gate first passes both tests while `rm -f`
  # unlinks a link it should never touch.
  set_gate "$_d" false
  hrun "$_d" "$_b" >"$T/r12b.log" 2>&1 || { cat "$T/r12b.log" >&2; fail "R12: gate-off symlink install exited non-zero"; }
  [ -L "$_d/$ROSTER_REL" ] \
    || fail "R12: with the gate OFF the symlinked roster was RECLAIMED — the symlink guard must run before the gate, and reclaiming through a link destroys an operator's link"
  [ "$(cat "$_outside")" = "not-a-roster" ] \
    || fail "R12: the gate-off path followed the roster symlink and damaged its target"
  rm -f "$_d/$ROSTER_REL"
}

# ── the roster is valid, parseable JSON ──────────────────────────────────────
test_roster_is_valid_json() {
  # A hand-rolled printf emitter gets STRUCTURE wrong independently of content: a trailing
  # comma after the last workers[] entry, or a malformed "workers": [] when nothing
  # resolved. Both shapes are loaded with a REAL parser here; `grep` cannot see either.
  _d="$(target json)"
  set_gate "$_d" true
  _b="$(stub_bin jsonfull claude codex agy gemini opencode)"
  hrun "$_d" "$_b" >"$T/json1.log" 2>&1 || { cat "$T/json1.log" >&2; fail "json: installer exited non-zero"; }
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$_d/$ROSTER_REL" \
    || fail "json: the POPULATED roster is not parseable JSON"
  [ "$(rq "$_d/$ROSTER_REL" nworkers)" = "5" ] \
    || fail "json: the populated fixture stubbed all five keys but the roster holds $(rq "$_d/$ROSTER_REL" nworkers) entries"
  [ "$(rq "$_d/$ROSTER_REL" toplevel)" = "capability_vocabulary,generated_by,schema,workers" ] \
    || fail "json: the roster's top-level keys are {$(rq "$_d/$ROSTER_REL" toplevel)}, expected exactly {capability_vocabulary,generated_by,schema,workers}"

  # THE KEY SET IS NOT THE CONTRACT — `generated_by`'s VALUE is a fixed literal. This is the
  # one field whose obvious lazy implementation (`"$0"`) is environment-derived, and the
  # emitter ships NO JSON escaper precisely because every value it writes is a
  # harness-authored literal from a closed set (harness-install.sh, the comment above
  # write_worker_roster). An invocation path is not that: it can hold `"` or `\`, it varies
  # between two otherwise identical installs, and the key-set check above cannot see any of
  # it. R9's abs-vs-rel pair pins the same invariant from the byte-identity side; this
  # pins the value itself, so the guarantee survives either case being rewritten.
  [ "$(rq "$_d/$ROSTER_REL" generated_by)" = "harness-install.sh" ] \
    || fail "json: generated_by is '$(rq "$_d/$ROSTER_REL" generated_by)', expected the fixed literal 'harness-install.sh' — an invocation-dependent value such as \$0 makes the roster carry environment-derived content, which is exactly the thing the emitter's no-escaper decision rests on being impossible"

  # The empty case: gate ON and NOTHING resolves. An empty roster MEANS something — this
  # machine can invoke none of the harness's front-ends — and a consumer must be able to
  # tell that from "the roster was never written", so the file must exist and be well
  # formed rather than be reclaimed.
  _e="$(target jsonempty)"
  set_gate "$_e" true
  _b0="$(stub_bin jsonempty)"
  hrun "$_e" "$_b0" >"$T/json2.log" 2>&1 || { cat "$T/json2.log" >&2; fail "json: empty-fixture installer exited non-zero"; }
  [ -f "$_e/$ROSTER_REL" ] \
    || fail "json: the gate is on and no CLI resolved, but no roster was written — an empty roster is an answer, not a reason to reclaim"
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$_e/$ROSTER_REL" \
    || fail "json: the EMPTY roster is not parseable JSON — a malformed \"workers\": [] is where a hand-rolled emitter breaks"
  [ "$(rq "$_e/$ROSTER_REL" nworkers)" = "0" ] \
    || fail "json: nothing resolved but the empty roster holds $(rq "$_e/$ROSTER_REL" nworkers) entries"
}

# ── run ──────────────────────────────────────────────────────────────────────
test_R1_enabled_writes_roster
pass "R1_enabled_writes_roster: the enabled gate writes .harness/workers.json from real detection (R1)"
test_R2_absent_key_writes_nothing
pass "R2_absent_key_writes_nothing: only the literal \`true\` enables the gate, and turning it on adds exactly the roster file (R2)"
test_R3_ungated_reclaims_existing
pass "R3_ungated_reclaims_existing: gate off + roster present ⇒ removed and reported (R3)"
test_R4_schema_is_one
pass "R4_schema_is_one: the top-level schema is the INTEGER 1 (R4)"
test_R5_one_entry_per_present_cli
pass "R5_one_entry_per_present_cli: one entry per resolving key in AGENT_KEYS order, each naming its key and command, with the field set EQUAL to {key,command,capabilities} — no path (R5)"
test_R5_unselected_cli_is_still_rostered
pass "R5_unselected_cli_is_still_rostered: an installed but UNSELECTED CLI still gets an entry; selection is a capability, never a filter (R5)"
test_R6_absent_cli_has_no_entry
pass "R6_absent_cli_has_no_entry: a command absent from PATH produces no entry, and the control with the stub added fires (R6)"
test_R7_capabilities_are_closed
pass "R7_capabilities_are_closed: capability_vocabulary EQUALS the sorted three-tag literal, and no entry carries a tag outside it (R4, R7)"
test_R7_each_tag_tracks_its_evidence
pass "R7_each_tag_tracks_its_evidence: every tag is present exactly when its evidence is and absent when it is not (R7)"
test_R7_selected_tag_survives_a_refused_write
pass "R7_selected_tag_survives_a_refused_write: harness-selected reports SELECTION and survives a refused glue write (R7)"
test_R8_never_executes_a_rostered_cli
pass "R8_never_executes_a_rostered_cli: presence is PATH resolution alone — no stub ran, on a run proven to have reached detection (R8)"
test_R9_rerun_is_byte_identical
pass "R9_rerun_is_byte_identical: identical roster inputs ⇒ byte-identical rosters, PATH reordering included (R9)"
R10RO_SKIPPED=0
test_R10_rerun_overwrites_from_fresh_state
[ "$R10RO_SKIPPED" = "0" ] || [ "$(id -u)" = "0" ] \
  || fail "R10: the read-only rows were SKIPPED as uid $(id -u) — the uid-0 skip fired for a user whose permission bits are NOT bypassed, so the rows that pin the read-only overwrite ran nowhere"
pass "R10_rerun_overwrites_from_fresh_state: a distinguishable stale roster is overwritten from freshly detected state (R10)"
test_R11_roster_is_gitignored
pass "R11_roster_is_gitignored: the roster path is ignored by .harness/.gitignore, ubiquitously and behaviorally (R11)"
test_R12_symlink_is_refused
pass "R12_symlink_is_refused: a symlinked roster is warned about and left alone — with the gate on AND with it off (R12)"
test_roster_is_valid_json
pass "roster_is_valid_json: populated and empty rosters both load in a real JSON parser with the expected shape"

echo "All worker-roster tests passed."
