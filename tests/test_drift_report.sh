#!/bin/sh
# test_drift_report.sh — E37-F03: the advisory living-doc drift report
# (tools/drift-report.py), its installer wiring's docs and the prose/ledger contracts.
#
# Behavioral rows drive the tool against tests/fixtures/drift/repo (copied into a fresh
# $T/<row>/repo per row, each variant derived with sed/awk/printf/cp so every row has exactly
# one cause) and pass --root "$R". HARNESS_DIR is unset for every run (env -u) so the row's
# root decides the harness directory. Prose rows slice docs/WORKFLOW.md and README.md through
# the fence-aware slicer (tests/lib/fence.awk) and anchor whole sentences from their subject
# over folded newlines. Co-occurrence is not polarity: read the diff.
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact VERSION
# literal; never git-diff a DO-NOT-TOUCH file against main; never write state/, a live spec or
# anything under $ROOT (the dogfood row runs on a `git archive HEAD` copy, never a symlink
# farm). Exit codes are asserted as `rc -eq N`, never a shell-dependent code.

set -eu
LC_ALL=C; export LC_ALL

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL="$ROOT/tools/drift-report.py"
FX="$ROOT/tests/fixtures/drift"
FENCE_AWK="$(cat "$ROOT/tests/lib/fence.awk")"
T="$(mktemp -d 2>/dev/null || mktemp -d -t driftreport)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)
# Root discovery (the tool's .git walk) stops at $T, so a TMPDIR that sits inside some work
# tree can never lend a row its .git (lesson 2026-10-17).
GIT_CEILING_DIRECTORIES="$T"; export GIT_CEILING_DIRECTORIES

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v python3 >/dev/null 2>&1 || fail "python3 is a hard harness dependency and is absent"
[ -d "$FX/repo/specs" ] || fail "setup: fixture tree $FX/repo is missing"

# fresh <row> — copy the fixture repo into $T/<row>/repo.
fresh() {
  rm -rf "$T/$1"; mkdir -p "$T/$1"
  cp -R "$FX/repo" "$T/$1/repo"
  R="$T/$1/repo"
}
# run_tool <args...> — stdout to $T/out, stderr to $T/err, exit code to $rc.
run_tool() { set +e; env -u HARNESS_DIR python3 "$TOOL" "$@" >"$T/out" 2>"$T/err"; rc=$?; set -e; }
both() { cat "$T/out" "$T/err" 2>/dev/null | tr '\n' '|'; }
# report — the report path the tool printed (stdout is exactly that one line).
report() { head -n 1 "$T/out"; }
# expect_ok <row> — exit 0, exactly one stdout line, a report at that path, stderr empty.
expect_ok() {
  [ "$rc" -eq 0 ] || fail "$1: expected rc 0, got $rc ($(both))"
  [ "$(wc -l < "$T/out" | tr -d ' ')" -eq 1 ] || fail "$1: expected exactly one stdout line ($(both))"
  [ -f "$(report)" ] || fail "$1: the printed path is not a report file ($(both))"
  [ ! -s "$T/err" ] || fail "$1: stderr is not empty ($(both))"
}
# section <report> <doc> — the fence-aware slice of `## <doc>` (heading excluded).
section() {
  awk -v h="## $2" "$FENCE_AWK"'
    fence_delim($0) { if (keep) print; next }
    !fence && /^#+ / { keep = ($0 == h); next }
    keep
  ' "$1"
}
# lno <file> <fixed-string> — the line number of the first line holding the string.
lno() { grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1; }
# readme_says <file-basename:line> — the fixture README documents the planted defect there.
readme_says() { grep -qF "| $1 |" "$FX/README.md" || fail "setup: the fixture README does not document $1"; }
# plant_bad — copy the negative ADR into the fresh copy.
plant_bad() { cp "$FX/defects/0002-bad.md" "$R/specs/adr/0002-bad.md"; }
# last_line <report>
last_line() { tail -n 1 "$1"; }

# ── R1: a clean root ⇒ a dated report, its path on stdout, exit 0 ────────────────────────
R1_clean_positive() {
  fresh r1pos
  [ ! -e "$R/progress/drift" ] || fail "R1_clean_positive: setup: progress/drift exists before the run"
  D="$(date +%Y-%m-%d)"
  run_tool --root "$R"
  expect_ok R1_clean_positive
  [ "$(cat "$T/out")" = "$R/progress/drift/$D.md" ] \
    || fail "R1_clean_positive: stdout is not the report's absolute path ($(both))"
  [ "$(last_line "$(report)")" = 'drift-report: No drift detected (4 document(s) read)' ] \
    || fail "R1_clean_positive: the summary is not 'No drift detected (4 document(s) read)' ($(tail -n 3 "$(report)" | tr '\n' '|'))"
  pass R1_clean_positive
}
R1_architecture_absent() {
  fresh r1arch; rm "$R/specs/architecture.md"
  run_tool --root "$R"
  expect_ok R1_architecture_absent
  _r="$(report)"
  grep -qxF '  - specs/architecture.md (absent)' "$_r" || fail "R1_architecture_absent: header lacks the (absent) item"
  section "$_r" specs/architecture.md | grep -qxF 'Absent — not a finding.' \
    || fail "R1_architecture_absent: the architecture section does not say 'Absent — not a finding.'"
  [ "$(last_line "$_r")" = 'drift-report: No drift detected (3 document(s) read)' ] \
    || fail "R1_architecture_absent: the summary does not say 3 document(s) read"
  pass R1_architecture_absent
}
R1_product_space_adr() {
  fresh r1shop
  run_tool --root "$R"; expect_ok R1_product_space_adr
  _r="$(report)"
  _a="$(lno "$_r" '  - specs/adr/0001-clean.md (read)')"; _b="$(lno "$_r" '  - specs/shop/adr/0001-shop.md (read)')"
  [ -n "$_a" ] && [ -n "$_b" ] && [ "$_a" -lt "$_b" ] \
    || fail "R1_product_space_adr: the product-space ADR is not listed after the platform ADR ($_a / $_b)"
  # the file is READ, not merely listed: a planted miss in it is a finding under its section
  printf 'It also names `tools/missing.py`.\n' >> "$R/specs/shop/adr/0001-shop.md"
  run_tool --root "$R"; expect_ok R1_product_space_adr
  section "$(report)" specs/shop/adr/0001-shop.md | grep -q '^- doc-names-missing specs/shop/adr/0001-shop.md:[0-9]* `tools/missing.py`' \
    || fail "R1_product_space_adr: a miss in the product-space ADR is not a finding under its section"
  pass R1_product_space_adr
}
R1_root_discovered_from_git() {
  fresh r1git
  cp "$TOOL" "$ROOT/tools/readiness-check.py" "$R/tools/"
  mkdir "$R/.git"
  set +e; env -u HARNESS_DIR python3 "$R/tools/drift-report.py" >"$T/out" 2>"$T/err"; rc=$?; set -e
  expect_ok "R1_root_discovered_from_git (.git dir)"
  case "$(cat "$T/out")" in "$R/progress/drift/"*) ;; *) fail "R1_root_discovered_from_git: the report is not under the discovered root ($(both))";; esac
  rm -rf "$R/.git" "$R/progress/drift"; printf 'gitdir: elsewhere\n' > "$R/.git"
  set +e; env -u HARNESS_DIR python3 "$R/tools/drift-report.py" >"$T/out" 2>"$T/err"; rc=$?; set -e
  expect_ok "R1_root_discovered_from_git (.git file)"
  case "$(cat "$T/out")" in "$R/progress/drift/"*) ;; *) fail "R1_root_discovered_from_git: a .git FILE is not a root marker ($(both))";; esac
  pass R1_root_discovered_from_git
}
# installed_layout <row> — the fixture moved under .harness/ with a config file and a src/ file.
installed_layout() {
  fresh "$1"
  mkdir "$R/.harness"
  (cd "$R" && mv specs tools agents docs tests progress scratchpad .harness/)
  : > "$R/.harness/harness.config.yaml"
  mkdir "$R/src"; : > "$R/src/app.py"
  printf 'It also names `src/app.py`.\n' >> "$R/.harness/specs/product.md"
}
R1_installed_layout() {
  installed_layout r1inst
  D="$(date +%Y-%m-%d)"
  run_tool --root "$R"; expect_ok R1_installed_layout
  [ "$(cat "$T/out")" = "$R/.harness/progress/drift/$D.md" ] || fail "R1_installed_layout: the report is not under .harness/progress/drift ($(both))"
  grep -qxF -- "- harness: $R/.harness" "$(report)" || fail "R1_installed_layout: the harness header is not <root>/.harness"
  [ "$(last_line "$(report)")" = 'drift-report: No drift detected (4 document(s) read)' ] \
    || fail "R1_installed_layout: the summary is not No drift detected ($(tail -n 3 "$(report)" | tr '\n' '|'))"
  # control: the ROOT, not .harness/, is the resolution root for src/app.py
  rm "$R/src/app.py"
  run_tool --root "$R"; expect_ok "R1_installed_layout control"
  [ "$(grep -c '^- doc-names-missing .*`src/app.py`' "$(report)" || true)" -eq 1 ] \
    || fail "R1_installed_layout: removing src/app.py did not yield exactly one doc-names-missing for it"
  pass R1_installed_layout
}
R1_dogfood_archive_copy() {
  rm -rf "$T/dog"; mkdir -p "$T/dog"
  git -C "$ROOT" archive HEAD | tar -x -C "$T/dog"
  mkdir "$T/dog/.git"
  run_tool --root "$T/dog"
  expect_ok R1_dogfood_archive_copy
  [ "$(grep -c '^  - specs/adr/' "$(report)" || true)" -ge 11 ] \
    || fail "R1_dogfood_archive_copy: the documents list holds fewer than eleven specs/adr/ items"
  pass R1_dogfood_archive_copy
}

# ── R4: the fixed report shape, --date, overwrite, stdout ────────────────────────────────
ADVISORY='Advisory: this report changes nothing. For each finding a human decides: update the doc, or update the code.'
NOT_CHECKED='Replaced patterns — a document that describes a mechanism the code now implements differently — are not detected; "No drift detected" means every named path and symbol resolves and nothing in the requested inventory is unnamed.'
R4_shape() {
  fresh r4shape
  run_tool --root "$R" --date 2026-01-02; expect_ok R4_shape
  _r="$(report)"
  [ "$(head -n 1 "$_r")" = '# Living-doc drift report — 2026-01-02' ] || fail "R4_shape: the title line is wrong ($(head -n 1 "$_r"))"
  grep -qxF -- "$ADVISORY" "$_r" || fail "R4_shape: the advisory sentence is missing or altered"
  grep -qxF -- "- root: $R" "$_r" || fail "R4_shape: the root header line is wrong"
  grep -qxF -- "- harness: $R" "$_r" || fail "R4_shape: the harness header line is wrong"
  [ "$(awk '/^- documents:$/ { f = 1; next } f && /^  / { print; next } f { exit }' "$_r")" = "  - specs/product.md (read)
  - specs/architecture.md (read)
  - specs/adr/0001-clean.md (read)
  - specs/shop/adr/0001-shop.md (read)" ] || fail "R4_shape: the documents list is not the four items in report order"
  grep -qxF -- '- inventory: not requested (pass --inventory <dir>)' "$_r" || fail "R4_shape: the inventory header line is wrong"
  [ "$(grep '^## ' "$_r" | tr '\n' '|')" = '## specs/product.md|## specs/architecture.md|## specs/adr/0001-clean.md|## specs/shop/adr/0001-shop.md|## Not checked by this tool|## Summary|' ] \
    || fail "R4_shape: the section headings are not the fixed set in order ($(grep '^## ' "$_r" | tr '\n' '|'))"
  for _d in specs/product.md specs/architecture.md specs/adr/0001-clean.md specs/shop/adr/0001-shop.md; do
    [ "$(section "$_r" "$_d" | grep -c '^No drift detected\.$')" -eq 1 ] || fail "R4_shape: section $_d does not hold 'No drift detected.'"
  done
  section "$_r" 'Not checked by this tool' | grep -qxF -- "$NOT_CHECKED" || fail "R4_shape: the not-checked section lacks the replaced-patterns sentence"
  [ "$(grep -c '^drift-report: ' "$_r")" -eq 1 ] || fail "R4_shape: there is not exactly one drift-report: line"
  [ "$(last_line "$_r")" = 'drift-report: No drift detected (4 document(s) read)' ] || fail "R4_shape: the file's last line is not the summary line"
  [ "$(grep '^## ' "$_r" | tail -n 1)" = '## Summary' ] || fail "R4_shape: ## Summary is not the last section"
  # no ADR at all => one 'ADRs: none found' item
  rm -f "$R"/specs/adr/*.md; rm -rf "$R/specs/shop"
  run_tool --root "$R" --date 2026-01-02; expect_ok R4_shape
  grep -qxF '  - ADRs: none found' "$(report)" || fail "R4_shape: no ADR does not read '  - ADRs: none found'"
  pass R4_shape
}
R4_date_override() {
  fresh r4date
  run_tool --root "$R" --date 2026-01-02; expect_ok R4_date_override
  case "$(report)" in */2026-01-02.md) ;; *) fail "R4_date_override: --date 2026-01-02 did not name the file 2026-01-02.md ($(both))";; esac
  run_tool --root "$R" --date=2026-01-03; expect_ok R4_date_override
  case "$(report)" in */2026-01-03.md) ;; *) fail "R4_date_override: --date=2026-01-03 did not name the file 2026-01-03.md ($(both))";; esac
  pass R4_date_override
}
R4_same_day_overwrite() {
  fresh r4same
  run_tool --root "$R" --date 2026-01-02; expect_ok R4_same_day_overwrite
  cp "$(report)" "$T/first.md"
  run_tool --root "$R" --date 2026-01-02; expect_ok R4_same_day_overwrite
  cmp -s "$T/first.md" "$(report)" || fail "R4_same_day_overwrite: a rerun on the same tree and date is not byte-identical"
  plant_bad
  run_tool --root "$R" --date 2026-01-02; expect_ok R4_same_day_overwrite
  _r="$(report)"
  [ "$(grep -c '^# Living-doc drift report' "$_r")" -eq 1 ] || fail "R4_same_day_overwrite: the rerun left more than one title line (append, not overwrite)"
  [ "$(grep -c 'tools/missing\.py' "$_r")" -eq 1 ] || fail "R4_same_day_overwrite: the planted defect is not reported exactly once"
  [ "$(grep -c 'No drift detected (' "$_r" || true)" -eq 0 ] || fail "R4_same_day_overwrite: a line from the previous run survived the overwrite"
  pass R4_same_day_overwrite
}
R4_stdout_is_path_only() {
  fresh r4out; plant_bad
  run_tool --root "$R" --date 2026-01-02; expect_ok R4_stdout_is_path_only
  [ "$(cat "$T/out")" = "$R/progress/drift/2026-01-02.md" ] || fail "R4_stdout_is_path_only: stdout is not exactly the report path ($(both))"
  pass R4_stdout_is_path_only
}

R1_clean_positive; R1_architecture_absent; R1_product_space_adr; R1_root_discovered_from_git
R1_installed_layout; R1_dogfood_archive_copy
R4_shape; R4_date_override; R4_same_day_overwrite; R4_stdout_is_path_only
echo "test_drift_report.sh: all rows passed"
