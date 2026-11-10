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
pass() { echo "ok - $1"; echo "$1" >> "$T/passed"; }
# row <name> — run one row and require that it passed under its own name: a row that returns
# early without `pass` (a platform skip, a stray return) is a failure, never a silent skip.
row() { "$1"; grep -qE "^$1( |\$)" "$T/passed" || fail "$1: the row returned without passing"; }

command -v python3 >/dev/null 2>&1 || fail "python3 is a hard harness dependency and is absent"
[ -d "$FX/repo/specs" ] || fail "setup: fixture tree $FX/repo is missing"

# fresh <row> — copy the fixture repo into $T/<row>/repo.
fresh() {
  rm -rf "$T/$1"; mkdir -p "$T/$1"
  cp -R "$FX/repo" "$T/$1/repo"
  R="$T/$1/repo"
}
# run_tool <args...> — stdout to $T/out, stderr to $T/err, exit code to $rc.
run_tool() { set +e; env -u HARNESS_DIR -u PYTHONDONTWRITEBYTECODE python3 "$TOOL" "$@" >"$T/out" 2>"$T/err"; rc=$?; set -e; }
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
  # precedence: the product's own root specs/ does not displace the installed layout
  mkdir -p "$R/specs"; printf '# own\n\nSee `tools/decoy-missing.py`.\n' > "$R/specs/product.md"
  run_tool --root "$R"; expect_ok "R1_installed_layout (root specs/)"
  grep -qxF -- "- harness: $R/.harness" "$(report)" || fail "R1_installed_layout: a root specs/ displaced the installed layout ($(both))"
  [ "$(last_line "$(report)")" = 'drift-report: No drift detected (4 document(s) read)' ] \
    || fail "R1_installed_layout: with a root specs/ the summary is not the .harness documents'"
  ! grep -qF 'decoy-missing.py' "$(report)" || fail "R1_installed_layout: the root specs/ decoy was read as a harness document"
  rm -r "$R/specs"
  # control: the ROOT, not .harness/, is the resolution root for src/app.py
  rm "$R/src/app.py"
  run_tool --root "$R"; expect_ok "R1_installed_layout control"
  [ "$(grep -c '^- doc-names-missing .*`src/app.py`' "$(report)" || true)" -eq 1 ] \
    || fail "R1_installed_layout: removing src/app.py did not yield exactly one doc-names-missing for it"
  pass R1_installed_layout
}
# Without harness.config.yaml the harness directory stays the root, whatever .harness/ holds.
R1_stray_harness_dir_is_not_installed() {
  fresh r1stray
  mkdir -p "$R/.harness/cache" "$R/.harness/specs"
  printf '# stale\n\nSee `tools/old-missing.py`.\n' > "$R/.harness/specs/product.md"
  run_tool --root "$R" --date 2026-01-02; expect_ok R1_stray_harness_dir_is_not_installed
  [ "$(cat "$T/out")" = "$R/progress/drift/2026-01-02.md" ] \
    || fail "R1_stray_harness_dir_is_not_installed: a .harness/ without the config file moved the report off <root>/progress/drift ($(both))"
  grep -qxF -- "- harness: $R" "$(report)" \
    || fail "R1_stray_harness_dir_is_not_installed: the harness header is not the root"
  [ "$(last_line "$(report)")" = 'drift-report: No drift detected (4 document(s) read)' ] \
    || fail "R1_stray_harness_dir_is_not_installed: the summary is not No drift detected over the root's four documents ($(tail -n 3 "$(report)" | tr '\n' '|'))"
  ! grep -qF 'old-missing.py' "$(report)" || fail "R1_stray_harness_dir_is_not_installed: the stale .harness/specs was read as the harness documents"
  pass R1_stray_harness_dir_is_not_installed
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
NOT_CHECKED='Replaced patterns — a document that describes a mechanism the code now implements differently — are not detected, and neither is a token outside the shapes the tool extracts: a backticked path whose first directory does not exist at the root (a typo such as tols/x.py), a bare file name found nowhere, or any token the implementation-readiness grammar ignores (placeholders, globs, URLs, absolute paths). "No drift detected" means every backticked repo-rooted path and path:name symbol the tool recognised resolves, and nothing in the requested inventory is unnamed.'
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
  # a real leap day is accepted: the real-date check is not a rejection of every 29 February
  run_tool --root "$R" --date 2028-02-29; expect_ok "R4_date_override (leap day)"
  case "$(report)" in */2028-02-29.md) ;; *) fail "R4_date_override: --date 2028-02-29 did not name the file 2028-02-29.md ($(both))";; esac
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

# ── R2: the two document finding codes and the inherited ignore rules ────────────────────
CHOICE_PATH='update doc (rewrite the path as it is today, or give it a placeholder prefix if it is not in this repository, or supersede the decision) or update code (restore it)'
CHOICE_SYMBOL='update doc (name the symbol as it is today) or update code (restore it)'
BAD=specs/adr/0002-bad.md
# one_line <report> <section-doc> <exact-line> — the section holds exactly one such line.
one_line() {
  [ "$(section "$1" "$2" | grep -cxF -- "$3" || true)" -eq 1 ] || fail "${4:-R2}: section $2 does not hold exactly one line: $3"
}
R2_path_missing() {
  fresh r2path; plant_bad
  readme_says 0002-bad.md:6; readme_says 0002-bad.md:4
  [ "$(lno "$FX/defects/0002-bad.md" 'tools/missing.py')" -eq 6 ] || fail "R2_path_missing: setup: tools/missing.py is not on line 6 of the planted file"
  [ "$(lno "$FX/defects/0002-bad.md" 'docs/gone.md')" -eq 4 ] || fail "R2_path_missing: setup: docs/gone.md is not on line 4 of the planted file"
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_path_missing
  one_line "$(report)" "$BAD" "- doc-names-missing $BAD:6 \`tools/missing.py\` — reconcile: $CHOICE_PATH" R2_path_missing
  one_line "$(report)" "$BAD" "- doc-names-missing $BAD:4 \`docs/gone.md\` — reconcile: $CHOICE_PATH" R2_path_missing
  pass R2_path_missing
}
R2_symbol_missing() {
  fresh r2sym; plant_bad
  readme_says 0002-bad.md:8
  [ "$(lno "$FX/defects/0002-bad.md" 'tools/real.py:nothere')" -eq 8 ] || fail "R2_symbol_missing: setup: the symbol is not on line 8 of the planted file"
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_symbol_missing
  one_line "$(report)" "$BAD" "- doc-names-missing-symbol $BAD:8 \`tools/real.py:nothere\` — reconcile: $CHOICE_SYMBOL" R2_symbol_missing
  # control: a present symbol is no finding; renaming it in the copy makes it one
  fresh r2sym2
  grep -qF 'tools/real.py:helper' "$R/specs/product.md" || fail "R2_symbol_missing: setup: the fixture product.md no longer names tools/real.py:helper"
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_symbol_missing
  [ "$(grep -c 'doc-names-missing-symbol' "$(report)" || true)" -eq 0 ] || fail "R2_symbol_missing: a present symbol was reported"
  sed 's/def helper/def helpr/' "$R/tools/real.py" > "$T/real.py"; cp "$T/real.py" "$R/tools/real.py"
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_symbol_missing
  [ "$(section "$(report)" specs/product.md | grep -c '^- doc-names-missing-symbol specs/product.md:[0-9]* `tools/real.py:helper` ')" -eq 1 ] \
    || fail "R2_symbol_missing: a renamed symbol is not exactly one finding under specs/product.md"
  pass R2_symbol_missing
}
R2_unresolved_path_colon_name_single_finding() {
  fresh r2unres; plant_bad
  [ "$(lno "$FX/defects/0002-bad.md" 'tools/nope.py:x')" -eq 10 ] || fail "R2_unresolved_path: setup: the table row is not on line 10"
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_unresolved_path_colon_name_single_finding
  one_line "$(report)" "$BAD" "- doc-names-missing $BAD:10 \`tools/nope.py:x\` — reconcile: $CHOICE_PATH" R2_unresolved_path_colon_name_single_finding
  [ "$(section "$(report)" "$BAD" | grep -c ':10 ')" -eq 1 ] || fail "R2_unresolved_path: line 10 yields more than one finding"
  [ "$(grep -c 'doc-names-missing-symbol.*nope' "$(report)" || true)" -eq 0 ] || fail "R2_unresolved_path: an unresolved path also reported its symbol"
  pass R2_unresolved_path_colon_name_single_finding
}
R2_fenced_decoy_invisible() {
  fresh r2fence; plant_bad
  [ "$(lno "$R/$BAD" 'fenced-decoy')" -eq 2 ] || fail "R2_fenced_decoy_invisible: setup: the decoy is not on line 2 of the planted file"
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_fenced_decoy_invisible
  [ "$(grep -c 'fenced-decoy' "$(report)" || true)" -eq 0 ] || fail "R2_fenced_decoy_invisible: a token inside fenced code was reported"
  pass R2_fenced_decoy_invisible
}
R2_every_line_kind_scanned() {
  fresh r2kinds; plant_bad
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_every_line_kind_scanned
  [ "$(section "$(report)" "$BAD" | sed -n 's/^- [a-z-]* [^ ]*:\([0-9]*\) .*/\1/p' | tr '\n' ' ')" = '4 6 8 10 ' ] \
    || fail "R2_every_line_kind_scanned: the heading, paragraph, blockquote and table-row findings are not at lines 4 6 8 10"
  [ "$(last_line "$(report)")" = 'drift-report: 4 finding(s) across 5 document(s) read, 0 code entries unnamed' ] \
    || fail "R2_every_line_kind_scanned: the summary does not count 4 finding(s)"
  pass R2_every_line_kind_scanned
}
R2_ignored_shapes() {
  fresh r2tok
  grep '^Ignored shapes:' "$R/specs/product.md" | grep -o '`[^`]*`' | tr -d '`' > "$T/tokens"
  [ "$(wc -l < "$T/tokens" | tr -d ' ')" -eq 13 ] || fail "R2_ignored_shapes: setup: the fixture names $(wc -l < "$T/tokens" | tr -d ' ') ignored tokens, not 13"
  _i=0
  while IFS= read -r _tok; do
    _i=$((_i + 1))
    fresh "r2tok$_i"
    [ -d "$R/scratchpad" ] && [ -d "$R/progress" ] || fail "R2_ignored_shapes: setup: scratchpad/ and progress/ must exist so only the run-time rule ignores them"
    grep -v '^Ignored shapes:' "$R/specs/product.md" > "$T/p.md"; cp "$T/p.md" "$R/specs/product.md"
    printf '\n- `%s`\n' "$_tok" >> "$R/specs/product.md"
    run_tool --root "$R" --date 2026-01-02; expect_ok "R2_ignored_shapes ($_tok)"
    [ "$(last_line "$(report)")" = 'drift-report: No drift detected (4 document(s) read)' ] \
      || fail "R2_ignored_shapes: the ignored shape '$_tok' produced a finding ($(grep '^- ' "$(report)" | head -n 2 | tr '\n' '|'))"
  done < "$T/tokens"
  [ "$_i" -eq 13 ] || fail "R2_ignored_shapes: the loop ran $_i iterations, not 13"
  pass R2_ignored_shapes
}
R2_duplicate_on_one_line_collapsed() {
  fresh r2dup
  printf '\nIt names `tools/nope.py` and again `tools/nope.py`.\n' >> "$R/specs/product.md"
  _n="$(lno "$R/specs/product.md" 'It names `tools/nope.py` and again')"
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_duplicate_on_one_line_collapsed
  [ "$(grep -c "^- doc-names-missing specs/product.md:$_n " "$(report)" || true)" -eq 1 ] || fail "R2_duplicate_on_one_line_collapsed: a token repeated on one line is not exactly one finding"
  [ "$(last_line "$(report)")" = 'drift-report: 1 finding(s) across 4 document(s) read, 0 code entries unnamed' ] \
    || fail "R2_duplicate_on_one_line_collapsed: the summary does not count 1 finding(s)"
  pass R2_duplicate_on_one_line_collapsed
}
R2_order_by_document_then_line() {
  fresh r2order; plant_bad
  printf '\nIt names `tools/zzz.py`.\n' >> "$R/specs/product.md"
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_order_by_document_then_line
  _r="$(report)"
  _a="$(grep -n '^## specs/product.md$' "$_r" | cut -d: -f1)"
  _b="$(grep -n "^## $BAD\$" "$_r" | cut -d: -f1)"
  [ "$_a" -lt "$_b" ] || fail "R2_order_by_document_then_line: the product section does not precede the planted ADR's"
  [ "$(section "$_r" "$BAD" | sed -n 's/^- [a-z-]* [^ ]*:\([0-9]*\) .*/\1/p' | tr '\n' ' ')" = '4 6 8 10 ' ] \
    || fail "R2_order_by_document_then_line: the lines inside the ADR section do not ascend 4 6 8 10"
  pass R2_order_by_document_then_line
}
R2_crlf_and_bom_keep_findings() {
  fresh r2enc; plant_bad
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_crlf_and_bom_keep_findings
  section "$(report)" "$BAD" > "$T/lf.sec"
  [ "$(grep -c '^- ' "$T/lf.sec")" -eq 4 ] || fail "R2_crlf_and_bom_keep_findings: setup: the LF run does not hold four findings"
  awk '{ printf "%s\r\n", $0 }' "$R/$BAD" > "$T/bad.crlf"; cp "$T/bad.crlf" "$R/$BAD"
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_crlf_and_bom_keep_findings
  section "$(report)" "$BAD" | cmp -s - "$T/lf.sec" || fail "R2_crlf_and_bom_keep_findings: a CRLF-terminated document yields different findings"
  fresh r2bom; plant_bad
  printf '\357\273\277' | cat - "$FX/defects/0002-bad.md" > "$R/$BAD"
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_crlf_and_bom_keep_findings
  section "$(report)" "$BAD" | cmp -s - "$T/lf.sec" || fail "R2_crlf_and_bom_keep_findings: a BOM-prefixed document yields different findings (the fence on line 1 must still open)"
  pass R2_crlf_and_bom_keep_findings
}
R2_non_utf8_target_not_searched() {
  fresh r2bin
  printf '\377' >> "$R/tools/real.py"
  printf '\nIt names `tools/real.py:nothere`.\n' >> "$R/specs/product.md"
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_non_utf8_target_not_searched
  [ "$(grep -c 'doc-names-missing-symbol' "$(report)" || true)" -eq 0 ] || fail "R2_non_utf8_target_not_searched: a symbol was searched in a target that is not valid UTF-8"
  pass R2_non_utf8_target_not_searched
}
R2_directory_target_not_searched() {
  fresh r2dirsym
  printf '\nIt names `tools/sub:thing`, a directory with a symbol form.\n' >> "$R/specs/product.md"
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_directory_target_not_searched
  [ "$(last_line "$(report)")" = 'drift-report: No drift detected (4 document(s) read)' ] \
    || fail "R2_directory_target_not_searched: a symbol form on a directory is a finding or an error ($(tail -n 3 "$(report)" | tr '\n' '|'))"
  pass R2_directory_target_not_searched
}

R2_exit0_with_findings() {
  fresh r2exit; plant_bad
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_exit0_with_findings
  [ "$(cat "$T/out")" = "$R/progress/drift/2026-01-02.md" ] || fail "R2_exit0_with_findings: stdout is not exactly the path"
  [ "$(last_line "$(report)")" = 'drift-report: 4 finding(s) across 5 document(s) read, 0 code entries unnamed' ] \
    || fail "R2_exit0_with_findings: the summary is wrong"
  pass R2_exit0_with_findings
}

# chk_exit2 <row> <stderr-fixed-string> — each row's argv is the minimal one ONLY that branch
# rejects, and it asserts exit 2, the stderr shape and the fixed string. Whether the string
# also excludes a second producer of exit 2 is each row's own choice of string (the usage text
# and the internal catch-all both carry common words): R5_progress_is_a_file anchors the
# write_report message for that reason.
chk_exit2() {
  [ "$rc" -eq 2 ] || fail "$1: expected rc 2, got $rc ($(both))"
  head -n 1 "$T/err" | grep -q '^drift-report: error: ' || fail "$1: stderr's first line is not 'drift-report: error: ...' ($(both))"
  grep -q 'usage:' "$T/err" || fail "$1: no usage on stderr ($(both))"
  [ ! -s "$T/out" ] || fail "$1: stdout is not empty on an error ($(both))"
  grep -qF -- "$2" "$T/err" || fail "$1: the error does not name '$2' ($(both))"
  pass "$1"
}

# ── R3: the opt-in inverse direction — files no living document names ─────────────────────
CHOICE_CODE='update doc (name it in the decision that owns it) or update code (remove it)'
INV='Code no living document names'
R3_inventory_unnamed() {
  fresh r3unn
  run_tool --root "$R" --date 2026-01-02 --inventory tools; expect_ok R3_inventory_unnamed
  _r="$(report)"
  [ "$(section "$_r" "$INV" | grep '^- ')" = "- code-unnamed \`tools/unnamed.py\` — reconcile: $CHOICE_CODE" ] \
    || fail "R3_inventory_unnamed: the inventory section is not exactly the one unnamed.py item ($(section "$_r" "$INV" | tr '\n' '|'))"
  grep -qxF -- '- inventory: tools (2 entries)' "$_r" || fail "R3_inventory_unnamed: the header is not '- inventory: tools (2 entries)'"
  [ "$(last_line "$_r")" = 'drift-report: 0 finding(s) across 4 document(s) read, 1 code entry unnamed' ] \
    || fail "R3_inventory_unnamed: the summary is wrong ($(last_line "$_r"))"
  pass R3_inventory_unnamed
}
R3_hidden_and_subdir_skipped() {
  fresh r3hid
  run_tool --root "$R" --date 2026-01-02 --inventory tools; expect_ok R3_hidden_and_subdir_skipped
  [ -f "$R/tools/.hidden.py" ] && [ -f "$R/tools/sub/inner.py" ] || fail "R3_hidden_and_subdir_skipped: setup: the fixture lost its hidden file or subdirectory"
  for _w in hidden sub/inner tools/sub; do
    [ "$(grep -c -- "$_w" "$(report)" || true)" -eq 0 ] || fail "R3_hidden_and_subdir_skipped: '$_w' was listed"
  done
  pass R3_hidden_and_subdir_skipped
}
R3_named_via_remap() {
  installed_layout r3remap
  run_tool --root "$R" --date 2026-01-02 --inventory tools; expect_ok R3_named_via_remap
  [ "$(section "$(report)" "$INV" | grep '^- ')" = "- code-unnamed \`tools/unnamed.py\` — reconcile: $CHOICE_CODE" ] \
    || fail "R3_named_via_remap: the .harness/tools inventory is not exactly the unnamed.py item ($(section "$(report)" "$INV" | tr '\n' '|'))"
  [ "$(grep -c 'real.py`' "$(report)" || true)" -eq 0 ] || fail "R3_named_via_remap: real.py, named through the .harness/ remap, was listed"
  pass R3_named_via_remap
}
R3_dir_ref_names_nothing() {
  fresh r3dir
  grep -qF '`tools/`' "$R/specs/architecture.md" || fail "R3_dir_ref_names_nothing: setup: architecture.md no longer names the directory tools/"
  run_tool --root "$R" --date 2026-01-02 --inventory tools; expect_ok R3_dir_ref_names_nothing
  [ "$(section "$(report)" "$INV" | grep -c '^- code-unnamed `tools/unnamed.py`')" -eq 1 ] \
    || fail "R3_dir_ref_names_nothing: a reference to the directory named a file inside it"
  pass R3_dir_ref_names_nothing
}
R3_inventory_repeat() {
  fresh r3rep
  run_tool --root "$R" --date 2026-01-02 --inventory tools --inventory agents; expect_ok R3_inventory_repeat
  _r="$(report)"
  section "$_r" "$INV" | grep -qF '`tools/unnamed.py`' || fail "R3_inventory_repeat: tools/unnamed.py is not listed"
  section "$_r" "$INV" | grep -qF '`agents/unnamed.md`' || fail "R3_inventory_repeat: agents/unnamed.md is not listed (only the last --inventory kept?)"
  grep -qxF -- '- inventory: tools, agents (4 entries)' "$_r" || fail "R3_inventory_repeat: the header is not '- inventory: tools, agents (4 entries)'"
  [ "$(last_line "$_r")" = 'drift-report: 0 finding(s) across 4 document(s) read, 2 code entries unnamed' ] || fail "R3_inventory_repeat: the summary is wrong ($(last_line "$_r"))"
  section "$_r" "$INV" > "$T/sec.a"
  run_tool --root "$R" --date 2026-01-02 --inventory=agents; expect_ok R3_inventory_repeat
  grep -qxF -- '- inventory: agents (2 entries)' "$(report)" || fail "R3_inventory_repeat: --inventory=agents is not read like --inventory agents"
  [ "$(section "$(report)" "$INV" | grep '^- ')" = "- code-unnamed \`agents/unnamed.md\` — reconcile: $CHOICE_CODE" ] || fail "R3_inventory_repeat: --inventory=agents lists the wrong entries"
  pass R3_inventory_repeat
}
R3_inventory_not_requested() {
  fresh r3none
  run_tool --root "$R" --date 2026-01-02; expect_ok R3_inventory_not_requested
  grep -qxF -- '- inventory: not requested (pass --inventory <dir>)' "$(report)" || fail "R3_inventory_not_requested: the header line is wrong"
  [ "$(grep -c '^## Code no living document names' "$(report)" || true)" -eq 0 ] || fail "R3_inventory_not_requested: the inventory section is present without the flag"
  pass R3_inventory_not_requested
}
R3_inventory_missing_dir_exit2() {
  fresh r3miss
  run_tool --root "$R" --inventory nope
  chk_exit2 R3_inventory_missing_dir_exit2 nope
}

# ── R5: usage / input / internal errors ⇒ exit 2; never exit 1; help semantics ────────────
R4_report_mode() {
  fresh r4mode
  (umask 022; env -u HARNESS_DIR python3 "$TOOL" --root "$R" --date 2026-01-02 >"$T/out" 2>"$T/err") || fail "R4_report_mode: setup: the run failed"
  [ "$(python3 -c 'import os, sys; print("%o" % (os.stat(sys.argv[1]).st_mode & 0o777))' "$R/progress/drift/2026-01-02.md")" = 644 ] \
    || fail "R4_report_mode: under umask 022 the report is not mode 644 (a temp file's 0600 leaked through)"
  pass R4_report_mode
}
R6_no_bytecode_written() {
  fresh r6pyc; plant_bad
  cp "$TOOL" "$ROOT/tools/readiness-check.py" "$R/tools/"
  tree_unchanged "$R/tools/drift-report.py" || fail "R6_no_bytecode_written: running a copy beside its resolver changed or added a file other than the report (a __pycache__?)"
  [ ! -e "$R/tools/__pycache__" ] || fail "R6_no_bytecode_written: a __pycache__ was written beside the resolver"
  pass R6_no_bytecode_written
}

R5_unknown_flag() { run_tool --bogus; chk_exit2 R5_unknown_flag 'unknown flag: --bogus'; }
R5_fix_flag_rejected() { run_tool --fix; chk_exit2 R5_fix_flag_rejected 'unknown flag: --fix'; }
R5_positional() { run_tool x; chk_exit2 R5_positional 'unexpected argument: x'; }
R5_root_no_value() { run_tool --root; chk_exit2 R5_root_no_value '--root needs'; }
R5_inventory_no_value() { fresh r5inv; run_tool --root "$R" --inventory; chk_exit2 R5_inventory_no_value '--inventory needs'; }
R5_date_no_value() { fresh r5dnv; run_tool --root "$R" --date; chk_exit2 R5_date_no_value '--date needs'; }
R5_root_not_a_dir() { run_tool --root "$T/nodir"; chk_exit2 R5_root_not_a_dir '--root is not a directory'; }
R5_inventory_not_relative() {
  fresh r5rel
  mkdir -p "$T/r5rel/x"  # so a joined `$R/../x` WOULD resolve under a mutant that skips the check
  run_tool --root "$R" --inventory /tmp
  chk_exit2 "R5_inventory_not_relative (absolute)" '--inventory must be a path relative to the root: /tmp'
  run_tool --root "$R" --inventory ../x
  chk_exit2 "R5_inventory_not_relative (..)" '--inventory must be a path relative to the root: ../x'
  run_tool --root "$R" --inventory ''
  chk_exit2 "R5_inventory_not_relative (empty)" '--inventory must be a path relative to the root:'
  # a `..` segment in a NON-leading position: tools/../../x reaches $T/r5rel/x outside the root
  run_tool --root "$R" --inventory tools/../../x
  chk_exit2 "R5_inventory_not_relative (inner ..)" '--inventory must be a path relative to the root: tools/../../x'
}
R5_no_git_ancestor_no_root() {
  rm -rf "$T/ceil"; mkdir -p "$T/ceil/.git" "$T/ceil/nogit/tools" "$T/ceil/specs"
  cp "$FX/repo/specs/product.md" "$T/ceil/specs/"  # a walk that ignored the ceiling would find a root WITH a document
  cp "$TOOL" "$ROOT/tools/readiness-check.py" "$T/ceil/nogit/tools/"
  set +e; env -u HARNESS_DIR GIT_CEILING_DIRECTORIES="$T/ceil" python3 "$T/ceil/nogit/tools/drift-report.py" >"$T/out" 2>"$T/err"; rc=$?; set -e
  chk_exit2 R5_no_git_ancestor_no_root 'holds .git; pass --root'  # the usage text also holds '--root', so anchor the message
}
R5_zero_docs() { fresh r5zero; rm -r "$R"/specs/*; run_tool --root "$R"; chk_exit2 R5_zero_docs 'no living documents'; }
R5_doc_invalid_utf8() {
  fresh r5utf; printf '\377' >> "$R/specs/adr/0001-clean.md"
  run_tool --root "$R"; chk_exit2 R5_doc_invalid_utf8 '0001-clean.md'
}
R5_date_malformed() {
  fresh r5dm
  run_tool --root "$R" --date 2026-1-1; chk_exit2 R5_date_malformed '--date is not a YYYY-MM-DD date: 2026-1-1'
  # Python >= 3.11's date.fromisoformat accepts these two on its own: only the shape check rejects them
  run_tool --root "$R" --date 20260102; chk_exit2 "R5_date_malformed (basic form)" '--date is not a YYYY-MM-DD date: 20260102'
  run_tool --root "$R" --date 2026-W01-1; chk_exit2 "R5_date_malformed (ISO week)" '--date is not a YYYY-MM-DD date: 2026-W01-1'
  [ ! -e "$R/progress/drift" ] || fail "R5_date_malformed: a report was written for a malformed date"
}
R5_date_impossible() {
  fresh r5di
  run_tool --root "$R" --date 2026-02-30; chk_exit2 R5_date_impossible '--date is not a YYYY-MM-DD date: 2026-02-30'
  # 29 February exists in 2028 (R4_date_override) but not in 2026: the check depends on the year
  run_tool --root "$R" --date 2026-02-29; chk_exit2 "R5_date_impossible (non-leap 29 Feb)" '--date is not a YYYY-MM-DD date: 2026-02-29'
  [ ! -e "$R/progress/drift" ] || fail "R5_date_impossible: a report was written for an impossible date"
}
R5_progress_is_a_file() {
  fresh r5prog; rm -r "$R/progress"; : > "$R/progress"
  run_tool --root "$R"; chk_exit2 R5_progress_is_a_file 'cannot write the report'
}
R5_sibling_missing() {
  fresh r5sib; rm -rf "$T/alone"; mkdir -p "$T/alone/tools"; cp "$TOOL" "$T/alone/tools/"
  set +e; env -u HARNESS_DIR python3 "$T/alone/tools/drift-report.py" --root "$R" >"$T/out" 2>"$T/err"; rc=$?; set -e
  chk_exit2 R5_sibling_missing 'readiness-check.py'
}
R5_no_report_on_error() {
  fresh r5norep; rm -r "$R"/specs/*
  run_tool --root "$R"; [ "$rc" -eq 2 ] || fail "R5_no_report_on_error: setup: zero documents did not exit 2"
  [ ! -e "$R/progress/drift" ] || fail "R5_no_report_on_error: a report was written on the zero-documents error"
  fresh r5norep2
  run_tool --root "$R" --date 2026-1-1; [ "$rc" -eq 2 ] || fail "R5_no_report_on_error: setup: a malformed date did not exit 2"
  [ ! -e "$R/progress/drift" ] || fail "R5_no_report_on_error: a report was written on the malformed-date error"
  pass R5_no_report_on_error
}
R5_stdout_empty_on_error() {
  run_tool --bogus; [ ! -s "$T/out" ] || fail "R5_stdout_empty_on_error: --bogus wrote to stdout"
  run_tool x; [ ! -s "$T/out" ] || fail "R5_stdout_empty_on_error: a positional argument wrote to stdout"
  pass R5_stdout_empty_on_error
}
R5_help_exit0() {
  fresh r5help
  for _h in -h --help; do
    run_tool --root "$R" "$_h"
    [ "$rc" -eq 0 ] || fail "R5_help_exit0: $_h exited $rc"
    grep -q '^usage:' "$T/out" || fail "R5_help_exit0: $_h printed no usage on stdout"
    [ ! -s "$T/err" ] || fail "R5_help_exit0: $_h wrote to stderr"
    [ ! -e "$R/progress/drift" ] || fail "R5_help_exit0: $_h wrote a report"
  done
  pass R5_help_exit0
}
R5_help_as_value_is_not_help() {
  run_tool --root --help; chk_exit2 "R5_help_as_value_is_not_help (--root)" '--root is not a directory: --help'
  fresh r5hv
  run_tool --root "$R" --inventory --help; chk_exit2 "R5_help_as_value_is_not_help (--inventory)" '--inventory is not a directory'
  run_tool --root "$R" --date --help; chk_exit2 "R5_help_as_value_is_not_help (--date)" '--date is not a YYYY-MM-DD date: --help'
}
R5_internal_error_no_traceback() {
  [ "$(id -u)" -ne 0 ] || { pass "R5_internal_error_no_traceback (skipped: root ignores directory modes)"; return 0; }
  fresh r5int; chmod 000 "$R/specs/adr"
  run_tool --root "$R"
  chmod 755 "$R/specs/adr"
  chk_exit2 R5_internal_error_no_traceback 'error: internal: PermissionError'
  [ "$(grep -c Traceback "$T/err" || true)" -eq 0 ] || fail "R5_internal_error_no_traceback: a traceback reached stderr"
}
R5_never_exit_1() {
  fresh r5one; plant_bad
  run_tool --root "$R"; [ "$rc" -eq 0 ] || fail "R5_never_exit_1: a run with findings exited $rc, not 0"
  [ "$(grep -cE '^[[:space:]]*(return 1|sys\.exit\(1\)|exit\(1\))[[:space:]]*(#.*)?$' "$TOOL" || true)" -eq 0 ] \
    || fail "R5_never_exit_1: the tool source holds a return 1 / exit(1)"
  pass R5_never_exit_1
}

# ── R6: the tree is unchanged but for the one report ──────────────────────────────────────
# tree_unchanged <tool> — run <tool> on the current $R (every finding code) and return 0 iff
# every file other than the report is byte-identical (cksum manifest, state/tasks.json
# included) and the report is the ONLY new path.
tree_unchanged() {
  find "$R" -type f | LC_ALL=C sort > "$T/paths.before"
  find "$R" -type f -exec cksum {} + | LC_ALL=C sort -k3 > "$T/sum.before"
  set +e; env -u HARNESS_DIR -u PYTHONDONTWRITEBYTECODE python3 "$1" --root "$R" --inventory tools --date 2026-01-02 >"$T/out" 2>"$T/err"; rc=$?; set -e
  [ "$rc" -eq 0 ] || fail "R6: the run exited $rc ($(both))"
  find "$R" -type f | LC_ALL=C sort > "$T/paths.after"
  find "$R" -type f -exec cksum {} + | LC_ALL=C sort -k3 > "$T/sum.after"
  [ "$(comm -13 "$T/paths.before" "$T/paths.after")" = "$R/progress/drift/2026-01-02.md" ] || return 1
  [ -z "$(comm -23 "$T/paths.before" "$T/paths.after")" ] || return 1
  grep -v '/progress/drift/' "$T/sum.after" | cmp -s - "$T/sum.before" || return 1
  return 0
}
R6_tree_unchanged_but_report() {
  fresh r6ctl; plant_bad
  # control: a copy of the tool that appends one byte to product.md must be SEEN by the manifest
  rm -rf "$T/r6tool"; mkdir -p "$T/r6tool/tools"
  cp "$ROOT/tools/readiness-check.py" "$T/r6tool/tools/"
  python3 - "$TOOL" "$T/r6tool/tools/drift-report.py" <<'PYEOF'
import sys
s = open(sys.argv[1]).read()
needle = "    print(path)\n    return 0\n"
assert s.count(needle) == 1, "control patch did not apply"
s = s.replace(needle, "    open(os.path.join(root, 'specs/product.md'), 'a').write('x')\n" + needle)
open(sys.argv[2], "w").write(s)
PYEOF
  if tree_unchanged "$T/r6tool/tools/drift-report.py"; then fail "R6_tree_unchanged_but_report CONTROL: the manifest did not see a one-byte edit to a living document"; fi
  fresh r6real; plant_bad
  [ -s "$R/state/tasks.json" ] || fail "R6_tree_unchanged_but_report: setup: the fixture board witness is missing"
  tree_unchanged "$TOOL" || fail "R6_tree_unchanged_but_report: the run changed, added or removed a file other than the report"
  grep -q 'doc-names-missing-symbol' "$R/progress/drift/2026-01-02.md" && grep -q '^- code-unnamed' "$R/progress/drift/2026-01-02.md" && grep -q '^- doc-names-missing ' "$R/progress/drift/2026-01-02.md" \
    || fail "R6_tree_unchanged_but_report: setup: the run did not exercise every finding code"
  pass R6_tree_unchanged_but_report
}

# ── R7: the resolver is imported by file path; none of its names is defined here ──────────
RESOLVER_NAMES='classify ignored shape_ignored resolve spans iter_unfenced _read symbol_present find_root parse_args wants_help'
# defines_any <file> — 0 iff the file defines or binds (column 0) any resolver name.
defines_any() {
  for _n in $RESOLVER_NAMES; do
    [ "$(grep -cE "^def $_n\\(" "$1" || true)" -eq 0 ] || return 0
    [ "$(grep -cE "^$_n *=" "$1" || true)" -eq 0 ] || return 0
  done
  return 1
}
R7_no_own_definitions() {
  printf 'def classify(x): pass\n' | cat "$TOOL" - > "$T/planted.py"
  defines_any "$T/planted.py" || fail "R7_no_own_definitions CONTROL: a planted def classify( was not seen"
  printf 'ignored = 1\n' | cat "$TOOL" - > "$T/planted.py"
  defines_any "$T/planted.py" || fail "R7_no_own_definitions CONTROL: a planted binding 'ignored = 1' was not seen"
  if defines_any "$TOOL"; then fail "R7_no_own_definitions: tools/drift-report.py defines or binds a resolver name itself"; fi
  pass R7_no_own_definitions
}
R7_no_local_binding() {
  python3 -B - "$TOOL" "$ROOT/tools/readiness-check.py" "$RESOLVER_NAMES" <<'PYEOF' || fail "R7_no_local_binding: the drift module binds a resolver name, or its resolver is not tools/readiness-check.py (see above)"
import importlib.util, os, sys
tool, resolver, names = sys.argv[1], sys.argv[2], sys.argv[3].split()
spec = importlib.util.spec_from_file_location("drift", tool)
drift = importlib.util.module_from_spec(spec)
spec.loader.exec_module(drift)
rc = drift._load_resolver()
for n in names:
    assert not hasattr(drift, n), "drift module has attribute " + n
assert os.path.realpath(rc.__file__) == os.path.realpath(resolver), "resolver is " + rc.__file__
assert callable(rc.classify)
PYEOF
  pass R7_no_local_binding
}
R7_sibling_missing_exit2() {
  fresh r7sib; rm -rf "$T/alone7"; mkdir -p "$T/alone7/tools"; cp "$TOOL" "$T/alone7/tools/"
  set +e; env -u HARNESS_DIR python3 "$T/alone7/tools/drift-report.py" --root "$R" >"$T/out" 2>"$T/err"; rc=$?; set -e
  chk_exit2 R7_sibling_missing_exit2 'readiness-check.py'
  grep -qF 'cannot load' "$T/err" || fail "R7_sibling_missing_exit2: the error does not say 'cannot load'"
}

# ── R9: the docs/WORKFLOW.md section and the README sentence ─────────────────────────────
# slice_doc <file> <exact-heading> — the fence-aware slice, heading line included, to the next
# heading, folded onto one line (newlines → spaces, runs squeezed).
slice_doc() {
  awk -v h="$2" "$FENCE_AWK"'
    fence_delim($0) { if (keep) print; next }
    !fence && /^#+ / { keep = ($0 == h); if (keep) print; next }
    keep
  ' "$1" | tr '\n' ' ' | tr -s ' '
}
WF_HEAD='## Living-doc drift report (E37-F03)'
R9_workflow_section() {
  _wf="$ROOT/docs/WORKFLOW.md"
  [ "$(grep -cxF -- "$WF_HEAD" "$_wf" || true)" -eq 1 ] || fail "R9_workflow_section: docs/WORKFLOW.md does not carry exactly one '$WF_HEAD' heading"
  _a="$(grep -nxF '## Drift check on epic rollup' "$_wf" | cut -d: -f1)"
  _b="$(grep -nxF -- "$WF_HEAD" "$_wf" | cut -d: -f1)"
  _c="$(grep -nxF '## Epic lifecycle' "$_wf" | cut -d: -f1)"
  { [ -n "$_a" ] && [ "$_a" -lt "$_b" ] && [ "$_b" -lt "$_c" ]; } \
    || fail "R9_workflow_section: the section is not between '## Drift check on epic rollup' ($_a) and '## Epic lifecycle' ($_c): $_b"
  slice_doc "$_wf" "$WF_HEAD" > "$T/wf.folded"
  cat > "$T/wf.anchors" <<'ANCHORS'
`python3 tools/drift-report.py` (installed: `python3 .harness/tools/drift-report.py`) compares them with the tree
writes `progress/drift/<YYYY-MM-DD>.md` — one section per document listing each `doc-names-missing` and `doc-names-missing-symbol` finding with the reconciliation choice (update the doc, or update the code) left to a human
and, when `--inventory <dir>` is passed, each `code-unnamed` file directly under that directory that no living document names.
It is advisory: no gate, no board write, no edit to any document or code; it exits 0 whenever the report was written and 2 only when it could not run, and it prints the report path.
Run it on demand — suggested once per release, before the `VERSION` bump — and read the report; a run on the same day overwrites that day's report.
It is distinct from the epic-rollup drift check above (the Scout re-validating planned epics), from `init.sh`'s installed-body drift guard and from `tools/test-drift-check.sh`'s weakened-assertion check.
Replaced patterns — a document that describes a mechanism the code now implements differently — are not detected, and neither is a token outside the shapes the tool extracts: a backticked path whose first directory does not exist at the root (a typo such as tols/x.py), a bare file name found nowhere, or any token the implementation-readiness grammar ignores (placeholders, globs, URLs, absolute paths).
"No drift detected" means every backticked repo-rooted path and path:name symbol the tool recognised resolves, and nothing in the requested inventory is unnamed.
ANCHORS
  [ "$(wc -l < "$T/wf.anchors" | tr -d ' ')" -eq 8 ] || fail "R9_workflow_section: setup: the anchor list is not eight sentences"
  while IFS= read -r _s; do
    grep -qF -- "$_s" "$T/wf.folded" || fail "R9_workflow_section: the section lacks the sentence: $_s"
  done < "$T/wf.anchors"
  for _re in '(Reviewer|Orchestrator)[^.]{0,60}(reject|block)' 'exit(s)? 1' 'gate(s|d)? on'; do
    ! grep -qiE -- "$_re" "$T/wf.folded" || fail "R9_workflow_section: the section matches the gate pattern /$_re/ — the report must stay advisory"
  done
  # closed world: any NET change in the folded word count reds (a word-count-neutral edit is
  # seen only by the sentence anchors above — a stated limit, not a guarantee)
  [ "$(wc -w < "$T/wf.folded" | tr -d ' ')" -eq 292 ] \
    || fail "R9_workflow_section: the section holds $(wc -w < "$T/wf.folded" | tr -d ' ') words, not the pasted 292"
  pass R9_workflow_section
}
R9_readme_sentence() {
  _rd="$ROOT/README.md"
  slice_doc "$_rd" '## How it works' > "$T/rd.folded"
  [ -s "$T/rd.folded" ] || fail "R9_readme_sentence: setup: could not slice '## How it works' from README.md"
  _b='On demand — suggested once per release — `tools/drift-report.py` compares the living documents (`specs/product.md`, `specs/architecture.md`, the ADRs) with the tree and writes an advisory `progress/drift/<date>.md` naming each backticked repo-rooted path or path:name symbol it recognises that the code lacks, and every file in a requested inventory that no document names, each with the reconciliation choice (doc or code) left to a human (E37-F03).'
  grep -qF -- "$_b" "$T/rd.folded" || fail "R9_readme_sentence: README '## How it works' lacks the drift-report sentence"
  _e2='Before the Builder sees a spec, the Doc-critic also paraphrases it back'
  grep -qF -- "$_e2" "$T/rd.folded" || fail "R9_readme_sentence: the E37-F02 sentence is gone from '## How it works'"
  grep -qF 'the Reviewer rejects on exit 1.' "$T/rd.folded" || fail "R9_readme_sentence: the E37-F01 three-lints sentence is gone"
  _la="$(grep -nF -- "$_e2" "$_rd" | head -n 1 | cut -d: -f1)"
  _lb="$(grep -nF -- 'On demand — suggested once per release —' "$_rd" | head -n 1 | cut -d: -f1)"
  [ -n "$_lb" ] && [ "$_lb" -gt "$_la" ] || fail "R9_readme_sentence: the drift-report sentence ($_lb) is not after the E37-F02 sentence ($_la)"
  pass R9_readme_sentence
}

# ── R10: ledger row C13, CHANGELOG/VERSION pairing ───────────────────────────────────────
# (that VERSION moved by one MINOR over main is the Reviewer's diff check — never a row here)
R10_version_changelog_ledger() {
  _rat="$ROOT/docs/RATIONALE.md"
  grep -qE '^\| C13 — Living-doc drift report \| Capability compensation \|' "$_rat" \
    || fail "R10_version_changelog_ledger: docs/RATIONALE.md has no C13 — Living-doc drift report row in the Capability compensation layer"
  grep '^| C13 ' "$_rat" | awk -F'|' '{ print $5 }' | grep -qE 'Ablation[^|]*controlled runs[^|]*doc-names-missing[^|]*Retain while it catches any' \
    || fail "R10_version_changelog_ledger: the C13 evidence cell lacks the ablation / retention wording"
  grep '^| C13 ' "$_rat" | awk -F'|' '{ print $4 }' | grep -qF 'the report extracts the backticked repo-rooted paths and `path:name` symbols it recognises' \
    || fail "R10_version_changelog_ledger: the C13 why cell does not say the report extracts only the symbols it recognises"
  [ "$(grep -n '^| C13 ' "$_rat" | cut -d: -f1)" -eq "$(( $(grep -n '^| C12 ' "$_rat" | cut -d: -f1) + 1 ))" ] \
    || fail "R10_version_changelog_ledger: the C13 row is not directly after C12"
  _v="$(cat "$ROOT/VERSION")"
  [ "$(grep -m1 '^## \[' "$ROOT/CHANGELOG.md" | cut -c1-$(( ${#_v} + 5 )))" = "## [$_v]" ] \
    || fail "R10_version_changelog_ledger: the newest CHANGELOG heading is not ## [$_v]"
  awk 'function chk() { if (a && b) ok = 1 }
       /^## \[/ { chk(); a = 0; b = 0 }
       /E37-F03/ { a = 1 }
       /drift-report/ { b = 1 }
       END { chk(); exit ok ? 0 : 1 }' "$ROOT/CHANGELOG.md" \
    || fail "R10_version_changelog_ledger: no CHANGELOG section names both E37-F03 and drift-report"
  pass R10_version_changelog_ledger
}

R2_line_token_pairs_distinct() {
  fresh r2pairs
  printf '\nA `tools/gone.py` and `tools/also.py`.\n\nAgain `tools/gone.py`.\n' >> "$R/specs/product.md"
  _n="$(lno "$R/specs/product.md" 'A `tools/gone.py` and `tools/also.py`.')"
  _m="$(lno "$R/specs/product.md" 'Again `tools/gone.py`.')"
  [ -n "$_n" ] && [ -n "$_m" ] && [ "$_n" -lt "$_m" ] || fail "R2_line_token_pairs_distinct: setup: the two lines are not in order ($_n / $_m)"
  run_tool --root "$R" --date 2026-01-02; expect_ok R2_line_token_pairs_distinct
  [ "$(section "$(report)" specs/product.md | grep '^- ' | sed 's/ — reconcile:.*//')" = "- doc-names-missing specs/product.md:$_n \`tools/gone.py\`
- doc-names-missing specs/product.md:$_n \`tools/also.py\`
- doc-names-missing specs/product.md:$_m \`tools/gone.py\`" ] \
    || fail "R2_line_token_pairs_distinct: the findings are not the three distinct (line, token) pairs in order ($(section "$(report)" specs/product.md | grep '^- ' | tr '\n' '|'))"
  [ "$(last_line "$(report)")" = 'drift-report: 3 finding(s) across 4 document(s) read, 0 code entries unnamed' ] \
    || fail "R2_line_token_pairs_distinct: the summary does not count 3 finding(s)"
  pass R2_line_token_pairs_distinct
}
R1_bare_name_resolves_beside_document() {
  fresh r1bare
  grep -qF 'a bare `glossary.md`' "$R/specs/product.md" || fail "R1_bare_name_resolves_beside_document: setup: product.md no longer names the bare glossary.md"
  [ -f "$R/specs/glossary.md" ] && ! grep -q 'Nothere' "$R/specs/glossary.md" || fail "R1_bare_name_resolves_beside_document: setup: the sibling is missing or already holds Nothere"
  run_tool --root "$R" --date 2026-01-02 --inventory specs; expect_ok R1_bare_name_resolves_beside_document
  [ "$(section "$(report)" "$INV" | grep -c 'specs/glossary.md')" -eq 0 ] \
    || fail "R1_bare_name_resolves_beside_document: a sibling named by a bare file name is listed as unnamed"
  [ "$(section "$(report)" "$INV" | grep -c '^- code-unnamed `specs/architecture.md`')" -eq 1 ] \
    || fail "R1_bare_name_resolves_beside_document: setup: the inventory does not list the genuinely unnamed sibling (an empty section proves nothing)"
  printf '\nIt also names `glossary.md:Nothere`.\n' >> "$R/specs/product.md"
  _n="$(lno "$R/specs/product.md" 'It also names `glossary.md:Nothere`.')"
  run_tool --root "$R" --date 2026-01-02; expect_ok R1_bare_name_resolves_beside_document
  [ "$(section "$(report)" specs/product.md | grep '^- ' | sed 's/ — reconcile:.*//')" = "- doc-names-missing-symbol specs/product.md:$_n \`glossary.md:Nothere\`" ] \
    || fail "R1_bare_name_resolves_beside_document: a missing symbol on a bare sibling is not exactly one finding ($(section "$(report)" specs/product.md | grep '^- ' | tr '\n' '|'))"
  pass R1_bare_name_resolves_beside_document
}
R1_non_adr_namespaces_excluded() {
  fresh r1ns
  for _d in specs/epics/adr specs/_templates/adr specs/adr/adr; do
    mkdir -p "$R/$_d"; printf '# X\n\nIt names `tools/missing.py`.\n' > "$R/$_d/0001-x.md"
  done
  run_tool --root "$R" --date 2026-01-02; expect_ok R1_non_adr_namespaces_excluded
  [ "$(grep -c 'tools/missing\.py' "$(report)" || true)" -eq 0 ] || fail "R1_non_adr_namespaces_excluded: a document under epics/, _templates/ or adr/adr/ was read"
  [ "$(grep -c '^  - specs/' "$(report)")" -eq 4 ] || fail "R1_non_adr_namespaces_excluded: the documents list is not the four fixture documents"
  [ "$(last_line "$(report)")" = 'drift-report: No drift detected (4 document(s) read)' ] \
    || fail "R1_non_adr_namespaces_excluded: the document count moved ($(last_line "$(report)"))"
  # control: the same document under a real product space IS read
  mkdir -p "$R/specs/other/adr"; cp "$R/specs/epics/adr/0001-x.md" "$R/specs/other/adr/"
  run_tool --root "$R" --date 2026-01-02; expect_ok R1_non_adr_namespaces_excluded
  [ "$(grep -c '^- doc-names-missing specs/other/adr/0001-x.md:' "$(report)" || true)" -eq 1 ] \
    || fail "R1_non_adr_namespaces_excluded: control: the same file under a product space is not read"
  pass R1_non_adr_namespaces_excluded
}

R3_inventory_counts_and_precedence() {
  fresh r3cnt
  # one entry, named: the header reads '1 entry', nothing is unnamed
  run_tool --root "$R" --date 2026-01-02 --inventory docs; expect_ok R3_inventory_counts_and_precedence
  grep -qxF -- '- inventory: docs (1 entry)' "$(report)" || fail "R3_inventory_counts_and_precedence: one entry does not read '(1 entry)'"
  section "$(report)" "$INV" | grep -qxF 'No drift detected.' || fail "R3_inventory_counts_and_precedence: a fully named inventory does not read 'No drift detected.'"
  [ "$(last_line "$(report)")" = 'drift-report: No drift detected (4 document(s) read)' ] || fail "R3_inventory_counts_and_precedence: a clean inventory changed the summary"
  # an empty inventory (only a hidden file): '0 entries'
  run_tool --root "$R" --date 2026-01-02 --inventory scratchpad; expect_ok R3_inventory_counts_and_precedence
  grep -qxF -- '- inventory: scratchpad (0 entries)' "$(report)" || fail "R3_inventory_counts_and_precedence: an empty directory does not read '(0 entries)'"
  # a trailing slash is stripped from the printed entry; a nested directory is an inventory
  run_tool --root "$R" --date 2026-01-02 --inventory tools/; expect_ok R3_inventory_counts_and_precedence
  section "$(report)" "$INV" | grep -qxF -- "- code-unnamed \`tools/unnamed.py\` — reconcile: $CHOICE_CODE" || fail "R3_inventory_counts_and_precedence: 'tools/' did not print entries as tools/<file>"
  run_tool --root "$R" --date 2026-01-02 --inventory tools/sub; expect_ok R3_inventory_counts_and_precedence
  section "$(report)" "$INV" | grep -qxF -- "- code-unnamed \`tools/sub/inner.py\` — reconcile: $CHOICE_CODE" || fail "R3_inventory_counts_and_precedence: a nested directory was not inventoried"
  # <root>/<dir> wins over <root>/.harness/<dir> when both are directories
  installed_layout r3prec
  mkdir "$R/tools"; : > "$R/tools/solo.py"
  run_tool --root "$R" --date 2026-01-02 --inventory tools; expect_ok R3_inventory_counts_and_precedence
  [ "$(section "$(report)" "$INV" | grep '^- ')" = "- code-unnamed \`tools/solo.py\` — reconcile: $CHOICE_CODE" ] \
    || fail "R3_inventory_counts_and_precedence: <root>/tools did not win over <root>/.harness/tools"
  grep -qxF -- '- inventory: tools (1 entry)' "$(report)" || fail "R3_inventory_counts_and_precedence: the header is not '- inventory: tools (1 entry)'"
  pass R3_inventory_counts_and_precedence
}
R1_harness_dir_env() {
  fresh r1env
  mkdir -p "$T/r1env/h/specs"; cp "$R/specs/product.md" "$R/specs/glossary.md" "$T/r1env/h/specs/"
  set +e; env HARNESS_DIR="$T/r1env/h" python3 "$TOOL" --root "$R" --date 2026-01-02 >"$T/out" 2>"$T/err"; rc=$?; set -e
  expect_ok R1_harness_dir_env
  [ "$(cat "$T/out")" = "$T/r1env/h/progress/drift/2026-01-02.md" ] || fail "R1_harness_dir_env: the report is not under \$HARNESS_DIR ($(both))"
  grep -qxF -- "- harness: $T/r1env/h" "$(report)" || fail "R1_harness_dir_env: the harness header is not \$HARNESS_DIR"
  grep -qxF '  - specs/architecture.md (absent)' "$(report)" || fail "R1_harness_dir_env: documents were not read from \$HARNESS_DIR/specs"
  [ ! -e "$R/progress/drift" ] || fail "R1_harness_dir_env: a report was written under the root"
  # precedence: $HARNESS_DIR wins over an installed config at the root. .harness/specs is populated
  # so the wrong order would succeed silently, not exit 2. Pins env-over-installed-config only.
  mkdir "$R/.harness"; : > "$R/.harness/harness.config.yaml"; cp -R "$R/specs" "$R/.harness/specs"
  set +e; env HARNESS_DIR="$T/r1env/h" python3 "$TOOL" --root "$R" --date 2026-01-02 >"$T/out" 2>"$T/err"; rc=$?; set -e
  expect_ok "R1_harness_dir_env (installed config)"
  [ "$(cat "$T/out")" = "$T/r1env/h/progress/drift/2026-01-02.md" ] \
    || fail "R1_harness_dir_env: an installed config at the root displaced \$HARNESS_DIR ($(both))"
  [ ! -e "$R/.harness/progress/drift" ] || fail "R1_harness_dir_env: a report was written under <root>/.harness"
  pass R1_harness_dir_env
}

row R1_clean_positive; row R1_architecture_absent; row R1_product_space_adr;
row R1_root_discovered_from_git; row R1_installed_layout; row R1_stray_harness_dir_is_not_installed;
row R1_dogfood_archive_copy;
row R4_shape; row R4_date_override; row R4_same_day_overwrite; row R4_stdout_is_path_only;
row R4_report_mode; row R2_path_missing; row R2_symbol_missing;
row R2_unresolved_path_colon_name_single_finding; row R2_fenced_decoy_invisible;
row R2_every_line_kind_scanned; row R2_ignored_shapes; row R2_duplicate_on_one_line_collapsed;
row R2_line_token_pairs_distinct; row R2_order_by_document_then_line;
row R1_bare_name_resolves_beside_document; row R1_non_adr_namespaces_excluded;
row R2_crlf_and_bom_keep_findings; row R2_non_utf8_target_not_searched;
row R2_directory_target_not_searched; row R2_exit0_with_findings; row R3_inventory_unnamed;
row R3_hidden_and_subdir_skipped; row R3_named_via_remap; row R3_dir_ref_names_nothing;
row R3_inventory_repeat; row R3_inventory_not_requested; row R3_inventory_missing_dir_exit2;
row R3_inventory_counts_and_precedence; row R1_harness_dir_env; row R5_unknown_flag;
row R5_fix_flag_rejected; row R5_positional; row R5_root_no_value; row R5_inventory_no_value;
row R5_date_no_value; row R5_root_not_a_dir; row R5_inventory_not_relative;
row R5_no_git_ancestor_no_root; row R5_zero_docs; row R5_doc_invalid_utf8;
row R5_date_malformed; row R5_date_impossible; row R5_progress_is_a_file;
row R5_sibling_missing; row R5_no_report_on_error; row R5_stdout_empty_on_error;
row R5_help_exit0; row R5_help_as_value_is_not_help; row R5_internal_error_no_traceback;
row R5_never_exit_1; row R6_tree_unchanged_but_report; row R6_no_bytecode_written;
row R7_no_own_definitions; row R7_no_local_binding; row R7_sibling_missing_exit2;
row R9_workflow_section; row R9_readme_sentence; row R10_version_changelog_ledger;
# Dispatch completeness: sees a defined-but-undispatched R*() row; does not see a row deleted
# together with its definition.
for f in $(sed -n 's/^\(R[0-9][0-9]*_[A-Za-z0-9_]*\)() *{.*/\1/p' "$ROOT/tests/test_drift_report.sh"); do
  grep -qE "^$f( |\$)" "$T/passed" || fail "$f: defined but not dispatched from the row list"
done
echo "test_drift_report.sh: all rows passed"
