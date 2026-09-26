#!/bin/sh
# .github/scripts/feedback-labeler.sh — E32-F04 source-repo labeler for marker-carrying
# issues. POSIX sh, dash-clean. Source-only (ADR-0005): never installed, never emitted.
#
# The marker grammar below is copied VERBATIM from E32-F02 (the marker's only writer and the
# grammar's authority per ADR-0006). Do NOT re-derive it here.
#
#   ^<!-- harness-feedback:v1 host=[A-Za-z0-9._-]+ version=[0-9]+\.[0-9]+\.[0-9]+ \
#     trigger=(harness-malfunction|contradictory-instruction|workaround|missing-capability) -->$
#
# Modes:
#   parse <body-file>     classify a body offline; prints the label set (one name per line:
#                         `harness-feedback` then the category label) or nothing at all.
#                         Exit 0 in every classification case (empty output = not a report).
#   label-issue <number>  read the opened-event body snapshot (GITHUB_EVENT_PATH) into a
#                         file, parse it, ensure the labels exist, and add them in one
#                         `gh issue edit` call. Actions always sets GITHUB_EVENT_PATH; a
#                         local run with no event payload falls back to the GitHub API.
#                         Exit 0 when it labels or deliberately no-ops; non-zero only when a
#                         required read/`gh` operation fails, so it shows in the Action log.
#
# Security posture (ADR-0006): the first body line is the ONLY classification input. No byte
# of the body is ever sourced, eval'd, passed to `sh -c`, or interpolated into a `gh` argv;
# the body reaches the parser only as a file written from the opened-event payload snapshot
# (or, when no event payload exists, from the API) — never as a shell word.

set -eu
LC_ALL=C
export LC_ALL

# The strict R4 grammar (F02's `harness-feedback:v1` marker), anchored at both ends.
# shellcheck disable=SC2034
MARKER_RE='^<!-- harness-feedback:v1 host=[A-Za-z0-9._-]+ version=[0-9]+\.[0-9]+\.[0-9]+ trigger=(harness-malfunction|contradictory-instruction|workaround|missing-capability) -->$'

usage() {
  printf 'usage: %s parse <body-file> | label-issue <issue-number>\n' "$0" >&2
}

# parse_body <body-file> — print the label set for a marker-carrying body, or nothing.
parse_body() {
  _pb_file="${1:-}"
  [ -n "$_pb_file" ] || return 0
  [ -f "$_pb_file" ] || return 0

  _pb_first="$(sed -n '1p' "$_pb_file")" || _pb_first=""
  [ -n "$_pb_first" ] || return 0

  # Whole-string, anchored match against the single first line. This is NOT a line-based
  # charset guard: `sed -n '1p'` yields one line by construction, so the `^...$` match is
  # total. (E32-F02 F5 paid for the line-oriented version of this check.)
  printf '%s\n' "$_pb_first" | grep -qE "$MARKER_RE" || return 0

  # Exactly one marker: no `harness-feedback:` token may appear after line 1. The anchored
  # first-line match already forbids extra content on line 1, so this makes "exactly one"
  # total. (Extract, then compare — never a whole-file `grep -c` alone.)
  if sed -n '2,$p' "$_pb_file" | grep -qF 'harness-feedback:'; then
    return 0
  fi

  # Extract the trigger from the VALIDATED first line (trust-on-validated-input): the
  # anchored grammar above has already restricted it to the four-value vocabulary, so this
  # capture needs no second membership check. (host/version charsets cannot contain a space,
  # so the first ` trigger=` is the field separator.)
  _pb_trigger="$(printf '%s\n' "$_pb_first" | sed -n 's/^.* trigger=\([^ ]*\) -->$/\1/p')"
  [ -n "$_pb_trigger" ] || return 0

  _pb_cat=bug
  case "$_pb_trigger" in
    missing-capability) _pb_cat=enhancement ;;
  esac

  printf '%s\n' 'harness-feedback'
  printf '%s\n' "$_pb_cat"
  return 0
}

# Fixed color/description values, used ONLY when creating a missing label (R8). An existing
# label is never created, updated, or otherwise touched.
label_color() {
  case "$1" in
    harness-feedback) printf '%s' '5319e7' ;;
    bug)              printf '%s' 'd73a4a' ;;
    enhancement)      printf '%s' 'a2eeef' ;;
    *)                printf '%s' '' ;;
  esac
}
label_desc() {
  case "$1" in
    harness-feedback) printf '%s' 'Machine-reported harness feedback (E32)' ;;
    bug)              printf '%s' "Something isn't working" ;;
    enhancement)      printf '%s' 'New feature or request' ;;
    *)                printf '%s' '' ;;
  esac
}

# probe_label_present <label> — 0 = definitely present, 1 = definitely absent, 2 = error.
# Only `200 OK` is present and only `404 Not Found` is absent; every other outcome is an
# error so a transient failure (401/403, 5xx, network, empty) is never read as "absent".
probe_label_present() {
  _pl_name="$1"
  _pl_rc=0
  if _pl_out="$(gh api --include "repos/$GH_REPO/labels/$_pl_name" 2>/dev/null)"; then
    _pl_rc=0
  else
    _pl_rc=$?
  fi
  _pl_status="$(printf '%s\n' "$_pl_out" | sed -n '1s/^[^ ]* \([0-9][0-9][0-9]\).*$/\1/p')"
  if [ "$_pl_rc" -eq 0 ] && [ "$_pl_status" = '200' ]; then
    return 0
  fi
  if [ "$_pl_rc" -ne 0 ] && [ "$_pl_status" = '404' ]; then
    return 1
  fi
  return 2
}

# ensure_labels <space-separated label list> — probe every label FIRST (so any probe error
# aborts before a single create), then create exactly the definitely-absent ones. Existing
# labels are left byte-for-byte alone (no --force).
ensure_labels() {
  _el_absent=""
  for _el_l in $1; do
    _el_rc=0
    probe_label_present "$_el_l" || _el_rc=$?
    case "$_el_rc" in
      0) : ;;                                 # present: never touched
      1) _el_absent="$_el_absent $_el_l" ;;   # absent: created below
      *) printf 'feedback-labeler: cannot determine whether label %s exists in %s\n' \
           "$_el_l" "$GH_REPO" >&2
         return 1 ;;
    esac
  done
  for _el_l in $_el_absent; do
    gh label create "$_el_l" --repo "$GH_REPO" \
      --color "$(label_color "$_el_l")" --description "$(label_desc "$_el_l")" || return 1
  done
  return 0
}

# label_issue <issue-number> — the read + apply path. No comment path exists anywhere.
label_issue() {
  _li_n="${1:-}"
  case "$_li_n" in
    ''|*[!0-9]*)
      printf 'feedback-labeler: invalid issue number: %s\n' "$_li_n" >&2
      return 2 ;;
  esac
  : "${GH_REPO:?GH_REPO must be set}"
  : "${GH_TOKEN:?GH_TOKEN must be set}"

  _li_tmp="$(mktemp "${TMPDIR:-/tmp}/.feedback-labeler.XXXXXX" 2>/dev/null)" \
    || { printf 'feedback-labeler: mktemp failed\n' >&2; return 1; }

  # The body is written to a FILE; it never enters an argv or a shell word. R1 fixes the
  # classification at filing time: prefer the `opened` event payload's body snapshot over
  # refetching the issue, so a later edit (or a rerun after an edit) cannot reclassify it.
  # Actions always sets GITHUB_EVENT_PATH; the `gh api` arm serves only a local run with no
  # event payload, where there is no snapshot to preserve. (Codex P2 #4109762155: `gh api`
  # has no event-snapshot semantics.)
  if [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "${GITHUB_EVENT_PATH:-}" ]; then
    jq -r '.issue.body // ""' "$GITHUB_EVENT_PATH" > "$_li_tmp" || {
      rm -f "$_li_tmp"
      printf 'feedback-labeler: failed to read the event body of issue %s\n' "$_li_n" >&2
      return 3
    }
  elif gh api "repos/$GH_REPO/issues/$_li_n" --jq .body > "$_li_tmp"; then
    :
  else
    rm -f "$_li_tmp"
    printf 'feedback-labeler: failed to fetch the body of issue %s\n' "$_li_n" >&2
    return 3
  fi

  _li_labels="$(parse_body "$_li_tmp")" || _li_labels=""
  rm -f "$_li_tmp"

  # Not a report: no probe, no create, no edit, no comment, exit 0 (R5).
  [ -n "$_li_labels" ] || return 0

  ensure_labels "$_li_labels" || return 4

  # Add the whole set in ONE call (R9).
  _li_csv=""
  _li_sep=""
  for _li_l in $_li_labels; do
    _li_csv="$_li_csv$_li_sep$_li_l"
    _li_sep=","
  done
  gh issue edit "$_li_n" --repo "$GH_REPO" --add-label "$_li_csv" || return 5
  return 0
}

case "${1:-}" in
  parse)
    shift
    if [ $# -ge 1 ]; then
      parse_body "$1"
    else
      usage; exit 2
    fi
    ;;
  label-issue)
    shift
    if [ $# -ge 1 ]; then
      label_issue "$1"
    else
      usage; exit 2
    fi
    ;;
  *)
    usage; exit 2
    ;;
esac
