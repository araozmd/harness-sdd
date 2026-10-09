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
#     anything other than `done`, is `skipped: <reason>` and never removed (R4). A
#     feature carrying a `parked` field (store/tasks.schema.json: PRESENCE MEANS
#     PARKED, regardless of shape) is never eligible either, even when its `status`
#     scalar reads `done` — reported as `skipped: status:parked` (R15, Codex
#     #4131629415).
#   - If the TaskStore itself cannot be read or parsed, OR a record's `id`/`status`
#     violates store/tasks.schema.json's grammar, OR the same feature `id` appears
#     more than once anywhere in the board (store/tasks.schema.json requires ids to
#     be globally unique — tools/next-task.mjs:271 enforces the same invariant on its
#     own read path), the WHOLE scan aborts before classifying or removing anything —
#     a tool-level error, distinct from a per-entry skip, and the process exits
#     non-zero (R5, R14).
#     KNOWN LIMITATION (disclosed, not an oversight): R15's parked check and R5/R14's
#     id/status grammar check are the only cross-field/shape validation this tool
#     performs. It does not re-validate store/tasks.schema.json's full cross-field
#     contract — e.g. a sliced feature's `done` requiring every slice `done` AND
#     `merged`, or any other invariant tasks-lock.py enforces at write time. A board
#     that reached an inconsistent cross-field state by bypassing that guarded write
#     path (a hand-edit, or an externally imported board) is already outside this
#     harness's supported operating model, and this tool does not attempt to re-derive
#     or re-enforce that integrity guarantee beyond the parked check above.
#   - An entry whose resolved real path is not a direct child of the resolved
#     scratchpad/ directory (e.g. a symlink escaping it) is skipped and reported as an
#     anomaly, never deleted through (R6).
#   - If `store.tasks` in harness.config.yaml is anything other than `local` (the only
#     backend this tool reads status from), the tool refuses outright before touching
#     `state/tasks.json` or scratchpad/ at all, and exits non-zero (R12).
#     KNOWN LIMITATION (disclosed, not an oversight): the R12 guard's hand-rolled
#     reader handles the realistic, common YAML authoring shapes exercised by this
#     file's own test suite, but it is not a full YAML parser. Uncommon or unusual
#     syntax, such as a block-scalar header whose indentation/chomping indicators
#     appear in a less-common order (Codex #4130134127), may cause a refusal rather
#     than resolve correctly. Escaped double-quoted mapping keys at the document
#     top level or directly within `store:` are explicitly refused (R12). Other
#     YAML features may still trip the guard; this reader is not a full parser.
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
  # (exit 0) means store.tasks is genuinely absent: no top-level `store:` key
  # exists anywhere in the file, or a `store:` block exists but itself omits
  # `tasks:` — the caller may default that to `local`. A non-zero exit means
  # "cannot confidently resolve, so fail closed, NOT default to local".
  #
  # Rounds 1-7 kept expanding (then, in rounds 6-7, re-contracting) a generic
  # whole-document YAML-shape validator that walked and classified EVERY line
  # in the file, not just `store:`'s own. Each round closed one shape gap by
  # opening another: an unrelated `fix_lane.shared_paths:` block-list (round 6)
  # and then an unrelated `verification.test_command: |` block scalar (Codex
  # #4128789217, round 7) both tripped the SAME "is this nested line a
  # recognized `key:` mapping entry" check the validator ran over the whole
  # document, because neither is one — the validator had no way to tell "a
  # YAML feature I don't parse, in a section I don't read" apart from "the
  # document is malformed", short of enumerating every such feature one at a
  # time forever.
  #
  # Round 8 stops enumerating YAML features altogether and narrows the scope
  # to what this function actually needs: find the top-level `store:` key, and
  # find that key's own `tasks:` child. `find_store_key()` below tracks ONLY
  # indentation-based nesting (legitimate and necessary to know where a block
  # begins and ends — see its own docstring) plus the two things this reader
  # has always needed to see to correctly locate `store:` itself: the
  # document's own top-level lines (so a whole-document flow-mapping/sequence
  # wrapper, or a stray multi-document marker, can never make the key search
  # walk right past a real `store:` key and misread it as absent — Codex
  # #4128053695/#4127549472, rounds 4-5) and `store:`'s own bounded block (so
  # its `tasks:` child can be resolved unambiguously). Nothing else in the
  # document — no matter what YAML feature it uses, a block scalar, a
  # sequence, a flow mapping, an anchor/alias, anything — is ever examined,
  # classified, or allowed to trigger a refusal. Round 8's first pass left one
  # gap open, though: a block scalar's own CONTENT lines were still being
  # key-matched like structure, so content that happened to read `store:` (a
  # heredoc inside an unrelated key) could still derail the search (Codex
  # #4129040215). `find_store_key()` now recognizes an actual block-scalar
  # header (`key: |`/`>` and its chomping/indentation indicators) and treats
  # every more-indented line after it as opaque literal text, unconditionally
  # — see its own docstring for the one YAML grammar rule this implements.
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
    # block-scalar continuation line, or anything else that is not a mapping
    # entry).
    m = _KEY_VALUE_RE.match(text)
    if not m:
        return None
    key = m.group(1) if m.group(1) is not None else m.group(2)
    if key is None:
        key = m.group(3)
    return key, m.group(4)


# Structural characters that disqualify a SCOPE outright, wherever within that
# scope they appear outside quotes: flow-mapping/-sequence delimiters, and the
# anchor/alias sigils YAML uses for `&name` / `*name`. Which scope this
# applies to matters: harness.config.yaml legitimately uses `[]` for empty
# lists under UNRELATED top-level keys elsewhere in the very same file (e.g.
# `fix_lane.shared_paths: []`) — this reader has no business rejecting the
# whole document over a shape in a section it never reads — so this set is
# only ever checked against (a) the document's own top-level lines, and (b)
# the `store:` key's own line plus its nested block, never anything nested
# under some OTHER top-level key.
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


def _is_sequence_item(stripped):
    # A YAML block-sequence item ('-' alone, or '-' followed by a space and the
    # item's own, possibly-empty, inline content). Only checked against the
    # document's own top-level lines and store:'s own block (see
    # _DISQUALIFYING_CHARS above) — a sequence nested under some OTHER
    # top-level key (e.g. `fix_lane.shared_paths:` block-list items) is
    # ordinary, unrelated YAML this reader never inspects at all.
    return stripped == "-" or stripped.startswith("- ")


def _is_document_marker(stripped):
    # YAML multi-document separator/end markers. This reader supports exactly
    # ONE document; one of these among the document's own top-level lines
    # disqualifies it outright — there is no legitimate top-level `key:` line
    # that is literally bare `---`/`...`.
    return stripped in ("---", "...") or stripped.startswith(("--- ", "---\t", "... ", "...\t"))


class _Refuse(Exception):
    pass


# A YAML block-scalar header: the literal ('|') or folded ('>') indicator,
# an optional explicit chomping indicator ('-'/'+'), and an optional explicit
# indentation indicator digit — e.g. `|`, `|-`, `|+`, `>`, `>2`, `|-2`.
# Comments are already stripped from `rest` before this is checked, so this
# never has to account for a trailing `# ...` itself. This is the ONE YAML
# grammar rule this reader implements for block scalars: detect where one
# opens, then treat every more-indented line after it as opaque literal
# content — never structure — regardless of what that content says (Codex
# #4129040215, round 8: a block scalar's content can itself contain a line
# that reads like `store:`, and YAML says that text is never interpreted).
_BLOCK_SCALAR_RE = re.compile(r'^[|>][+-]?[0-9]?$')


def find_store_key(entries):
    # Locate the top-level `store:` key by walking the document top to
    # bottom, tracking ONLY indentation-based nesting — never what any OTHER
    # line's content IS (with exactly one exception: recognizing a block
    # scalar's own header line, below, so its content can be skipped rather
    # than misread as structure). That tracking answers exactly two narrow
    # questions about a candidate `store:` line: (a) is it directly under the
    # document's own root (nothing else encloses it — i.e. it really is
    # top-level, however that document happens to indent its top level), and
    # (b) if not, is its immediate parent a key that already carries its own
    # inline scalar value (invalid nesting — the document's structure around
    # `store:` is broken, not merely "store: absent")? Frames are popped by
    # plain indentation comparison alone, so a sequence, flow mapping,
    # anchor, or anything else nested under some UNRELATED top-level key is
    # walked past and never inspected for its own shape (round 6/7).
    #
    # Round 7's fix left one gap: a block-scalar header line (`key: |`) has a
    # non-empty `rest` (the `|` itself), so it was recorded as a CLOSED frame
    # (is_open=False) — the same shape as `key: some scalar`. A later line
    # that is really just opaque block-scalar CONTENT, but happens to start
    # with `store:` (e.g. inside a `test_command: |` heredoc), was then
    # walked into that closed frame's "child" check and wrongly raised
    # _Refuse() as `store:` invalidly nested under a scalar-valued key —
    # Codex #4129040215. Round 8 closes this by recognizing the block-scalar
    # header itself (see _BLOCK_SCALAR_RE) and marking its frame specially:
    # every subsequent entry more indented than that header's own line is
    # opaque content and is skipped unconditionally, before ANY key-matching
    # or structural check ever runs on it — not just the key=="store" one.
    #
    # The one remaining exception, matching this reader's contract since
    # rounds 4-5, is the document's own TOP-LEVEL lines themselves: those are
    # still checked for the exact shapes that hid a real `store:` key from a
    # naive search (a flow-style mapping/sequence or anchor/alias, or a YAML
    # multi-document marker) — never anything nested under them, and never
    # anything that is itself opaque block-scalar content.
    #
    # Returns (store_idx, store_indent, store_rest) for a top-level `store:`
    # key found, or (None, None, None) when the document genuinely has none
    # anywhere. Raises _Refuse when the search itself cannot confidently
    # tell — an unreadable top-level line, or `store:` invalidly nested under
    # a scalar-valued key.
    ROOT = (-1, True, False)  # (indent, open, is_block_scalar)
    stack = [ROOT]
    found = None  # first top-level `store:` match, held until the scan finishes
    for idx, (indent, stripped) in enumerate(entries):
        while len(stack) > 1 and indent <= stack[-1][0]:
            stack.pop()
        _, parent_open, parent_is_block_scalar = stack[-1]

        if parent_is_block_scalar:
            # Opaque literal content of an open block scalar: never
            # classified, never key-matched, never structurally interpreted
            # — full stop, whatever it says (Codex #4129040215). Its own
            # indentation already guarantees it stays nested here until a
            # line back at or below the block scalar header's indentation
            # pops this frame above.
            continue

        is_top_level = len(stack) == 1

        if is_top_level:
            if _is_document_marker(stripped):
                raise _Refuse()
            if _contains_unquoted(stripped, _DISQUALIFYING_CHARS):
                raise _Refuse()
            if _is_sequence_item(stripped):
                raise _Refuse()

        kv = split_key_value(stripped)
        if is_top_level and kv is not None and stripped.startswith('"') and "\\" in kv[0]:
            raise _Refuse()
        if kv is not None:
            key, rest = kv
            is_open = rest.strip() == ""
        else:
            if is_top_level:
                # A top-level, non-blank, non-comment line that is not an ordinary
                # `key:` mapping entry, not a list item, not a document marker, and
                # does not contain a disqualifying flow/anchor character either —
                # e.g. an explicit-key YAML mapping entry (`? tasks` / `: obsidian`,
                # Codex #4130253947). This reader recognizes no such shape, so it
                # cannot tell whether this line is, or hides, the real `store:` key;
                # treating it as ordinary skippable content would let it walk right
                # past an actual backend selection and default to "absent ⇒ local".
                # Refuse rather than silently continue past genuinely unclassifiable
                # top-level content — narrower than round 5's abandoned
                # whole-document validator: this fires ONLY on the document's own
                # top-level lines, never on anything nested under some OTHER key
                # (round 7-10's scope-narrowing is untouched).
                raise _Refuse()
            key, rest, is_open = None, "", False

        if key == "store":
            if is_top_level:
                if found is not None:
                    # A second top-level `store:` block — which of the two is
                    # authoritative is genuinely ambiguous (Codex #4132718580,
                    # round 18, the top-level counterpart of round 17's
                    # duplicate-`id` TaskStore fix): refuse rather than
                    # silently using whichever one this scan happened to see
                    # first.
                    raise _Refuse()
                found = (idx, indent, rest.strip())
            elif not parent_open:
                raise _Refuse()
            # Legitimately nested under some OTHER open block (an unrelated
            # key that happens to also be named `store`) — not ours; keep
            # scanning for a real top-level one.

        is_block_scalar = kv is not None and _BLOCK_SCALAR_RE.match(rest.strip()) is not None
        stack.append((indent, is_open, is_block_scalar))

    if found is not None:
        return found
    return None, None, None


def parse_store_tasks(path):
    try:
        # utf-8-sig: transparently strips a leading UTF-8 BOM if present (and is a
        # no-op otherwise) — without it, a BOM'd config's first line reads as
        # "﻿store:", the top-level key search never matches, and the tool
        # would silently conclude store: is absent and default to local instead
        # of refusing — the exact failure class every prior round closed.
        with open(path, "r", encoding="utf-8-sig") as fh:
            raw_lines = fh.read().splitlines()
    except FileNotFoundError:
        # A missing config file is a READ FAILURE, not "no store: key found in an
        # existing file" — it can never establish which TaskStore backend is
        # authoritative, so it must fail closed exactly like any other unreadable
        # config (the OSError branch just below), not silently resolve to "absent,
        # default local" and let the caller proceed to delete scratch directories
        # under an unverified backend (Codex #4130253950).
        return (None, 1)
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

    try:
        store_idx, store_indent, store_rest = find_store_key(entries)
    except _Refuse:
        return (None, 1)

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

    # store:'s own bounded block: every subsequent entry more indented than
    # the store: line's OWN indentation, up to the first entry back at or
    # below it (which ends the block, and is never itself part of it — so a
    # `tasks:` key belonging to a DIFFERENT top-level block is never mistaken
    # for this one's). This is pure indentation comparison — it says nothing
    # about what any of those later lines ARE, only where they stop being
    # inside store:'s block.
    block = []
    for indent, stripped in entries[store_idx + 1:]:
        if indent <= store_indent:
            break
        block.append((indent, stripped))

    if not block:
        return ("", 0)  # `store:` present with no children — tasks absent

    # store:'s own block is the ONE nested scope, besides the top level
    # itself, this reader still classifies — its schema is a scalar or a
    # plain block mapping, never a flow mapping/sequence/anchor or a list,
    # since resolving its `tasks:` child is the one thing this function
    # actually has to do.
    for _, block_stripped in block:
        if _contains_unquoted(block_stripped, _DISQUALIFYING_CHARS):
            return (None, 1)
        if _is_sequence_item(block_stripped):
            return (None, 1)
        if split_key_value(block_stripped) is None:
            # Neither an ordinary `key:` mapping entry nor a recognized
            # disqualifying/sequence shape — e.g. an explicit-key YAML mapping
            # entry (`? tasks` / `: obsidian`, Codex #4130253947). store:'s own
            # schema is a scalar or a plain block mapping, never anything else
            # (see this block's own docstring above), so a line here this reader
            # cannot classify as an ordinary key is ambiguous, not "not tasks:" —
            # refuse rather than silently walking past it and concluding tasks:
            # is absent.
            return (None, 1)

    child_indent = min(indent for indent, _ in block)
    tasks_line = None
    for indent, stripped in block:
        if indent != child_indent:
            continue
        kv = split_key_value(stripped)
        if kv is not None and stripped.startswith('"') and "\\" in kv[0]:
            return (None, 1)
        if kv is not None and kv[0] == "tasks":
            if tasks_line is not None:
                # A second `tasks:` key at store:'s own child indentation —
                # which of the two selects the authoritative backend is
                # genuinely ambiguous (Codex #4132718580, round 18, the
                # nested-key counterpart of round 17's duplicate-`id`
                # TaskStore fix): refuse rather than silently letting
                # whichever occurrence this scan saw first win. Keep
                # scanning (not break) so a duplicate is never missed
                # merely because it happens to appear after other keys.
                return (None, 1)
            tasks_line = kv[1].strip()

    if tasks_line is None:
        return ("", 0)  # `tasks:` genuinely absent from the `store:` block
    if tasks_line == "":
        return (None, 1)  # `tasks:` present but with no inline scalar (e.g.
        # its own nested block) — flow was already ruled out for this block above.
    resolved = unquote(tasks_line)
    if resolved == "":
        return (None, 1)  # `tasks:` present with an EXPLICIT empty scalar —
        # `""` or `''` unquoting to an empty string. This is NOT the same as
        # `tasks:` being absent: someone deliberately wrote an empty value,
        # and empty string is not `local`/`obsidian`/`jira`/anything this tool
        # recognizes. Returning it as a plain "" success here would be
        # byte-identical, from the caller's shell side, to the genuinely-absent
        # case just above — `${STORE_TASKS:-local}` cannot distinguish "unset"
        # from "set to empty string" — and would silently default to `local`,
        # defeating R12's whole refuse-on-ambiguity contract (Codex
        # #4130742436). Refuse here instead, before that conflation can happen.
    return (resolved, 0)


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

# ── TaskStore read, ONCE, before classifying a single entry (R5, R14) ─────────────
# A read/parse failure here is a TOOL-LEVEL error: abort the whole scan, classify and
# remove nothing, exit non-zero. This is deliberately distinct from a per-entry R4
# skip, which never touches the exit code. R14 folds a schema-invalid record into
# this SAME abort path deliberately: this printed line is later split by the shell
# side on tab/newline (`lookup_status`'s `awk -F'\t'`), so an `id`/`status` string
# that is syntactically valid JSON but violates store/tasks.schema.json's grammar —
# e.g. a status of `pending\nE99-F99\tdone` — can forge an extra `id\tstatus` row
# naming a feature that does not exist, with a fabricated status (Codex #4130566648).
# The schema's `id` pattern and `status` enum are validated BEFORE printing any row,
# and either check failing exits 1 exactly like the read/parse failure above, so a
# schema-invalid TaskStore hits the identical `TASKSTORE_RC -ne 0` die() below — the
# record is just as untrustworthy as one this reader cannot parse at all.
TASKSTORE_OUT=$(python3 - "$BOARD" <<'PYEOF'
import json
import re
import sys

FID_RE = re.compile(r"^E[0-9]+-F[0-9]+$")
STATUS_ENUM = {"pending", "spec-ready", "in-progress", "in-review", "done"}

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

seen_fids = set()
for epic in epics:
    if not isinstance(epic, dict):
        # Schema-invalid record (Codex #4131236393): store/tasks.schema.json
        # requires every epics[] element to be an object, same as it requires
        # every features[] element to be one (below). Abort the whole scan
        # rather than silently skipping a structurally invalid epic — a
        # partially-validated board can never be trusted.
        sys.exit(1)
    feats = epic.get("features")
    if not isinstance(feats, list):
        # Same schema requirement, one field over: an epic's `features` must
        # be an array. A missing/non-array value is just as schema-invalid as
        # a non-object array element and must abort the same way.
        sys.exit(1)
    for feat in feats:
        if not isinstance(feat, dict):
            # Schema-invalid record (Codex #4131236393): a non-object element
            # in the features[] array (e.g. a bare number) is schema-invalid
            # exactly like a malformed/missing id or status below — silently
            # skipping it let a partially-invalid board carry on and delete a
            # real done feature's scratch. Abort the whole scan instead.
            sys.exit(1)
        fid = feat.get("id")
        status = feat.get("status")
        if (
            not isinstance(fid, str)
            or not isinstance(status, str)
            or not FID_RE.fullmatch(fid)
            or status not in STATUS_ENUM
        ):
            # Schema-invalid record (R14): a missing/non-string id or status is
            # just as schema-invalid as a malformed-but-present string value —
            # either shape could otherwise inject a forged row into this
            # tab-delimited output, or let a partially-validated board carry on
            # past a record that never proved its own shape. Abort the whole
            # scan instead of silently skipping just this one record.
            sys.exit(1)
        if fid in seen_fids:
            # R14 extension (Codex #4132354818): store/tasks.schema.json requires
            # feature ids to be globally unique across the whole board, and
            # tools/next-task.mjs:271 already enforces exactly this invariant on the
            # canonical selector's own read path (`if (featureIds.has(feature.id))
            # throw ...`). lookup_status()'s awk lookup below matches on first `$1 ==
            # id` and exits — so a duplicate id let array order silently decide which
            # row's status won. Codex's repro paired a `done` row with a later
            # `in-progress` row for the same id and reproduced --apply deleting the
            # live record's scratch. The duplicate id is itself the schema violation,
            # regardless of whether the two rows happen to agree on status — abort the
            # whole scan the same way every other schema-invalid record above does,
            # rather than resolving the ambiguity by trusting whichever row this loop
            # reaches first.
            sys.exit(1)
        seen_fids.add(fid)
        # R15 (Codex #4131629415): store/tasks.schema.json's `parked` field is a
        # cross-field invariant this reader otherwise never sees — its own
        # $comment says PRESENCE MEANS PARKED, regardless of shape, and a `done`
        # status may never accompany it (the schema forbids that combination
        # outright). The sanctioned write path (tasks-lock.py) already refuses a
        # done+parked transition, so this combination can only reach state/
        # tasks.json by bypassing that guard — a hand-edit or an imported board,
        # both already outside this harness's supported operating model. Report
        # the actual liveness here rather than trust the raw `done` scalar: print
        # "parked" instead of "done" so lookup_status()'s `$_status != "done"`
        # check downstream naturally treats the row as ineligible, without a
        # second parked-tracking mechanism. This is a narrow, targeted guard —
        # NOT full cross-field schema validation; see this file's header comment
        # for the disclosed remaining gap.
        if status == "done" and "parked" in feat:
            status = "parked"
        print(fid + "\t" + status)
PYEOF
)
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
  # Three glob patterns, not one: POSIX `*` alone never matches a dot-prefixed name,
  # so a dot-prefixed directory or dangling symlink under scratchpad/ would otherwise
  # never be enumerated at all — omitted from the summary's `total` and never given a
  # verdict (Codex #4129683699). `.[!.]*` matches single-dot-prefixed names (excludes
  # literal `.` and `..` themselves) and `..?*` matches double-dot-prefixed names
  # (`..foo`, excludes literal `..`); the three patterns are mutually exclusive
  # character classes, so no entry is ever matched by more than one of them. When any
  # one pattern has no match, it expands to its own literal unmatched-pattern string
  # (no nullglob in POSIX sh), which the existing `[ -e ] || [ -L ]` guard below
  # rejects for each pattern independently, same as it always has for the bare `*`.
  for _entry in "$SCRATCHPAD"/* "$SCRATCHPAD"/.[!.]* "$SCRATCHPAD"/..?*; do
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
