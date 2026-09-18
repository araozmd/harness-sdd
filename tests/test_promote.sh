#!/bin/sh
# test_promote.sh — test contract for E28-F03 (installer promotion to an umbrella
# coordinator). Zero-dependency POSIX sh, matching tests/test_cascade.sh's house style
# (self-cleaning mktemp tree, fail/pass helpers, env sandbox). Covers R1 (docs+static),
# R2-R9 and R11 from E28-F03.tests.md; the single-target/wiring assertions (R1, R10)
# live in tests/test_install.sh.
#
# Conventions inherited from the sibling suites and from progress/lessons.md:
#   * Positive control before every negative and every ordering claim.
#   * Any extracted span is bounded STRUCTURALLY, asserted non-empty, and given a
#     line-count floor — never bounded on the line that happens to be last today.
#   * No VERSION literal: the bump sync is owned by tests/test_codex_native.sh.
#   * Byte-identity / nothing-written claims assert a floor first, never a bare cmp on a
#     possibly-empty extract.
#   * The suite writes only inside $T; it never touches state/, specs/, progress/ or the
#     developer's home.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL="$SRC/harness-install.sh"
INSTALL_DOC="$SRC/docs/INSTALL.md"
UMBRELLA_DOC="$SRC/docs/UMBRELLA.md"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-promote)"
trap 'rm -rf "$T"' EXIT
export CODEX_HOME="$T/codex-home"
export HARNESS_AGENTS="claude"
export HARNESS_PR_LOOP_ENABLED=false

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

[ -f "$INSTALL" ] || fail "harness-install.sh not found at $INSTALL"
[ -f "$INSTALL_DOC" ] || fail "docs/INSTALL.md not found at $INSTALL_DOC"
[ -f "$UMBRELLA_DOC" ] || fail "docs/UMBRELLA.md not found at $UMBRELLA_DOC"

# git is required by every promotion case (create + git init + the landing audit). Its
# absence is a NAMED suite-level skip, never a silent pass.
if ! command -v git >/dev/null 2>&1; then
  pass "git is unavailable — promotion test suite skipped (git is required) [git_required_skip]"
  echo "All promote tests skipped (git unavailable)."
  exit 0
fi

# ── helpers ────────────────────────────────────────────────────────────────────

# snapshot <target> <dest> — copy the .harness tree and the root listing for a strict
# "wrote nothing" comparison. cp -R (content) + ls -A (the root gained nothing).
snapshot() {
  rm -rf "$2"; mkdir -p "$2"
  cp -R "$1/.harness" "$2/.harness" 2>/dev/null || true
  ls -A "$1" > "$2/root.list"
}
unchanged() { # <target> <snap>
  diff -r "$2/.harness" "$1/.harness" >/dev/null 2>&1 || return 1
  ls -A "$1" > "$2/root.now" 2>/dev/null || true
  cmp -s "$2/root.list" "$2/root.now" || return 1
  return 0
}

# build_single <dir> — a fresh single-target install committed to a local git work tree,
# so the landing audit has a work tree to verify. The commit uses an explicit identity so
# it never depends on the box's global git config.
build_single() {
  _bs_dir="$1"
  mkdir -p "$_bs_dir"
  sh "$INSTALL" "$_bs_dir" >/dev/null 2>&1 || fail "build_single: single install failed at $_bs_dir"
  ( cd "$_bs_dir" && git init -q && git add -A && \
    git -c user.name=test -c user.email=test@example.com commit -q -m initial ) >/dev/null 2>&1 \
    || fail "build_single: cannot create the fixture git repo at $_bs_dir"
}

# build_single_nogit <dir> — a single install whose ROOT is not a git work tree (the R9
# non-git-target case). The installer never requires git, so this stays a valid install.
build_single_nogit() {
  _bn_dir="$1"
  mkdir -p "$_bn_dir"
  sh "$INSTALL" "$_bn_dir" >/dev/null 2>&1 || fail "build_single_nogit: single install failed at $_bn_dir"
}

# write_draft <file> — the bounded Planner draft shape: three deployables, `path: ../<key>`.
#   alpha  — sentinel-appending scaffold (proves it ran; the append counter proves it
#            never re-runs)
#   beta   — empty scaffold_cmd
#   gamma  — failing scaffold_cmd (best-effort warning, run continues)
write_draft() {
  cat > "$1" <<'YAML'
# umbrella.manifest.draft.yaml — DRAFT, written by /sdd-plan.
# This file is inert: it is not a switch, and only E28-F03's promotion acts on it.
repos:
  alpha:
    path: ../alpha
    init: ./init.sh
    test_command: "npm test"
    delegate_cmd: ""
    scaffold_cmd: "echo x >> scaffold-count"
  beta:
    path: ../beta
    init: ./init.sh
    test_command: "pytest"
    delegate_cmd: ""
    scaffold_cmd: ""
  gamma:
    path: ../gamma
    init: ./init.sh
    test_command: "make test"
    delegate_cmd: ""
    scaffold_cmd: "exit 7"
YAML
}

# promote <umbrella> <draft> <outfile> <errfile> — run promotion; echoes the exit code.
# Accepts 0 and 3 only where a case says so; callers assert the exact contract.
promote() {
  _pr_rc=0
  sh "$INSTALL" --umbrella "$1" --from-manifest "$2" >"$3" 2>"$4" || _pr_rc=$?
  printf '%s\n' "$_pr_rc"
}

# doc_sentence_with <span> <needle> — the ONE sentence of the folded span that names
# <needle>, split on ". " (never a bare period, so dotted tokens stay whole). Empty when
# no sentence names the needle (a stale/moved anchor, which callers must treat as failure).
doc_sentence_with() {
  printf '%s' "$1" | tr '\n' ' ' | awk '
    { s=$0; gsub(/\. /, "\n"); print s }' | awk -v n="$2" '
    index(tolower($0), tolower(n)) { print; exit }'
}

# require_tokens <label> <span> <token>...
require_tokens() {
  _rt_label="$1"; _rt_span="$2"; shift 2
  for _rt_t in "$@"; do
    printf '%s' "$_rt_span" | grep -qiF -e "$_rt_t" \
      || fail "$_rt_label: extracted span does not carry '$_rt_t'"
  done
}

# require_sentence_pair <label> <span> <needle> <a> <b> — the sentence naming <needle>
# must carry BOTH <a> and <b>. An empty sentence (needle dropped/moved) is a red, and the
# needle's own presence is positively controlled by the sentence lookup.
require_sentence_pair() {
  _rsp_label="$1"; _rsp_span="$2"; _rsp_needle="$3"; _rsp_a="$4"; _rsp_b="$5"
  _rsp_sent="$(doc_sentence_with "$_rsp_span" "$_rsp_needle")"
  [ -n "$_rsp_sent" ] \
    || fail "$_rsp_label: no sentence naming '$_rsp_needle' found — the statement was dropped or moved out of the section"
  printf '%s' "$_rsp_sent" | grep -qiF "$_rsp_a" \
    || fail "$_rsp_label: the sentence naming '$_rsp_needle' does not carry '$_rsp_a'"
  printf '%s' "$_rsp_sent" | grep -qiF "$_rsp_b" \
    || fail "$_rsp_label: the sentence naming '$_rsp_needle' does not carry '$_rsp_b'"
}

# ── R1: the invocation is documented on all three surfaces ─────────────────────
test_promotion_docs_contract() {
  # (1) usage header: the comment block at the top of harness-install.sh (structural: from
  # line 2 to the first non-comment line), with a line-count floor.
  _hdr="$(awk 'NR==1{next} /^#/{print;next} {exit}' "$INSTALL")"
  [ "$(printf '%s\n' "$_hdr" | grep -c '' || true)" -ge 40 ] \
    || fail "R1 docs: usage-header extraction is empty/stale (got $(printf '%s\n' "$_hdr" | grep -c '' || true) lines) — the anchor checks would be vacuous"
  require_tokens "R1 usage header" "$_hdr" "--from-manifest <file>" "umbrella mode" "--from-manifest"

  # (2) docs/UMBRELLA.md promotion section, bounded `^## ` → next `^## `.
  _umb="$(awk '/^## Promoting a single install to a coordinator/{k=1;next} k && /^## /{exit} k' "$UMBRELLA_DOC")"
  [ "$(printf '%s\n' "$_umb" | grep -c '' || true)" -ge 15 ] \
    || fail "R1 docs: docs/UMBRELLA.md promotion section extraction is empty/stale — the anchor checks would be vacuous"
  require_tokens "R1 UMBRELLA.md" "$_umb" \
    "--from-manifest <file>" "umbrella.manifest.draft.yaml" "single install" \
    "scaffold_cmd" "--shared-repo" "--dry-run"
  require_sentence_pair "R1 re-base"  "$_umb" "re-base"  "path" "umbrella root"
  require_sentence_pair "R1 local-git" "$_umb" "local git" "remote" "owes"
  require_sentence_pair "R1 fail-closed" "$_umb" "fails closed" "repos:" "fails closed"
  require_sentence_pair "R1 key-align" "$_umb" "promotion requires" "directory" "promotion requires"
  require_sentence_pair "R1 remedy"   "$_umb" "remedy"   "rename" "/sdd-plan"
  require_sentence_pair "R1 scaffold-opaque" "$_umb" "scaffold_cmd" "opaque" "only promotion"
  require_sentence_pair "R1 landing-audit" "$_umb" "landing audit" "3" "landing audit"

  # (3) docs/INSTALL.md `## Umbrella mode` span (structurally bounded).
  _inst="$(awk '/^## Umbrella mode/{k=1;next} k && /^## /{exit} k' "$INSTALL_DOC")"
  [ "$(printf '%s\n' "$_inst" | grep -c '' || true)" -ge 20 ] \
    || fail "R1 docs: docs/INSTALL.md umbrella-mode span extraction is empty/stale — the anchor checks would be vacuous"
  require_tokens "R1 INSTALL.md" "$_inst" "--from-manifest <file>" "umbrella.manifest.draft.yaml" "UMBRELLA.md"

  pass "promotion invocation documented on usage header + both docs surfaces (R1) [test_promotion_docs_contract]"
}
test_promotion_docs_contract

# ── R2: a missing/invalid/empty-repos manifest aborts, writing nothing ─────────
test_manifest_gates_fail_closed() {
  for _case in absent norepos zero; do
    _u="$T/r2-$_case"; _d="$_u/.harness/umbrella.manifest.draft.yaml"
    build_single "$_u"
    case "$_case" in
      absent)  rm -f "$_d" ;;
      norepos) printf '# comments only — no repos mapping\n' > "$_d" ;;
      zero)    printf 'repos:\n' > "$_d" ;;
    esac
    snapshot "$_u" "$T/r2-$_case-snap"
    _out="$T/r2-$_case.out"; _err="$T/r2-$_case.err"
    _rc="$(promote "$_u" "$_d" "$_out" "$_err")"
    [ "$_rc" != "0" ] \
      || fail "R2 ($_case): promotion accepted an invalid draft (rc=$_rc); the gate is open"
    grep -qF "$_d" "$_out" "$_err" \
      || fail "R2 ($_case): the refusal does not name the manifest path '$_d' — the operator cannot tell which file was refused"
    unchanged "$_u" "$T/r2-$_case-snap" \
      || fail "R2 ($_case): a refused promotion wrote into the target (a gate must fire before any write)"
  done
  # Positive control: the valid draft on the SAME fixture shape runs and creates children,
  # so "refused" is not satisfied by every run failing.
  _u="$T/r2-valid"; _d="$_u/.harness/umbrella.manifest.draft.yaml"
  build_single "$_u"; write_draft "$_d"
  _rc="$(promote "$_u" "$_d" "$T/r2-valid.out" "$T/r2-valid.err")"
  case "$_rc" in 0|3) : ;; *) fail "R2 positive control: a valid draft failed (rc=$_rc) — the gate tests prove nothing" ;; esac
  [ -d "$_u/alpha/.harness" ] \
    || fail "R2 positive control: the valid draft did not create/install a child — the gate tests prove nothing"
  pass "missing/no-repos/zero-entry manifests abort non-zero writing nothing, valid draft proceeds (R2) [test_manifest_gates_fail_closed]"
}
test_manifest_gates_fail_closed

# ── R3: paths are re-based from the draft dir to the umbrella root ─────────────
test_paths_rebased_to_umbrella_root() {
  _u="$T/r3"; _d="$_u/.harness/umbrella.manifest.draft.yaml"
  build_single "$_u"; write_draft "$_d"
  _rc="$(promote "$_u" "$_d" "$T/r3.out" "$T/r3.err")"
  case "$_rc" in 0|3) : ;; *) fail "R3: valid promotion failed (rc=$_rc)" ;; esac
  _m="$_u/umbrella.manifest.yaml"
  [ -f "$_m" ] || fail "R3: live manifest was not seeded"
  [ "$(grep -c '' "$_m" || true)" -ge 10 ] \
    || fail "R3: live manifest is empty/too small — the value checks would be vacuous"
  grep -Eq '^repos:[[:space:]]*$' "$_m" || fail "R3: live manifest has no top-level repos:"
  for _k in alpha beta gamma; do
    grep -Eq "^  $_k:[[:space:]]*$" "$_m" || fail "R3: live manifest missing entry '$_k'"
    grep -qF "    path: ./$_k" "$_m" || fail "R3: live entry '$_k' not re-based to ./$_k"
    if grep -qF "path: ../$_k" "$_m"; then
      fail "R3: live manifest carries the draft's ../$_k base (the F02 Q1 regression)"
    fi
  done
  # the draft's REAL fields, not manifest_upsert's TODO placeholders.
  grep -qF 'test_command: "npm test"' "$_m" || fail "R3: live entry did not carry the draft's test_command"
  grep -qF 'test_command: "pytest"' "$_m" || fail "R3: live entry did not carry the draft's test_command (beta)"
  grep -qF 'scaffold_cmd: "echo x >> scaffold-count"' "$_m" || fail "R3: live entry did not carry the draft's scaffold_cmd"
  if grep -qF 'TODO' "$_m"; then
    fail "R3: live manifest carries manifest_upsert's TODO placeholders instead of the draft's fields"
  fi
  # ordering: repos: physically precedes the first entry key (both anchors present first).
  grep -Eq '^repos:[[:space:]]*$' "$_m" || fail "R3 ordering: repos: header absent"
  grep -Eq '^  [a-z0-9-]+:[[:space:]]*$' "$_m" || fail "R3 ordering: no entry keys present"
  awk '/^repos:[[:space:]]*$/{h=NR} /^  [a-z0-9-]+:[[:space:]]*$/{if(!e)e=NR} END{exit !(h && e && h<e)}' "$_m" \
    || fail "R3 ordering: repos: does not precede the first entry key"
  pass "draft paths re-base to ./<key> at the umbrella root, fields carried over (R3) [test_paths_rebased_to_umbrella_root]"
}
test_paths_rebased_to_umbrella_root

# ── R4: unsafe/existing child paths abort, writing nothing ─────────────────────
test_path_gates_fail_closed() {
  _mk() { # <case> <draft-body-with-\n-escapes>
    _g_u="$T/r4-$1"; _g_d="$_g_u/.harness/umbrella.manifest.draft.yaml"
    build_single "$_g_u"
    { printf 'repos:\n'; printf '%b' "$2"; } > "$_g_d"
    snapshot "$_g_u" "$T/r4-$1-snap"
    _g_rc="$(promote "$_g_u" "$_g_d" "$T/r4-$1.out" "$T/r4-$1.err")"
    [ "$_g_rc" != "0" ] || fail "R4 ($1): promotion accepted an unsafe path (rc=$_g_rc)"
    unchanged "$_g_u" "$T/r4-$1-snap" \
      || fail "R4 ($1): a refused promotion wrote into the target"
  }
  _mk escape "  evil:\n    path: ../../evil\n"
  grep -qF '../../evil' "$T/r4-escape.out" "$T/r4-escape.err" || fail "R4 (escape): refusal does not name ../../evil"
  [ ! -e "$T/r4-escape/evil" ] || fail "R4 (escape): the escaping child was created"

  _mk nondirect "  alpha:\n    path: ../sub/alpha\n"
  grep -qF '../sub/alpha' "$T/r4-nondirect.out" "$T/r4-nondirect.err" || fail "R4 (nondirect): refusal does not name ../sub/alpha"
  [ ! -e "$T/r4-nondirect/sub" ] || fail "R4 (nondirect): a non-direct child directory was created"

  _mk mismatch "  api-v2:\n    path: ../api.v2\n"
  grep -qF '../api.v2' "$T/r4-mismatch.out" "$T/r4-mismatch.err" || fail "R4 (mismatch): refusal does not name ../api.v2"
  [ ! -e "$T/r4-mismatch/api.v2" ] || fail "R4 (mismatch): a basename!=key directory was created"
  grep -qF 'rename' "$T/r4-mismatch.out" "$T/r4-mismatch.err" || fail "R4 (mismatch): refusal omits the 'rename' remedy"
  grep -qF '/sdd-plan' "$T/r4-mismatch.out" "$T/r4-mismatch.err" || fail "R4 (mismatch): refusal omits the '/sdd-plan' remedy"

  _mk nopath "  alpha:\n    init: ./init.sh\n"
  [ ! -e "$T/r4-nopath/alpha" ] || fail "R4 (nopath): a pathless entry created a child"

  # existing child, not a git work tree
  _ng="$T/r4-nongit"; _ngd="$_ng/.harness/umbrella.manifest.draft.yaml"
  build_single "$_ng"
  { printf 'repos:\n'; printf '%b' "  alpha:\n    path: ../alpha\n"; } > "$_ngd"
  mkdir -p "$_ng/alpha"
  _ng_rc="$(promote "$_ng" "$_ngd" "$T/r4-nongit.out" "$T/r4-nongit.err")"
  [ "$_ng_rc" != "0" ] || fail "R4 (nongit): an existing non-git child was accepted"
  grep -qF "$_ng/alpha" "$T/r4-nongit.out" "$T/r4-nongit.err" || fail "R4 (nongit): refusal does not name the child path"
  grep -qF 'rename' "$T/r4-nongit.out" "$T/r4-nongit.err" || fail "R4 (nongit): refusal omits the 'rename' remedy"
  grep -qF '/sdd-plan' "$T/r4-nongit.out" "$T/r4-nongit.err" || fail "R4 (nongit): refusal omits the '/sdd-plan' remedy"

  # existing regular file in the child's place
  _rf="$T/r4-regfile"; _rfd="$_rf/.harness/umbrella.manifest.draft.yaml"
  build_single "$_rf"
  { printf 'repos:\n'; printf '%b' "  alpha:\n    path: ../alpha\n"; } > "$_rfd"
  : > "$_rf/alpha"
  _rf_rc="$(promote "$_rf" "$_rfd" "$T/r4-regfile.out" "$T/r4-regfile.err")"
  [ "$_rf_rc" != "0" ] || fail "R4 (regfile): an existing regular file was accepted"
  grep -qF "$_rf/alpha" "$T/r4-regfile.out" "$T/r4-regfile.err" || fail "R4 (regfile): refusal does not name the offending path"
  grep -qF 'rename' "$T/r4-regfile.out" "$T/r4-regfile.err" || fail "R4 (regfile): refusal omits the 'rename' remedy"
  grep -qF '/sdd-plan' "$T/r4-regfile.out" "$T/r4-regfile.err" || fail "R4 (regfile): refusal omits the '/sdd-plan' remedy"

  # Positive control: the aligned ../<key> shape on a SEPARATE fixture IS accepted and the
  # child appears — the refusals above are not satisfied by every run failing.
  _u="$T/r4-valid"; _d="$_u/.harness/umbrella.manifest.draft.yaml"
  build_single "$_u"
  printf 'repos:\n  solo:\n    path: ../solo\n    init: ./init.sh\n    test_command: ""\n    delegate_cmd: ""\n' > "$_d"
  _rc="$(promote "$_u" "$_d" "$T/r4-valid.out" "$T/r4-valid.err")"
  case "$_rc" in 0|3) : ;; *) fail "R4 positive control: aligned ../<key> shape was refused (rc=$_rc)" ;; esac
  [ -e "$_u/solo/.git" ] || fail "R4 positive control: the aligned child was not created as a git repo"
  pass "escaping/non-direct/mismatched/pathless/non-git/regular-file paths abort writing nothing, remedy named; aligned shape accepted (R4) [test_path_gates_fail_closed]"
}
test_path_gates_fail_closed

# ── R5: missing children created + git-inited + installed + recorded ───────────
test_missing_children_created_and_recorded() {
  _u="$T/r5"; _d="$_u/.harness/umbrella.manifest.draft.yaml"
  build_single "$_u"; write_draft "$_d"
  _rc="$(promote "$_u" "$_d" "$T/r5.out" "$T/r5.err")"
  case "$_rc" in 0|3) : ;; *) fail "R5: promotion failed (rc=$_rc)" ;; esac
  _m="$_u/umbrella.manifest.yaml"
  [ "$(grep -cE '^  [a-z0-9-]+:[[:space:]]*$' "$_m" || true)" -ge 3 ] \
    || fail "R5: live manifest has fewer than 3 entries — the per-entry checks would be vacuous"
  for _k in alpha beta gamma; do
    [ -d "$_u/$_k" ] || fail "R5: child '$_k' directory missing"
    [ -e "$_u/$_k/.git" ] || fail "R5: child '$_k' is not a local git repo (.git missing)"
    [ -f "$_u/$_k/.harness/agents/builder.md" ] || fail "R5: child '$_k' did not receive the cascade install"
    grep -Eq "^  $_k:[[:space:]]*$" "$_m" || fail "R5: live manifest missing '$_k'"
    grep -qF "    path: ./$_k" "$_m" || fail "R5: live manifest missing path ./$_k"
  done
  # Positive control: the child install genuinely happened (not just empty dirs).
  [ "$(cat "$_u/alpha/.harness/.harness-version")" = "$(cat "$SRC/VERSION")" ] \
    || fail "R5 positive control: alpha's install version does not match the source — the dirs are not a real install"

  # Non-clobber: a pre-existing key under repos: is preserved verbatim, exactly once.
  _u2="$T/r5-pre"; _d2="$_u2/.harness/umbrella.manifest.draft.yaml"
  build_single "$_u2"; write_draft "$_d2"
  cat > "$_u2/umbrella.manifest.yaml" <<'MAN'
repos:
  alpha:
    path: ./alpha
    init: ./init.sh
    test_command: "keep me"
    delegate_cmd: ""
MAN
  _rc="$(promote "$_u2" "$_d2" "$T/r5-pre.out" "$T/r5-pre.err")"
  case "$_rc" in 0|3) : ;; *) fail "R5 non-clobber: promotion failed (rc=$_rc)" ;; esac
  grep -qF 'test_command: "keep me"' "$_u2/umbrella.manifest.yaml" \
    || fail "R5 non-clobber: a pre-existing entry field was overwritten (promote-before-cascade order violated)"
  [ "$(grep -cE '^  alpha:[[:space:]]*$' "$_u2/umbrella.manifest.yaml")" = "1" ] \
    || fail "R5 non-clobber: the pre-existing 'alpha' key was duplicated"
  grep -Eq '^  beta:[[:space:]]*$' "$_u2/umbrella.manifest.yaml" \
    || fail "R5 non-clobber: an absent key was not inserted alongside the preserved one"
  pass "missing children created + git-inited + installed + recorded; pre-existing entry preserved (R5) [test_missing_children_created_and_recorded]"
}
test_missing_children_created_and_recorded

# ── R6: scaffold_cmd best-effort, only for created children, stderr-only warning ─
test_scaffold_cmd_best_effort() {
  _u="$T/r6"; _d="$_u/.harness/umbrella.manifest.draft.yaml"
  build_single "$_u"; write_draft "$_d"
  _rc="$(promote "$_u" "$_d" "$T/r6.out" "$T/r6.err")"
  case "$_rc" in 0|3) : ;; *) fail "R6: promotion failed (rc=$_rc)" ;; esac
  [ -s "$_u/alpha/scaffold-count" ] \
    || fail "R6: alpha's scaffold_cmd did not run (no sentinel inside the child)"
  [ -f "$_u/gamma/.harness/agents/builder.md" ] \
    || fail "R6: gamma did not receive a valid harness install after its scaffold_cmd failed"
  # the warning is on STDERR ONLY, names the child and the exit status, and carries the
  # command text (positive control on the span, not just the text).
  [ -s "$T/r6.err" ] || fail "R6: stderr is empty — the warning assertion would be vacuous"
  grep -qE 'scaffold_cmd failed.*gamma.*7' "$T/r6.err" \
    || fail "R6: stderr lacks a single line naming 'scaffold_cmd failed', the child 'gamma' and exit 7"
  grep -qF 'exit 7' "$T/r6.err" \
    || fail "R6 positive control: the warning does not carry the opaque command text"
  if grep -qF 'scaffold_cmd failed' "$T/r6.out"; then
    fail "R6: the scaffold warning leaked onto stdout — the stream contract is stderr-only"
  fi
  pass "scaffold_cmd runs only for created children, best-effort, warning names child+command on stderr (R6) [test_scaffold_cmd_best_effort]"
}
test_scaffold_cmd_best_effort

# ── R7: idempotent re-run + byte-identical to a plain cascade child ────────────
test_rerun_idempotent_and_matches_plain_cascade() {
  _u="$T/r7"; _d="$_u/.harness/umbrella.manifest.draft.yaml"
  build_single "$_u"; write_draft "$_d"
  _rc="$(promote "$_u" "$_d" "$T/r7.out" "$T/r7.err")"
  case "$_rc" in 0|3) : ;; *) fail "R7: first promotion failed (rc=$_rc)" ;; esac
  _m="$_u/umbrella.manifest.yaml"
  cp -R "$_m" "$T/r7-manifest.before"
  cp -R "$_u/alpha/.harness" "$T/r7-alpha-harness.before"
  cp -R "$_u/beta/.harness" "$T/r7-beta-harness.before"
  _cnt_before="$(grep -c '' "$_u/alpha/scaffold-count" || true)"
  # re-run on the UNCOMMITTED tree (R9: no dirty-tree refusal).
  _rc="$(promote "$_u" "$_d" "$T/r7.out2" "$T/r7.err2")"
  case "$_rc" in 0|3) : ;; *) fail "R7: idempotent re-run refused (rc=$_rc) — a dirty-tree gate was added" ;; esac
  [ "$(grep -cE '^  [a-z0-9-]+:[[:space:]]*$' "$_m" || true)" -ge 3 ] \
    || fail "R7: live manifest lost its entries on re-run"
  cmp -s "$T/r7-manifest.before" "$_m" \
    || fail "R7: re-run changed the live manifest (not idempotent)"
  diff -r "$T/r7-alpha-harness.before" "$_u/alpha/.harness" >/dev/null 2>&1 \
    || fail "R7: re-run changed alpha's installed harness"
  diff -r "$T/r7-beta-harness.before" "$_u/beta/.harness" >/dev/null 2>&1 \
    || fail "R7: re-run changed beta's installed harness"
  _cnt_after="$(grep -c '' "$_u/alpha/scaffold-count" || true)"
  [ "$_cnt_before" = "$_cnt_after" ] \
    || fail "R7: scaffold_cmd re-ran on an existing child (counter $_cnt_before -> $_cnt_after)"

  # Identical to a plain cascade: build a sibling plain umbrella with an alpha git repo,
  # run the cascade WITHOUT --from-manifest, then diff the two alpha harness trees.
  _p="$T/r7-plain"; mkdir -p "$_p/alpha"
  ( cd "$_p/alpha" && git init -q ) >/dev/null 2>&1 || fail "R7: plain fixture git init failed"
  sh "$INSTALL" --umbrella "$_p" >"$T/r7-plain.out" 2>&1 || true
  [ -f "$_p/alpha/.harness/agents/builder.md" ] \
    || fail "R7: plain cascade did not install the alpha child — the identity check would be vacuous"
  diff -r "$_p/alpha/.harness" "$_u/alpha/.harness" >/dev/null 2>&1 \
    || fail "R7: a promoted child's harness differs from the same child under a plain cascade"
  pass "re-run creates nothing / runs no scaffold / keeps byte-identity, equal to a plain cascade child (R7) [test_rerun_idempotent_and_matches_plain_cascade]"
}
test_rerun_idempotent_and_matches_plain_cascade

# ── R8: --dry-run previews everything and writes nothing ───────────────────────
test_dry_run_writes_nothing() {
  _u="$T/r8"; _d="$_u/.harness/umbrella.manifest.draft.yaml"
  build_single "$_u"; write_draft "$_d"
  snapshot "$_u" "$T/r8-snap"
  _rc=0
  sh "$INSTALL" --umbrella "$_u" --from-manifest "$_d" --dry-run >"$T/r8.out" 2>"$T/r8.err" || _rc=$?
  [ "$_rc" = "0" ] || fail "R8: --dry-run promotion exited $_rc (want 0)"
  grep -qF 'promotion preview' "$T/r8.out" || fail "R8: no 'promotion preview' header"
  for _k in alpha beta gamma; do
    grep -qF "would create child: $_k" "$T/r8.out" || fail "R8: no 'would create child: $_k' preview"
    grep -qF "would re-base path: $_k" "$T/r8.out" || fail "R8: no 'would re-base path: $_k' preview"
  done
  grep -qF 'would git init' "$T/r8.out" || fail "R8: no 'would git init' preview"
  grep -qF 'would run scaffold_cmd: alpha' "$T/r8.out" || fail "R8: no 'would run scaffold_cmd: alpha' preview"
  [ ! -e "$_u/alpha" ] || fail "R8: --dry-run created a child directory"
  [ ! -e "$_u/umbrella.manifest.yaml" ] || fail "R8: --dry-run wrote the live manifest"
  unchanged "$_u" "$T/r8-snap" || fail "R8: --dry-run modified the target's .harness tree"
  # Positive control: the same fixture WITHOUT --dry-run does write, so "writes nothing"
  # is discriminating rather than a claim every run satisfies.
  _rc="$(promote "$_u" "$_d" "$T/r8b.out" "$T/r8b.err")"
  case "$_rc" in 0|3) : ;; *) fail "R8 positive control: non-dry run failed (rc=$_rc)" ;; esac
  [ -d "$_u/alpha" ] || fail "R8 positive control: the non-dry run did not create children"
  [ -f "$_u/umbrella.manifest.yaml" ] || fail "R8 positive control: the non-dry run did not write the live manifest"
  pass "--dry-run previews create/git-init/scaffold/re-base and writes nothing; real run writes (R8) [test_dry_run_writes_nothing]"
}
test_dry_run_writes_nothing

# ── R9: the landing audit is the ONLY git-state gate ───────────────────────────
test_landing_audit_is_the_gate() {
  _u="$T/r9"; _d="$_u/.harness/umbrella.manifest.draft.yaml"
  # A git WORK TREE whose install is left uncommitted, so the audit has to report the
  # coordinator unlanded alongside the fresh children. (A committed install is
  # byte-identical after re-install and would read `landed`; harness.config.yaml is
  # project-owned and excluded from the audited path set, so a config edit would not do.)
  mkdir -p "$_u"
  sh "$INSTALL" "$_u" >/dev/null 2>&1 || fail "R9: fixture install failed"
  ( cd "$_u" && git init -q ) >/dev/null 2>&1 || fail "R9: fixture git init failed"
  write_draft "$_d"
  _rc="$(promote "$_u" "$_d" "$T/r9.out" "$T/r9.err")"
  [ "$_rc" = "3" ] \
    || fail "R9: promotion into an unlanded git-work-tree target exited $_rc (want the audit's 3)"
  grep -qF 'landing audit' "$T/r9.out" || fail "R9: no 'landing audit' section"
  grep -qE 'unlanded.*coordinator' "$T/r9.out" || fail "R9: the audit does not name the coordinator as unlanded"
  for _k in alpha beta gamma; do
    grep -qE "unlanded.*$_k" "$T/r9.out" || fail "R9: the audit does not name the fresh child '$_k' as unlanded"
  done
  # Positive control: the run actually wrote files (so "HEAD unchanged" is meaningful).
  [ -f "$_u/alpha/.harness/agents/builder.md" ] || fail "R9 positive control: alpha was not installed"
  if git -C "$_u" rev-parse HEAD >/dev/null 2>&1; then
    fail "R9: promotion created a commit in the coordinator — it must never commit"
  fi
  if git -C "$_u/alpha" rev-parse HEAD >/dev/null 2>&1; then
    fail "R9: promotion created a commit in a fresh child (HEAD resolved)"
  fi

  # Non-git target: the audit reports it as not verifiable, and does NOT count it unlanded.
  _un="$T/r9-nogit"; _dn="$_un/.harness/umbrella.manifest.draft.yaml"
  build_single_nogit "$_un"; write_draft "$_dn"
  _rc="$(promote "$_un" "$_dn" "$T/r9-nogit.out" "$T/r9-nogit.err")"
  case "$_rc" in 0|3) : ;; *) fail "R9 non-git: promotion failed unexpectedly (rc=$_rc)" ;; esac
  grep -qE 'no git.*coordinator' "$T/r9-nogit.out" \
    || fail "R9 non-git: the audit did not report the coordinator as not-a-work-tree"
  grep -qF 'cannot verify' "$T/r9-nogit.out" || fail "R9 non-git: the not-verifiable wording is absent"
  if grep -qE 'unlanded.*coordinator' "$T/r9-nogit.out"; then
    fail "R9 non-git: a non-git target was counted as unlanded (it is unverifiable, not divergent)"
  fi

  # No other gate: a second run with an uncommitted tree is accepted (rc in {0,3}).
  _rc="$(promote "$_u" "$_d" "$T/r9.out2" "$T/r9.err2")"
  case "$_rc" in 0|3) : ;; *) fail "R9: a second uncommitted run was refused (rc=$_rc) — a dirty-tree gate was added" ;; esac

  # Positive control: commit everything, re-run, and the fully-landed target exits 0 —
  # proving the 3 above was the audit and not a broken run. Commit the CHILDREN first:
  # `git add -A` at the root of a work tree holding an UNBORN child repo fails with
  # "does not have a commit checked out", which would make this control unrunnable.
  for _k in alpha beta gamma; do
    ( cd "$_u/$_k" && git add -A && git -c user.name=test -c user.email=test@example.com commit -q -m land ) >/dev/null 2>&1 \
      || fail "R9 positive control: could not commit child '$_k'"
  done
  ( cd "$_u" && git add -A && git -c user.name=test -c user.email=test@example.com commit -q -m land ) >/dev/null 2>&1 \
    || fail "R9 positive control: could not commit the coordinator"
  _rc=0
  sh "$INSTALL" --umbrella "$_u" --from-manifest "$_d" >"$T/r9.out3" 2>"$T/r9.err3" || _rc=$?
  [ "$_rc" = "0" ] \
    || fail "R9 positive control: a fully-committed promotion exited $_rc (want 0) — the audit's 3 may be masking a broken run"
  pass "landing audit exits 3 naming unlanded targets, counts a non-git target unverifiable, commits nothing, and is the only git gate (R9) [test_landing_audit_is_the_gate]"
}
test_landing_audit_is_the_gate

# ── R10 (focused half): no --from-manifest ⇒ no promotion step ─────────────────
test_no_promotion_without_flag() {
  _u="$T/r10"; _d="$T/r10-draft.yaml"
  build_single "$_u"
  # A valid draft sits in the target's .harness/; its PRESENCE must never be the trigger.
  write_draft "$_u/.harness/umbrella.manifest.draft.yaml"
  snap_draft="$_u/.harness/umbrella.manifest.draft.yaml"
  _rc=0
  sh "$INSTALL" --umbrella "$_u" >"$T/r10.out" 2>"$T/r10.err" || _rc=$?
  case "$_rc" in 0|3) : ;; *) fail "R10: plain --umbrella cascade failed (rc=$_rc)" ;; esac
  for _k in alpha beta gamma; do
    [ ! -e "$_u/$_k" ] || fail "R10: a plain cascade created the draft child '$_k' — the draft's presence was treated as the promotion trigger"
  done
  # the plain cascade still writes its normal root manifest for the children it discovered
  # (there are none here, so the header alone) — that IS today's behavior.
  [ -f "$_u/umbrella.manifest.yaml" ] \
    || fail "R10: the plain cascade did not write its normal root umbrella.manifest.yaml"
  cmp -s "$snap_draft" "$_u/.harness/umbrella.manifest.draft.yaml" \
    || fail "R10: the plain cascade modified the draft (promotion leaked without the flag)"
  pass "a draft's presence is not the switch: plain cascade runs no promotion step (R10) [test_no_promotion_without_flag]"
}
test_no_promotion_without_flag

# ── R11: the promoted root keeps its board and project-owned state ─────────────
test_board_and_project_state_preserved() {
  _u="$T/r11"; _d="$_u/.harness/umbrella.manifest.draft.yaml"
  build_single "$_u"
  # Sentinel edits to project-owned files (all preserved by the ordinary install/upgrade).
  printf '\n# SENTINEL-ROOT-BOARD\n' >> "$_u/.harness/state/tasks.json"
  printf '\nSENTINEL-PRODUCT\n' >> "$_u/.harness/specs/product.md"
  mkdir -p "$_u/.harness/progress"
  printf '\nSENTINEL-HISTORY\n' >> "$_u/.harness/progress/history.md"
  sed -e 's|^\( *test_command:\).*|\1 "sentinel-cmd"|' "$_u/.harness/harness.config.yaml" > "$_u/.harness/cfg.b" \
    && mv "$_u/.harness/cfg.b" "$_u/.harness/harness.config.yaml"
  # Positive control: the files existed and were non-empty BEFORE the run.
  [ -s "$_u/.harness/state/tasks.json" ] || fail "R11 setup: root board missing/empty before the run"
  [ -s "$_u/.harness/specs/product.md" ] || fail "R11 setup: product.md missing/empty before the run"
  cp "$_u/.harness/state/tasks.json" "$T/r11-tasks.before"
  cp "$_u/.harness/specs/product.md" "$T/r11-product.before"
  cp "$_u/.harness/progress/history.md" "$T/r11-history.before"
  write_draft "$_d"
  _rc="$(promote "$_u" "$_d" "$T/r11.out" "$T/r11.err")"
  case "$_rc" in 0|3) : ;; *) fail "R11: promotion failed (rc=$_rc)" ;; esac
  cmp -s "$T/r11-tasks.before" "$_u/.harness/state/tasks.json" \
    || fail "R11: promotion replaced/altered the root board (state/tasks.json)"
  cmp -s "$T/r11-product.before" "$_u/.harness/specs/product.md" \
    || fail "R11: promotion altered specs/product.md"
  cmp -s "$T/r11-history.before" "$_u/.harness/progress/history.md" \
    || fail "R11: promotion altered progress/history.md"
  grep -qF 'SENTINEL-ROOT-BOARD' "$_u/.harness/state/tasks.json" \
    || fail "R11: the root board sentinel was lost"
  grep -qF 'test_command: "sentinel-cmd"' "$_u/.harness/harness.config.yaml" \
    || fail "R11: a config value was not carried over unchanged"
  # no child gained a PROMOTION-written board: a child's tasks.json is the cascade's own
  # fresh seed and must not contain the root's marker.
  if grep -qF 'SENTINEL-ROOT-BOARD' "$_u/alpha/.harness/state/tasks.json"; then
    fail "R11: promotion wrote the root's board into a child"
  fi
  pass "promotion carries over the root's board/specs/progress/config; no child board written (R11) [test_board_and_project_state_preserved]"
}
test_board_and_project_state_preserved

echo "All promote tests passed."
