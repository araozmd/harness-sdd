#!/bin/sh
# test_cascade.sh — test contract for E03-F02 (cascade installer).
# Zero-dependency POSIX sh, matching tests/test_install.sh house style (self-cleaning
# mktemp tree, fail/pass helpers). Covers every R-id in cascade-installer.tests.md.
# The single-target non-regression suite (tests/test_install.sh) must also stay green;
# this file additionally asserts R24's single-target-unchanged contract directly.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL="$SRC/harness-install.sh"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-cascade)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# build_umbrella <dir> — populate a fresh umbrella fixture tree.
#   viernes-bff/.git (dir)  lia-api/.git (file)  not_a_repo/ (no .git)
#   bad_Name/.git (invalid key grammar)  .hidden/.git (dotfile)  .harness/ (own)
build_umbrella() {
  _u="$1"
  mkdir -p "$_u/viernes-bff/.git"          # git child, .git as a DIRECTORY
  mkdir -p "$_u/lia-api"; : > "$_u/lia-api/.git"   # git child, .git as a FILE
  mkdir -p "$_u/not_a_repo"                # non-git child
  mkdir -p "$_u/bad_Name/.git"             # git child, INVALID key grammar
  mkdir -p "$_u/.hidden/.git"              # dotfile dir
  mkdir -p "$_u/.harness"                  # pre-existing own harness dir name
}

# ── R3: arg guards make no filesystem writes ──────────────────────────────────
sh "$INSTALL"                       >/dev/null 2>&1 && fail "missing-arg should exit non-zero (R3)"
sh "$INSTALL" "$SRC"                >/dev/null 2>&1 && fail "self-target should exit non-zero (R3)"
sh "$INSTALL" --umbrella            >/dev/null 2>&1 && fail "--umbrella without dir should exit non-zero (R3)"
NODIR="$T/does-not-exist"
sh "$INSTALL" --umbrella "$NODIR"   >/dev/null 2>&1 && fail "--umbrella non-dir should exit non-zero (R3)"
[ -e "$NODIR" ] && fail "--umbrella on a bad dir made a filesystem change (R3)"
pass "arg guards reject bad invocations, no writes (R3) [arg_guards_no_writes]"

# ── R2 / R24: no --umbrella ⇒ single-target only, no cascade/manifest ──────────
ST="$T/single"; mkdir -p "$ST"
sh "$INSTALL" "$ST" >/dev/null 2>&1 || fail "single-target install failed (R2)"
[ -d "$ST/.harness" ]                 || fail "single-target .harness missing (R2)"
[ ! -f "$ST/umbrella.manifest.yaml" ] || fail "single-target wrote a manifest — cascade leaked (R2)"
pass "no --umbrella ⇒ single-target only, no manifest/discovery (R2) [single_target_no_cascade]"

# R24: single-target install output/layout matches the pre-F02 contract. We assert the
# value-preserving migration changes no set value: seed a bootstrap value, upgrade,
# confirm it survives and the rest of the single-target install is intact.
sed -e 's|^\( *test_command:\).*|\1 "pytest -q"|' "$ST/.harness/harness.config.yaml" > "$ST/.harness/cfg.b" \
  && mv "$ST/.harness/cfg.b" "$ST/.harness/harness.config.yaml"
sh "$INSTALL" "$ST" >/dev/null 2>&1 || fail "single-target upgrade failed (R24)"
grep -q 'test_command: "pytest -q"' "$ST/.harness/harness.config.yaml" \
  || fail "single-target upgrade changed a bootstrap value (R24)"
[ "$(grep -cF '<!-- harness:begin -->' "$ST/CLAUDE.md")" = "1" ] \
  || fail "single-target upgrade duplicated the pointer block (R24)"
pass "single-target behaviorally unchanged, migration value-preserving (R24) [single_target_unchanged]"

# ── umbrella mode fresh run (drives most integration R-ids) ────────────────────
U="$T/umb"; mkdir -p "$U"; build_umbrella "$U"
OUT="$T/run1.out"
sh "$INSTALL" --umbrella "$U" >"$OUT" 2>&1 || fail "umbrella mode exited non-zero (R1)"

# R1: umbrella mode accepted and ran.
grep -q "umbrella cascade" "$OUT" || fail "umbrella mode banner absent (R1)"
pass "--umbrella <dir> mode accepted and runs (R1) [umbrella_mode_runs]"

# R5: coordinator profile (full body) written to <umbrella>/.harness/.
[ -d "$U/.harness" ]                          || fail "coordinator .harness missing (R5)"
[ -f "$U/.harness/AGENTS.md" ]                || fail "coordinator body (AGENTS.md) missing (R5)"
[ -f "$U/.harness/agents/orchestrator.md" ]   || fail "coordinator role bodies missing (R5)"
[ -f "$U/.harness/store/tasks.schema.json" ]  || fail "coordinator schema missing (R5)"
pass "coordinator profile (full body) installed in <umbrella>/.harness/ (R5) [coordinator_body_installed]"

# R6: coordinator umbrella.manifest set to the manifest path (fresh).
grep -Eq '^[[:space:]]*manifest:[[:space:]]*"\.\./umbrella\.manifest\.yaml"' "$U/.harness/harness.config.yaml" \
  || fail "coordinator umbrella.manifest not set to the manifest path (R6)"
pass "coordinator umbrella.manifest set to manifest path on fresh install (R6) [coordinator_manifest_key_set]"

# R7: coordinator has integration_command key; no extra coordinator test_command set
# (test_command remains blank-on-seed, exactly as single-target).
grep -Eq '^[[:space:]]*integration_command:' "$U/.harness/harness.config.yaml" \
  || fail "coordinator integration_command key missing (R7)"
grep -q 'test_command: ""' "$U/.harness/harness.config.yaml" \
  || fail "coordinator test_command not blank-on-seed (R7)"
pass "coordinator carries integration_command, no extra test_command (R7) [coordinator_integration_key]"

# R8: .git as a directory AND as a file both selected.
[ -d "$U/viernes-bff/.harness" ] || fail ".git-dir child not installed (R8)"
[ -d "$U/lia-api/.harness" ]     || fail ".git-file child not installed (R8)"
pass ".git as directory OR file both selected (R8) [git_dir_or_file_selected]"

# R9: dotfile dirs and the umbrella's own .harness skipped.
[ ! -d "$U/.hidden/.harness" ]  || fail "dotfile child .hidden was installed (R9)"
grep -q '\.hidden' "$U/umbrella.manifest.yaml" 2>/dev/null && fail ".hidden leaked into manifest (R9)"
grep -Eq '^  harness:' "$U/umbrella.manifest.yaml" 2>/dev/null && fail "own .harness leaked into manifest (R9)"
pass "dotfile dirs and own .harness skipped (R9) [hidden_and_harness_skipped]"

# R10: each git child gets the normal child profile (same layout as single-target).
[ -f "$U/viernes-bff/.harness/agents/builder.md" ] || fail "child profile body missing (R10)"
[ -f "$U/viernes-bff/.harness/state/tasks.json" ]  || fail "child project workspace not seeded (R10)"
[ -f "$U/viernes-bff/CLAUDE.md" ]                  || fail "child pointer not written (R10)"
[ -f "$U/lia-api/.harness/agents/builder.md" ]     || fail "second child profile body missing (R10)"
pass "each git child gets the normal child profile (R10) [child_profile_installed]"

# R11: umbrella.manifest.yaml created with a top-level repos: mapping.
[ -f "$U/umbrella.manifest.yaml" ]                  || fail "umbrella.manifest.yaml not created (R11)"
grep -Eq '^repos:[[:space:]]*$' "$U/umbrella.manifest.yaml" || fail "manifest missing top-level repos: (R11)"
pass "umbrella.manifest.yaml created with repos: header (R11) [manifest_created]"

# R12: each git child gets an entry (key, relative path, TODO placeholders).
grep -Eq '^  viernes-bff:[[:space:]]*$' "$U/umbrella.manifest.yaml" || fail "viernes-bff entry missing (R12)"
grep -Eq '^  lia-api:[[:space:]]*$'     "$U/umbrella.manifest.yaml" || fail "lia-api entry missing (R12)"
grep -q 'path: ./viernes-bff'           "$U/umbrella.manifest.yaml" || fail "viernes-bff relative path missing (R12)"
grep -q 'path: ./lia-api'               "$U/umbrella.manifest.yaml" || fail "lia-api relative path missing (R12)"
grep -q 'delegate_cmd:'                 "$U/umbrella.manifest.yaml" || fail "delegate_cmd placeholder missing (R12)"
grep -q 'TODO'                          "$U/umbrella.manifest.yaml" || fail "TODO placeholders missing (R12)"
pass "each child entry has key, relative path, TODO placeholders (R12) [manifest_entries_populated]"

# R13: invalid-named child skipped + clear message, no entry / no install.
grep -q "bad_Name" "$OUT"                       || fail "no message naming the invalid child (R13)"
grep -q "a-z0-9" "$OUT"                          || fail "skip message does not state the grammar (R13)"
[ ! -d "$U/bad_Name/.harness" ]                  || fail "invalid-named child was installed (R13)"
grep -q 'bad_Name' "$U/umbrella.manifest.yaml" && fail "invalid-named child written to manifest (R13)"
pass "invalid-named child skipped + warned, no entry/install (R13) [invalid_name_skipped]"

# R15: written manifest passes init.sh repo-key + path grammar (no warning, umbrella mode).
INITOUT="$T/initout"
( cd "$U" && ./.harness/init.sh ) >"$INITOUT" 2>&1 || fail "coordinator init.sh non-zero on populated manifest (R15)"
grep -q "umbrella mode: manifest present" "$INITOUT" || fail "init.sh did not engage umbrella mode (R15)"
grep -q "not a valid slice-id segment" "$INITOUT" && fail "init.sh flagged a manifest repo-key grammar error (R15)"
grep -q "path not found" "$INITOUT" && fail "init.sh flagged a missing manifest path (R15)"
pass "manifest readable by init.sh, valid repo-keys + paths (R15) [manifest_init_compatible]"

# R22: version stamp + manifest.txt for coordinator and each child.
[ "$(cat "$U/.harness/.harness-version")" = "$(cat "$SRC/VERSION")" ] || fail "coordinator version mismatch (R22)"
[ "$(cat "$U/viernes-bff/.harness/.harness-version")" = "$(cat "$SRC/VERSION")" ] || fail "child version mismatch (R22)"
[ -f "$U/.harness/manifest.txt" ]            || fail "coordinator manifest.txt missing (R22)"
[ -f "$U/viernes-bff/.harness/manifest.txt" ] || fail "child manifest.txt missing (R22)"
[ -f "$U/lia-api/.harness/manifest.txt" ]    || fail "second child manifest.txt missing (R22)"
pass "version stamp + manifest.txt for coordinator and each child (R22) [stamp_and_manifest_each]"

# R23: coordinator manifest.txt lists umbrella.manifest.yaml as a project-owned artifact.
grep -q 'umbrella.manifest.yaml' "$U/.harness/manifest.txt" || fail "coordinator manifest.txt omits umbrella.manifest.yaml (R23)"
pass "coordinator manifest.txt lists umbrella.manifest.yaml (R23) [coordinator_manifest_txt_lists_manifest]"

# R4: default scan is depth-1 only — a git repo nested two levels deep is NOT installed.
DEEP="$T/deep"; mkdir -p "$DEEP"
mkdir -p "$DEEP/level1/level2/.git"   # only reachable via depth 2
sh "$INSTALL" --umbrella "$DEEP" >/dev/null 2>&1 || fail "depth fixture install failed (R4)"
[ ! -d "$DEEP/level1/level2/.harness" ] || fail "depth-2 repo installed under default scan (R4)"
[ ! -d "$DEEP/level1/.harness" ]        || fail "non-git intermediate installed (R4)"
pass "default scan is depth-1 only (R4) [depth_one_default]"

# ── R14 / R16 / R17 / R21: re-run idempotency + preservation ───────────────────
# Mutate a manifest entry field and a child's project file, add a NEW git child,
# bootstrap-fill a child config value, then re-run.
sed 's|^\( *delegate_cmd:\).*|\1 "./run-sdd.sh"   # bootstrap-filled|' "$U/umbrella.manifest.yaml" > "$U/m.b" \
  && mv "$U/m.b" "$U/umbrella.manifest.yaml"
echo 'SENTINEL-CHILD-STATE' >> "$U/viernes-bff/.harness/state/tasks.json"
cp "$U/viernes-bff/.harness/state/tasks.json" "$T/child-tasks.orig"
sed -e 's|^\( *test_command:\).*|\1 "npm test"|' "$U/viernes-bff/.harness/harness.config.yaml" > "$U/viernes-bff/.harness/cfg.b" \
  && mv "$U/viernes-bff/.harness/cfg.b" "$U/viernes-bff/.harness/harness.config.yaml"
mkdir -p "$U/new-repo/.git"   # a NEW git child to be discovered on re-run
PTRBEFORE="$(grep -cF '<!-- harness:begin -->' "$U/viernes-bff/CLAUDE.md")"

sh "$INSTALL" --umbrella "$U" >/dev/null 2>&1 || fail "umbrella re-run failed (R14)"

# R14: new repo discovered + appended; existing entry field NOT overwritten.
grep -Eq '^  new-repo:[[:space:]]*$' "$U/umbrella.manifest.yaml" || fail "new git child not appended on re-run (R14)"
grep -q 'delegate_cmd: "./run-sdd.sh"' "$U/umbrella.manifest.yaml" \
  || fail "re-run clobbered a bootstrap-filled manifest field (R14)"
[ "$(grep -cE '^  viernes-bff:[[:space:]]*$' "$U/umbrella.manifest.yaml")" = "1" ] \
  || fail "re-run duplicated an existing manifest entry (R14)"
pass "re-run adds new repos, never overwrites existing entry fields (R14) [manifest_upsert_preserves]"

# R16: child project-owned files preserved.
cmp -s "$U/viernes-bff/.harness/state/tasks.json" "$T/child-tasks.orig" \
  || fail "child state/tasks.json clobbered on re-run (R16)"
grep -qF 'SENTINEL-CHILD-STATE' "$U/viernes-bff/.harness/state/tasks.json" \
  || fail "child project sentinel lost on re-run (R16)"
pass "re-run preserves each child's project-owned files (R16) [child_project_files_preserved]"

# R17: child entrypoint block not duplicated.
[ "$(grep -cF '<!-- harness:begin -->' "$U/viernes-bff/CLAUDE.md")" = "1" ] \
  || fail "child pointer block duplicated on re-run (R17)"
[ "$PTRBEFORE" = "1" ] || fail "child pointer block was not singular after first run (R17)"
pass "re-run does not duplicate the entrypoint block in children (R17) [child_pointer_not_duplicated]"

# R21: migration ran on a child upgrade (bootstrap value retained) — proves migration
# applies on both profiles, zero-dep (no yq/jq/python invoked by the cascade itself).
grep -q 'test_command: "npm test"' "$U/viernes-bff/.harness/harness.config.yaml" \
  || fail "child upgrade did not preserve bootstrap value through migration (R21)"
grep -Eq '^[[:space:]]*integration_command:' "$U/viernes-bff/.harness/harness.config.yaml" \
  || fail "child config missing integration_command after migration (R21)"
pass "migration runs on coordinator and child, value-preserving, zero-dep (R21) [migrate_both_profiles]"

# ── Config migration unit tests (R18, R19, R20) ────────────────────────────────
# Pre-F01 config: no umbrella: block at all, a bootstrap-set test_command and a
# trailing comment that must survive byte-for-byte.
PRE="$T/pre-f01"; mkdir -p "$PRE/.harness"
printf '0.1.0\n' > "$PRE/.harness/.harness-version"
cat > "$PRE/.harness/harness.config.yaml" <<'EOF'
store:
  tasks: local
verification:
  init_script: ./init.sh
  test_command: "pytest -q"   # keep me exactly
  lint_command: ""
EOF
cp "$PRE/.harness/harness.config.yaml" "$T/pre.before"

sh "$INSTALL" "$PRE" >/dev/null 2>&1 || fail "pre-F01 upgrade failed (R18)"

# R18: missing default keys appended (integration_command under verification:, and a
# whole umbrella: header+manifest block since the section was absent).
grep -Eq '^[[:space:]]*integration_command:' "$PRE/.harness/harness.config.yaml" \
  || fail "integration_command not appended on pre-F01 upgrade (R18)"
grep -Eq '^umbrella:[[:space:]]*$' "$PRE/.harness/harness.config.yaml" \
  || fail "umbrella: header not appended on pre-F01 upgrade (R18)"
grep -Eq '^[[:space:]]*manifest:' "$PRE/.harness/harness.config.yaml" \
  || fail "umbrella.manifest not appended on pre-F01 upgrade (R18)"
# E05-F02: the telemetry: block (header + enabled + log) is appended when absent.
grep -Eq '^telemetry:[[:space:]]*$' "$PRE/.harness/harness.config.yaml" \
  || fail "telemetry: header not appended on pre-telemetry upgrade (R18)"
grep -Eq '^[[:space:]]*enabled:' "$PRE/.harness/harness.config.yaml" \
  || fail "telemetry.enabled not appended on pre-telemetry upgrade (R18)"
grep -Eq '^[[:space:]]*log:[[:space:]]*telemetry\.jsonl' "$PRE/.harness/harness.config.yaml" \
  || fail "telemetry.log not appended on pre-telemetry upgrade (R18)"
pass "upgrade appends missing default keys to a pre-F01 config (R18) [migrate_appends_missing_keys]"

# R19: every already-present line is byte-for-byte retained (value + comment).
grep -qF 'test_command: "pytest -q"   # keep me exactly' "$PRE/.harness/harness.config.yaml" \
  || fail "migration altered an existing value or comment (R19)"
# none of the original lines may be removed.
while IFS= read -r ln; do
  [ -z "$ln" ] && continue
  grep -qF "$ln" "$PRE/.harness/harness.config.yaml" || fail "migration removed line: $ln (R19)"
done < "$T/pre.before"
pass "migration preserves existing values/comments byte-for-byte (R19) [migrate_preserves_values]"

# R20: a complete config is left identical — run migration twice, assert no change.
cp "$PRE/.harness/harness.config.yaml" "$T/pre.after1"
sh "$INSTALL" "$PRE" >/dev/null 2>&1 || fail "second pre-F01 upgrade failed (R20)"
cmp -s "$PRE/.harness/harness.config.yaml" "$T/pre.after1" \
  || { echo "--- diff ---"; diff "$T/pre.after1" "$PRE/.harness/harness.config.yaml" || true; \
       fail "migration not idempotent on a complete config (R20)"; }
pass "migration is a no-op on a complete config, idempotent (R20) [migrate_idempotent]"

# ── P2 (Codex #7): manifest header added when a comments-only manifest pre-exists ─
# A pre-existing manifest with no top-level `repos:` (empty/comments-only) must still
# end up with the header, else init.sh cannot read the appended child entries.
HU="$T/umb-hdr"; mkdir -p "$HU/repo-a/.git"
printf '# pre-existing manifest, comments only\n' > "$HU/umbrella.manifest.yaml"
sh "$INSTALL" --umbrella "$HU" >/dev/null 2>&1 || fail "umbrella install over comments-only manifest failed (Codex #7)"
grep -Eq '^repos:[[:space:]]*$' "$HU/umbrella.manifest.yaml" \
  || { echo "--- manifest ---"; cat "$HU/umbrella.manifest.yaml"; fail "repos: header not added to a comments-only manifest (Codex #7)"; }
grep -Eq '^  repo-a:[[:space:]]*$' "$HU/umbrella.manifest.yaml" \
  || fail "child entry missing after header fix (Codex #7)"
# the header must precede the first child entry.
awk '/^repos:[[:space:]]*$/{h=NR} /^  repo-a:/{e=NR} END{exit !(h && e && h<e)}' "$HU/umbrella.manifest.yaml" \
  || fail "repos: header does not precede child entry (Codex #7)"
( cd "$HU" && ./.harness/init.sh >/dev/null 2>&1 ) || fail "coordinator init.sh not green after header fix (Codex #7)"
pass "comments-only manifest gets a repos: header before child entries (Codex #7) [manifest_header_when_missing]"

# ── P2 (Codex #7): umbrella mode activates for ALL blank manifest YAML forms ────
# A manually-cleared, unquoted `manifest:` value must still be pointed at the
# generated manifest (not only the double-quoted "" form).
BU="$T/umb-blank"; mkdir -p "$BU/.harness" "$BU/repo-a/.git"
cat > "$BU/.harness/harness.config.yaml" <<'CFG'
tasks: local
verification:
  test_command: ""
umbrella:
  manifest:
CFG
sh "$INSTALL" --umbrella "$BU" >/dev/null 2>&1 || fail "umbrella install over unquoted-blank manifest failed (Codex #7)"
grep -Eq '^[[:space:]]*manifest:[[:space:]]*"\.\./umbrella\.manifest\.yaml"' "$BU/.harness/harness.config.yaml" \
  || { echo "--- coord cfg ---"; grep -n manifest "$BU/.harness/harness.config.yaml"; fail "unquoted-blank manifest not activated (Codex #7)"; }
( cd "$BU" && ./.harness/init.sh >/dev/null 2>&1 ) || fail "coordinator init.sh not green after blank-form activation (Codex #7)"
pass "umbrella mode activates for unquoted/blank manifest values (Codex #7) [manifest_blank_forms_activate]"

# ── P1 (Codex #7 r2): migration-added manifest (blank + trailing comment) activates ─
# A pre-F01 coordinator (no umbrella block) upgraded via --umbrella: migrate_config
# adds `manifest: ""   # comment`, and the activation must rewrite it despite the
# trailing comment — otherwise the upgraded coordinator stays inert.
PU="$T/umb-pref01"; mkdir -p "$PU/.harness" "$PU/repo-a/.git"
printf 'tasks: local\nverification:\n  test_command: "x"\n' > "$PU/.harness/harness.config.yaml"
sh "$INSTALL" --umbrella "$PU" >/dev/null 2>&1 || fail "pre-F01 coordinator upgrade failed (Codex #7 r2)"
grep -Eq '^[[:space:]]*manifest:[[:space:]]*"\.\./umbrella\.manifest\.yaml"' "$PU/.harness/harness.config.yaml" \
  || { echo "--- cfg ---"; grep -nE 'umbrella:|manifest:' "$PU/.harness/harness.config.yaml"; fail "migration-added blank+comment manifest not activated — coordinator inert (Codex #7 r2)"; }
( cd "$PU" && ./.harness/init.sh >/dev/null 2>&1 ) || fail "upgraded coordinator init.sh not green (Codex #7 r2)"
pass "migration-added manifest (blank + comment) is activated on upgrade (Codex #7 r2) [migrate_added_manifest_activates]"

# ── P2 (Codex #7 r2): a commented section header must not be duplicated ─────────
# `verification: # comment` must be recognized so migration inserts the key under it
# rather than appending a second `verification:` mapping.
CU="$T/cmt-hdr"; mkdir -p "$CU/.harness"
printf 'tasks: local\nverification: # local commands\n  test_command: "y"\n' > "$CU/.harness/harness.config.yaml"
sh "$INSTALL" "$CU" >/dev/null 2>&1 || fail "single-target upgrade over commented header failed (Codex #7 r2)"
vc=$(grep -c '^verification:' "$CU/.harness/harness.config.yaml")
[ "$vc" = "1" ] || { echo "--- cfg ---"; cat "$CU/.harness/harness.config.yaml"; fail "commented 'verification:' header duplicated ($vc found) (Codex #7 r2)"; }
grep -Eq '^[[:space:]]*integration_command:' "$CU/.harness/harness.config.yaml" \
  || fail "integration_command not inserted under commented header (Codex #7 r2)"
grep -qF 'verification: # local commands' "$CU/.harness/harness.config.yaml" \
  || fail "commented header altered (Codex #7 r2)"
pass "commented section header recognized, not duplicated on migration (Codex #7 r2) [migrate_commented_header_no_dup]"

# ── P1 (Codex #7 r2): the harness source itself is skipped as an umbrella child ──
# If $SRC is an immediate child of the umbrella, it must NOT be installed into.
SU="$T/umb-src"; mkdir -p "$SU/repo-a/.git"
ln -s "$SRC" "$SU/harness-sdd" 2>/dev/null || true
if [ -L "$SU/harness-sdd" ]; then
  OUT="$T/src.out"
  sh "$INSTALL" --umbrella "$SU" >"$OUT" 2>&1 || fail "umbrella install with source-as-child failed (Codex #7 r2)"
  grep -qiE "harness source|not installing into the harness" "$OUT" \
    || { echo "--- out ---"; cat "$OUT"; fail "harness source not reported as skipped (Codex #7 r2)"; }
  grep -Eq '^  harness-sdd:[[:space:]]*$' "$SU/umbrella.manifest.yaml" 2>/dev/null \
    && fail "harness source wrongly added to manifest (Codex #7 r2)"
  pass "harness source skipped when it is an umbrella child (Codex #7 r2) [skip_harness_source_child]"
else
  pass "harness-source-child skip (symlink unsupported here — skipped) [skip_harness_source_child]"
fi

# ── Codex #7 r4 (simplified): manifest is ALWAYS the umbrella root; custom path warns ─
# Locked design: the auto-populated manifest lives at <umbrella>/umbrella.manifest.yaml.
# A coordinator with a CUSTOM non-root manifest path must NOT cause children to be
# written under a non-root file (their `path:` is relative to the manifest dir and
# would mis-resolve). The cascade warns and populates the root manifest instead.
XU="$T/umb-custom"; mkdir -p "$XU/.harness" "$XU/repo-a/.git"
cat > "$XU/.harness/harness.config.yaml" <<'CFG'
tasks: local
verification:
  integration_command: ""
umbrella:
  manifest: "../custom/coord-manifest.yaml"
CFG
XOUT="$T/custom.out"
sh "$INSTALL" --umbrella "$XU" >"$XOUT" 2>&1 || fail "umbrella install with custom manifest path failed (Codex #7 r4)"
grep -qiE "custom path|only auto-populates the root" "$XOUT" \
  || { echo "--- out ---"; cat "$XOUT"; fail "custom manifest path did not warn (Codex #7 r4)"; }
grep -Eq '^  repo-a:[[:space:]]*$' "$XU/umbrella.manifest.yaml" \
  || { echo "--- root manifest ---"; cat "$XU/umbrella.manifest.yaml" 2>/dev/null; fail "discovered repo not written to the ROOT manifest (Codex #7 r4)"; }
[ -e "$XU/custom/coord-manifest.yaml" ] && fail "cascade wrote to the unsupported custom manifest path (Codex #7 r4)"
# the configured custom value is left as the user set it (not auto-rewritten).
grep -qF 'manifest: "../custom/coord-manifest.yaml"' "$XU/.harness/harness.config.yaml" \
  || fail "custom umbrella.manifest value was overwritten (Codex #7 r4)"
pass "custom manifest path warns; root manifest is populated (Codex #7 r4) [custom_manifest_warns_root_used]"

# ── P2 (Codex #7 r4): new entries are inserted INSIDE repos:, not after a later section ─
# A pre-existing manifest with a trailing top-level section (e.g. metadata:) must
# receive the new repo UNDER repos:, before that section — else init.sh stops scanning.
MU="$T/umb-sections"; mkdir -p "$MU/.harness" "$MU/repo-b/.git"
printf 'tasks: local\n' > "$MU/.harness/harness.config.yaml"
cat > "$MU/umbrella.manifest.yaml" <<'MAN'
repos:
  repo-a:
    path: ./repo-a
metadata:
  note: keep me last
MAN
sh "$INSTALL" --umbrella "$MU" >/dev/null 2>&1 || fail "umbrella install over sectioned manifest failed (Codex #7 r4)"
# repo-b must appear AFTER repos: and BEFORE metadata: (i.e. inside the repos mapping).
awk '/^repos:/{r=NR} /^  repo-b:/{b=NR} /^metadata:/{m=NR} END{exit !(r && b && m && r<b && b<m)}' "$MU/umbrella.manifest.yaml" \
  || { echo "--- manifest ---"; cat "$MU/umbrella.manifest.yaml"; fail "repo-b not inserted inside repos: before the metadata section (Codex #7 r4)"; }
# metadata section preserved intact.
grep -qF 'note: keep me last' "$MU/umbrella.manifest.yaml" || fail "trailing section was clobbered (Codex #7 r4)"
pass "new repo inserted inside repos: ahead of later sections (Codex #7 r4) [manifest_insert_within_repos]"

# ── P2 (Codex #7 r5): existing-entry check is scoped to the repos: mapping ──────
# A same-named two-space key in an UNRELATED section must not be mistaken for the
# repo entry — the discovered child must still be added under repos:.
EU="$T/umb-dupkey"; mkdir -p "$EU/.harness" "$EU/repo-a/.git"
printf 'tasks: local\n' > "$EU/.harness/harness.config.yaml"
cat > "$EU/umbrella.manifest.yaml" <<'MAN'
repos:
metadata:
  repo-a: not-a-real-repo-entry
MAN
sh "$INSTALL" --umbrella "$EU" >/dev/null 2>&1 || fail "install over decoy-key manifest failed (Codex #7 r5)"
awk '/^repos:/{r=NR} /^  repo-a:[[:space:]]*$/{e=NR} /^metadata:/{m=NR} END{exit !(r && e && m && r<e && e<m)}' "$EU/umbrella.manifest.yaml" \
  || { echo "--- manifest ---"; cat "$EU/umbrella.manifest.yaml"; fail "repo-a not added under repos: despite a decoy metadata.repo-a key (Codex #7 r5)"; }
pass "existing-entry check scoped to repos:, decoy key ignored (Codex #7 r5) [entry_check_scoped_to_repos]"

# ── P2 (Codex #7 r5): migrate_config manifest lookup scoped to umbrella: section ─
# A nested `metadata: manifest: ...` must NOT suppress adding the umbrella.manifest default.
GU="$T/umb-nested"; mkdir -p "$GU/.harness" "$GU/repo-a/.git"
cat > "$GU/.harness/harness.config.yaml" <<'CFG'
tasks: local
metadata:
  manifest: artifacts.json
CFG
sh "$INSTALL" --umbrella "$GU" >/dev/null 2>&1 || fail "install over nested-manifest config failed (Codex #7 r5)"
# the umbrella block + manifest must have been added and activated to the root manifest.
awk '/^umbrella:[[:space:]]*(#.*)?$/{u=1;next} u&&/^[^[:space:]#]/{u=0} u&&/^[[:space:]]+manifest:[[:space:]]*"\.\.\/umbrella\.manifest\.yaml"/{ok=1} END{exit ok?0:1}' "$GU/.harness/harness.config.yaml" \
  || { echo "--- cfg ---"; cat "$GU/.harness/harness.config.yaml"; fail "umbrella.manifest not added/activated despite an unrelated nested manifest: (Codex #7 r5)"; }
grep -qF 'manifest: artifacts.json' "$GU/.harness/harness.config.yaml" \
  || fail "unrelated nested manifest value was disturbed (Codex #7 r5)"
( cd "$GU" && ./.harness/init.sh >/dev/null 2>&1 ) || fail "coordinator init.sh not green (Codex #7 r5)"
pass "migrate scopes manifest lookup to umbrella: section (Codex #7 r5) [migrate_manifest_scoped_to_umbrella]"

# ── P2 (Codex #7 r5): a symlinked umbrella resolving to the source is rejected ──
SLU="$T/umb-srclink"
ln -s "$SRC" "$SLU" 2>/dev/null || true
if [ -L "$SLU" ]; then
  sh "$INSTALL" --umbrella "$SLU" >/dev/null 2>&1 && fail "symlinked umbrella -> source was NOT rejected (Codex #7 r5)"
  pass "symlinked umbrella that resolves to the source is rejected (Codex #7 r5) [umbrella_symlink_to_source_rejected]"
else
  pass "umbrella-symlink-to-source guard (symlink unsupported here — skipped) [umbrella_symlink_to_source_rejected]"
fi

echo "All cascade tests passed."
