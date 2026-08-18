#!/bin/sh
# run-tests.sh — run the harness suites concurrently and report only what failed. (E99)
#
# Two costs motivated this, both measured on this repo at 27 suites:
#
#   wall clock — the suites run serially in 634s. They do not share state: every one builds
#                its fixture under its own `mktemp` dir and sandboxes HOME and CODEX_HOME
#                per case, and none writes into state/, specs/, progress/ or telemetry.jsonl.
#                Run 8-wide they finish in 183s with all 27 still passing.
#
#   tokens     — the Reviewer runs this command EVERY round and reads the result. The serial
#                suites emit ~77KB (~19k tokens) of chatter on a fully GREEN run, 32KB of it
#                from test_install.sh's per-run installer warnings. A green run tells the
#                Reviewer exactly one thing, so on success this prints one summary line.
#                On failure it prints the failing suites' output IN FULL — the diagnostic is
#                the whole point, and truncating it to save tokens would be a false economy.
#
# THE SHELL THE SUITES RUN UNDER IS PART OF THE RESULT (E99-F135). Every suite here
# declares `#!/bin/sh`, and `sh` is a different program on different machines: bash in
# POSIX mode on macOS, dash on Debian/Ubuntu. So "all 42 suites passed" was a claim about
# the developer's machine that read like a claim about the code. Three environment-
# dependent greens in two days came from exactly that gap, and one of them was found by
# this change: `mk_sandbox_bin` in test_pr_loop.sh trusted `command -v env`, which dash
# resolves to the first NAME match even when it is not executable — GREEN under bash,
# exit 126 under dash, same tree.
#
# So the runner now (a) picks the STRICTEST SHELL IT CAN ACTUALLY PROBE and EXECUTES the
# suites under it, (b) parse-checks every suite AND every tool with `-n` first, and
# (c) PRINTS THE SHELL IT USED in the summary. (a) and (b) are both needed: `local`,
# `[[ ]]`, `echo -e` and arrays all PARSE fine under dash and fail at RUNTIME, so a parse
# gate alone would certify only that a file parses on Debian.
#
# Usage:
#   tools/run-tests.sh [--jobs N] [--serial] [suite...]
#
#   --jobs N   concurrency (default 8). N=1 is identical to --serial.
#   --serial   run one at a time; use when bisecting a suspected cross-suite interaction.
#   suite...   specific suites to run (default: every tests/test_*.sh)
#
# Exit codes:
#   0  every suite passed
#   1  at least one suite failed (its full output is on stderr)
#   3  a suite or tool did not PARSE under the strict shell (nothing was executed)
#   4  usage error / no suites found / malformed dash allowlist
#
# NOTE ON ISOLATION: concurrency here is a claim about the suites, not a wish. If a future
# suite starts writing to a shared path, it will fail intermittently under --jobs and pass
# under --serial. That asymmetry is the bug report: fix the suite's isolation rather than
# pinning the runner to serial, or the whole 3.5x goes away one suite at a time.

set -eu
LC_ALL=C; export LC_ALL

jobs=8
suites=""

usage() {
  printf 'usage: run-tests.sh [--jobs N] [--serial] [suite...]\n' >&2
  exit 4
}

while [ $# -gt 0 ]; do
  case "$1" in
    --jobs)   [ $# -ge 2 ] || usage
              case "$2" in ''|*[!0-9]*) usage ;; esac
              [ "$2" -ge 1 ] || usage
              jobs="$2"; shift 2 ;;
    --serial) jobs=1; shift ;;
    -h|--help) usage ;;
    -*) usage ;;
    *)  suites="$suites $1"; shift ;;
  esac
done

# ── grep-flavour probe (E99-F12) — WARN ONLY, once, before any suite runs ─────────────
#
# Every script here and most of the suites shell out to `grep`. On a machine where `grep`
# has been replaced — increasingly common, since it is a popular Homebrew/`cargo install`
# swap — local results can diverge from CI in a way NO SUITE HERE CAN CATCH, because the
# suites run under the same `grep` they would have to be testing. The cost is already on
# the record: two E99-F11 findings could not be reproduced or refuted locally, and both
# fixes shipped on documented `LC_ALL` semantics rather than on evidence.
#
# BEHAVIOURAL, NOT A VERSION STRING. The brand is a proxy; the divergence is the fact. A
# probe that feeds one invalid UTF-8 byte sequence through `grep` and demands the line back
# tests exactly what bites — and it costs one subprocess, needs no `--version` (some builds
# print it to stderr, some exit non-zero), and would also catch a future GNU/BSD regression
# that a name check would wave through. `--version` is read ONLY to make the message
# actionable, and its failure is silent.
#
# Run under the runner's own `LC_ALL=C`, which is the locale the suites actually see. The
# replacement that motivated this (ugrep 7.5.0) drops the line under every locale, C
# included, so this is not a locale misconfiguration the operator can dismiss.
#
# NEVER fails the run. A hard failure over a working `grep` would be a far worse false
# positive than the problem it reports, and a grep that cannot be found at all stays silent
# — the suites fail loudly on their own, and "your grep drops lines" would be a lie.
if command -v grep >/dev/null 2>&1; then
  # `if ... ; then` on the assignment: reads the same with or without `set -e`, and a grep
  # that exits non-zero here is itself a symptom, not a reason to abort the run.
  if _gf_n="$(printf 'a\303(b\n' | grep -c '' 2>/dev/null)"; then :; else _gf_n=""; fi
  if [ "$_gf_n" != "1" ]; then
    # `1{s/…/g;p;}`, NOT `1s/…/gp`: the `p` FLAG on an `s` command prints only when the
    # substitution actually matched, so a version line with no control characters — the
    # normal case — printed nothing and the warning silently lost its most useful half.
    if _gf_v="$(grep --version 2>/dev/null | sed -n '1{s/[[:cntrl:]]//g;p;}')"; then :; else _gf_v=""; fi
    _gf_sfx=""
    if [ -n "$_gf_v" ]; then _gf_sfx=" [reports: $_gf_v]"; fi
    printf '⚠️  grep (%s) drops lines containing invalid UTF-8 — it is neither GNU nor BSD grep, so suites here can pass or fail for reasons unrelated to the code (warn-only)%s\n' \
      "$(command -v grep)" "$_gf_sfx" >&2
    unset _gf_v _gf_sfx
  fi
  unset _gf_n
fi

# Resolve suites relative to the repo/harness root this script lives in, so the runner works
# from any cwd — the Reviewer does not always invoke it from the root.
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ -z "$suites" ]; then
  for s in "$root"/tests/test_*.sh; do
    [ -f "$s" ] || continue
    suites="$suites $s"
  done
fi

# shellcheck disable=SC2086
set -- $suites
[ $# -gt 0 ] || {
  printf 'run-tests: no suites found under %s/tests\n' "$root" >&2
  exit 4
}
total=$#

# ── the strictest shell we can actually PROBE (E99-F135) ──────────────────────────────
#
# A REAL PROBE, not an assumption and not a name on PATH: the candidate must execute a
# script and hand back its status, and it must accept `-n`. Anything that fails either
# test is not usable as the runner's shell no matter what it is called.
#
# Order is by strictness, not preference: dash and posh reject the bash extensions the
# suites must not rely on; `sh` is the floor — where it is bash (macOS) the run is weaker,
# which is exactly why the shell gets NAMED in the summary instead of being assumed.
strict_sh=""
for _cand in dash posh ash sh; do
  _p="$(command -v "$_cand" 2>/dev/null)" || _p=""
  [ -n "$_p" ] || continue
  _rc=0; "$_p" -c 'exit 41' 2>/dev/null || _rc=$?
  [ "$_rc" -eq 41 ] || continue                 # it did not run a script and return its status
  "$_p" -n /dev/null 2>/dev/null || continue    # it cannot parse-check, so the pre-flight is impossible
  strict_sh="$_p"
  break
done
[ -n "$strict_sh" ] || strict_sh="/bin/sh"      # never leave the runner without a shell

# fallback_sh — where an ALLOWLISTED suite runs. It must be a GENUINELY DIFFERENT, more
# permissive interpreter than `strict_sh`, or the exemption buys nothing and the report lies.
#
# Taking the host's `sh` unconditionally was wrong in both directions:
#   * macOS with no dash → strict_sh IS /bin/sh, so the warning read
#     "ran under /bin/sh, not /bin/sh" — a self-contradiction printed as a finding.
#   * Debian/Ubuntu → /bin/sh IS dash, so an allowlisted, genuinely dash-incompatible suite
#     still ran under dash and still failed, while being reported as exempt. The one host
#     where the exemption actually matters is the one where it did nothing.
#
# So prefer the shells that ACCEPT what dash rejects — bash, ksh, zsh — and compare by
# resolved identity, not by spelling: /bin/sh and /usr/bin/sh can be the same interpreter
# under two names, and a string compare would call them different.
_realsh() {                                     # resolve a shell path as far as we cheaply can
  _rs_p="$1"
  if command -v readlink >/dev/null 2>&1; then
    _rs_r="$(readlink -f "$_rs_p" 2>/dev/null)" || _rs_r=""
    [ -n "$_rs_r" ] && { printf '%s\n' "$_rs_r"; return 0; }
  fi
  printf '%s\n' "$_rs_p"
}
_strict_real="$(_realsh "$strict_sh")"
fallback_sh=""
for _fb in bash ksh zsh sh; do
  _p="$(command -v "$_fb" 2>/dev/null)" || _p=""
  [ -n "$_p" ] || continue
  [ "$(_realsh "$_p")" = "$_strict_real" ] && continue   # same interpreter ⇒ no exemption in it
  _rc=0; "$_p" -c 'exit 41' 2>/dev/null || _rc=$?
  [ "$_rc" -eq 41 ] || continue
  fallback_sh="$_p"
  break
done
# `fallback_sh` may legitimately end up EMPTY — a host whose only shell is the strict one.
# That is reported where the exemption is reported, never papered over: an exemption that
# cannot be honoured must not be counted as one.

# shell_ident <path> — an identification string for a shell, or NOTHING when none could be
# ESTABLISHED. It never guesses and never hardcodes: an invented version in the summary
# would be worse than the ambiguity this whole change exists to remove.
#
# dash has no `--version` on ANY platform (it exits non-zero with "Illegal option --"),
# which is why there are three probes and a silent give-up rather than one.
shell_ident() {
  _si_p="$1"; _si_out=""
  # 1. the usual suspect — answers for bash/ksh/zsh/busybox, never for dash.
  if _si_v="$("$_si_p" --version 2>/dev/null)"; then
    _si_out="$(printf '%s\n' "$_si_v" | sed -n '1{s/[[:cntrl:]]//g;p;}')"
  fi
  # 2. the SCCS marker, via what(1) — this is how the macOS /bin/dash identifies itself
  #    ("PROGRAM:dash PROJECT:dash-16"), since it has no --version.
  if [ -z "$_si_out" ] && command -v what >/dev/null 2>&1; then
    _si_out="$(what "$_si_p" 2>/dev/null | sed -n '2{s/^[[:space:]]*//;s/[[:space:]][[:space:]]*/ /g;s/[[:cntrl:]]//g;p;}')" || _si_out=""
  fi
  # 3. the package manager — on Debian/Ubuntu, the platform this gate exists for, dash has
  #    neither of the above but dpkg knows exactly which version it shipped.
  if [ -z "$_si_out" ] && command -v dpkg-query >/dev/null 2>&1; then
    _si_pkg="$(dpkg-query -S "$_si_p" 2>/dev/null | sed -n '1s/:.*//p')" || _si_pkg=""
    if [ -n "$_si_pkg" ]; then
      _si_out="$(dpkg-query -W -f='${Package} ${Version}' "$_si_pkg" 2>/dev/null)" || _si_out=""
    fi
  fi
  printf '%s' "$_si_out"
}
strict_id="$(shell_ident "$strict_sh")" || strict_id=""
[ -n "$strict_id" ] || strict_id="unidentified"

# ── the dash allowlist — NAMED exemptions only, and it can only shrink ────────────────
#
# One line per exemption in tests/dash-allowlist.txt, in exactly this shape:
#
#     # known-broken under dash: <suite> — <issue id>
#
# FAIL-CLOSED. A suite that is not named here runs under the strict shell, full stop; an
# entry that names no issue, or names a suite that does not exist, is a usage error rather
# than a silent exemption. The failure mode this guards is the UNNAMED skip: a suite that
# quietly stops running is the invisible-debt problem this feature exists to end, so the
# list is required to be readable, attributable, and pruned.
#
# An allowlisted suite is exempt from EXECUTING under dash. It is NOT exempt from the
# `-n` pre-flight below, and it still runs under the host `sh`.
#
# TWO DIFFERENT SCOPES, deliberately (Codex #153 r1 P2):
#
#   VALIDATION is FILE-WIDE. Every entry is parsed and checked against the disk no matter
#   which suites this invocation selected. A stale entry is a maintenance defect in the
#   list itself, so narrowing this to the selection would make it invisible to anyone
#   running a subset — the list could rot indefinitely and only a full run would say so.
#
#   EXEMPTION is SELECTION-SCOPED (computed below, once the selection is known). Warning
#   about or counting a suite that was never selected does not merely miscount: it prints
#   "ran under /bin/sh" about a suite that DID NOT RUN AT ALL. A false statement in the
#   one line this whole feature exists to make trustworthy is worse than the ambiguity it
#   set out to remove.
allow_file="$root/tests/dash-allowlist.txt"
allowed=""
if [ -f "$allow_file" ]; then
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in
      "# known-broken under dash:"*) ;;
      *) continue ;;
    esac
    _entry="${_line#\# known-broken under dash:}"
    case "$_entry" in
      *" — "*) ;;
      *) printf 'run-tests: malformed dash allowlist entry (no " — <issue id>"): %s\n' "$_line" >&2
         printf 'run-tests: required shape: # known-broken under dash: <suite> — <issue id>\n' >&2
         exit 4 ;;
    esac
    _a_suite="${_entry%% — *}"
    _a_issue="${_entry#* — }"
    # trim the surrounding spaces without leaning on a tool the caller may have stripped
    while :; do case "$_a_suite" in ' '*) _a_suite="${_a_suite# }" ;; *' ') _a_suite="${_a_suite% }" ;; *) break ;; esac; done
    while :; do case "$_a_issue" in ' '*) _a_issue="${_a_issue# }" ;; *' ') _a_issue="${_a_issue% }" ;; *) break ;; esac; done
    if [ -z "$_a_suite" ] || [ -z "$_a_issue" ]; then
      printf 'run-tests: dash allowlist entry names no suite or no issue id: %s\n' "$_line" >&2
      exit 4
    fi
    if [ ! -f "$root/tests/$_a_suite" ]; then
      printf 'run-tests: dash allowlist names a suite that does not exist: %s (prune it — the list may only shrink)\n' "$_a_suite" >&2
      exit 4
    fi
    allowed="$allowed $_a_suite"
  done < "$allow_file"
fi

# The exemption set: the allowlist INTERSECTED with the suites this run actually selected.
# Everything downstream — which interpreter each child uses, the warning, the count — reads
# `exempt`, never `allowed`, so nothing can be reported about a suite that never ran.
exempt=""
if [ -n "$allowed" ]; then
  for _s in "$@"; do
    _sb="$(basename "$_s")"
    case " $allowed " in
      *" $_sb "*)
        case " $exempt " in
          *" $_sb "*) ;;                        # a suite named twice is still one exemption
          *) exempt="$exempt $_sb" ;;
        esac ;;
    esac
  done
fi

# ── `-n` pre-flight, over EVERY suite in this run AND every tool ──────────────────────
#
# Nearly free, and it catches the whole parse-error class at the cheapest possible point —
# before a single suite has run, so a syntax error is reported as a syntax error instead of
# as 40 confusing failures. It covers ALLOWLISTED suites too: an exemption from executing
# under dash is not an exemption from parsing under it.
#
# tools/*.sh are included because a parse error in a TOOL is WORSE than one in a test. A
# test fails loudly; a tool that dies mid-run takes a caller's behavior with it, quietly.
preflight_bad=""
for _f in "$@" "$root"/tools/*.sh; do
  [ -f "$_f" ] || continue
  if _pf_err="$("$strict_sh" -n "$_f" 2>&1)"; then :; else
    preflight_bad="$preflight_bad $(basename "$_f")"
    {
      printf '\n===== PARSE FAILED under %s: %s =====\n' "$strict_sh" "$_f"
      printf '%s\n' "$_pf_err"
    } >&2
  fi
done
if [ -n "$preflight_bad" ]; then
  printf '\nrun-tests: %s -n pre-flight FAILED (nothing was executed):%s\n' \
    "$strict_sh" "$preflight_bad" >&2
  exit 3
fi

work="$(mktemp -d)" || { printf 'run-tests: mktemp failed\n' >&2; exit 4; }
trap 'rm -rf "$work"' EXIT INT TERM

# The suites shell out to the TOOLS as `sh tools/foo.sh`, which resolves through PATH — so
# without this the tools would keep running under the host `sh` no matter what the suites
# run under, and a runtime bashism in a tool would stay invisible. A PATH-first `sh` that
# execs the strict shell closes that gap: on Debian it is a no-op (sh IS dash), on macOS it
# makes the tools face what Debian users' tools already face.
#
# BEST-EFFORT ON PURPOSE. It needs `chmod`, and one suite deliberately runs this runner
# with a PATH stripped to a handful of utilities; failing there would break a legitimate
# test over an optimization. If the shim cannot be built, the suites still run under the
# strict shell and only the tool-level coverage is lost.
shim=""
if [ "$strict_sh" != "$fallback_sh" ]; then
  if mkdir -p "$work/shim" 2>/dev/null \
     && printf '#!/bin/sh\nexec %s "$@"\n' "$strict_sh" >"$work/shim/sh" 2>/dev/null \
     && chmod +x "$work/shim/sh" 2>/dev/null; then
    shim="$work/shim"
  fi
fi

# One child per suite, throttled by xargs -P. Each writes its own log and its own rc file,
# so nothing is interleaved and nothing is lost. `xargs` exit status is deliberately ignored
# (`|| true`): a non-zero child would abort the batch early and hide the other results — the
# rc files below are the source of truth for pass/fail.
#
# Each child picks its own shell: the strict one, or — for a NAMED allowlist entry only —
# the host `sh`. The shim goes on PATH for strict runs so the tools follow the suite.
printf '%s\n' "$@" | xargs -P "$jobs" -I _SUITE_ sh -c '
  suite="$1"; work="$2"; strict="$3"; fallback="$4"; allow="$5"; shim="$6"
  base="$(basename "$suite")"
  run="$strict"
  case " $allow " in
    # An empty `fallback` means no interpreter on this host is more permissive than the
    # strict one, so there is nothing to be exempt INTO — run under the strict shell and let
    # the result stand. The summary reports the exemption as not honoured rather than
    # silently claiming a leniency that was never applied.
    *" $base "*) [ -z "$fallback" ] || run="$fallback" ;;
    *) [ -z "$shim" ] || { PATH="$shim:$PATH"; export PATH; } ;;
  esac
  if "$run" "$suite" >"$work/$base.log" 2>&1; then
    echo 0 >"$work/$base.rc"
  else
    echo $? >"$work/$base.rc"
  fi
' _ _SUITE_ "$work" "$strict_sh" "$fallback_sh" "$exempt" "$shim" || true

failed=0
failed_names=""
for suite in "$@"; do
  base="$(basename "$suite")"
  rc=1
  [ -f "$work/$base.rc" ] && rc="$(cat "$work/$base.rc")"
  # A suite that produced no rc file never ran (killed, or xargs aborted the batch). That is
  # a failure: silence must not read as success.
  if [ "$rc" -ne 0 ]; then
    failed=$((failed + 1))
    failed_names="$failed_names $base"
    {
      printf '\n===== FAILED (rc=%s): %s =====\n' "$rc" "$base"
      [ -f "$work/$base.log" ] && cat "$work/$base.log"
    } >&2
  fi
done

# An exemption is never allowed to be invisible: if anything ran under the host shell
# instead of the strict one, it is named, every run, on stderr...
exempt_note=""
if [ -n "$exempt" ] && [ -z "$fallback_sh" ]; then
  # The exemption could NOT be honoured: this host has no interpreter more permissive than
  # the strict one, so the suite ran under the strict shell anyway. Saying "exempt" here
  # would claim a leniency that was never applied — and on the host where `sh` IS dash that
  # is precisely the case where an allowlisted suite still fails. Report the truth and count
  # nothing; the suite's own result already stands on its own.
  printf '⚠️  exemption NOT honoured (no shell on this host is more permissive than %s, so these ran under it anyway):%s — see %s\n' \
    "$strict_sh" "$exempt" "$allow_file" >&2
elif [ -n "$exempt" ]; then
  printf '⚠️  exempt from the dash gate (ran under %s, not %s):%s — see %s\n' \
    "$fallback_sh" "$strict_sh" "$exempt" "$allow_file" >&2
  # ...and COUNTED in the summary itself, on stdout. The warning above is on stderr, and a
  # caller that captures only stdout would otherwise read "all N suites passed (/bin/dash)"
  # while some of those N never faced dash at all — the exact invisible skip this list is
  # supposed to prevent.
  _n_exempt=0
  for _e in $exempt; do _n_exempt=$((_n_exempt + 1)); done
  exempt_note="$(printf ', %d exempt' "$_n_exempt")"
fi

# THE SUMMARY NAMES THE SHELL. "all 42 suites passed" is ambiguous precisely because `sh`
# is a different program on different machines; naming the shell and its identification
# turns the same run into a claim someone else can act on.
if [ "$failed" -eq 0 ]; then
  printf 'all %d suites passed (%s [%s], --jobs %d%s)\n' \
    "$total" "$strict_sh" "$strict_id" "$jobs" "$exempt_note"
  exit 0
fi

printf '\n%d of %d suites FAILED under %s [%s]:%s\n' \
  "$failed" "$total" "$strict_sh" "$strict_id" "$failed_names" >&2
exit 1
