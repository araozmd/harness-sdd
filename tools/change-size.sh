#!/bin/sh
# change-size.sh — measure a branch's change size against the change_size budget (E21-F02).
#
# Runs at the Reviewer → PR handoff: the last moment where splitting is still cheap. Once a
# PR exists it carries review threads, a Codex history, and someone waiting on a depends_on
# edge; before it exists, splitting costs a rebase.
#
# ADVISORY BY CONSTRUCTION. This never blocks: it always exits 0 unless it was invoked wrong
# or cannot measure. The tier is reported on stdout for a human (or the Orchestrator) to act
# on. A hard cap is the wrong instrument — a rename sweep or a generated contract can be
# thousands of lines at near-zero review risk per line.
#
# Usage:
#   tools/change-size.sh [--base <ref>] [--format text|json] [--repo <dir>]
#
#   --base    ref to diff against (default: origin/main, then main, then master)
#   --format  text (default, human-readable) | json (one object, for a caller to parse)
#   --repo    repository to measure (default: the current working directory)
#
# Exit codes:
#   0  measured (ANY tier — ok, advise, or escalate). The tier is in the output.
#   4  usage error / not a git repo / no usable base ref  (nothing measured)
#
# Budgets come from `change_size:` in harness.config.yaml, resolved under HARNESS_DIR. An
# absent block or an absent key falls back to the documented defaults below, so a target
# whose config predates E21-F01 measures correctly rather than failing.

set -eu

# Deterministic globs and sort order regardless of the caller's locale (cf. fix-worktree.sh).
LC_ALL=C
export LC_ALL

DEF_ADVISE_LINES=1500
DEF_ESCALATE_LINES=3000
DEF_ADVISE_FILES=25
DEF_ESCALATE_FILES=50

usage() {
  printf 'usage: change-size.sh [--base <ref>] [--format text|json] [--repo <dir>]\n' >&2
  exit 4
}

base=""; format="text"; repo="."
while [ $# -gt 0 ]; do
  case "$1" in
    --base)   [ $# -ge 2 ] || usage; base="$2"; shift 2 ;;
    --format) [ $# -ge 2 ] || usage; format="$2"; shift 2 ;;
    --repo)   [ $# -ge 2 ] || usage; repo="$2";   shift 2 ;;
    -h|--help) usage ;;
    *) printf 'change-size.sh: unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done
case "$format" in text|json) : ;; *) printf 'change-size.sh: --format must be text or json\n' >&2; usage ;; esac
[ -d "$repo" ] || { printf 'change-size.sh: not a directory: %s\n' "$repo" >&2; exit 4; }
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 \
  || { printf 'change-size.sh: not a git repository: %s\n' "$repo" >&2; exit 4; }

# ── budget ───────────────────────────────────────────────────────────────────────
# Scoped to the top-level `change_size:` section so a same-named key elsewhere in the YAML
# is never read (the section-scoped awk idiom the installer's _cfg_* helpers use).
_cfg_change_size() { # _cfg_change_size <file> <key>
  [ -f "$1" ] || return 0
  awk -v want="$2" '
    /^change_size:[[:space:]]*(#.*)?$/ { in_cs = 1; next }
    /^[^[:space:]#]/                   { in_cs = 0 }
    in_cs {
      line = $0
      sub(/#.*$/, "", line)                       # strip trailing comment
      if (match(line, "^[[:space:]]+" want "[[:space:]]*:")) {
        v = substr(line, RSTART + RLENGTH)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        if (v ~ /^[0-9]+$/) { print v; exit }
      }
    }
  ' "$1"
}

_hdir="${HARNESS_DIR:-}"
if [ -z "$_hdir" ]; then
  if [ -f "$repo/.harness/harness.config.yaml" ]; then _hdir="$repo/.harness"
  else _hdir="$repo"; fi
fi
_cfg="$_hdir/harness.config.yaml"

_v="$(_cfg_change_size "$_cfg" advise_lines   || true)"; advise_lines="${_v:-$DEF_ADVISE_LINES}"
_v="$(_cfg_change_size "$_cfg" escalate_lines || true)"; escalate_lines="${_v:-$DEF_ESCALATE_LINES}"
_v="$(_cfg_change_size "$_cfg" advise_files   || true)"; advise_files="${_v:-$DEF_ADVISE_FILES}"
_v="$(_cfg_change_size "$_cfg" escalate_files || true)"; escalate_files="${_v:-$DEF_ESCALATE_FILES}"

# ── base ref ─────────────────────────────────────────────────────────────────────
# Ask git what the default branch actually IS before guessing. `origin/HEAD` is the
# authoritative answer on any clone that has it, and it is the only candidate that works on a
# repo whose default is `develop`, `trunk`, or anything else. The hard-coded list is the
# fallback for a clone without an origin/HEAD ref, not the primary path — a caller on a
# non-`main` repo should get a measurement, not exit 4 and a Reviewer told to carry on
# without measuring anything.
if [ -z "$base" ]; then
  _oh="$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$_oh" ] && git -C "$repo" rev-parse --verify --quiet "$_oh" >/dev/null 2>&1; then
    base="$_oh"
  else
    for _c in origin/main main origin/master master origin/trunk trunk; do
      if git -C "$repo" rev-parse --verify --quiet "$_c" >/dev/null 2>&1; then base="$_c"; break; fi
    done
  fi
fi
[ -n "$base" ] || { printf 'change-size.sh: no base ref found (tried origin/main, main, origin/master, master); pass --base\n' >&2; exit 4; }
git -C "$repo" rev-parse --verify --quiet "$base" >/dev/null 2>&1 \
  || { printf 'change-size.sh: base ref does not resolve: %s\n' "$base" >&2; exit 4; }

# Measure against the MERGE BASE, not the base tip: the branch may have been rebased or
# carry merge commits, and only the merge base measures what a reviewer will actually read.
mb="$(git -C "$repo" merge-base HEAD "$base" 2>/dev/null || true)"
[ -n "$mb" ] || { printf 'change-size.sh: no merge base between HEAD and %s\n' "$base" >&2; exit 4; }

# ── classify ─────────────────────────────────────────────────────────────────────
# Production = everything that is NOT a test, NOT a spec/progress doc, and NOT declared
# generated. The classifier is deliberately multi-ecosystem: a wrong classifier does not
# make the number slightly off, it makes it meaningless. Extend via change_size.test_paths
# / generated_paths (one extended-regex per line) when a repo does not match these.
_extra() { # _extra <key> — newline-separated list values from the change_size section
  [ -f "$_cfg" ] || return 0
  awk -v want="$1" '
    /^change_size:[[:space:]]*(#.*)?$/ { in_cs = 1; next }
    /^[^[:space:]#]/                   { in_cs = 0; in_l = 0 }
    in_cs && match($0, "^[[:space:]]+" want "[[:space:]]*:[[:space:]]*(#.*)?$") { in_l = 1; next }
    in_cs && in_l {
      line = $0; sub(/#.*$/, "", line)
      if (match(line, /^[[:space:]]+-[[:space:]]+/)) {
        v = substr(line, RSTART + RLENGTH); gsub(/^[[:space:]]*["'"'"']?|["'"'"']?[[:space:]]*$/, "", v)
        if (v != "") print v
      } else if (line ~ /[^[:space:]]/) { in_l = 0 }
    }
  ' "$_cfg"
}

TEST_RE='(^|/)tests?/|(^|/)__tests__/|[._-](test|spec)\.[a-z]+$|_test\.(go|py|rb)$|^test_[^/]*\.(py|sh)$|/test_[^/]*\.(py|sh)$|Test[s]?\.(java|kt|cs)$'
DOC_RE='(^|/)(specs|progress|docs)/|(^|/)(CHANGELOG|README)\.md$'
GEN_RE='(^|/)(vendor|node_modules|dist|build)/|\.lock$|(^|/)(package-lock\.json|yarn\.lock|poetry\.lock|Cargo\.lock|go\.sum)$|\.(pb|generated)\.[a-z]+$'
# One entry, one regex — read LINE by line. `for _p in $(...)` word-splits on IFS, so a
# configured pattern containing a space, e.g. `(^|/)integration tests/`, would be appended as
# TWO alternatives (`(^|/)integration|tests/`) and every production path starting with
# `integration` would silently drop out of the budget. Fed from a here-document rather than a
# pipe, because a piped `while read` runs in a subshell and the appended value would not
# survive the loop.
_tp="$(_extra test_paths || true)"
if [ -n "$_tp" ]; then
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    TEST_RE="$TEST_RE|$_p"
  done <<CS_TEST_PATHS
$_tp
CS_TEST_PATHS
fi
_gp="$(_extra generated_paths || true)"
if [ -n "$_gp" ]; then
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    GEN_RE="$GEN_RE|$_p"
  done <<CS_GEN_PATHS
$_gp
CS_GEN_PATHS
fi

# Measure the WORKING TREE against the merge base, not `"$mb"...HEAD`. The default
# in-session `agents/builder.md` has no commit step: it edits, tests, and hands the feature
# to the Reviewer, so at the moment this check runs the implementation is routinely staged or
# unstaged. A `...HEAD` diff would omit the entire feature and cheerfully report tier `ok`
# with zero production lines — the check reporting green on precisely the branch it exists to
# measure. `git diff <commit>` covers committed + staged + unstaged with no double counting
# (and equals `<commit>...HEAD` exactly when the tree is clean, since $mb IS the merge base).
#
# `-z`, for the same reason `ls-files -z` is used below. `core.quotePath=false` does NOT stop
# git C-quoting a TRACKED path containing `"`, a backslash or a tab — that knob governs
# non-ASCII bytes only. `src/foo".spec.js` then arrives as the quoted text `"src/foo\".spec.js"`,
# whose trailing quote defeats the `[._-](test|spec)\.[a-z]+$` suffix rule: a TEST file is
# charged to the PRODUCTION budget and the tier is silently overstated. NUL framing is the only
# form git never encodes.
#
# `-z` also changes numstat's record framing, and not to the obvious shape:
#   normal   "<add>\t<del>\t<path>" NUL
#   rename   "<add>\t<del>\t"       NUL <src> NUL <dst> NUL   — the path field is EMPTY and TWO
#                                                               extra fields follow
# Rename detection is on by default, so that is not an exotic case; parsed naively each half of
# a rename looks like its own malformed record. Fold it back into one record keyed on the
# DESTINATION, which is what a reviewer actually reads.
#
# (Known limits, shared with the untracked pass below. A filename containing a literal NEWLINE is
# not supported — it splits on the `tr`. A pathname ENDING in a tab survives classification, but
# the `while IFS=<tab> read` loops that render the concentration list strip it, because tab is
# IFS whitespace; both are far outside the supported set and neither is worth the complexity.
# Every other special character round-trips, including an interior TAB, which is why the awk
# passes rejoin fields 3..NF into the pathname.)
stats="$(git -C "$repo" diff --numstat -z "$mb" 2>/dev/null | tr '\0' '\n' | awk -F'\t' '
  st == 2 { st = 1; next }                        # rename source — the destination is what counts
  st == 1 { print hdr $0; st = 0; next }          # rename destination — re-attach its counts
  NF == 3 && $3 == "" { hdr = $0; st = 2; next }  # rename header: the path field is empty
  { print }
' || true)"

# Untracked files are invisible to `git diff` at any range, and a new feature is mostly new
# FILES — the single largest thing this check could miss. Count their lines directly and
# append them in the same numstat shape. `--exclude-standard` honours .gitignore, so build
# output and the harness's own scratch stay out.
# `-z` (NUL-delimited). `ls-files` C-quotes a path containing `"`, `\`, or a tab even under
# core.quotePath=false — it returns `a"b.js` as the seven characters `"a\"b.js"`. That encoded
# text was then used as the pathname, `[ -f ]` failed, and the file was silently skipped: whole
# untracked Builder output disappearing from the measurement. NUL framing is the only form git
# never encodes.
# (Known limit: a filename containing a literal NEWLINE is not supported here — it would still
# split on the tr below. Every other special character now round-trips.)
_untracked="$(git -C "$repo" ls-files -z --others --exclude-standard 2>/dev/null | tr '\0' '\n' || true)"
if [ -n "$_untracked" ]; then
  _extra_stats="$(printf '%s\n' "$_untracked" | while IFS= read -r _f; do
      [ -n "$_f" ] || continue
      # SYMLINKS. git stores a symlink as a blob holding its link value: exactly ONE line,
      # whatever it points at. `[ -f ]` FOLLOWS the link, so a link to a regular file passed that
      # guard and the line count below read the TARGET — a link to a 2,000-line file contributed
      # 2,000 lines before commit and 1 after, reintroducing the commit-coupling R5b exists to
      # remove. What stops the read-through is this branch EXISTING: the `continue` short-
      # circuits before any counting. Placing it BEFORE `[ -f ]` buys something different and
      # also wanted — a broken link and a link to a directory both fail `[ -f ]` and were dropped
      # to 0, while git counts them 1 like any other mode-120000 blob.
      # (Keep every comment inside this command substitution APOSTROPHE-FREE. bash 3.2 in sh
      # mode does not honour `#` when re-scanning a `$( … )` body, so an apostrophe opens a
      # quote that swallows the rest of the block and `sh -n` rejects a file dash accepts.)
      if [ -h "$repo/$_f" ]; then printf '1\t0\t%s\n' "$_f"; continue; fi
      [ -f "$repo/$_f" ] || continue
      # `awk END{print NR}`, not `wc -l`: wc counts NEWLINES, so a file whose last line is
      # unterminated is undercounted by one — and a one-line file with no trailing newline
      # reports ZERO additions. git --numstat counts it correctly once committed, so wc would
      # make the tier depend on whether the Builder had committed yet.
      printf '%s\t0\t%s\n' "$(awk 'END{print NR}' "$repo/$_f")" "$_f"
    done)"
  [ -z "$_extra_stats" ] || stats="$stats
$_extra_stats"
fi
[ -n "$stats" ] || stats=""

# Passed through the ENVIRONMENT, not `awk -v`. An `-v` assignment runs the value through
# awk's string-escape decoding, so `\.` arrives as a bare `.` — a wildcard — and gawk even
# warns about it. The literal separators would silently become "any character", so a
# production file named `src/foo-testXjs` would match the TEST classifier and drop out of the
# production budget, understating the tier. ENVIRON does no such decoding.
export CS_TEST_RE="$TEST_RE" CS_DOC_RE="$DOC_RE" CS_GEN_RE="$GEN_RE"
eval "$(printf '%s\n' "$stats" | awk -F'\t' '
  BEGIN { tre = ENVIRON["CS_TEST_RE"]; dre = ENVIRON["CS_DOC_RE"]; gre = ENVIRON["CS_GEN_RE"] }
  # An EMPTY $stats still arrives as one blank record from `printf %s\n ""`. Without this the
  # unconditional handler counts it as a production file, so a clean tree reports
  # production_files: 1 — and a branch sitting on exactly advise_files/escalate_files gets
  # pushed into the next tier by a file that does not exist.
  NF < 3 { next }
  {
    # A binary file reports "-" for both counts. Discarding the record entirely defeated the
    # FILE budget, which exists precisely to fire independently of lines: a branch adding 30
    # production images reported production_files: 0 and tier ok. Count the file, contribute
    # no lines.
    # Fields 3..NF, not just $3: under `-z` a pathname containing a literal TAB is no longer
    # C-quoted by git, so it splits across fields and `$3` alone would truncate `src/a<TAB>b.js`
    # to `src/a` — losing every classifier suffix on it.
    f = $3; for (i = 4; i <= NF; i++) f = f "\t" $i
    n = ($1 == "-") ? 0 : $1 + 0
    if (f ~ gre)      { g += n; gf++ }
    else if (f ~ tre) { t += n; tf++ }
    else if (f ~ dre) { d += n; df++ }
    else              { p += n; pf++; if (n > 0) prod[f] = n }
    total += n; files++
  }
  END {
    printf "prod=%d; tests=%d; docs=%d; gen=%d; total=%d; files=%d; prod_files=%d\n",
           p+0, t+0, d+0, g+0, total+0, files+0, pf+0
  }')"

# Tier: whichever of lines/files is worse wins. Files matter independently of lines —
# 60 one-line edits is a different review object than one 600-line file.
tier="ok"
if [ "$prod" -gt "$advise_lines" ] || [ "$prod_files" -gt "$advise_files" ]; then tier="advise"; fi
if [ "$prod" -gt "$escalate_lines" ] || [ "$prod_files" -gt "$escalate_files" ]; then tier="escalate"; fi

# Concentration: WHERE the lines are. The actionable question at this point is "where do I
# cut", not "how big is it" — and review risk is not uniform across a diff.
top="$(printf '%s\n' "$stats" | awk -F'\t' '
  BEGIN { tre = ENVIRON["CS_TEST_RE"]; dre = ENVIRON["CS_DOC_RE"]; gre = ENVIRON["CS_GEN_RE"] }
  NF < 3 { next }
  $1 == "-" { next }
  { f = $3; for (i = 4; i <= NF; i++) f = f "\t" $i     # see the classifier pass: `-z` lets a
    if (f ~ gre || f ~ tre || f ~ dre) next             # literal TAB through in a pathname
    printf "%d\t%s\n", $1, f }' | sort -rn | head -5)"

# JSON string escaping for a path interpolated into --format json output. A valid git
# filename may contain `"`, `\`, or any C0 control character, and emitting one raw produces
# output that exits 0 and is unparseable — the worst failure shape for a machine interface,
# because the caller only finds out when jq dies. Now that the numstat pass reads `-z`, git's
# C-quoting no longer hides control bytes behind `\t`-style encodings: the real byte reaches
# here and has to be escaped on our side.
#
# Escape the CLASS, not the characters someone happened to report — a CR rule beside the tab
# rule just leaves the next control character to be discovered the same way. `\b \t \n \f \r`
# get their short escapes; every other C0 control (U+0000–U+001F) gets `\u00XX`. U+0000 cannot
# occur here — no shell variable or environment value can carry a NUL — so the table starts at
# U+0001, where index() doubles as the code point. DEL (U+007F) is NOT escaped: it is not a C0
# control and JSON does not require it. The string travels via the ENVIRONMENT, not a pipe, so
# awk never record-splits it and even a literal newline would be escaped, not misframed.
_json_escape() {
  CS_RAW="$1" awk '
    BEGIN {
      s = ENVIRON["CS_RAW"]
      ctrls = ""
      for (i = 1; i < 32; i++) ctrls = ctrls sprintf("%c", i)
      out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\")      e = "\\\\"
        else if (c == "\"") e = "\\\""
        else {
          p = index(ctrls, c)
          if (p == 0)       e = c
          else if (p == 8)  e = "\\b"
          else if (p == 9)  e = "\\t"
          else if (p == 10) e = "\\n"
          else if (p == 12) e = "\\f"
          else if (p == 13) e = "\\r"
          else              e = sprintf("\\u%04x", p)
        }
        out = out e
      }
      printf "%s", out
    }'
}

if [ "$format" = json ]; then
  printf '{"base":"%s","merge_base":"%s","tier":"%s","production_lines":%d,"production_files":%d,' \
    "$base" "$mb" "$tier" "$prod" "$prod_files"
  printf '"test_lines":%d,"doc_lines":%d,"generated_lines":%d,"total_lines":%d,"total_files":%d,' \
    "$tests" "$docs" "$gen" "$total" "$files"
  printf '"budget":{"advise_lines":%d,"escalate_lines":%d,"advise_files":%d,"escalate_files":%d},' \
    "$advise_lines" "$escalate_lines" "$advise_files" "$escalate_files"
  printf '"top_production_files":['
  _first=1
  printf '%s\n' "$top" | while IFS="$(printf '\t')" read -r _n _f; do
    [ -n "${_f:-}" ] || continue
    [ "$_first" = 1 ] || printf ','
    printf '{"file":"%s","additions":%d}' "$(_json_escape "$_f")" "$_n"
    _first=0
  done
  printf ']}\n'
  exit 0
fi

printf 'change size vs %s (merge-base %s)\n' "$base" "$(printf '%s' "$mb" | cut -c1-9)"
printf '  production   %6d lines  %4d files   (budget: advise >%d/%d, escalate >%d/%d)\n' \
  "$prod" "$prod_files" "$advise_lines" "$advise_files" "$escalate_lines" "$escalate_files"
printf '  tests        %6d lines\n' "$tests"
printf '  docs/specs   %6d lines\n' "$docs"
printf '  generated    %6d lines  (excluded from the budget)\n' "$gen"
printf '  total        %6d lines  %4d files\n' "$total" "$files"
case "$tier" in
  ok)       printf '\n  tier: ok — inside the budget.\n' ;;
  advise)   printf '\n  tier: ADVISE — split, or record one line saying why not.\n' ;;
  escalate) printf '\n  tier: ESCALATE — record a split plan, or an explicit override naming the reason.\n' ;;
esac
if [ "$tier" != ok ] && [ -n "$top" ]; then
  printf '\n  where the production lines are (cut here, not into equal thirds — review risk\n'
  printf '  concentrates: on the PR that motivated this budget, 10%% of the files carried 67%%\n'
  printf '  of the findings):\n'
  printf '%s\n' "$top" | while IFS="$(printf '\t')" read -r _n _f; do
    [ -n "${_f:-}" ] || continue
    printf '    %6d  %s\n' "$_n" "$_f"
  done
fi
printf '\n  This is advisory. It never blocks a PR — it asks for a recorded decision.\n'
exit 0
