#!/bin/sh
# harness-report.sh — file ONE allow-listed harness-feedback report upstream (E32-F02).
#
# The caller is E32-F03's reporting rule; F04 (the labeler) and F05 (triage) consume the
# marker this tool writes. Automatic filing runs with no human review, so the privacy
# contract lives here, in one auditable place:
#
#   THE ALLOW-LIST IS THE GUARANTEE, REDACTION IS A SECOND LAYER.
#   Every outbound field (title, body, duplicate-search query) is built ONLY from values
#   that passed a fixed allow-list (enum, grammar, or harness ownership). Free-form text
#   (--notes-file) is never an input to the title, body, or search query; it lives only in
#   the local progress/feedback/ copy. The corpus redaction pass (R8) runs afterward.
#
# THE TOOL NEVER FAILS THE CALLER. Missing --trigger/--symptom, an out-of-allow-list value,
# a duplicate, a capped or tokenless session, a non-semver VERSION, a missing/unauthenticated/
# erroring `gh` — every one exits 0 and, where R11 applies, writes the local copy. There is
# NO non-zero operational exit path.
#
# Usage:
#   harness-report.sh
#     --trigger   <harness-malfunction|contradictory-instruction|workaround|missing-capability>
#     --symptom   <one of the nine fixed symptom codes>
#     [--file     <harness-relative-path>]...        # repeatable; only accepted ones are used
#     [--command  <harness command name>]            # semantic allow-list (R4)
#     [--exit-code <n>]                              # [0-9]{1,3}
#     [--role     <enumerated role>]
#     [--phase    <enumerated phase>]
#     [--session-id <token>]                         # [A-Za-z0-9._-]{1,64};
#                                                    # env HARNESS_FEEDBACK_SESSION_ID also read
#     [--notes-file <path>]                          # free-form; LOCAL COPY ONLY
#   harness-report.sh redact                         # stdin -> redacted stdout (R8), exit 0
#
# Which test pins each guarantee:
#   R1 marker grammar ............ test_feedback_report.sh::test_marker_grammar
#   R2 disabled silent ........... test_feedback_report.sh::test_disabled_is_silent
#   R3 repo resolution ........... test_feedback_report.sh::test_repo_resolution
#   R4 field allow-list .......... test_feedback_report.sh::test_field_allowlist_rejects
#   R5 harness-owned files ....... test_feedback_report.sh::test_harness_owned_file_filter
#   R6 title format .............. test_feedback_report.sh::test_title_format
#   R7 body allow-list ........... test_feedback_report.sh::test_body_allowlisted_no_freeform
#   R8 redaction corpus .......... test_feedback_report.sh::test_redaction_corpus
#   R9 duplicate search .......... test_feedback_report.sh::test_duplicate_skips_create
#   R10 session cap .............. test_feedback_report.sh::test_session_cap
#   R11 local copy / fallback .... test_feedback_report.sh::test_local_copy_and_fallback
#   R12 shipping artifacts ....... test_feedback_report.sh::test_shipping_artifacts
#
# POSIX sh, dash-clean (tools/run-tests.sh parse-checks this file with the strict shell).

set -eu
LC_ALL=C
export LC_ALL

# ── governing harness dir (ADR-0004) ─────────────────────────────────────────────────────
# <repo-root>/tools/harness-report.sh in the source layout; <target>/.harness/tools/…
# installed. This is F01's "governing harness dir" (R3, R11), the same convention as
# tools/change-size.sh. Config, the local fallback, the session ledger and the ownership
# authority all resolve relative to it — never the umbrella's.
H="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"

# Project root and the harness-relative prefix (R5): a target's body lives under .harness/,
# the source layout's body IS the repo root.
case "$H" in
  */.harness) _pfx=".harness/"; _proj="${H%/*}" ;;
  *)           _pfx="";          _proj="$H" ;;
esac

# ── redaction corpus (R8) ────────────────────────────────────────────────────────────────
# The fixed corpus from E32-F02.plan.md. Order matters: token shapes first, then emails,
# then named-prefix absolute paths. The FIRST line is preserved byte-exact when it is the
# R1 marker — a corpus collision with an allow-listed marker field (a token-shaped host,
# say) must never rewrite the sole reporter↔triage contract. Pinned by
# test_redaction_corpus's marker-preservation control.
redact_stream() {
  awk '
    function scrub(line) {
      gsub(/gh[pousr]_[A-Za-z0-9]+/, "[REDACTED-SECRET]", line)
      gsub(/github_pat_[A-Za-z0-9_]+/, "[REDACTED-SECRET]", line)
      gsub(/sk-[A-Za-z0-9_-]+/, "[REDACTED-SECRET]", line)
      gsub(/AKIA[A-Z0-9]{16}/, "[REDACTED-SECRET]", line)
      gsub(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+/, "[REDACTED-EMAIL]", line)
      gsub(/\/(home|Users|tmp|private)\/[^[:space:]]+/, "[REDACTED-PATH]", line)
      return line
    }
    NR == 1 && $0 ~ /^<!-- harness-feedback:v1 / { print; next }
    { print scrub($0) }
  '
}

# ── redact mode (R8) — the same pass, exposed on stdin/stdout ────────────────────────────
if [ "${1:-}" = "redact" ]; then
  redact_stream
  exit 0
fi

# ── defaults ─────────────────────────────────────────────────────────────────────────────
DEFAULT_REPO="github.com/araozmd/harness-sdd"
CFG="$H/harness.config.yaml"

_trigger=""; _symptom=""; _role=""; _phase=""; _command=""; _exit_code=""
_notes_file=""; _session_arg=""; _files_raw=""

# ── argument parser ──────────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --trigger)   shift; if [ $# -gt 0 ]; then _trigger="$1";   shift; fi ;;
    --symptom)   shift; if [ $# -gt 0 ]; then _symptom="$1";   shift; fi ;;
    --role)      shift; if [ $# -gt 0 ]; then _role="$1";      shift; fi ;;
    --phase)     shift; if [ $# -gt 0 ]; then _phase="$1";     shift; fi ;;
    --command)   shift; if [ $# -gt 0 ]; then _command="$1";   shift; fi ;;
    --exit-code) shift; if [ $# -gt 0 ]; then _exit_code="$1"; shift; fi ;;
    --session-id) shift; if [ $# -gt 0 ]; then _session_arg="$1"; shift; fi ;;
    --notes-file) shift; if [ $# -gt 0 ]; then _notes_file="$1"; shift; fi ;;
    --file)      shift; if [ $# -gt 0 ]; then _files_raw="$_files_raw$1
"; shift; fi ;;
    *)           shift ;;
  esac
done

# ── config resolution, F01 contract verbatim (R2, R3, R10) ───────────────────────────────
# Top-level `feedback:` section only; trailing `# comment` stripped. Quotes are NOT
# stripped: F01's contract says a quoted "true" is OFF and a quoted/odd repo is malformed.
_cfg_feedback() { # _cfg_feedback <file> <key>
  [ -f "$1" ] || return 0
  awk -v k="$2" '
    BEGIN { re = "^[[:space:]]+" k ":" }
    /^feedback:[[:space:]]*(#.*)?$/ { f = 1; next }
    f && /^[^[:space:]#]/ { f = 0 }
    f && $0 ~ re {
      sub(/^[[:space:]]+[^:]*:[[:space:]]*/, "")
      sub(/[[:space:]]*#.*$/, "")
      sub(/[[:space:]]+$/, "")
      print; exit
    }
  ' "$1"
}

# R2: only the bare, unquoted, lower-case token `true` enables. Anything else (missing
# block/key, empty, "true", True) is OFF: no gh invocation, no report file, exit 0.
_enabled="$(_cfg_feedback "$CFG" enabled)"
if [ "$_enabled" != "true" ]; then
  exit 0
fi

# R3: [HOST/]OWNER/REPO — 2 or 3 parts of [A-Za-z0-9._-]+. Missing/empty resolves to the
# shipped default; anything else (scheme, empty part, 4+ parts, other chars) is malformed
# and turns reporting OFF exactly as R2 (no gh, no report file, exit 0).
_repo_raw="$(_cfg_feedback "$CFG" repo)"
if [ -z "$_repo_raw" ]; then
  _repo_raw="$DEFAULT_REPO"
fi
_repo_resolved="$(
  printf '%s' "$_repo_raw" | awk -F/ '
    NF < 2 || NF > 3 { exit 1 }
    { for (i = 1; i <= NF; i++) if ($i == "" || $i !~ /^[A-Za-z0-9._-]+$/) exit 1 }
    { if (NF == 2) print "github.com", $1, $2; else print $1, $2, $3 }
  '
)" || _repo_resolved=""
if [ -z "$_repo_resolved" ]; then
  exit 0
fi
_host="${_repo_resolved%% *}"
_rest="${_repo_resolved#* }"
_owner="${_rest%% *}"
_name="${_rest#* }"

# R10: non-negative integer; missing/invalid resolves to 3; 0 files nothing upstream.
_max_raw="$(_cfg_feedback "$CFG" max_per_session)"
case "$_max_raw" in
  ''|*[!0-9]*) _max=3 ;;
  *)           _max="$(printf '%s' "$_max_raw" | sed 's/^0*//')"
               [ -n "$_max" ] || _max=0 ;;
esac

# ── allow-list validators (R4) ───────────────────────────────────────────────────────────
_valid_trigger() {
  case "$1" in
    harness-malfunction|contradictory-instruction|workaround|missing-capability) return 0 ;;
    *) return 1 ;;
  esac
}
_valid_symptom() {
  case "$1" in
    init-failure|install-failure|tool-failure|board-write-failure|gate-unsatisfiable) return 0 ;;
    instruction-conflict|doc-conflict|workflow-gap|state-corruption) return 0 ;;
    *) return 1 ;;
  esac
}
_valid_role() {
  case "$1" in
    orchestrator|architect|builder|builder-heavy|reviewer|scout) return 0 ;;
    driller|fixer|planner|inception|doc-critic|pr-fixer) return 0 ;;
    *) return 1 ;;
  esac
}
_valid_phase() {
  case "$1" in
    inception|architect|builder|reviewer|scout|slice-dispatch|handoff|install) return 0 ;;
    *) return 1 ;;
  esac
}
_valid_exit_code() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 3 ]
}
# R4's `--command` is a SEMANTIC allow-list: the name must resolve to something the
# installed body ships, so a project-specific token cannot ride the field upstream.
# Accepts a basename of a regular file under $H/tools/, init.sh, harness-install.sh, or a
# shipped sdd-* unit in the body.
_valid_command() {
  _c="$1"
  case "$_c" in */*) return 1 ;; esac
  if [ -f "$H/tools/$_c" ]; then return 0; fi
  case "$_c" in
    init.sh|harness-install.sh)
      if [ -f "$H/$_c" ]; then return 0; fi ;;
  esac
  case "$_c" in sdd-*) : ;; *) return 1 ;; esac
  if [ -d "$_proj/.agents/skills/$_c" ]; then return 0; fi
  if [ -f "$_proj/.claude/commands/$_c.md" ]; then return 0; fi
  if [ -f "$_proj/.opencode/command/$_c.md" ]; then return 0; fi
  return 1
}
_valid_session() {
  case "$1" in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# Resolve the harness version. Source layout ships VERSION at the harness root; an
# installed target has no VERSION file — it carries the stamp .harness/.harness-version,
# which holds the same bytes (R1). Either way the field's [0-9]+.[0-9]+.[0-9]+ grammar
# gates the marker; a non-semver value files nothing.
_resolve_version() {
  if [ -f "$H/VERSION" ]; then
    sed -n '1{s/[[:space:]]*$//;p;}' "$H/VERSION"
  elif [ -f "$H/.harness-version" ]; then
    sed -n '1{s/[[:space:]]*$//;p;}' "$H/.harness-version"
  fi
}
_is_semver() {
  printf '%s' "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'
}

# ── working dir (temp body/listing) under the local feedback dir ─────────────────────────
_wk=""
_cleanup() { if [ -n "$_wk" ]; then rm -rf "$_wk" 2>/dev/null || true; fi; }
trap _cleanup EXIT INT TERM HUP

_make_work() {
  [ -n "$_wk" ] && return 0
  mkdir -p "$H/progress/feedback" 2>/dev/null || return 1
  _wk="$H/progress/feedback/.report-tmp.$$"
  (umask 077 && mkdir -p "$_wk") 2>/dev/null || { _wk=""; return 1; }
  return 0
}

# ── harness-owned file validation (R5) ───────────────────────────────────────────────────
# Normalise to a harness-relative path, then accept it only when the ownership authority +
# `git ls-files --cached --others --exclude-standard` report the project-relative form as
# part of the harness body. Absolute paths, `..` escapes and project-owned paths are
# dropped; if none is accepted, no upstream issue is created (R5's local-only branch).
_file_ok() {
  _c="$1"
  case "/$_c/" in *"/../"*) return 1 ;; esac
  printf '%s' "$_c" | grep -qE '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$'
}

_prepare_listing() {
  _listing="$_wk/listing"
  : > "$_listing"
  "$H/tools/harness-owned-paths.sh" body "$H" > "$_wk/pathspecs" 2>/dev/null || true
  set --
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    set -- "$@" "$_p"
  done < "$_wk/pathspecs"
  if [ "$#" -gt 0 ] && command -v git >/dev/null 2>&1; then
    git -C "$_proj" ls-files --cached --others --exclude-standard -z -- "$@" 2>/dev/null \
      | tr '\000' '\n' > "$_listing" || true
  fi
}

# ── validation: collect accepted fields, mark the report rejected on any violation ───────
_reject=""
_setreject() { [ -n "$_reject" ] || _reject="$1"; }

_a_trigger=""; _a_symptom=""; _a_role=""; _a_phase=""; _a_command=""; _a_exit=""
_a_ver=""; _files=""

if [ -z "$_trigger" ] || ! _valid_trigger "$_trigger"; then
  _setreject trigger
else
  _a_trigger="$_trigger"
fi
if [ -z "$_symptom" ] || ! _valid_symptom "$_symptom"; then
  _setreject symptom
else
  _a_symptom="$_symptom"
fi
if [ -n "$_role" ]; then
  if _valid_role "$_role"; then _a_role="$_role"; else _setreject role; fi
fi
if [ -n "$_phase" ]; then
  if _valid_phase "$_phase"; then _a_phase="$_phase"; else _setreject phase; fi
fi
if [ -n "$_exit_code" ]; then
  if _valid_exit_code "$_exit_code"; then _a_exit="$_exit_code"; else _setreject exit-code; fi
fi
if [ -n "$_command" ]; then
  if _valid_command "$_command"; then _a_command="$_command"; else _setreject command; fi
fi

_a_ver="$(_resolve_version)" || _a_ver=""

# File validation costs a git call, so skip it once the report is already rejected.
if [ -z "$_reject" ]; then
  if [ -n "$_files_raw" ] && _make_work && _prepare_listing; then
    printf '%s\n' "$_files_raw" | while IFS= read -r _cand; do
      [ -n "$_cand" ] || continue
      _file_ok "$_cand" || continue
      grep -qxF -- "$_pfx$_cand" "$_listing" 2>/dev/null || continue
      printf '%s\n' "$_cand"
    done > "$_wk/accepted" || true
    _files="$(cat "$_wk/accepted" 2>/dev/null)" || _files=""
  fi
  if [ -z "$_files" ]; then
    _setreject file
  fi
  if ! _is_semver "$_a_ver"; then
    _setreject version
  fi
fi

# ── local report writer (R11) ────────────────────────────────────────────────────────────
# For every enabled report — filed or not — write progress/feedback/<timestamp>.md with the
# accepted structured fields and the free-form notes verbatim. Collisions within one second
# get -2, -3, … suffixes (tests call the tool repeatedly in the same second).
_ts=""
write_local_copy() {
  _dir="$H/progress/feedback"
  mkdir -p "$_dir" 2>/dev/null || true
  if [ -z "$_ts" ]; then
    _ts="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null)" || _ts="0"
    [ -n "$_ts" ] || _ts="0"
  fi
  _f="$_dir/$_ts.md"
  _n=2
  while [ -e "$_f" ]; do
    _f="$_dir/$_ts-$_n.md"
    _n=$((_n + 1))
  done
  {
    printf '# Harness feedback report\n\n'
    printf 'Outcome: %s\n' "$_outcome"
    if [ -n "${_reason:-}" ]; then printf 'Reason: %s\n' "$_reason"; fi
    printf 'Timestamp: %s\n' "$_ts"
    if [ -n "$_host" ]; then printf 'Repo: %s/%s/%s\n' "$_host" "$_owner" "$_name"; fi
    if [ -n "$_a_ver" ];            then printf 'Harness version: %s\n' "$_a_ver"; fi
    if [ -n "$_a_trigger" ];        then printf 'Trigger: %s\n' "$_a_trigger"; fi
    if [ -n "$_a_symptom" ];        then printf 'Symptom: %s\n' "$_a_symptom"; fi
    if [ -n "$_files" ]; then
      printf '%s\n' "$_files" | while IFS= read -r _ff; do
        [ -n "$_ff" ] || continue
        printf 'File: %s\n' "$_ff"
      done
    fi
    if [ -n "$_a_command" ];        then printf 'Command: %s\n' "$_a_command"; fi
    if [ -n "$_a_exit" ];           then printf 'Exit code: %s\n' "$_a_exit"; fi
    if [ -n "$_a_role" ];           then printf 'Role: %s\n' "$_a_role"; fi
    if [ -n "$_a_phase" ];          then printf 'Phase: %s\n' "$_a_phase"; fi
    if [ -n "$_session_arg" ];      then printf 'Session: %s\n' "$_session_arg"; fi
    printf '\nNotes:\n'
  } > "$_f" 2>/dev/null || true
  if [ -n "$_notes_file" ] && [ -f "$_notes_file" ]; then
    cat "$_notes_file" >> "$_f" 2>/dev/null || true
  fi
  printf '\n' >> "$_f" 2>/dev/null || true
}

_finish() { # _finish <outcome> [reason]
  _outcome="$1"
  _reason="${2:-}"
  write_local_copy
  exit 0
}

# R4/R5/R1: any rejected/missing field, no accepted harness file, or a non-semver VERSION
# means no upstream issue — the local report records the struct fields, exit 0.
if [ -n "$_reject" ]; then
  _finish rejected "$_reject"
fi

# ── session identity (R10) ───────────────────────────────────────────────────────────────
_session="${_session_arg:-${HARNESS_FEEDBACK_SESSION_ID:-}}"
if ! _valid_session "$_session"; then
  _finish no-session
fi

# ── per-session cap (R10) ─────────────────────────────────────────────────────────────────
_ledger="$H/progress/feedback/.session-count"
_created=0
if [ -s "$_ledger" ]; then
  _lses="$(sed -n '1{s/ .*//;p;}' "$_ledger" 2>/dev/null)" || _lses=""
  _lcnt="$(sed -n '1{s/^[^ ]* //;p;}' "$_ledger" 2>/dev/null)" || _lcnt=""
  if [ "$_lses" = "$_session" ]; then
    case "$_lcnt" in
      ''|*[!0-9]*) _created=0 ;;
      *)           _created="$_lcnt" ;;
    esac
  fi
fi
if [ "$_created" -ge "$_max" ]; then
  _finish capped
fi

# ── upstream: gh present, authenticated on the resolved host (R3, R11) ────────────────────
if ! command -v gh >/dev/null 2>&1; then
  _finish fallback no-gh
fi
if ! gh auth status --hostname "$_host" >/dev/null 2>&1; then
  _finish fallback gh-auth
fi

# ── duplicate search (R9) ─────────────────────────────────────────────────────────────────
# Query is built ONLY from the R6 fixed title, scoped to the title field. `gh --search` is
# full-text, so it is a candidate filter: the report is a duplicate only when a returned
# title EQUALS the fixed title exactly (client-side comparison) — a mere mention must not
# suppress a distinct report.
_first_file="$(printf '%s\n' "$_files" | sed -n '1p')"
_title="[harness-feedback] $_a_trigger $_a_symptom in $_first_file"
_search="in:title $_title"

if _list_out="$(GH_HOST="$_host" gh issue list --repo "$_owner/$_name" --state open \
      --search "$_search" --json number,title --limit 50 2>/dev/null)"; then
  :
else
  _finish fallback gh-list
fi
_titles=""
if [ -n "$_list_out" ]; then
  _titles="$(printf '%s' "$_list_out" | tr -d '\n' \
    | grep -o '"title"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null \
    | sed 's/^"title"[[:space:]]*:[[:space:]]*"//; s/"$//')" || _titles=""
fi
if [ -n "$_titles" ]; then
  if printf '%s\n' "$_titles" | grep -qxF -- "$_title"; then
    _finish duplicate
  fi
fi

# ── assemble the upstream body (R1, R6, R7), redact label lines (R8), create (R9) ────────
if ! _make_work; then
  _finish fallback no-workdir
fi
_marker="<!-- harness-feedback:v1 host=$_host version=$_a_ver trigger=$_a_trigger -->"
_body_raw="$_wk/body.raw"
{
  printf '%s\n' "$_marker"
  printf 'Harness version: %s\n' "$_a_ver"
  printf 'Trigger: %s\n' "$_a_trigger"
  printf 'Symptom: %s\n' "$_a_symptom"
  printf '%s\n' "$_files" | while IFS= read -r _ff; do
    [ -n "$_ff" ] || continue
    printf 'File: %s\n' "$_ff"
  done
  if [ -n "$_a_command" ]; then printf 'Command: %s\n' "$_a_command"; fi
  if [ -n "$_a_exit" ];    then printf 'Exit code: %s\n' "$_a_exit"; fi
  if [ -n "$_a_role" ];    then printf 'Role: %s\n' "$_a_role"; fi
  if [ -n "$_a_phase" ];   then printf 'Phase: %s\n' "$_a_phase"; fi
} > "$_body_raw" 2>/dev/null || true
_body_red="$_wk/body.redacted"
redact_stream < "$_body_raw" > "$_body_red" 2>/dev/null || true

if GH_HOST="$_host" gh issue create --repo "$_owner/$_name" --title "$_title" \
     --body-file "$_body_red" >/dev/null 2>&1; then
  _created=$((_created + 1))
  printf '%s %s\n' "$_session" "$_created" > "$_ledger" 2>/dev/null || true
  _finish filed
else
  _finish fallback gh-create
fi
