#!/bin/sh
# tools/sweep-scratch.sh — E34-F01 automated scratch-dir sweep (the disk-hygiene
# backstop for the `scratchpad/<feature-id>-<role>/` namespacing convention that
# agents/builder.md, agents/reviewer.md, agents/fixer.md and agents/pr-fixer.md
# document). Nothing removes a role's own scratch directory when it writes it — the
# convention only tells a role WHERE to write, never when to clean up. This tool is
# the "when": once the owning feature's TaskStore status is `done`, its scratch is
# reclaimable, and this is the only thing that reclaims it.
#
# usage: sweep-scratch.sh [<feature-id>] [--apply]
#
#   <feature-id>  optional, exactly `E[0-9]+-F[0-9]+` — restrict the scan to
#                 immediate scratchpad/ entries whose parsed feature id equals it.
#                 Absent ⇒ scan every immediate entry.
#   --apply       mutate the filesystem (remove eligible entries). Absent ⇒ dry-run:
#                 report only, touch nothing. This is the ONLY switch between the two
#                 modes — classification and reporting are identical in both (R1).
#
# FAIL-CLOSED, on five distinct axes:
#   - An entry whose name does not start with `<feature-id>-` is `unrecognized` and is
#     NEVER acted on, in any mode (R2).
#   - An entry whose feature id is absent from the TaskStore, or whose status is
#     anything other than `done`, is `skipped: <reason>` and never removed (R4).
#   - If the TaskStore itself cannot be read or parsed, the WHOLE scan aborts before
#     classifying or removing anything — a tool-level error, distinct from a
#     per-entry skip, and the process exits non-zero (R5).
#   - An entry whose resolved real path is not a direct child of the resolved
#     scratchpad/ directory (e.g. a symlink escaping it) is skipped and reported as an
#     anomaly, never deleted through (R6).
#   - If `store.tasks` in harness.config.yaml is anything other than `local` (the only
#     backend this tool reads status from), the tool refuses outright before touching
#     `state/tasks.json` or scratchpad/ at all, and exits non-zero (R12).
#
# The tool never mutates the TaskStore, never writes outside the one resolved
# scratchpad/ directory, and never globs or acts on scratchpad/ itself.
#
# Self-location and canonical-primary resolution deliberately mirror
# tools/fix-worktree.sh (E15-F02): this makes the sweep correct even when invoked
# from inside an isolated worktree — it always acts on the ONE canonical scratchpad/
# and the ONE canonical TaskStore, never on whichever checkout happened to invoke it.

set -u

die() { echo "sweep-scratch: $*" >&2; exit 1; }

usage() { die "usage: sweep-scratch.sh [<feature-id>] [--apply]"; }

absolute_dir() { (CDPATH= cd -- "$1" 2>/dev/null && pwd -P); }

is_feature_id() {
  printf '%s' "$1" | grep -Eq '^E[0-9]+-F[0-9]+$'
}

# ── arg parsing ────────────────────────────────────────────────────────────────────
APPLY=0
SCOPE=
for _arg in "$@"; do
  case "$_arg" in
    --apply)
      [ "$APPLY" -eq 0 ] || usage
      APPLY=1
      ;;
    *)
      is_feature_id "$_arg" || usage
      [ -z "$SCOPE" ] || usage
      SCOPE="$_arg"
      ;;
  esac
done

# ── self-location + canonical primary resolution (mirrors tools/fix-worktree.sh) ──
resolve_repository() {
  CALLER_TOP="$(git rev-parse --show-toplevel 2>/dev/null)" ||
    die "must run inside a non-bare Git worktree"
  CALLER_TOP="$(absolute_dir "$CALLER_TOP")" ||
    die "cannot resolve caller worktree"
  COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
    die "cannot resolve shared Git directory"
  COMMON_DIR="$(absolute_dir "$COMMON_DIR")" ||
    die "cannot resolve shared Git directory"

  PRIMARY=
  PRIMARY_COUNT=0
  while IFS= read -r _line; do
    case "$_line" in
      "worktree "*)
        _candidate=${_line#worktree }
        [ -d "$_candidate" ] || continue
        _candidate_git="$(git -C "$_candidate" rev-parse --absolute-git-dir 2>/dev/null)" ||
          die "cannot inspect registered worktree: $_candidate"
        _candidate_git="$(absolute_dir "$_candidate_git")" ||
          die "cannot resolve Git directory for: $_candidate"
        if [ "$_candidate_git" = "$COMMON_DIR" ]; then
          PRIMARY="$(absolute_dir "$_candidate")"
          PRIMARY_COUNT=$((PRIMARY_COUNT + 1))
        fi
        ;;
      bare) die "bare worktree records are unsupported" ;;
    esac
  done <<EOF
$(git worktree list --porcelain 2>/dev/null)
EOF
  [ "$PRIMARY_COUNT" -eq 1 ] ||
    die "cannot identify exactly one canonical primary worktree"

  SELF_DIR="$(absolute_dir "$(dirname -- "$0")")" ||
    die "cannot locate helper"
  case "$SELF_DIR" in
    "$CALLER_TOP/tools")
      BOARD="$PRIMARY/state/tasks.json"
      CONFIG="$PRIMARY/harness.config.yaml"
      ;;
    "$CALLER_TOP/.harness/tools")
      BOARD="$PRIMARY/.harness/state/tasks.json"
      CONFIG="$PRIMARY/.harness/harness.config.yaml"
      ;;
    *) die "helper must run from tools/ or .harness/tools/ in the caller worktree" ;;
  esac
  # scratchpad/ is ALWAYS resolved at <primary>/scratchpad, never inside .harness/ —
  # it is where Builder/Reviewer/Fixer/PR-fixer sessions actually write, regardless
  # of source vs. installed layout.
  SCRATCHPAD="$PRIMARY/scratchpad"
}
resolve_repository

# ── TaskStore backend guard (R12) ──────────────────────────────────────────────────
# Everything below assumes the `local` TaskStore backend (`store.tasks: local` in
# harness.config.yaml, store/local.md): a flat JSON file this process reads directly.
# When `store.tasks` is `obsidian`, feature status lives in specs/ frontmatter instead
# (store/obsidian.md) and `tasks.json` is only an optional, possibly stale or absent,
# mirror — reading it as the source of truth here could leave completed scratch forever
# (mirror absent/stale) or delete still-active scratch (a stale mirror that still says
# `done`). Parsing every backend's canonical status source is out of scope for this
# feature (E34-F01.spec.md scopes liveness to "TaskStore status `done`", and this repo's
# own harness.config.yaml sets `store.tasks: local`), so refuse outright for any other
# configured backend instead: fail closed, exit non-zero, touch nothing.
_cfg_store_tasks() { # _cfg_store_tasks <file> — echoes store.tasks; empty output
  # (exit 0) means store.tasks is genuinely absent: the document matches the ONE
  # canonical shape this parser accepts (see validate_canonical_shape below) and
  # has no top-level `store:` key at all, or a `store:` block present but omitting
  # `tasks:` — the caller may default that to `local`. A non-zero exit means one
  # of two DISTINCT refusal cases, both "cannot confidently resolve, so fail
  # closed, NOT default to local":
  #   1. the document does not match the one recognized shape AT ALL (a flow-style
  #      mapping/sequence anywhere — top-level or nested, a multi-document
  #      `---`/`...` marker, an anchor/alias, or any other structural surprise).
  #      This is checked BEFORE any key search, so a whole-document wrapper the
  #      key search would otherwise walk right past — e.g.
  #      `{store: {tasks: obsidian, docs: local}}`, whose first "key" tokenizes
  #      as the single fused string `{store` and so never matches `store` — can
  #      never be silently read as "store: absent" (Codex #4128053695, round 5).
  #   2. the document IS the recognized shape, but a `store:` block present in
  #      it still cannot be resolved to a `tasks:` scalar (e.g. `store: local` —
  #      the store: line's own value is a bare scalar, not a mapping).
  # Four straight rounds (block-only baseline -> flow-style value -> indented
  # block -> quoted keys) each added one more "and also accept this shape too"
  # branch to the key search itself. Round 5 stops that: the shape validator
  # below is the ONLY gate, checked once, up front, and is not aware of `store`
  # or `tasks` as key names at all — it is a generic block-YAML-nesting check,
  # not one more special case.
  python3 - "$1" <<'PYEOF'
import re
import sys


def strip_comment(line):
    # Naive but quote-aware '#' stripping: good enough for this one config
    # file's own shape (store:/tasks: values never themselves contain a '#').
    out = []
    in_squote = in_dquote = False
    for ch in line:
        if ch == "'" and not in_dquote:
            in_squote = not in_squote
        elif ch == '"' and not in_squote:
            in_dquote = not in_dquote
        elif ch == "#" and not in_squote and not in_dquote:
            break
        out.append(ch)
    return "".join(out)


def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
        return v[1:-1]
    return v


_KEY_VALUE_RE = re.compile(
    r'^(?:"((?:[^"\\]|\\.)*)"|\'([^\']*)\'|([^\s:\'"]+))\s*:(.*)$'
)


def split_key_value(text):
    # THE ONE tokenizer for "<key>: <value-or-nothing>", where <key> is a bare
    # token OR a single- or double-quoted string (quotes stripped here, so the
    # caller never sees them) — independent of indentation depth. Returns
    # (key, rest-of-text-after-the-colon), or None when `text` does not start
    # with a recognized key token followed by ':' at all (e.g. a list item, a
    # continuation line, or anything else that is not a mapping entry).
    m = _KEY_VALUE_RE.match(text)
    if not m:
        return None
    key = m.group(1) if m.group(1) is not None else m.group(2)
    if key is None:
        key = m.group(3)
    return key, m.group(4)


# Structural characters that disqualify a SCOPE outright, wherever within that
# scope they appear outside quotes: flow-mapping/-sequence delimiters, and the
# anchor/alias sigils YAML uses for `&name` / `*name` (a merge key's own alias
# reference is always one of these, so no separate `<<` check is needed). Which
# scope this applies to matters: harness.config.yaml legitimately uses `[]` for
# empty lists under UNRELATED top-level keys elsewhere in the very same file
# (e.g. `fix_lane.shared_paths: []`) — this reader has no business rejecting
# the whole document over a shape in a section it never reads — so this set is
# only ever checked against (a) the document's own top-level lines, and (b) the
# `store:` key's own line plus its nested block, never the rest of the document.
_DISQUALIFYING_CHARS = frozenset("{}[]&*")


def _contains_unquoted(text, chars):
    in_squote = in_dquote = False
    for ch in text:
        if ch == "'" and not in_dquote:
            in_squote = not in_squote
        elif ch == '"' and not in_squote:
            in_dquote = not in_dquote
        elif ch in chars and not in_squote and not in_dquote:
            return True
    return False


def _is_document_marker(stripped):
    # YAML multi-document separator/end markers. This reader supports exactly
    # ONE document; any of these disqualify the whole file, wherever they are —
    # there is no legitimate top-level or nested `key:` line that is literally
    # bare `---`/`...`, so checking the whole document has no false-positive risk.
    return stripped in ("---", "...") or stripped.startswith(("--- ", "---\t", "... ", "...\t"))


def validate_canonical_shape(entries):
    # The ONE document shape this parser accepts: a plain block-style mapping —
    # `key:` lines at one consistent top-level indentation, none of them a flow
    # mapping/sequence — whose values are each either absent, an inline scalar,
    # or a further-indented plain block-style nested mapping (never a line
    # indented under a key that already carries an inline scalar value). This
    # is deliberately generic: it never names `store` or `tasks`, and it never
    # inspects content NESTED under an unrelated top-level key, so a `[]` or
    # similar flow value two sections away from `store:` (this repo's own
    # harness.config.yaml has several) can never make an otherwise-canonical
    # document refuse. Returns None when `entries` matches; otherwise a short
    # reason string (the caller only needs "it didn't match", but a reason
    # keeps this auditable).
    if not entries:
        return None  # a genuinely empty document is the canonical empty shape

    for _, stripped in entries:
        if _is_document_marker(stripped):
            return "multi-document YAML ('---'/'...' marker) is not supported"

    base_indent = entries[0][0]
    for indent, stripped in entries:
        if indent == base_indent and _contains_unquoted(stripped, _DISQUALIFYING_CHARS):
            return "a top-level flow-style mapping/sequence or anchor/alias is not supported"

    # A virtual root block, always open, at an indent strictly below every real
    # entry — so top-level entries are always valid children of it. Each stack
    # frame is (indent, is_open): "open" means that entry's own inline value
    # was empty, i.e. it is a block-mapping key that may legitimately have
    # further-indented children.
    stack = [(base_indent - 1, True)]
    for indent, stripped in entries:
        while stack and indent <= stack[-1][0]:
            stack.pop()
        if not stack:
            return "a line indented below every open block"
        _, parent_open = stack[-1]
        if not parent_open:
            return "a line indented under a key that already has an inline scalar value"
        kv = split_key_value(stripped)
        if kv is None:
            return "a line that is not a recognized 'key:' mapping entry"
        _, rest = kv
        stack.append((indent, rest.strip() == ""))
    return None


def parse_store_tasks(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw_lines = fh.read().splitlines()
    except FileNotFoundError:
        return ("", 0)
    except OSError:
        return (None, 1)

    entries = []  # (indent, stripped-content) per non-blank, non-comment line
    for line in raw_lines:
        content = strip_comment(line)
        stripped = content.strip()
        if stripped == "":
            continue
        indent = len(content) - len(content.lstrip(" \t"))
        entries.append((indent, stripped))

    if validate_canonical_shape(entries) is not None:
        return (None, 1)

    if not entries:
        return ("", 0)

    # The shape validator above already guarantees every entry at this
    # indentation is a recognized `key:` line, and that indentation is
    # consistent for the whole document — so no further "is this ambiguous?"
    # fallback is needed here; an unresolved `store:`-looking key at some OTHER
    # indentation is now structurally impossible to have slipped through.
    base_indent = entries[0][0]

    store_idx = None
    store_rest = ""
    for idx, (indent, stripped) in enumerate(entries):
        if indent != base_indent:
            continue
        key, rest = split_key_value(stripped)
        if key == "store":
            store_idx = idx
            store_rest = rest.strip()
            break

    if store_idx is None:
        return ("", 0)  # no top-level `store:` key anywhere — tasks absent

    if _contains_unquoted(store_rest, _DISQUALIFYING_CHARS):
        return (None, 1)  # e.g. `store: {tasks: obsidian}` — a flow mapping
        # right on the store: line itself is refused here explicitly rather
        # than falling into the bare-scalar check below with a confusing
        # "the whole {...} string looked like a scalar" reading.

    if store_rest != "":
        return (None, 1)  # a scalar (or anything else) on the `store:` line
        # itself — reaching here (no disqualifying chars) means a bare
        # non-mapping scalar, e.g. `store: local`.

    # Block style: the block's own direct lines are every subsequent entry
    # more indented than the top level, up to the first entry back at or
    # below it (which ends the block, and is never itself part of it — so a
    # `tasks:` key belonging to a DIFFERENT top-level block is never mistaken
    # for this one's).
    block = []
    for indent, stripped in entries[store_idx + 1:]:
        if indent <= base_indent:
            break
        block.append((indent, stripped))

    if not block:
        return ("", 0)  # `store:` present with no children — tasks absent

    # The store: block is the ONE scope, besides the top level itself, where a
    # flow-style mapping/sequence or anchor/alias is refused even though it is
    # nested — this repo's harness.config.yaml uses `[]`/flow elsewhere in the
    # document (outside store:), which is out of scope and left alone; only
    # store's OWN block must be plain block-style, since its own `tasks:` value
    # is what this reader must resolve to a scalar.
    for _, block_stripped in block:
        if _contains_unquoted(block_stripped, _DISQUALIFYING_CHARS):
            return (None, 1)

    child_indent = min(indent for indent, _ in block)
    tasks_line = None
    for indent, stripped in block:
        if indent != child_indent:
            continue
        kv = split_key_value(stripped)
        if kv is not None and kv[0] == "tasks":
            tasks_line = kv[1].strip()
            break

    if tasks_line is None:
        return ("", 0)  # `tasks:` genuinely absent from the `store:` block
    if tasks_line == "":
        return (None, 1)  # `tasks:` present but with no inline scalar (e.g.
        # its own nested block) — flow was already ruled out for this block above.
    return (unquote(tasks_line), 0)


_value, _code = parse_store_tasks(sys.argv[1])
if _code != 0:
    sys.exit(1)
if _value:
    print(_value)
sys.exit(0)
PYEOF
}

if ! STORE_TASKS="$(_cfg_store_tasks "$CONFIG")"; then
  die "cannot recognize 'tasks:' under the 'store:' block in $CONFIG; refusing to guess whether the configured backend is local"
fi
STORE_TASKS="${STORE_TASKS:-local}"
[ "$STORE_TASKS" = "local" ] ||
  die "unsupported TaskStore backend store.tasks: $STORE_TASKS — this tool only reads the 'local' backend ($BOARD); refusing to scan or mutate scratchpad/ for any other backend"

# ── TaskStore read, ONCE, before classifying a single entry (R5) ──────────────────
# A read/parse failure here is a TOOL-LEVEL error: abort the whole scan, classify and
# remove nothing, exit non-zero. This is deliberately distinct from a per-entry R4
# skip, which never touches the exit code.
TASKSTORE_OUT="$(python3 - "$BOARD" <<'PYEOF'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    sys.exit(1)

if not isinstance(data, dict):
    sys.exit(1)

epics = data.get("epics")
if not isinstance(epics, list):
    sys.exit(1)

for epic in epics:
    if not isinstance(epic, dict):
        continue
    feats = epic.get("features")
    if not isinstance(feats, list):
        continue
    for feat in feats:
        if not isinstance(feat, dict):
            continue
        fid = feat.get("id")
        status = feat.get("status")
        if isinstance(fid, str) and isinstance(status, str):
            print(fid + "\t" + status)
PYEOF
)"
TASKSTORE_RC=$?
[ "$TASKSTORE_RC" -eq 0 ] ||
  die "cannot read or parse the TaskStore at $BOARD — aborting the whole scan; nothing was classified, nothing was removed (exit $TASKSTORE_RC)"

lookup_status() {
  printf '%s\n' "$TASKSTORE_OUT" | awk -F'\t' -v id="$1" '
    $1 == id { print $2; found = 1; exit }
    END { if (!found) print "__NOTFOUND__" }
  '
}

# ── classification (R2): leading E[0-9]+-F[0-9]+ followed by a hyphen ─────────────
# Echoes the parsed feature id, or nothing when the name does not match.
parse_fid() {
  _pf_name="$1"
  _pf_fid="$(printf '%s' "$_pf_name" | grep -Eo '^E[0-9]+-F[0-9]+' || :)"
  [ -n "$_pf_fid" ] || return 0
  _pf_rest="${_pf_name#"$_pf_fid"}"
  case "$_pf_rest" in
    -?*) printf '%s' "$_pf_fid" ;;
  esac
}

# ── R6 safety check: real path of the entry must be a DIRECT child of the resolved
# real path of scratchpad/ — dereferences symlinks, so a symlink pointing outside
# scratchpad/ (or a dangling one, or one to a non-directory) never passes.
is_safe_child() {
  [ -d "$1" ] || return 1
  _isc_real="$(CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P)" || return 1
  [ -n "$_isc_real" ] || return 1
  [ "$(dirname -- "$_isc_real")" = "$SCRATCHPAD_REAL" ]
}

SCRATCHPAD_REAL=""
if [ -d "$SCRATCHPAD" ]; then
  SCRATCHPAD_REAL="$(absolute_dir "$SCRATCHPAD")" || die "cannot resolve scratchpad/ real path"
fi

TOTAL=0
N_REMOVED=0
N_ELIGIBLE=0
N_SKIPPED=0
N_UNRECOGNIZED=0
BYTES_RECLAIMED=0
# R13: set the instant an `rm -rf` actually fails (permissions, read-only fs, I/O
# error) on an otherwise-eligible entry — distinct from every other exit-code case,
# and the ONLY thing that flips the final exit non-zero once classification has
# begun (R7's tool-level errors abort before this point; a plain skip never sets it).
ANY_REMOVE_FAILED=0

if [ -n "$SCRATCHPAD_REAL" ]; then
  for _entry in "$SCRATCHPAD"/*; do
    [ -e "$_entry" ] || [ -L "$_entry" ] || continue
    _name="${_entry##*/}"
    _fid="$(parse_fid "$_name")"

    # R8: a scope argument restricts the scan to entries matching it — anything else
    # (including an unrecognized entry, whose parsed id is always empty) is not even
    # reported for that invocation.
    if [ -n "$SCOPE" ] && [ "$_fid" != "$SCOPE" ]; then
      continue
    fi

    TOTAL=$((TOTAL + 1))

    if [ -z "$_fid" ]; then
      N_UNRECOGNIZED=$((N_UNRECOGNIZED + 1))
      echo "$_name	unrecognized"
      continue
    fi

    _status="$(lookup_status "$_fid")"

    if [ "$_status" = "__NOTFOUND__" ]; then
      N_SKIPPED=$((N_SKIPPED + 1))
      echo "$_name	skipped: not-found"
      continue
    fi

    if [ "$_status" != "done" ]; then
      N_SKIPPED=$((N_SKIPPED + 1))
      echo "$_name	skipped: status:$_status"
      continue
    fi

    # status is done — the only case eligible for removal. Safety check right before
    # any removal (R6), never before: a non-done entry never reaches this line.
    if ! is_safe_child "$_entry"; then
      N_SKIPPED=$((N_SKIPPED + 1))
      echo "$_name	skipped: symlink-escape"
      continue
    fi

    if [ "$APPLY" -eq 1 ]; then
      _size_kb="$(du -sk "$_entry" 2>/dev/null | awk '{print $1}')"
      case "$_size_kb" in ''|*[!0-9]*) _size_kb=0 ;; esac
      if rm -rf -- "$_entry"; then
        N_REMOVED=$((N_REMOVED + 1))
        BYTES_RECLAIMED=$((BYTES_RECLAIMED + _size_kb * 1024))
        echo "$_name	removed"
      else
        N_SKIPPED=$((N_SKIPPED + 1))
        ANY_REMOVE_FAILED=1
        echo "$_name	skipped: remove-failed"
      fi
    else
      N_ELIGIBLE=$((N_ELIGIBLE + 1))
      echo "$_name	eligible"
    fi
  done
fi

echo "summary: total=$TOTAL removed=$N_REMOVED eligible=$N_ELIGIBLE skipped=$N_SKIPPED unrecognized=$N_UNRECOGNIZED bytes_reclaimed=$BYTES_RECLAIMED"
# R13: the full summary always prints first; only the exit code reflects a removal
# failure, and only when at least one occurred — every other case (dry-run, a clean
# --apply run, or --apply with only classification skips) still exits 0.
[ "$ANY_REMOVE_FAILED" -eq 0 ] || exit 1
exit 0
