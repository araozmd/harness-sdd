#!/bin/sh
# pr-round-trend.sh — is this PR's review CONVERGING, or just being resampled? (E21-F03)
#
# `pr_loop.max_rounds` caps the loop and labels the PR needs-human. What it never said is
# what the human should CONCLUDE. In practice the conclusion drawn is "run it again": on
# viernes-ai/viernes-bookings-api PR #76 the operator posted `@codex review` twelve times by
# hand. Rounds 5–12 cost roughly 2M input tokens and 8 hours of wall clock to keep
# rediscovering that the diff was too large to review in one pass.
#
# The information that would have ended it after round 4 was already on the PR and nobody
# aggregated it — the per-round blocking-finding count:
#
#     R1 R2 R3 R4 R5 R6 R7 R8 R9 R10 R11 R12
#      1  3  1  2  1  3  1  2  2   1   2   1     (P1 only; 20 P1 + 15 P2 total)
#
# A DECAYING count means the review is converging and one more round is rational. A FLAT
# count means the reviewer is sampling a surface larger than one pass can cover, and more
# rounds buy more samples, not more confidence. Those two look identical at the cap today.
#
# Reads only the loop's own round cache — no `gh`, no network, no new state. Everything here
# is rebuildable from `.pr-loop/<pr>/round-*/`, which the loop already writes.
#
# ── WHAT THE ROUND CACHE HAS TO SAY, AND WHY (E99-F126 + E99-F116) ───────────────────────
#
# The first version of this tool read exactly one file per round, `blocking.json`, and took
# its LENGTH as the round's finding count. That file answers neither question this tool asks.
#
# E99-F126 — an empty array meant two opposite things. "Reviewed, nothing blocked" and "no
# review ever landed" are byte-identical as `[]`. MEASURED on araozmd/harness-sdd#141: the
# rounds went 2 blocking → round 2 WATCHER TIMEOUT (exit 2, zero Codex activity) → 2
# blocking. Recording the timed-out round as `[]` produced "verdict: converging — the finding
# rate is coming down. One more round is rational."; deleting that one file changed the
# verdict to `insufficient`. The flat 2,2 was the honest signal and the tool never saw it. So
# the bias ran toward "yes, another round" exactly when review was NOT landing — the case
# where another round is most wasteful — and recording a timeout as a clean round was
# silently rewarded. The loop already guards this exact two-meanings-of-empty hazard at the
# MERGE gate (tools/pr-gate.sh consults `wait-for-codex.sh evaluate` precisely because an
# empty blocking set is ambiguous); it did not guard it here.
#
# E99-F116 — the rate was blind whenever the operator overrode a severity. `blocking.json` is
# filtered to the CONFIGURED `pr_loop.blocking_severities`, but the runbook tells the operator
# to read findings, not severities ("a P2 can be substantively blocking"). On viernes-ai/
# viernes-web PR #85, three consecutive Codex P2s were each judged blocking and fixed while
# P2 sat outside the configured filter, so every `blocking.json` was empty or absent and this
# tool reported "no round with a readable blocking.json — nothing to trend" through a textbook
# non-converging run.
#
# The repair is two files the loop now writes, and this tool now reads:
#
#   round-<n>/outcome     one word — findings | clean | timeout | unresolved. The round's
#                         TERMINAL STATE, stated rather than inferred from an array's length.
#                         Only `findings` and `clean` are rounds that were actually reviewed
#                         and may enter the rate; `timeout` and `unresolved` are reported
#                         SEPARATELY, never folded into the rate and never dropped.
#   round-<n>/acted.json  what the round ACTUALLY treated as blocking, one row per finding,
#                         each carrying its own `severity` and an `override` flag. The MERGE
#                         gate keeps reading the conservative configured `blocking.json` —
#                         that is a separate decision and stays conservative — while the rate
#                         reads what was acted on, so an override is visible AS an override.
#
# Backward compatibility. A cache written before this change has neither file, and MUST NOT
# be read as a run of clean rounds. Order of derivation, per round:
#   1. `outcome` present and recognised           → authoritative.
#   2. a non-empty acted/blocking set             → `findings` (findings prove a review landed).
#   3. an empty set, with `pr.json` on disk       → ask `wait-for-codex.sh evaluate`, the same
#                                                   offline probe the merge gate uses:
#                                                   clean ⇒ clean, findings ⇒ findings,
#                                                   anything else ⇒ `timeout` (reported, not
#                                                   counted). This alone catches the #141
#                                                   shape in an OLD cache.
#   4. otherwise                                  → `unknown`: still counted when a number was
#                                                   readable, so a legacy cache still trends,
#                                                   but NAMED in the report as a round whose
#                                                   outcome nobody recorded. Never silently
#                                                   counted as clean.
#
# Usage:
#   tools/pr-round-trend.sh --cache <.pr-loop/<pr>> [--format text|json] [--window <n>]
#                           [--diff-files <n>] [--diff-lines <n>]
#
# Exit codes:
#   0  reported (any verdict)          4  usage error / unreadable cache
#
# ADVISORY. It reports a series and a verdict; it never fails a PR and never merges one.

set -eu
LC_ALL=C; export LC_ALL

WINDOW=3          # "the last N rounds each produced >=1 blocking finding" ⇒ not converging
CONCENTRATED_FILES=3   # a diff no wider than this cannot be split along file seams
cache=""; format="text"; diff_files=""; diff_lines=""

usage() {
  printf 'usage: pr-round-trend.sh --cache <.pr-loop/<pr>> [--format text|json] [--window <n>] [--diff-files <n>] [--diff-lines <n>]\n' >&2
  exit 4
}
while [ $# -gt 0 ]; do
  case "$1" in
    --cache)  [ $# -ge 2 ] || usage; cache="$2";  shift 2 ;;
    --format) [ $# -ge 2 ] || usage; format="$2"; shift 2 ;;
    --window) [ $# -ge 2 ] || usage; WINDOW="$2"; shift 2 ;;
    --diff-files) [ $# -ge 2 ] || usage; diff_files="$2"; shift 2 ;;
    --diff-lines) [ $# -ge 2 ] || usage; diff_lines="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) printf 'pr-round-trend.sh: unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done
[ -n "$cache" ] || usage
case "$format" in text|json) : ;; *) printf 'pr-round-trend.sh: --format must be text or json\n' >&2; usage ;; esac
case "$WINDOW" in ''|*[!0-9]*) printf 'pr-round-trend.sh: --window must be a positive integer\n' >&2; usage ;; esac
[ "$WINDOW" -ge 1 ] || usage
case "$diff_files" in '') : ;; *[!0-9]*) printf 'pr-round-trend.sh: --diff-files must be a non-negative integer\n' >&2; usage ;; esac
case "$diff_lines" in '') : ;; *[!0-9]*) printf 'pr-round-trend.sh: --diff-lines must be a non-negative integer\n' >&2; usage ;; esac
[ -d "$cache" ] || { printf 'pr-round-trend.sh: no such cache dir: %s\n' "$cache" >&2; exit 4; }
command -v jq >/dev/null 2>&1 || { printf 'pr-round-trend.sh: jq is required (same dependency as /sdd-pr-loop)\n' >&2; exit 4; }

# The offline review-state probe, used ONLY to disambiguate an empty blocking set in a cache
# written before `outcome` existed. Same file, same rules, same exit codes the merge gate
# relies on — there must be exactly one implementation of "a resolved Codex review".
EVALUATOR="$(dirname -- "$0")/wait-for-codex.sh"

# ── the series ───────────────────────────────────────────────────────────────────
# Only rounds that were ACTUALLY REVIEWED enter the rate. A round that timed out or aborted
# before classifying has no finding count — counting its empty set as 0 fakes a convergence
# that never happened (E99-F126), and dropping it silently hides a run that is failing to get
# reviewed at all. It is neither counted nor dropped: it is reported.
#
# Sort by the NUMERIC suffix, not by the glob. A shell glob expands lexicographically, so at
# ten or more rounds `round-*/` yields round-1, round-10, round-11, round-12, round-2, … and
# the last-N window would trend rounds 7–9 while calling them the latest. That is not a
# cosmetic ordering bug: on a twelve-round PR — the exact case this tool exists for — it can
# invert the verdict and tell the human to keep reviewing.
series=""; rounds=""; n_rounds=0
notrev=""; n_notrev=0          # rounds that were never reviewed — reported, never in the rate
unrec=""; n_unrec=0            # counted rounds whose outcome nobody recorded (legacy cache)
overrides=0; override_sevs=""  # findings acted on DESPITE sitting outside blocking_severities
TAB="$(printf '\t')"

# _counts_file <round-dir> — the file the RATE is computed from. `acted.json` (what the round
# actually treated as blocking, severities intact) when the loop wrote it; otherwise the
# configured `blocking.json`, which is all a pre-E99-F116 cache has.
_counts_file() {
  if   [ -f "$1/acted.json" ];    then printf '%s' "$1/acted.json"
  elif [ -f "$1/blocking.json" ]; then printf '%s' "$1/blocking.json"
  fi
}

# Collect the suffixes first, then `sort -n`. The collection loop stays OUTSIDE a command
# substitution on purpose: an unparenthesised `case` pattern inside `$( … )` closes the
# substitution early in some shells, which is a parse error rather than a wrong answer.
_nums=""
for d in "$cache"/round-*/; do
  [ -d "$d" ] || continue
  _b="${d%/}"; _b="${_b##*/}"; _n="${_b#round-}"
  case "$_n" in ''|*[!0-9]*) continue ;; esac
  _nums="$_nums$_n
"
done
_ordered="$(printf '%s' "$_nums" | sort -n)"
for _n in $_ordered; do
  d="$cache/round-$_n"

  # (a) the count, from acted.json when present
  _cf="$(_counts_file "$d")"
  _c=""
  if [ -n "$_cf" ]; then
    _c="$(jq 'if type == "array" then length else empty end' "$_cf" 2>/dev/null || true)"
    case "${_c:-}" in ''|*[!0-9]*) _c="" ;; esac
  fi

  # (b) the severity overrides this round acted on. Severity survives PER ROW, so a finding
  # fixed despite its severity being outside `pr_loop.blocking_severities` is visible AS an
  # override rather than vanishing from the rate the way PR #85's three P2s did.
  if [ -f "$d/acted.json" ]; then
    _ov="$(jq '[ .[]? | select(.override == true) ] | length' "$d/acted.json" 2>/dev/null || true)"
    case "${_ov:-}" in ''|*[!0-9]*) _ov=0 ;; esac
    if [ "$_ov" -gt 0 ]; then
      overrides=$((overrides + _ov))
      # Sanitised inside jq, not in the shell: `severity` is copied from a Codex comment body
      # and this list is later word-split (and interpolated into --format json). A severity
      # containing `*` would glob against the cwd; one containing `"` would emit unparseable
      # JSON. Restrict it to the shape a severity tag can actually have.
      override_sevs="$override_sevs $(jq -r '[ .[]? | select(.override == true)
                | ((.severity // "?") | gsub("[^A-Za-z0-9._-]"; "")) | select(. != "") ]
              | unique | join(" ")' "$d/acted.json" 2>/dev/null || true)"
    fi
  fi

  # (c) the OUTCOME — stated if the loop stated it, else derived, else unknown.
  _outcome=""; _src=""
  if [ -f "$d/outcome" ]; then
    _o="$(head -n 1 "$d/outcome" 2>/dev/null | tr -d ' \t\r\n' || true)"
    case "${_o:-}" in
      findings|clean|timeout|unresolved) _outcome="$_o"; _src=recorded ;;
    esac
  fi
  if [ -z "$_outcome" ]; then
    if [ -n "$_c" ] && [ "$_c" -gt 0 ]; then
      _outcome=findings; _src=derived            # findings are self-proving: a review landed
    elif [ -f "$d/pr.json" ] && [ -f "$EVALUATOR" ]; then
      _rc=0; sh "$EVALUATOR" evaluate "$d" >/dev/null 2>&1 || _rc=$?
      case "$_rc" in
        3) _outcome=clean;    _src=derived ;;
        0) _outcome=findings; _src=derived ;;
        *) _outcome=timeout;  _src=derived ;;    # pending/unreadable ⇒ no review resolved
      esac
    else
      _outcome=unknown; _src=unknown
    fi
  fi

  # (d) bucket it
  case "$_outcome" in
    clean)
      [ -n "$_c" ] || _c=0                        # a clean round legitimately writes no set
      rounds="$rounds $_n"; series="$series $_c"; n_rounds=$((n_rounds + 1)) ;;
    findings)
      if [ -z "$_c" ]; then
        # Reviewed, but the count was never written (or is unparseable). There is no number
        # to trend; say so rather than substituting zero.
        notrev="$notrev$_n${TAB}uncounted${TAB}$_src
"; n_notrev=$((n_notrev + 1))
      else
        rounds="$rounds $_n"; series="$series $_c"; n_rounds=$((n_rounds + 1))
      fi ;;
    timeout|unresolved)
      notrev="$notrev$_n${TAB}$_outcome${TAB}$_src
"; n_notrev=$((n_notrev + 1)) ;;
    *)
      if [ -n "$_c" ]; then
        # Legacy cache: a readable count with no recorded outcome, and (by (c)) necessarily
        # ZERO — the ambiguous case. Counted, so a cache written before this change still
        # trends, but named below: an empty set here is indistinguishable from a round that
        # never got reviewed.
        rounds="$rounds $_n"; series="$series $_c"; n_rounds=$((n_rounds + 1))
        unrec="$unrec $_n"; n_unrec=$((n_unrec + 1))
      else
        notrev="$notrev$_n${TAB}unknown${TAB}unknown
"; n_notrev=$((n_notrev + 1))
      fi ;;
  esac
done

# ── the verdict ──────────────────────────────────────────────────────────────────
# Deliberately the SIMPLEST rule that separates the two cases, because it has to be
# explainable inside a needs-human message: "the last N REVIEWED rounds each produced at
# least one blocking finding". A least-squares slope would be defensible and unreadable.
#
# A converging PR (3 → 1 → 0) does not trip it: the last round is 0.
# PR #76 (1 3 1 2 1 3 …) trips it at round 3 and never stops tripping it.
verdict="converging"
if [ "$n_rounds" -lt "$WINDOW" ]; then
  verdict="insufficient"
else
  _tail="$(printf '%s\n' $series | tail -n "$WINDOW")"
  _allnz=1
  for _v in $_tail; do [ "$_v" -ge 1 ] || _allnz=0; done
  [ "$_allnz" -eq 1 ] && verdict="non-converging"
fi

# ── concentration ────────────────────────────────────────────────────────────────
# Where the findings are, across every round. The counts file already carries `.path`, so
# this is one jq pass over files the loop wrote anyway. It turns "split this PR" from advice
# into a pointer: on PR #76 the same grouping put 11 of 33 findings on ONE file that was
# 5.4% of the diff.
# Aggregate ONLY the rounds already validated above. Globbing every file back in means one
# malformed file makes the whole `jq -s` fail, `top` silently becomes empty, and the handoff
# says "split this PR" while naming no seams — losing the concentration data on exactly the
# report that exists to carry it. The per-round loop already excluded that file; the
# concentration pass must honour the same exclusion rather than re-deriving its own input.
#
# Concatenate inside a loop with each path QUOTED, rather than building one unquoted
# `$_readable` word list. `--cache` is caller-supplied and a `.pr-loop` dir under a path with a
# space in it (`/Users/me/My Repos/…`) is ordinary; an unquoted expansion split that single
# filename into several arguments, every `cat` failed, and `top` came back empty under the
# `|| true` — losing the seam list on exactly the non-converging handoff that exists to carry
# it, while the verdict still printed and looked fine. `$rounds` itself holds only digits
# (validated above), so word-splitting THAT is safe and intended.
top=""; n_paths=0
if [ -n "$rounds" ]; then
  _agg="$(for _rn in $rounds; do
            _f="$(_counts_file "$cache/round-$_rn")"
            [ -n "$_f" ] && cat "$_f" 2>/dev/null || true
          done)"
  top="$(printf '%s' "$_agg" | jq -r -s 'add // [] | map(.path // "(no path)") | group_by(.) | map({p:.[0], n:length})
              | sort_by(-.n) | .[:5] | .[] | "\(.n)\t\(.p)"' 2>/dev/null || true)"
  n_paths="$(printf '%s' "$_agg" | jq -r -s 'add // [] | map(.path // "(no path)") | unique | length' 2>/dev/null || true)"
  case "${n_paths:-}" in ''|*[!0-9]*) n_paths=0 ;; esac
fi

# ── which remedy the non-converging verdict is allowed to recommend ──────────────
# "SPLIT THIS PR" is the right advice for the 17,202-addition diff that motivated this tool.
# It is UNFOLLOWABLE advice on a small one, and unfollowable advice teaches operators to
# ignore the tool. Two runs are on the record: viernes-web PR #85 (2 files, ~150 lines, all
# four findings in ONE function) and E17-F04 (311 lines / 4 files, findings in one parse
# cascade — "trend verdict DISPUTED on the record", progress/history.md).
#
# The downgrade is only ever taken on PROOF, never on a guess: the caller must supply the
# diff width (`--diff-files`, e.g. from `tools/change-size.sh`) AND the findings must all sit
# in a single file. Without `--diff-files` the tool does not know how wide the diff is, so it
# keeps the split remedy — the pre-existing behaviour, unchanged.
remedy="split"
if [ "$n_paths" -le 1 ] && [ -n "$diff_files" ] && [ "$diff_files" -le "$CONCENTRATED_FILES" ]; then
  remedy="concentrate"
fi

# JSON string escaping for a path interpolated into --format json. A valid git filename may
# contain `"` or `\`; emitting one raw produces output that exits 0 and cannot be parsed — the
# worst shape for a machine interface. Same defect, same fix as tools/change-size.sh.
# Backslash first, or it would double-escape the quotes it just added.
_json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

_override_sevs_uniq="$(printf '%s\n' $override_sevs | sort -u | tr '\n' ' ' | sed -e 's/^ *//' -e 's/ *$//')"

if [ "$format" = json ]; then
  printf '{"verdict":"%s","rounds":%d,"window":%d,"series":[' "$verdict" "$n_rounds" "$WINDOW"
  _f=1; for _v in $series; do [ "$_f" = 1 ] || printf ','; printf '%s' "$_v"; _f=0; done
  printf '],"round_ids":['
  _f=1; for _v in $rounds; do [ "$_f" = 1 ] || printf ','; printf '%s' "$_v"; _f=0; done
  printf '],"not_reviewed":['
  _f=1
  printf '%s' "$notrev" | while IFS="$TAB" read -r _rn _oc _sr; do
    [ -n "${_rn:-}" ] || continue
    [ "$_f" = 1 ] || printf ','
    printf '{"round":%d,"outcome":"%s","source":"%s"}' "$_rn" "$_oc" "$_sr"; _f=0
  done
  printf '],"unrecorded_rounds":['
  _f=1; for _v in $unrec; do [ "$_f" = 1 ] || printf ','; printf '%s' "$_v"; _f=0; done
  printf '],"overrides":%d,"override_severities":[' "$overrides"
  _f=1; for _v in $_override_sevs_uniq; do [ "$_f" = 1 ] || printf ','; printf '"%s"' "$(_json_escape "$_v")"; _f=0; done
  printf '],"remedy":"%s","top_files":[' "$remedy"
  _f=1
  printf '%s\n' "$top" | while IFS="$TAB" read -r _n _p; do
    [ -n "${_p:-}" ] || continue
    [ "$_f" = 1 ] || printf ','
    printf '{"path":"%s","findings":%d}' "$(_json_escape "$_p")" "$_n"; _f=0
  done
  printf ']}\n'
  exit 0
fi

# ── text report ──────────────────────────────────────────────────────────────────
# The not-reviewed block prints FIRST and unconditionally when it is non-empty, even when
# there is no rate at all. A run that is failing to get reviewed is the finding.
_print_not_reviewed() {
  [ "$n_notrev" -gt 0 ] || return 0
  printf '  !! %d round(s) were NEVER REVIEWED and are not in the rate above:\n' "$n_notrev"
  printf '%s' "$notrev" | while IFS="$TAB" read -r _rn _oc _sr; do
    [ -n "${_rn:-}" ] || continue
    printf '       round %-3s %-10s (%s)\n' "$_rn" "$_oc" "$_sr"
  done
  printf '     A round that never got a review is not evidence of convergence, and it is not\n'
  printf '     a clean round either. If reviews are not landing, another round buys nothing\n'
  printf '     until that is fixed — check the Codex GitHub App, the watcher ceiling, and\n'
  printf '     tools/wait-for-codex.sh preflight before spending one.\n'
}

_print_unrecorded() {
  [ "$n_unrec" -gt 0 ] || return 0
  printf '  !! no outcome was recorded for round(s):%s\n' "$unrec"
  printf '     Their empty blocking set is indistinguishable from a round that never got\n'
  printf '     reviewed, so the verdict above may be optimistic. They are counted only\n'
  printf '     because this cache predates round-<n>/outcome; a loop that writes it has no\n'
  printf '     such ambiguity.\n'
}

if [ "$n_rounds" -eq 0 ]; then
  printf 'no reviewed round with a readable finding count under %s — nothing to trend\n' "$cache"
  _print_not_reviewed
  exit 0
fi

printf 'blocking findings per reviewed round (%s):\n' "$cache"
printf '  round '; for _r in $rounds; do printf '%4s' "$_r"; done; printf '\n'
printf '  count '; for _c in $series; do printf '%4s' "$_c"; done; printf '\n\n'
if [ "$overrides" -gt 0 ]; then
  printf '  %d of those findings were SEVERITY OVERRIDES (%s) — acted on although\n' \
    "$overrides" "$_override_sevs_uniq"
  printf '  pr_loop.blocking_severities excludes them. They are in the rate because they were\n'
  printf '  in the fix budget; the merge gate still reads the configured blocking.json.\n\n'
fi
case "$verdict" in
  insufficient)
    printf '  verdict: insufficient — fewer than %d REVIEWED rounds with a readable finding count.\n' "$WINDOW" ;;
  converging)
    printf '  verdict: converging — the finding rate is coming down. One more round is rational.\n' ;;
  non-converging)
    printf '  verdict: NON-CONVERGING — the last %d reviewed rounds each produced a blocking finding.\n' "$WINDOW"
    if [ "$remedy" = concentrate ]; then
      printf '\n  DO NOT SPLIT, and do not re-review. Every finding lands in ONE file of a\n'
      printf '  %s-file' "$diff_files"
      if [ -n "$diff_lines" ]; then printf '/%s-line' "$diff_lines"; fi
      printf ' diff, so there is no seam to cut along — splitting cannot separate\n'
      printf '  findings that are already in one place. A flat rate here means the round loop is\n'
      printf '  not converging on that one region: change its SHAPE (rewrite it, or hand the whole\n'
      printf '  set to a stronger worker in one combined pass) and re-open review only afterwards.\n'
    else
      printf '\n  SPLIT THIS PR. Do not re-review it. A flat rate means the reviewer is sampling a\n'
      printf '  surface larger than one pass can cover, so another round buys another sample, not\n'
      printf '  more confidence — and a clean round would be indistinguishable from a round that\n'
      printf '  happened to land somewhere quiet.\n'
    fi
    if [ -n "$top" ]; then
      if [ "$remedy" = concentrate ]; then
        printf '\n  findings concentrate here:\n'
      else
        printf '\n  findings concentrate here — cut along these seams:\n'
      fi
      printf '%s\n' "$top" | while IFS="$TAB" read -r _n _p; do
        [ -n "${_p:-}" ] || continue
        printf '    %3d  %s\n' "$_n" "$_p"
      done
    fi ;;
esac
printf '\n'
_print_not_reviewed
_print_unrecorded
exit 0
