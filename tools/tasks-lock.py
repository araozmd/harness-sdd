#!/usr/bin/env python3
# tasks-lock.py — portable advisory lock for the harness board write path.
#
# Guards every persisted `state/tasks.json` mutation with a single advisory
# `fcntl.flock` on the sibling lockfile `state/tasks.json.lock` (resolved under
# HARNESS_DIR — see below), so concurrent writers (E15 parallel fix chains) can never
# lose an update (last-writer-wins clobber). The whole critical section runs in
# ONE process holding ONE lock:
#
#     acquire flock (bounded)  →  RE-READ state/tasks.json from disk  →
#     apply the single mutation  →  validate (JSON parse + schema)   →
#     atomic write (temp + os.replace)  →  release.
#
# Re-reading INSIDE the lock is the entire point: a second concurrent writer
# sees the first writer's committed result before applying its own mutation.
#
# Portability (R9): uses only the CPython stdlib `fcntl` (present on every POSIX
# platform the harness targets); it does NOT shell out to the Linux-only
# `flock(1)` binary, which is absent on the macOS dev platform.
#
# The `store.on_write_command` hook is intentionally NOT run here — the caller
# runs it AFTER this process returns (i.e. after the lock is released, R7).
#
# Usage:
#   tasks-lock.py set-status <id> <status> [--evidence REF]... [--timeout SECONDS]
#       Set the status of the object <id> addresses (feature id `E06-F06` or
#       epic id `E06`) in state/tasks.json, under the lock.
#       Moving ANY feature to `done` requires --evidence (E99-F102): once for a
#       single-repo feature, and once per slice repository — in the bound form
#       `--evidence <repo>=<ref>` — for a SLICED one. Each ref is RESOLVED and
#       checked against the default branch per the decision table below; the write is
#       REFUSED only where the claim is provably wrong.
#   tasks-lock.py apply --mutator <path> [--timeout SECONDS]
#       Run an external mutator on the freshly-read board (used for tests and
#       for callers that express a different single mutation). The mutator is a
#       python file exposing `mutate(data) -> data`.
#
# HARNESS_DIR (env) selects the board root. Precedence (R12), fail-SAFE:
#   (1) an explicit HARNESS_DIR env override always wins (escape hatch, highest
#       precedence). The /sdd-fix-parallel coordinator (F03) sets this to the
#       canonical main harness directory for every worktree worker, which makes
#       ALL git layouts correct regardless of what auto-discovery can recover.
#   (2) else, IF AND ONLY IF we are inside a genuine LINKED worktree (`git
#       rev-parse --git-dir` != `--git-common-dir`), best-effort auto-discovery for
#       the STANDARD `.git` worktree layout: a linked worktree's
#       `git rev-parse --git-common-dir` points at the MAIN repo's `.git` dir, so
#       its parent is the main worktree root. We ACCEPT this canonical root ONLY IF
#       the board actually exists there (`<canonical>/state/tasks.json`). Every
#       worker, in any standard-layout worktree, then reads/writes the SAME
#       state/tasks.json and contends on the SAME state/tasks.json.lock inode, so
#       the no-lost-update guarantee (R1) holds across worktrees, not just within
#       one directory. A PRIMARY checkout is NEVER remapped — it already IS the
#       main working tree, and under `git init --separate-git-dir`/submodules the
#       parent of its (external) common dir is an unrelated directory that could
#       otherwise be mistaken for the main worktree and silently written.
#   (3) else, decide by whether we are inside a LINKED git worktree:
#       - IF inside a linked worktree (a parallel-fix worker) but auto-discovery
#         did NOT yield an existing canonical board — as happens under exotic
#         layouts (`git init --separate-git-dir`, submodules) where the main
#         worktree path is provably UNRECOVERABLE from a linked worktree — then
#         FAIL LOUDLY (non-zero, actionable message) demanding an explicit
#         HARNESS_DIR. We NEVER silently fall back to the linked worktree's OWN
#         board — that would be a silent wrong-board write defeating the
#         shared-board guarantee.
#       - ELSE (not in a worktree at all: the ordinary single-repo / self-location
#         case, i.e. serial /sdd-next) fall back to this helper's own self-location
#         (parent-of-parent of __file__) — the source (tools/tasks-lock.py) and
#         installed (.harness/tools/tasks-lock.py) layouts both work from ANY cwd.
#
# This makes the standard worktree layout work automatically, exotic layouts fail
# safe (loud + actionable) instead of corrupting board state, and the F03
# coordinator's HARNESS_DIR injection makes ALL layouts correct.
#
# Standard-layout resolution (case 2): we preserve the source-vs-installed layout
# by computing the harness subpath as the helper's self-located dir RELATIVE to
# the current worktree toplevel (`git rev-parse --show-toplevel`), then
# re-applying that same relative subpath under the main worktree root (source →
# <main>/state/…; installed → <main>/.harness/state/…). Git runs via subprocess
# with the helper's OWN tools/ directory as cwd (`os.path.dirname(__file__)`) — a
# path that is inside the current worktree in BOTH the source (<root>/tools) and
# installed (<root>/.harness/tools) layouts, so discovery resolves the MAIN
# worktree from any linked worktree. (Using the PARENT of the self-located harness
# dir would escape the repo in the source layout, where the harness dir IS the
# toplevel.) On ANY git failure (not a repo, git absent, timeout, unexpected
# layout) we fall through to the case-3 decision — never crash, never block.

import argparse
import errno
import fcntl
import glob
import importlib.util
import io
import json
import math
import os
import re
import stat
import subprocess
import sys
import time

# Bounded lock acquisition: a single named constant. Short enough to surface a
# stuck holder quickly, long enough that a legitimate held critical section
# (a re-read + small JSON write) never times out under 2-3-way contention.
# A human may tune this at the gate; the requirement is only "bounded + clear
# error, never a silent hang" (R5).
DEFAULT_TIMEOUT_SECONDS = 10.0
_POLL_INTERVAL_SECONDS = 0.05

TASKS_REL = os.path.join("state", "tasks.json")
LOCK_REL = os.path.join("state", "tasks.json.lock")
SCHEMA_REL = os.path.join("store", "tasks.schema.json")


def _die(msg):
    sys.stderr.write("tasks-lock: %s\n" % msg)
    sys.exit(1)


def _self_harness_dir():
    """Self-located board root: parent-of-parent of this file's absolute path.

    The helper lives at <HARNESS_DIR>/tools/tasks-lock.py, so the harness dir is
    the parent of the parent of __file__. Robust to any cwd and correct in both
    the source and installed (.harness/tools/) layouts.
    """
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _git(args, cwd):
    """Run `git <args>` in <cwd>, returning stripped stdout or None on ANY error.

    Never raises and never blocks: a bounded timeout, and any non-zero exit,
    missing git binary, or timeout maps to None so the caller falls back to
    self-location.
    """
    try:
        out = subprocess.run(
            ["git"] + list(args),
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    text = out.stdout.decode("utf-8", "replace").strip()
    return text or None


def _in_linked_worktree():
    """True iff the helper is running inside a LINKED git worktree.

    A linked worktree is a parallel-fix worker (F02/F03): git keeps its
    per-worktree git dir (`git rev-parse --git-dir`, e.g. a
    `<common>/worktrees/<name>` path) DISTINCT from the shared common dir
    (`git rev-parse --git-common-dir`, the MAIN repo's `.git`). For a PRIMARY
    checkout the two are IDENTICAL — including `git init --separate-git-dir` and
    submodule primaries, whose git dir simply lives outside the working tree but
    is still the single common dir (there is no separate per-worktree dir). So the
    ONLY reliable discriminant is `--git-dir` vs `--git-common-dir`:

      * EQUAL   → PRIMARY checkout (colocated, separate-git-dir, or submodule
                  primary) → NOT linked → serial self-location applies.
      * DISTINCT → genuine LINKED worktree → the loud-fail-if-no-canonical-board
                  behavior applies.

    Comparing the common dir's PARENT against the worktree toplevel (the prior
    approach) misclassified separate-git-dir/submodule PRIMARIES as linked,
    because their common dir sits outside the toplevel even though nothing is
    linked. Both paths are realpath-normalized before comparison. Returns False on
    any git failure (not a repo, git absent) so a non-repo self-location run is
    never misclassified as a worktree.
    """
    cwd = os.path.dirname(os.path.abspath(__file__))  # the tools/ dir

    git_dir = _git(["rev-parse", "--git-dir"], cwd=cwd)
    if git_dir is None:
        return False  # not a git repo at all → not a worktree; self-locate.
    common_dir = _git(["rev-parse", "--git-common-dir"], cwd=cwd)
    if common_dir is None:
        return False

    # Both may be reported relative to the cwd we ran git in; anchor + normalize
    # so equal git dirs compare equal despite symlinked temp dirs (macOS /var →
    # /private/var) or relative-vs-absolute reporting.
    git_dir = os.path.realpath(os.path.join(cwd, git_dir))
    common_dir = os.path.realpath(os.path.join(cwd, common_dir))

    # DISTINCT ⇒ genuine linked worktree; EQUAL ⇒ any PRIMARY checkout.
    return git_dir != common_dir


def _canonical_harness_dir():
    """Map the self-located harness dir onto the MAIN worktree root (R12).

    Applies ONLY inside a genuine LINKED worktree. A PRIMARY checkout already IS
    the main working tree, so it must self-locate: under
    `git init --separate-git-dir` (and submodule primaries) the common `.git` dir
    lives outside the checkout, and its parent is an unrelated directory — if that
    directory happened to hold another harness board, remapping would silently
    write the WRONG board. Gating on `_in_linked_worktree()` removes that class of
    mis-resolution entirely.

    Returns the canonical board root in the main working tree ONLY when that
    board actually exists there (`<canonical>/state/tasks.json`); otherwise None
    (not a linked worktree, git is unavailable, the layout is unexpected/exotic,
    or the resolved main root carries no board) — in which case the caller applies
    the case-3 fail-safe decision.

    The main worktree root is the parent of the common `.git` dir that a linked
    worktree's `git rev-parse --git-common-dir` reports. We then preserve the
    source-vs-installed layout by re-applying the helper's harness subpath
    (relative to the CURRENT worktree toplevel) under that main root.
    """
    # PRIMARY checkouts (colocated, separate-git-dir, submodule) self-locate: the
    # checkout IS the main worktree, so there is nothing to remap and the parent
    # of a separate common dir must never be mistaken for a main worktree root.
    if not _in_linked_worktree():
        return None
    # realpath everywhere: git reports fully symlink-resolved paths (e.g. macOS
    # /var → /private/var), while self_dir comes from __file__; normalising both
    # sides makes the relpath subtraction below correct despite symlinked temp
    # dirs and worktree roots.
    self_dir = os.path.realpath(_self_harness_dir())
    # Run git discovery from a cwd GUARANTEED to be inside the current worktree
    # for BOTH layouts. The helper's own directory (the tools/ dir) is always
    # inside the worktree — source: <root>/tools, installed: <root>/.harness/tools.
    # Do NOT use os.path.dirname(self_dir): in the SOURCE layout self_dir is the
    # worktree TOPLEVEL, so its parent is OUTSIDE the repo and both rev-parse
    # calls then fail or resolve a DIFFERENT repo, silently defeating R12.
    git_dir = os.path.dirname(os.path.abspath(__file__))  # the tools/ dir

    common_dir = _git(["rev-parse", "--git-common-dir"], cwd=git_dir)
    if common_dir is None:
        return None
    # --git-common-dir may be relative to the cwd we ran git in; anchor it.
    common_dir = os.path.realpath(os.path.join(git_dir, common_dir))
    main_root = os.path.dirname(common_dir)  # parent of the common `.git` dir
    if not os.path.isdir(main_root):
        return None

    toplevel = _git(["rev-parse", "--show-toplevel"], cwd=git_dir)
    if toplevel is None:
        return None
    toplevel = os.path.realpath(toplevel)

    # Harness subpath = self-located harness dir relative to the current worktree
    # toplevel (source layout → ""; installed layout → ".harness"). Re-apply it
    # under the main worktree root so both layouts resolve canonically.
    rel = os.path.relpath(self_dir, toplevel)
    if rel.startswith(os.pardir + os.sep) or rel == os.pardir:
        # self_dir is not under the worktree toplevel — unexpected; fall back.
        return None
    if rel == os.curdir:
        rel = ""

    canonical = os.path.normpath(os.path.join(main_root, rel))
    # ACCEPT the auto-resolved canonical root ONLY if the board actually exists
    # there. Under `git init --separate-git-dir` / submodules the parent of the
    # common `.git` dir is the metadata dir, NOT the real main worktree, so this
    # existence check rejects the wrong path and lets the caller fail SAFE (loud)
    # rather than resolve HARNESS_DIR to a boardless metadata dir.
    if not os.path.exists(os.path.join(canonical, TASKS_REL)):
        return None
    return canonical


def _harness_dir():
    """Resolve the board root (see module docstring for full precedence), fail-SAFE.

    (1) explicit HARNESS_DIR env override [highest precedence — the F03
    coordinator sets this]; (2) best-effort auto-discovery of the canonical
    main-worktree root for the STANDARD `.git` worktree layout, accepted only when
    the canonical board exists there; (3) otherwise, decide by worktree context:
    inside a LINKED worktree (a parallel-fix worker) with no existing canonical
    board → FAIL LOUDLY demanding explicit HARNESS_DIR (never silently write the
    linked worktree's OWN board); NOT in a worktree at all → self-location
    fallback (the ordinary serial /sdd-next path, unchanged).
    """
    override = os.environ.get("HARNESS_DIR")
    if override:
        return override
    canonical = _canonical_harness_dir()
    if canonical is not None:
        return canonical
    # Auto-discovery did NOT yield an existing canonical board. Fail SAFE: if we
    # are inside a linked worktree (a parallel-fix worker under an exotic layout
    # where the main worktree path is unrecoverable from git — separate-git-dir,
    # submodules), do NOT silently fall back to the linked worktree's OWN board
    # (a wrong-board write that defeats the shared-board guarantee). Demand an
    # explicit HARNESS_DIR instead — which the /sdd-fix-parallel coordinator sets.
    if _in_linked_worktree():
        _die(
            "running inside a linked git worktree but could not resolve the "
            "canonical board; set HARNESS_DIR to the main harness directory "
            "explicitly (the /sdd-fix-parallel coordinator sets this "
            "automatically)"
        )
    # Ordinary single-repo / non-worktree case: self-locate (serial /sdd-next).
    return _self_harness_dir()


def _acquire(lock_fd, lockfile, timeout):
    """Bounded, non-blocking poll for an exclusive advisory lock (R3, R5)."""
    deadline = time.monotonic() + timeout
    while True:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return
        except OSError as exc:
            if exc.errno not in (errno.EACCES, errno.EAGAIN):
                raise
            if time.monotonic() >= deadline:
                _die(
                    "could not acquire advisory lock on %s within %.3gs "
                    "(another writer is holding it); aborting rather than "
                    "blocking indefinitely or writing unlocked"
                    % (lockfile, timeout)
                )
            time.sleep(_POLL_INTERVAL_SECONDS)


def _load_shared_validator(want_module=False):
    """Import the SINGLE canonical validator shared with init.sh.

    `tools/validate-board.py` is the one source of truth for what a valid board
    is; init.sh runs it as a CLI and this helper imports its `validate(data,
    schema) -> list[str]` so the guarded write fail-stops (R4) on EXACTLY the
    same rules the gate enforces. Previously this file carried a partial
    hand-rolled copy that silently accepted boards init.sh rejected (wrong `sdd`
    type, malformed slices, …); the shared import removes that drift at its root.

    Loaded by absolute path from the sibling file so it works in both the source
    (tools/) and installed (.harness/tools/) layouts regardless of sys.path.
    """
    validator_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                  "validate-board.py")
    spec = importlib.util.spec_from_file_location("_validate_board", validator_path)
    if spec is None or spec.loader is None:
        _die("could not load shared validator from %s" % validator_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not hasattr(module, "validate"):
        _die("shared validator %s does not define validate(data, schema)"
             % validator_path)
    # The frontmatter sync below reads spec/epic files with the validator's OWN parser
    # (`_frontmatter`, `_spec_files`, `_resolve_under_root`) rather than a second copy.
    # The gate and the writer must agree byte-for-byte on what a file declares — a writer
    # that parsed frontmatter its own way would reintroduce exactly the divergence this
    # whole feature exists to remove.
    return module if want_module else module.validate


def _load_schema(schema_path):
    with open(schema_path) as fh:
        return json.load(fh)


def _import_mutator(path):
    spec = importlib.util.spec_from_file_location("_tasks_lock_mutator", path)
    if spec is None or spec.loader is None:
        _die("could not load mutator module from %s" % path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not hasattr(module, "mutate"):
        _die("mutator %s does not define mutate(data) -> data" % path)
    return module.mutate


def _string_mask(text):
    """Per-index mask: 1 where `text[i]` lies inside a JSON string literal.

    One forward pass respecting backslash escapes. Structural scans consult this
    so a `{`, `}`, `[` or `]` appearing inside a title or path never miscounts
    nesting. Computed ONCE per resolution and threaded through the scans below
    (recomputing it per call would make id resolution quadratic on large boards).
    """
    mask = bytearray(len(text))
    escaped = False
    instr = False
    for i, ch in enumerate(text):
        if instr:
            mask[i] = 1
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                instr = False  # this closing quote is still part of the string
        else:
            if ch == '"':
                instr = True
                mask[i] = 1
    return mask


def _scan_object_span(text, inner_pos, in_string=None):
    """Given a char offset inside a JSON object, return (start, end) of that object.

    [start:end) spans from the object's opening `{` to the matching closing `}`
    (inclusive of both braces). The scan is brace-aware AND string-aware: braces
    inside string literals (and their escapes) are ignored, so a `{`/`}` in a
    title or path never miscounts the nesting. Returns None if a balanced object
    cannot be delimited around `inner_pos`.

    We first walk backwards to the `{` that opens the object containing
    `inner_pos` (tracking string state forward from the document start so we know,
    at every index, whether a brace is structural), then walk forward from that
    `{` counting depth to its match.
    """
    if in_string is None:
        in_string = _string_mask(text)

    # Walk backward from inner_pos to the opening `{` of the enclosing object,
    # skipping any nested `{...}`/`}` pairs and ignoring braces inside strings.
    depth = 0
    start = None
    i = inner_pos
    while i >= 0:
        ch = text[i]
        if not in_string[i]:
            if ch == "}":
                depth += 1
            elif ch == "{":
                if depth == 0:
                    start = i
                    break
                depth -= 1
        i -= 1
    if start is None:
        return None

    # Walk forward from the opening `{` to its matching `}`.
    depth = 0
    j = start
    n = len(text)
    while j < n:
        ch = text[j]
        if not in_string[j]:
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return (start, j + 1)
        j += 1
    return None


def _depth1_key_matches(text, in_string, obj_start, obj_end, pattern):
    """Yield `pattern` matches that are DIRECT members of the object [obj_start, obj_end).

    A match nested inside a child object (a slice, an extension object) is
    skipped: the smallest object enclosing the match must be this object itself.
    """
    for m in pattern.finditer(text, obj_start, obj_end):
        enclosing = _scan_object_span(text, m.start(), in_string)
        if enclosing is not None and enclosing[0] == obj_start:
            yield m


def _depth1_value_start(text, in_string, obj_start, obj_end, key):
    """Offset of the VALUE of the direct member `key`, or None if absent."""
    pat = re.compile(r'"' + re.escape(key) + r'"\s*:\s*')
    for m in _depth1_key_matches(text, in_string, obj_start, obj_end, pat):
        return m.end()
    return None


def _iter_array_object_spans(text, in_string, arr_start):
    """Yield (start, end) spans of the DIRECT object elements of the array at `arr_start`.

    `arr_start` is the offset of the array's `[`. Objects nested deeper inside an
    element are not yielded — only the elements themselves.
    """
    if arr_start is None or arr_start >= len(text) or text[arr_start] != "[":
        return
    depth = 0
    i = arr_start
    n = len(text)
    while i < n:
        if not in_string[i]:
            ch = text[i]
            if ch == "[":
                depth += 1
            elif ch == "]":
                depth -= 1
                if depth == 0:
                    return
            elif ch == "{" and depth == 1:
                span = _scan_object_span(text, i, in_string)
                if span is None:
                    return
                yield span
                i = span[1]
                continue
        i += 1


def _depth1_id(text, in_string, obj_start, obj_end):
    """The direct `id` string value of an object, or None.

    On a duplicated `id` member we return the LAST, matching `json.loads`
    semantics, so object SELECTION always agrees with the parsed board the
    validator sees — a first-match walk could otherwise pick an object whose
    effective id is something else entirely.
    """
    pat = re.compile(r'"id"\s*:\s*"([^"]*)"')
    value = None
    for m in _depth1_key_matches(text, in_string, obj_start, obj_end, pat):
        value = m.group(1)
    return value


def _find_status_span(text, target_id):
    """Locate the `"status": "<value>"` span of the object <target_id> addresses.

    Returns (start, end, old_status) into `text`, where [start:end) is exactly the
    quoted status VALUE token (we replace only the value between the quotes).
    Deriving the span from the ORIGINAL text (not a re-serialization) is what makes
    the write minimal-diff: every other byte — indentation, inline vs multiline
    arrays, trailing newline — is preserved verbatim (R6).

    Resolution is STRUCTURAL (R13) in BOTH senses — it never trusts textual order:

    * We do not accept the first textual `"id": "<target_id>"` in the DOCUMENT.
      The schema permits additional properties, so a board may carry an extension
      object (a mirror record, a cache entry) whose `id` equals a real feature or
      epic id. If such an object appeared earlier in the file and had a `status`,
      a document-wide search would silently retitle THAT object's status and leave
      the addressed task untouched — and the result still schema-validates. So we
      WALK the board: root → `epics[]` elements → each epic's `features[]`
      elements, matching only a DIRECT `id` member at each level. Only a genuine
      epic or feature is addressable; anything outside those two arrays is invisible.
    * Within the matched object we replace the `status` that is a DIRECT member
      (not merely the first `"status"` at-or-after the id, and not a nested
      slice's), so a board ordering `status` before `id` cannot shift the patch
      onto the next object.

    Returns None if the id (or a status key within its object) is not found, so the
    caller can fail-stop exactly like before.
    """
    in_string = _string_mask(text)

    # Delimit the root object (first STRUCTURAL `{`, i.e. not one inside a string).
    root_brace = None
    for i, ch in enumerate(text):
        if ch == "{" and not in_string[i]:
            root_brace = i
            break
    if root_brace is None:
        return None
    root = _scan_object_span(text, root_brace, in_string)
    if root is None:
        return None

    def status_span_of(obj_start, obj_end):
        # JSON permits (while discouraging) DUPLICATE members. If the target
        # object carries two `status` members, `json.loads` keeps the LAST while
        # a first-match text patch rewrites the FIRST — the helper would exit 0
        # having persisted a board whose EFFECTIVE status never changed, i.e. the
        # sole supported write path silently no-ops the requested transition.
        # Rather than guess which token is authoritative, fail-stop loudly.
        pat = re.compile(r'"status"\s*:\s*"([^"]*)"')
        found = [
            m for m in _depth1_key_matches(text, in_string, obj_start, obj_end, pat)
        ]
        if len(found) > 1:
            _die(
                "object %r has %d direct 'status' members; refusing to patch an "
                "ambiguous board (json parsing would keep the LAST while a text "
                "patch rewrites the FIRST, silently no-opping the transition). "
                "Remove the duplicate key and re-run." % (target_id, len(found))
            )
        for m in found:
            return (m.start(1), m.end(1), m.group(1))
        return None

    epics_start = _depth1_value_start(text, in_string, root[0], root[1], "epics")
    for e_start, e_end in _iter_array_object_spans(text, in_string, epics_start):
        if _depth1_id(text, in_string, e_start, e_end) == target_id:
            return status_span_of(e_start, e_end)
        feats_start = _depth1_value_start(text, in_string, e_start, e_end, "features")
        for f_start, f_end in _iter_array_object_spans(text, in_string, feats_start):
            if _depth1_id(text, in_string, f_start, f_end) == target_id:
                return status_span_of(f_start, f_end)
    return None


def _refuse_if_parked(text, target_id):
    """A park holds against a status transition (E06-F07).

    A park that a transition silently clears is not a park — it is a suggestion, which is
    exactly the advisory-prose failure the field exists to end. So `set-status` refuses,
    names the reason (so the operator does not have to go read the board to learn why
    their write bounced), and points at the unpark step. Unparking is a separate explicit
    act via the existing `apply --mutator` escape hatch, after which the ordinary
    transition succeeds — no new write verb.

    READ-ONLY. It parses `text` only to inspect; it never reserializes, so the
    minimal-diff text patch that follows is completely unaffected. A board too malformed
    to parse is left to the post-transform schema validation, which reports it properly
    instead of being masked by a park message here.

    Epics carry no `parked` (features only, by decision), so an epic id simply falls
    through.
    """
    try:
        data = json.loads(text)
    except ValueError:
        return
    if not isinstance(data, dict):
        return
    for ep in data.get("epics") or []:
        if not isinstance(ep, dict):
            continue
        for ft in ep.get("features") or []:
            if not isinstance(ft, dict) or ft.get("id") != target_id:
                continue
            park = ft.get("parked")
            if isinstance(park, dict) and park.get("reason"):
                # E99-F77: an owner gate refuses with the SAME force but a different
                # instruction. "unpark it" alone invites the operator to clear the gate
                # and carry on, which for an owner gate would walk the feature to `done`
                # while the attestations it is waiting on are still outstanding. Name who
                # has to act first; the unpark step is still how you proceed afterwards.
                if park.get("gate") == "owner":
                    _die(
                        "%s is owner-gated (%s) — a person must act first, then unpark it "
                        "before changing status" % (target_id, park["reason"])
                    )
                _die(
                    "%s is parked (%s) — unpark it before changing status"
                    % (target_id, park["reason"])
                )
            return


# ---------------------------------------------------------------------------
# Landing evidence on `done` (E99-F102 contract + E99-F129 verification).
#
# `done` is what stops the selector routing an item, so a feature marked `done`
# whose work never merged is both unshipped AND unreachable — nothing will pick it
# up again, and downstream briefs cite it as a landed mechanism. An audit of 148
# `done` features across seven repos found FOUR such items — E99-F58 and E99-F59
# (commits on never-pushed local branches), E09-F02 and E99-F29 (their only PRs
# closed UNMERGED) — none of them found by a check. E99-F29 is the harm already in
# the corpus: the board title of E99-F32, the feature that actually shipped the
# Spanish outcome, cites E99-F29 as landed.
#
# ⚠️ THE ONE QUESTION, ANSWERED ONCE — the decision table (E99-F129).
#
# Verification is not a feature; it is a single question asked of every ref: WHAT
# HAPPENS WHEN VERIFICATION IS IMPOSSIBLE? The predecessor answered it per input, as
# fixes accumulated, and five review rounds each found the same shape again — a
# default branch guessed by name, one sha attesting many slices, a stale local tip, a
# slice repository located by directory basename, an unrecognised hash format. Each
# was one more input for which "I cannot check" silently became "fine, proceed". So
# the answer is a TABLE, written before the code, and the code below is that table in
# order. `store/local.md` and the CHANGELOG carry the same table; the suite mirrors it
# row for row, each with a control.
#
#   #  situation                                              outcome
#   ── ────────────────────────────────────────────────────── ───────────────────
#   1  `none:<why>`                                           declared
#   2  ref resolves to no git object anywhere                 unchecked + warning
#   3  binding names a repo the MANIFEST does not contain     REFUSE
#   4  manifest names it, directory absent/unreadable here    unchecked
#   5  repo located, object unknown in it                     unchecked
#   6  default branch undeterminable                          unchecked
#   7  ancestry checkable and TRUE                            ancestor
#   8  ancestry FALSE and the base tip is confirmed current   REFUSE
#   9  ancestry FALSE, tip NOT confirmed                      unchecked
#
# THE GOVERNING ASYMMETRY, and the reason the table leans the way it does:
#
#   * A FALSE ATTESTATION is worse than no attestation. The record then carries the
#     authority of a check that never happened, and every later reader — a brief, a
#     re-audit, a dependent feature — treats it as settled. So `ancestor` is emitted
#     ONLY from row 7, where ancestry was actually computed against a base this
#     checkout could name.
#   * A FALSE REFUSAL is worse than a silent pass. A guard that rejects genuinely
#     merged work is one that gets routed around, switched off, or worked around with
#     `none:<why>` — after which it protects nothing at all. So refusal is reserved
#     for the two situations where the claim is provably wrong: row 8 (the work is
#     demonstrably not on a base we confirmed is current) and row 3 (the claim names
#     a repository the project does not declare — malformed, and checkable with no
#     I/O at all).
#
# Rows 3 and 4 are the distinction that was missing: a MALFORMED CLAIM is the
# operator's error and is refused; NOT BEING ABLE TO SEE A REPOSITORY FROM HERE is
# this checkout's limitation and degrades. Row 3 is not a new policy — `next-task.mjs`
# already raises `manifest-error` for a slice naming a repository absent from the
# manifest, so a board that would be refused here is one the selector already halts
# on. Row 3 applies ONLY where a manifest is configured AND readable: with no manifest
# there is no authority to call the claim malformed, so repository resolution falls
# back to a best-effort search and every miss degrades to row 4/5.
#
# Rows 8 and 9 are the stale-tip lesson. `refs/remotes/origin/*` is a local SNAPSHOT:
# after a PR merges, a clone that has not fetched still points `origin/main` at an
# older commit, and an ancestry test against it reports "not merged" about work that
# IS on the default branch. Measured against the predecessor: a commit that was
# literally the remote's main tip was refused with the same message as one that had
# never left the laptop. So a refusal is confirmed against the remote's real tip
# first, and an unconfirmable one degrades (row 9) instead of blocking.
#
# What this does NOT attempt, deliberately: confirming the tip on the ACCEPT side.
# For a stale local tip to produce a wrong `ancestor` the remote would have to have
# been rewritten; a wrong refusal needs only an ordinary merge, which is the common
# case. Probing on every accept would put a bounded network call on the happy path
# for an adversarial case, so row 7 answers from the local tip.
#
# ── WHICH REPOSITORY IS THIS CLAIM ABOUT? the identity contract ──────────────
#
# The nine rows above enumerate VERIFICATION OUTCOMES for a (ref, repository) pair.
# They presume that pair is already settled. It is not — it is established by a search
# order, a path out of a manifest, and an assumption that a ref names one repository —
# and that presumption has produced findings four separate times: a slice repo located
# by directory basename; the manifest missing from the plan→write fingerprint; a ref
# resolving in several candidates and silently taking the first; and a lexical path in
# the witness that a retargeted symlink walks straight past. Those are not rows. They
# are one missing dimension, so it is stated here, before the code, like the rows.
#
# I1 — WHEN MAY A REF BE RESOLVED BY SEARCH?
#   A BINDING (`<repo>=<ref>`) names the repository, so no search happens. The bound
#   form is legal on ANY feature now, sliced or not: while nothing verified the name it
#   was refused on a single-repo feature (it would have recorded a repository nobody
#   checked), but the name is checked here, and a binding is the operator's only way to
#   say WHICH repository an ambiguous ref belongs to.
#   Without a binding the ref is searched across the nearby repositories, and the search
#   must land on EXACTLY ONE. If two or more resolve it, the claim is AMBIGUOUS and is
#   REFUSED — naming the candidates and the two remedies (pass the immutable commit id,
#   or bind it). Not "take the first": `_repo_candidates()` tries the harness dir and its
#   parent BEFORE the children, so the first hit is the umbrella's own bookkeeping
#   repository — the one repository that never contains feature work. Measured, on an
#   umbrella whose board repo and child both have `main`: `--evidence main` recorded
#   `{"verified": "ancestor", "repo": "umb"}`, attesting a board-keeping commit for a
#   feature whose work is in the child. Any ordering here is a guess; the only answer
#   that is not a guess is to require the claim to be unambiguous. This refusal is the
#   row-3 kind — a malformed claim, checkable and with a legal remedy — not the row-8
#   kind, so it does not risk rejecting merged work.
#
# I2 — WHAT IS A REPOSITORY'S IDENTITY?
#   For the fingerprint: the REALPATH of the work tree, with the lexical path kept beside
#   it. A lexical path is not an identity — `path: ../alpha` where `alpha` is a symlink
#   reads identically before and after the link is retargeted, while the repository
#   underneath is a different one. Keeping both catches both moves: the manifest text
#   changing (lexical differs) and the link changing (realpath differs).
#   For deciding whether two candidates are "two repositories": the realpath of the
#   repository's COMMON GIT DIR, so linked worktrees of one repository collapse to one
#   candidate instead of reading as ambiguity and refusing a claim that is not ambiguous.
#   What realpath does NOT cover, stated rather than implied: a repository REPLACED IN
#   PLACE — same realpath, different objects. That is deliberate. The fingerprint is a
#   coherence check against concurrent HARNESS activity across a sub-second window, not a
#   defence against an adversary swapping a checkout under a running process. The
#   stronger identity — hashing the base tip into the witness — would abort whenever
#   anyone else's merge advanced the default branch, i.e. routinely, in exactly the busy
#   repositories this is meant to serve; and a guard that aborts routinely is one people
#   stop reading.
#
# I3 — DOES THE SINGLE-REPO PATH NEED THE SAME DISCIPLINE?
#   Yes, and it did not have it: the fingerprint covered only sliced features, so an
#   unsliced resolution carried no identity stability at all. The witness now covers
#   both — for a sliced feature the manifest's (repo → lexical, realpath) entries; for an
#   unsliced one the chosen repository AND the candidate set that made the choice
#   unambiguous, so a repository appearing beside the board between plan and write aborts
#   instead of silently changing what the claim was about. Both are recomputed inside the
#   lock with filesystem calls only — no child process, no network — so the lock still
#   holds nothing but the pure re-read → patch → validate → replace.
#
# ── how a ref becomes an object: ask git, never a regex ──────────────────────
# The predecessor pattern-matched `^[0-9a-fA-F]{7,40}$` to decide what was worth
# resolving, which silently skipped SHA-256's 64-character ids — they fell through to
# "not a commit id" and were recorded unchecked. Nothing here pattern-matches an
# object id. Every non-`none:` value is handed to `git rev-parse --verify <ref>^{commit}`
# and git decides what is an object; anything git will not resolve is row 2.
#
# A consequence to be deliberate about: a BRANCH NAME resolves too, and a branch is a
# MOVING target — recording `main` as the landing would be an attestation that decays
# the moment the branch moves. So the record keeps BOTH, and they mean different
# things: `ref` is what the operator claimed, verbatim (unchanged from the contract
# half, and what a human recognises); `commit` is the immutable id that ref resolved
# to AT RECORD TIME, and it is what ancestry was actually computed on and what a later
# re-audit must re-check. `commit` is present exactly when this checkout resolved the
# object, so its presence is itself the signal that something was looked up; the schema
# additionally requires it wherever `verified` is the proved value, because an
# attestation nobody can re-check is the defect this whole feature exists to remove.
#
# ── why `slices[]` is NOT the attestation ────────────────────────────────────
# A sliced feature LOOKS attested: the schema refuses `done` unless every slice is
# `done` AND `merged`. But nothing in this harness ever WRITES `slice.merged` —
# every occurrence in tools/ is a read or a type assertion, and `store/local.md`
# tells the agent to set it through `apply --mutator`. It is hand-typed, i.e.
# exactly the say-so this flag replaces. E09-F02 is the proof: a SLICED feature,
# three slices all `merged: true`, whose first slice's own `pr` field points at
# viernes-infra#24 — closed, unmerged. So `--evidence` is required for EVERY feature
# `done`, sliced or not; exempting the weaker mechanism from the stronger one would
# ship that hole documented as safe. The slice invariant still applies
# independently — a sliced feature must satisfy BOTH.
#
# ── and why ONE ref cannot attest a SLICED feature ───────────────────────────
# A single feature-level value names no repository, so it attests no particular
# slice: one slice's merge commit would carry the whole feature to `done` while
# another slice sat unmerged. Evidence for a sliced feature is therefore BOUND PER
# SLICE REPOSITORY — `--evidence <repo>=<ref>`, repeated once per slice repo. A bare
# `--evidence <ref>` on a sliced feature is REFUSED (naming the required form and the
# repos), a binding naming a repo the feature has no slice in is REFUSED, a repeated
# binding is REFUSED, and a missing binding is REFUSED naming the repos still owed.
# The binding is what makes the follow-up's per-repository check EXPRESSIBLE at all;
# here it is enforced as a shape, and the record carries one entry per repository so
# the eventual verdict has somewhere to land.
#
# `set-status <feature> done` requires `--evidence REF` (single-repo feature) or
# `--evidence <repo>=REF` repeated once per slice repo (sliced feature), where REF is:
#
#   <anything>     anything git can resolve to a commit (a sha of any width, a tag,
#                  a branch) is VERIFIED per the table above; anything it cannot is
#                  transcribed and recorded unchecked (row 2).
#   none:<why>     work with no commit at all (a console action, a supersession).

_DECLARED_PREFIX = "none:"
# How much a `verified` value proves, weakest first. A sliced feature's feature-level
# record rolls up to the WEAKEST of its slices, so `ancestor` at the feature level
# means EVERY slice proved ancestry in its OWN repository — never that one of them did.
_VERIFIED_RANK = {"unchecked": 0, "declared": 1, "ancestor": 2}
# The one git config a repository can use to STATE its default branch when nothing
# published one. An explicit operator declaration is the only authoritative LOCAL
# signal; it is consulted last, so it can never override a default the remote publishes.
_DECLARED_DEFAULT_CONFIG = "harness.defaultBranch"
# A `--evidence` value may bind its ref to a slice repository: `<repo>=<ref>`. The
# repo side is deliberately a strict, narrow character class — a URL
# (`.../pull/1?a=b`) and a `none: why = x` reason both contain `=` but neither has a
# prefix that matches, so they are still read as plain refs and nothing silently
# reinterprets an unsliced feature's evidence as a binding.
_BINDING_RE = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*)=(.+)$", re.S)


# ── git plumbing: bounded, never raising, never blocking ─────────────────────


def _git_rc(args, cwd):
    """Run `git <args>` in <cwd>; return the exit code, or None if git could not run.

    `_git` above collapses every non-zero exit to None, which is right for discovery
    and wrong here: `merge-base --is-ancestor` reports "not an ancestor" as exit 1 and
    a broken invocation (bad object, not a repo) as something else, and conflating them
    would turn "this work never merged" into "we could not check" — the silent pass
    this whole feature exists to end.
    """
    try:
        out = subprocess.run(
            ["git"] + list(args),
            cwd=cwd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return out.returncode


def _git_out(args, cwd):
    """Run `git <args>` in <cwd>; return stdout (possibly EMPTY) or None on any error.

    `_git` collapses empty output to None, which is right for "did this resolve?"
    questions and wrong for ENUMERATIONS: a repository with no branches at all and a
    command that failed must not look alike to a caller about to count.
    """
    try:
        out = subprocess.run(
            ["git"] + list(args),
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    return out.stdout.decode("utf-8", "replace")


def _resolve_commit(repo, ref):
    """The immutable commit id `ref` names in `repo`, or None. NO PATTERN MATCHING.

    Asking git is the whole point: `^[0-9a-fA-F]{7,40}$` silently excluded SHA-256's
    64-character ids, and any hand-written pattern will exclude the next thing git
    learns to resolve. `--verify` with the `^{commit}` peel means a tag or a branch
    answers with the commit it points at, and anything that is not a commit answers
    with nothing.
    """
    return _git(["rev-parse", "--verify", "--quiet", ref + "^{commit}"], cwd=repo)


def _is_commit(repo, ref):
    """True iff `ref` names a commit in `repo`."""
    return _resolve_commit(repo, ref) is not None


# ── where a repository lives: the MANIFEST is the authority (rows 3 and 4) ───


def _config_value(hdir, dotted):
    """Read one dotted key out of harness.config.yaml, or None.

    A deliberately tiny indentation reader for the same two-level shape
    `tools/next-task.mjs` parses, and no more: the board write path must not acquire a
    YAML dependency, and the only key it needs is `umbrella.manifest`.
    """
    path = os.path.join(hdir, "harness.config.yaml")
    try:
        with io.open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, ValueError):
        return None
    section, _, leaf = dotted.partition(".")
    in_section = False
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        key, sep, value = line.strip().partition(":")
        if not sep:
            continue
        if indent == 0:
            in_section = key.strip() == section
            continue
        if in_section and key.strip() == leaf:
            return value.strip().strip('"').strip("'")
    return None


def _manifest_repos(hdir):
    """(state, {repo: absolute path}) from the umbrella manifest.

    state is "absent" (no manifest configured, or the file is not there — umbrella mode
    is off and there is no authority to call a claim malformed), "unreadable" (named but
    unusable, treated exactly like absent: this checkout's problem, not the operator's),
    or "present".

    ⚠️ `path:` is resolved relative to THE MANIFEST FILE'S OWN DIRECTORY, not to the
    harness dir and not by assuming the key is a directory name. The shipped example
    uses siblings (`../viernes-bff`) and nothing requires a key to equal its basename —
    the predecessor scanned the harness dir's parent for a child whose basename matched
    the key, so an aliased or relocated repository resolved NOWHERE and its unmerged
    evidence was accepted as `unchecked`. The manifest says where a repository is; that
    is what it is for.
    """
    rel = _config_value(hdir, "umbrella.manifest")
    if not rel:
        return "absent", {}
    mpath = os.path.join(hdir, rel)
    if not os.path.isfile(mpath):
        return "absent", {}
    try:
        with io.open(mpath, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, ValueError):
        return "unreadable", {}
    mdir = os.path.dirname(os.path.abspath(mpath))
    repos = {}
    repos_indent = None
    key_indent = None
    current = None
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if "\t" in raw[: len(raw) - len(raw.lstrip())]:
            return "unreadable", {}      # tab indentation: same refusal next-task makes
        indent = len(raw) - len(raw.lstrip(" "))
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        key, sep, value = line.strip().partition(":")
        if not sep:
            continue
        key = key.strip()
        value = value.strip()
        if repos_indent is None:
            if indent == 0 and key == "repos":
                repos_indent = indent
            continue
        if indent <= repos_indent:
            repos_indent = None          # left the repos mapping
            current = None
            continue
        if key_indent is None:
            key_indent = indent
        if indent == key_indent:
            current = key
            repos.setdefault(current, None)
        elif current is not None and key == "path" and value:
            repos[current] = os.path.normpath(os.path.join(mdir, value.strip('"').strip("'")))
    if not repos:
        return "unreadable", {}
    # A repo declared with no `path:` still EXISTS as a declaration (row 3 must not fire
    # for it); it simply cannot be located (row 4).
    return "present", repos


def _repo_identity(path):
    """A repository's identity for the fingerprint: (lexical path, realpath). See I2."""
    return (path, os.path.realpath(path))


def _same_repository(a, b):
    """True iff two candidate directories are the SAME repository (I2).

    Two linked worktrees are two directories and one repository; comparing paths would
    read them as an ambiguity and refuse a claim that is not ambiguous. `--git-common-dir`
    is what git itself uses to answer this.
    """
    ca = _git(["rev-parse", "--git-common-dir"], cwd=a)
    cb = _git(["rev-parse", "--git-common-dir"], cwd=b)
    if ca is None or cb is None:
        return False
    return os.path.realpath(os.path.join(a, ca)) == os.path.realpath(os.path.join(b, cb))


def _repo_candidates(hdir, pairs=False):
    """Repositories to search when NO manifest declares one — best effort, nearest first.

    (1) the harness dir itself (source layout: the harness repo root); (2) its parent
    (installed layout: the product repo holding `.harness/`); (3) the immediate children
    of (2) that are work trees. Directory probing only; no git process is spawned.
    """
    seen = []
    reals = []

    def add(path):
        if not path:
            return
        real = os.path.realpath(path)
        if real in reals:
            return
        if os.path.exists(os.path.join(real, ".git")):
            reals.append(real)
            seen.append((path, real))

    hdir = os.path.realpath(hdir)
    add(hdir)
    parent = os.path.dirname(hdir)
    add(parent)
    for root in (parent, hdir):
        try:
            entries = sorted(os.listdir(root))
        except OSError:
            continue
        for name in entries:
            if name.startswith("."):
                continue
            add(os.path.join(root, name))
    return seen if pairs else [real for _lex, real in seen]


def _locate_repo(repo_name, hdir):
    """Where a SLICE's repository is. Returns (dirs, row) — row 3 refuses, row 4 degrades.

    row is None when a directory was found; "3" when the manifest is the authority and
    does not declare this repository at all (a malformed claim, refused by the caller);
    "4" when it is declared but not usable from here (or when there is no manifest and
    the fallback search found nothing).
    """
    state, repos = _manifest_repos(hdir)
    if state == "present":
        if repo_name not in repos:
            return [], "3"
        path = repos[repo_name]
        if path and os.path.exists(os.path.join(path, ".git")):
            return [path], None
        return [], "4"
    # No usable manifest ⇒ no authority to call the claim malformed. Best-effort search,
    # and every miss is row 4: "I cannot see it from here".
    dirs = [p for p in _repo_candidates(hdir) if os.path.basename(p) == repo_name]
    return (dirs, None) if dirs else ([], "4")


# ── which branch counts as "the default" ─────────────────────────────────────


def _local_default_ref(repo, has_origin):
    """A repository's default branch from LOCAL signals only, or None. Never a name guess.

    Existence is not authority: taking the first of ("main", "master") that EXISTS
    recorded a commit that had never reached `trunk` as proved, on a remoteless repo
    whose real default was trunk. Two local signals survive that objection — an explicit
    `git config harness.defaultBranch`, and having exactly ONE local branch (where "the
    default" has no other candidate to be, which is the shape an umbrella root has).

    `HEAD` is deliberately NOT consulted: in a working checkout it doubles as "the branch
    you happen to be on", and the commonest way to reach this code is standing on the
    feature branch you just finished — trusting it would attest the unmerged commit under
    your feet. With an origin present, only the explicit declaration may speak: a clone
    holding one branch says nothing about a remote whose default is something else.
    """
    declared = _git(["config", "--get", _DECLARED_DEFAULT_CONFIG], cwd=repo)
    if declared:
        return declared if _is_commit(repo, declared) else None
    if has_origin:
        return None
    branches = _git_out(
        ["for-each-ref", "--format=%(refname:short)", "refs/heads/"], cwd=repo
    )
    if branches is None:
        return None
    names = [b for b in branches.split("\n") if b.strip()]
    if len(names) == 1 and _is_commit(repo, names[0]):
        return names[0]
    return None


def _default_ref(repo):
    """The repo's default branch ref, or None (row 6) — DISCOVERED, never guessed.

    Order: what the remote published (`refs/remotes/origin/HEAD`), else what the remote
    says now (`ls-remote --symref`), else what the repository can establish about itself
    without guessing. None is not a failure; it is the honest answer to "I could not
    tell", and the caller records unchecked.
    """
    head = _git(["symbolic-ref", "--quiet", "refs/remotes/origin/HEAD"], cwd=repo)
    if head:
        return head[len("refs/remotes/") :] if head.startswith("refs/remotes/") else head

    has_origin = _git(["remote", "get-url", "origin"], cwd=repo) is not None
    if not has_origin:
        return _local_default_ref(repo, has_origin=False)

    symref = _git(["ls-remote", "--symref", "origin", "HEAD"], cwd=repo)
    for line in (symref or "").splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "ref:" and parts[2] == "HEAD":
            branch = parts[1]
            if branch.startswith("refs/heads/"):
                ref = "origin/" + branch[len("refs/heads/") :]
                if _is_commit(repo, ref):      # usable only if we have it locally
                    return ref
            return None
    # The remote exists but could not be asked (offline, no auth). Only an explicit
    # declaration may answer for it.
    return _local_default_ref(repo, has_origin=True)


def _remote_tip(repo, base):
    """What the REMOTE currently has for the branch `base` tracks, or None.

    None means "not askable": `base` is not a remote-tracking ref (a declared or
    single local branch cannot be stale against anything), or the remote could not be
    reached.
    """
    if not base.startswith("origin/"):
        return None
    branch = "refs/heads/" + base[len("origin/") :]
    out = _git_out(["ls-remote", "origin", branch], cwd=repo)
    for line in (out or "").splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] == branch:
            return parts[0]
    return None


def _confirm_refutation(repo, commit, base):
    """Rows 8 and 9: a local "not an ancestor" is only a REFUSAL if the tip is CURRENT.

    Only a remote-tracking base can be stale — it is explicitly a local SNAPSHOT of a
    ref that lives elsewhere. A local branch (a single-branch remoteless repository, or
    one named by `harness.defaultBranch`) is not a cache of anything: its tip is the
    whole of the truth this repository has, so a refusal against it is already
    definitive (row 8).

    Returns (verdict, detail) with verdict in {"refuted", "ancestor", "stale"}.
    """
    if not base.startswith("origin/"):
        # A LOCAL base is definitive only when there is no remote for it to be stale
        # against. With an `origin` configured, a local base means discovery could not
        # reach the remote (`_default_ref` only falls back to a local signal after
        # `ls-remote` fails), so what "merged" means was never established — that is row
        # 9, not row 8. Measured: a commit already on the remote's `main` was REFUSED in
        # an offline clone carrying `harness.defaultBranch=main`.
        if _git(["remote", "get-url", "origin"], cwd=repo) is not None:
            return "stale", (
                "an `origin` is configured but could not be consulted, so this local "
                "base may not be what the remote calls its default branch"
            )
        return "refuted", None
    tip = _remote_tip(repo, base)
    if tip is None:
        return "stale", "the remote could not be asked for its current tip"
    local = _git(["rev-parse", "--verify", "--quiet", base + "^{commit}"], cwd=repo)
    if local == tip:
        return "refuted", None
    if not _is_commit(repo, tip):
        return "stale", (
            "the remote has moved to %s, which this checkout does not have" % tip[:12]
        )
    rc = _git_rc(["merge-base", "--is-ancestor", commit, tip], cwd=repo)
    if rc == 0:
        return "ancestor", None
    if rc == 1:
        return "refuted", None
    return "stale", "the ancestry check against the remote tip could not be run"


# ── the table itself ─────────────────────────────────────────────────────────


def _warn(msg):
    sys.stderr.write("tasks-lock: warning: %s\n" % msg)


def _unchecked(ref, repo_name, why, commit=None):
    """A row that could not reach a verdict: recorded, warned about, never a proof."""
    _warn("%s — recording it UNCHECKED. Nothing here proved the work merged." % why)
    record = {"ref": ref, "verified": "unchecked"}
    if commit is not None:
        record["commit"] = commit
    if repo_name is not None:
        record["repo"] = repo_name
    return record


def _refuse_ambiguous(ref, hits):
    """I1: an unbound ref that resolves in more than one repository attests nothing."""
    _die(
        "evidence %s resolves in %d different repositories (%s), so it does not say "
        "WHICH one this feature landed in — and taking the first would take the harness "
        "dir's own repository, which is searched before the children and is the one "
        "repository that never holds feature work. Pass the immutable commit id (which "
        "normally exists in only one of them), or bind the claim: --evidence <repo>=<ref>."
        % (ref, len(hits), ", ".join(os.path.basename(h) for h in hits))
    )


def _verify_in_repos(ref, repo_name, dirs, hdir, trace=None):
    """Rows 2/5/6/7/8/9 over a candidate list. Returns a record, or _die()s on 8.

    One repository proving ancestry wins over another's negative: a sha is legitimately
    an ancestor in the repository that owns the work and unknown in its siblings.
    """
    refuted = None       # (repo, base, commit) — row 8, only if nothing else proves it
    unbased = []         # row 6: object known here, no default branch nameable
    stale = []           # row 9: ancestry false, tip unconfirmed
    resolved = None      # any commit id we managed to resolve, for the record

    # I1 — IDENTITY BEFORE VERDICT. Establish WHICH repository the claim is about before
    # asking any of the nine rows about it. An unbound ref that resolves in several
    # repositories is ambiguous, and no ordering of the candidates can settle it.
    hits = [r for r in dirs if _resolve_commit(r, ref) is not None]
    if repo_name is None and len(hits) > 1:
        distinct = []
        for h in hits:
            if not any(_same_repository(h, d) for d in distinct):
                distinct.append(h)
        if len(distinct) > 1:
            _refuse_ambiguous(ref, distinct)
        hits = distinct
    if hits and trace is not None:
        trace.append((repo_name or "", ) + _repo_identity(hits[0]))
    for repo in (hits or dirs):
        commit = _resolve_commit(repo, ref)
        if commit is None:
            continue                                   # rows 2/5: unknown here
        resolved = resolved or commit
        base = _default_ref(repo)
        if base is None:
            unbased.append(os.path.basename(repo))     # row 6
            continue
        rc = _git_rc(["merge-base", "--is-ancestor", commit, base], cwd=repo)
        if rc == 0:                                    # ROW 7
            record = {
                "ref": ref,
                "commit": commit,
                "verified": "ancestor",
                "repo": repo_name or os.path.basename(repo),
                "base": base,
            }
            return record
        if rc != 1:
            continue                                   # the invocation itself failed
        verdict, detail = _confirm_refutation(repo, commit, base)
        if verdict == "ancestor":                      # ROW 7, via the remote's real tip
            return {
                "ref": ref,
                "commit": commit,
                "verified": "ancestor",
                "repo": repo_name or os.path.basename(repo),
                "base": base,
            }
        if verdict == "refuted":                       # ROW 8 (pending: another may prove)
            if refuted is None:
                refuted = (os.path.basename(repo), base, commit)
            continue
        stale.append((os.path.basename(repo), base, detail))   # ROW 9
    if refuted is not None:                            # ROW 8 — the only ancestry refusal
        where, base, commit = refuted
        # Name the repository the OPERATOR named (the manifest key / slice repo) rather
        # than the directory it happens to live in, and show the resolved id only when it
        # differs from what was typed — for a plain sha the parenthetical is noise, for a
        # branch name it is the whole point.
        named = repo_name or where
        shown = ref if commit.startswith(ref) or ref == commit else "%s → %s" % (ref, commit[:12])
        _die(
            "%s%s is NOT an ancestor of %s in %s, and %s is confirmed current — the work "
            "is not merged, so `done` would be false. Merge it and pass the merge commit, "
            "or pass %snone:<why> if there is no commit to point at."
            % (
                "slice repository %s: " % repo_name if repo_name else "",
                shown,
                base,
                named,
                base,
                "--evidence %s=" % repo_name if repo_name else "--evidence ",
            )
        )
    if stale:                                          # ROW 9
        where, base, detail = stale[0]
        return _unchecked(
            ref,
            repo_name,
            "evidence %s is not reachable from the LOCAL %s in %s, but that refusal "
            "could not be confirmed against the remote (%s), so refusing it might reject "
            "work that IS merged. Run `git -C %s fetch origin` and re-run for a "
            "definitive answer" % (ref, base, where, detail, where),
            commit=resolved,
        )
    if unbased:                                        # ROW 6
        return _unchecked(
            ref,
            repo_name,
            "evidence %s resolves in %s, but that repository names no default branch "
            "this checkout can trust (nothing published or reachable, and no `git config "
            "%s`)" % (ref, ", ".join(unbased), _DECLARED_DEFAULT_CONFIG),
            commit=resolved,
        )
    return _unchecked(                                 # ROWS 2 / 5
        ref,
        repo_name,
        "evidence %s could not be resolved to a commit in %s"
        % (ref, ("repository %s" % repo_name) if repo_name else
           ("any repository near %s" % hdir)),
    )


def _classify(ref, repo_name=None, hdir=None, trace=None):
    """One --evidence value → one landing record. THE DECISION TABLE, in order.

    `repo_name` is the slice repository the value was bound to (None for a single-repo
    feature, which searches the nearby repositories instead).
    """
    ref = ref.strip()
    if not ref:
        _die(
            "--evidence must not be empty"
            if repo_name is None
            else "--evidence %s=<ref>: the ref is empty" % repo_name
        )
    if ref.startswith(_DECLARED_PREFIX):               # ROW 1
        why = ref[len(_DECLARED_PREFIX) :].strip()
        if not why:
            _die(
                "--evidence none:<why> needs a reason after the colon — "
                "'no commit' with no explanation is the say-so this replaces"
            )
        record = {"ref": ref, "verified": "declared"}
        if repo_name is not None:
            record["repo"] = repo_name
        return record
    if repo_name is None:
        return _verify_in_repos(ref, None, _repo_candidates(hdir), hdir, trace)
    dirs, row = _locate_repo(repo_name, hdir)
    if row == "3":                                     # ROW 3 — malformed claim, REFUSED
        _die(
            "%s is not declared in the umbrella manifest, so evidence bound to it "
            "attests nothing: the manifest is what says where a repository lives, and a "
            "slice naming a repository it does not contain is a board `next-task.mjs` "
            "already halts on (manifest-error). Add it to the manifest, or correct the "
            "binding." % repo_name
        )
    if row == "4":                                     # ROW 4 — cannot see it from here
        return _unchecked(
            ref,
            repo_name,
            "repository %s is declared but cannot be read from this checkout, so "
            "evidence %s for that slice was NOT checked" % (repo_name, ref),
        )
    return _verify_in_repos(ref, repo_name, dirs, hdir, trace)


def _landing_record(evidence, hdir, trace=None):
    """The single-repo feature's record."""
    return _classify(evidence, None, hdir, trace)


def _split_binding(arg):
    """`<repo>=<ref>` ⇒ (repo, ref); anything else ⇒ (None, arg). See `_BINDING_RE`."""
    m = _BINDING_RE.match(arg.strip())
    if m is None:
        return None, arg
    return m.group(1), m.group(2)


def _slice_repos(feature):
    """The slice repositories of `feature`, in board order, de-duplicated.

    Empty ⇒ treat the feature as single-repo. A `slices` array malformed enough to
    yield no repository names is not silently trusted either way: the board that
    results is schema-validated before the atomic replace, so it fail-stops there
    with a message about the real defect.
    """
    repos = []
    slices = feature.get("slices") if isinstance(feature, dict) else None
    if not isinstance(slices, list):
        return repos
    for sl in slices:
        if not isinstance(sl, dict):
            continue
        repo = sl.get("repo")
        if isinstance(repo, str) and repo and repo not in repos:
            repos.append(repo)
    return repos


def _sliced_landing_record(target_id, evidence_list, slice_repos, hdir, trace=None):
    """Bind every slice repository to its OWN evidence. Returns the feature record.

    The feature-level `verified` rolls up to the WEAKEST slice (`_VERIFIED_RANK`), so
    the feature can never read stronger than the least-attested slice it covers.
    """
    listed = ", ".join(slice_repos)
    bindings = {}
    for arg in evidence_list:
        repo, ref = _split_binding(arg)
        if repo is None:
            _die(
                "%s is sliced across %d repositories (%s), so evidence must name the "
                "repository it landed in: pass --evidence <repo>=<ref> once per slice "
                "repository. %r names none, and one slice's merge commit cannot attest "
                "another slice's work — that is how a feature goes `done` with a slice "
                "still unmerged."
                % (target_id, len(slice_repos), listed, arg)
            )
        if repo not in slice_repos:
            _die(
                "%s has no slice in repository %r — its slice repositories are: %s"
                % (target_id, repo, listed)
            )
        if repo in bindings:
            _die(
                "two --evidence values bind repository %r; each slice repository "
                "takes exactly one" % repo
            )
        bindings[repo] = ref
    missing = [r for r in slice_repos if r not in bindings]
    if missing:
        _die(
            "%s: no landing evidence for %s. Every slice repository needs its own "
            "--evidence <repo>=<ref> (a ref, or none:<why>); the slice `merged` flags "
            "are hand-typed and E09-F02 proves they can read `merged: true` against a "
            "closed, unmerged PR." % (target_id, ", ".join(missing))
        )
    records = [_classify(bindings[r], r, hdir, trace) for r in slice_repos]
    verified = min(records, key=lambda r: _VERIFIED_RANK[r["verified"]])["verified"]
    return {
        "ref": "; ".join("%s=%s" % (r["repo"], r["ref"]) for r in records),
        "verified": verified,
        "slices": records,
    }


def _feature_entry(text, target_id):
    """(is_feature, feature_dict) for `target_id`, from a READ-ONLY parse.

    (False, None) for an epic id, an unparseable board, or an id that is not on the
    board at all — every one of those is somebody else's error to report, and masking
    it behind an evidence message would be worse than letting the existing path
    fail-stop on it.
    """
    try:
        data = json.loads(text)
    except ValueError:
        return False, None
    if not isinstance(data, dict):
        return False, None
    for ep in data.get("epics") or []:
        if not isinstance(ep, dict):
            continue
        for ft in ep.get("features") or []:
            if isinstance(ft, dict) and ft.get("id") == target_id:
                return True, ft
    return False, None


def _resolve_landing(text, target_id, status, evidence_list, hdir, trace=None):
    """The `done`-transition precondition. Returns a `landed` record or None.

    NOT pure: the per-ref verdicts run git (and, on the refusal path, ask the remote).
    That is exactly why this is called from `_landing_plan` BEFORE the board lock is
    taken, never from inside the critical section — see the plan/fingerprint block below.
    """
    is_feature, feature = _feature_entry(text, target_id)
    if evidence_list and status != "done":
        _die("--evidence records a landing; it applies only to a `done` transition")
    if status != "done" or not is_feature:
        # Epics roll up from their features, each of which carried its own evidence;
        # requiring it again at the epic would be a second attestation of the same facts.
        if evidence_list and not is_feature:
            _die("--evidence applies to a feature; %s is not one" % target_id)
        return None
    slice_repos = _slice_repos(feature)
    if not evidence_list:
        _die(
            "%s: `done` needs evidence the work landed — pass %s. It is recorded, not "
            "yet verified, and that record is what makes a re-audit possible: a `done` "
            "nobody can re-check is how E99-F58/E99-F59/E09-F02/E99-F29 sat unshipped "
            "and unroutable on this board — E09-F02 with every slice hand-marked "
            "`merged: true` against a closed, unmerged PR."
            % (
                target_id,
                (
                    "--evidence <repo>=<ref> once for each of its slice "
                    "repositories (%s)" % ", ".join(slice_repos)
                )
                if slice_repos
                else "--evidence <ref|none:why>",
            )
        )
    if slice_repos:
        return _sliced_landing_record(target_id, evidence_list, slice_repos, hdir, trace)
    if len(evidence_list) > 1:
        _die(
            "%s has no slices, so it takes exactly one --evidence (got %d). "
            "Repeated evidence binds one value per SLICE repository."
            % (target_id, len(evidence_list))
        )
    bound_repo, bound_ref = _split_binding(evidence_list[0])
    if bound_repo is not None:
        # I1: legal on a single-repo feature, and the ONLY way to disambiguate a ref that
        # resolves in more than one nearby repository. The contract half refused this
        # because nothing verified the name; here the name is resolved and checked, so
        # recording it is a statement about a repository that was actually consulted.
        return _classify(bound_ref, bound_repo, hdir, trace)
    return _landing_record(evidence_list[0], hdir, trace)


def _write_landed(text, target_id, record):
    """Patch `landed` into the feature object, replacing any existing record.

    Text surgery, not a re-serialize, for the same reason the status patch is (R6):
    every other byte — indentation, inline vs multiline arrays, the trailing newline —
    stays verbatim. The result is json.loads + schema validated by the caller before
    the atomic replace, so a malformed insert fail-stops instead of landing.
    """
    blob = json.dumps(record, separators=(", ", ": "), sort_keys=True)
    in_string = _string_mask(text)
    span = _find_status_span(text, target_id)
    if span is None:
        _die("id %r not found in board" % target_id)
    status_start = span[0]
    obj = _scan_object_span(text, status_start, in_string)
    if obj is None:
        _die("could not delimit the object for %r while recording evidence" % target_id)
    obj_start, obj_end = obj

    existing = _depth1_value_start(text, in_string, obj_start, obj_end, "landed")
    if existing is not None:
        old = _scan_object_span(text, existing, in_string)
        if old is None or old[0] != existing:
            _die(
                "%s.landed is not an object; refusing to overwrite it blind" % target_id
            )
        return text[: old[0]] + blob + text[old[1] :]

    # Insert immediately after the status member. `end + 1` steps past the closing
    # quote of the status VALUE (the span brackets the value between the quotes).
    at = span[1] + 1
    line_start = text.rfind("\n", 0, status_start) + 1
    prefix = text[line_start:status_start]
    indent = prefix[: len(prefix) - len(prefix.lstrip())]
    if re.match(r'^\s*"status"\s*:\s*"$', prefix):
        # `status` opens its own line (the pretty-printed board): match its
        # indentation, so the diff is one ADDED line rather than one very long
        # rewritten one.
        return text[:at] + ",\n" + indent + '"landed": ' + blob + text[at:]
    # Several members share the line (the compact fixtures, and hand-written boards):
    # stay on it — a newline here would reflow a line nobody asked to reformat.
    return text[:at] + ', "landed": ' + blob + text[at:]


# ── the landing PLAN: resolved BEFORE the lock, re-validated INSIDE it ────────
#
# Verification talks to the NETWORK — `ls-remote` to discover a default branch, and
# again to confirm a refusal. Each call is bounded, but a SLICED feature probes once
# per slice repository, so three unreachable slice remotes cost ~15s. Run inside the
# critical section, that made the SOLE supported write path hold `tasks.json.lock` for
# the whole probe: measured on the predecessor, a concurrent writer with a 1s bounded
# acquisition was starved out and ITS TRANSITION WAS LOST — the no-lost-update
# guarantee (R1) the lock exists for, defeated by the guard built on top of it.
#
# So the probes run BEFORE `run()` takes the lock, and the lock still covers only the
# pure re-read → patch → validate → atomic-replace it always did. The contract half
# left a note saying exactly this must happen when I/O returned; this is that.
#
# The ordering constraint it creates: WHICH repositories to probe is read from the
# board, and the board is what the lock protects. Trading a starvation bug for a
# TOCTOU bug would be no trade at all, so the pre-lock resolution carries a SHAPE
# FINGERPRINT — `(is_feature, slice repos in order)`, precisely the inputs that decided
# what was probed and what the record must cover. It is recomputed from the
# authoritative in-lock re-read and compared. Equal ⇒ the resolution answers for the
# board being written. Different ⇒ ABORT, byte-identical board, "re-run"; we never
# silently write a record resolved for a different slice set, and never re-probe under
# the lock. Anything else about the board may change freely — another feature's status,
# a title, a park — because none of it affects which repository a ref is checked in.


def _manifest_witness(hdir, repos):
    """What the MANIFEST told the plan about exactly the repositories it probed.

    The manifest is the authority for row 3 and the locator for row 4, so it is part of
    what a resolution ASSUMED and therefore part of what must be re-validated. Without
    this the fingerprint pinned only the slice NAMES: repoint `alpha` at a different
    checkout while the probe is in flight and the names still match, so a proof computed
    against the old checkout was written for a repository the board no longer points at.
    Reproduced before it was fixed — `verified: "ancestor"` landed while the manifest
    named a checkout that had never seen the commit.

    Two deliberate choices:

    * The witness covers ONLY the repositories this feature has slices in, not the whole
      file. An unrelated repo's path changing did not affect this resolution, and the
      shape fingerprint's whole discipline is to pin the inputs that decided what was
      probed — nothing more, or ordinary concurrent edits would abort unrelated writes.
    * It is the (repo, path) PAIRS rather than a content hash. Both detect a change; only
      the pairs let the abort message name WHICH repository moved and to where, and the
      set is one feature's slice repos, so there is nothing to compress.

    The manifest STATE travels with it: absent → present flips whether row 3 can refuse at
    all, so a resolution made under "no authority" must not be written under one.
    """
    state, mapping = _manifest_repos(hdir)
    # This witness owns exactly one question: did the MANIFEST TEXT change? The realpath
    # dimension — the same text now pointing somewhere else — belongs to the identity
    # witness below, which also covers the single-repo path. Keeping a realpath here as
    # well made the two redundant: a mutation campaign could kill NEITHER, because either
    # alone caught the swap, and a guard no test can distinguish is a guard no test
    # protects. One question per witness.
    return (state, tuple((r, mapping.get(r)) for r in repos))


def _identity_witness(hdir, repos, used):
    """I3: what this resolution decided the claim was ABOUT, recomputable without I/O.

    `used` is what resolution actually consulted — (label, lexical, realpath) — and for a
    single-repo feature the CANDIDATE SET is carried too, because that set is what made
    the choice unambiguous: a repository appearing beside the board between plan and write
    changes what an unbound ref means, and must abort rather than quietly re-decide.
    Everything here is filesystem-only, so the in-lock re-check spawns nothing.
    """
    used_now = tuple(sorted((label, lex, os.path.realpath(lex)) for label, lex, _r in used))
    if repos:
        return ("sliced", used_now, ())
    return ("single", used_now, tuple(_repo_candidates(hdir, pairs=True)))


_UNSET = object()


def _landing_shape(text, target_id, hdir, used=(), manifest=_UNSET):
    """The inputs that decide WHAT gets probed, and what the answer was computed against.

    (is_feature, ordered slice repos, manifest witness, identity witness). The manifest
    witness stays scoped to sliced features — that path is the only one that consults it,
    so a manifest appearing or vanishing must not abort a write it could not influence —
    while the IDENTITY witness (I3) covers both paths.
    """
    is_feature, feature = _feature_entry(text, target_id)
    repos = tuple(_slice_repos(feature) if is_feature else ())
    # `manifest` is passed in by the PLAN, captured BEFORE resolution ran. It must be the
    # value the resolution actually used, not whatever the file says once resolution has
    # finished: reading it afterwards would collapse the very window this guard covers —
    # measured, when a refactor moved the capture after the probe and R17c reddened.
    mwit = (
        (_manifest_witness(hdir, repos) if repos else None)
        if manifest is _UNSET
        else manifest
    )
    return (
        is_feature,
        repos,
        mwit,
        _identity_witness(hdir, repos, used) if is_feature else None,
    )


def _landing_plan(target_id, status, evidence_list, hdir):
    """Resolve the landing OUTSIDE the lock, and fingerprint what it assumed.

    Returns {"shape": …, "record": … | None}. Refusals happen here, before any lock is
    taken — a refusal never contends for the lock at all. A board that cannot be read
    yet yields an empty shape and no record; `run()` reports the missing board itself.
    """
    try:
        with open(os.path.join(hdir, TASKS_REL)) as fh:
            text = fh.read()
    except OSError:
        text = ""
    # Capture what the manifest says BEFORE resolution consults it, so the fingerprint
    # records the state the answer was computed under (see `_landing_shape`).
    _is_feature, _feature = _feature_entry(text, target_id)
    _repos = tuple(_slice_repos(_feature) if _is_feature else ())
    manifest_before = _manifest_witness(hdir, _repos) if _repos else None
    trace = []
    record = _resolve_landing(text, target_id, status, evidence_list, hdir, trace)
    return {
        "shape": _landing_shape(
            text, target_id, hdir, trace, manifest=manifest_before
        ),
        "record": record,
        "used": tuple(trace),
    }


def _shape_str(shape):
    is_feature, repos, witness, identity = shape
    if not is_feature:
        return "not a feature on this board"
    if not repos:
        seen = ""
        if identity is not None and identity[1]:
            seen = " resolved in %s" % ", ".join(real for _l, _x, real in identity[1])
        return "a single-repo feature%s" % seen
    where = ""
    if witness is not None:
        state, pairs = witness
        where = " with manifest %s: %s" % (
            state,
            ", ".join(
                "%s=%s" % (r, lex if lex else "<unlocatable>") for r, lex in pairs
            ),
        )
    return "a feature sliced across %s%s" % (", ".join(repos), where)


def _check_plan_still_applies(text, target_id, plan, hdir):
    """Re-validate the pre-lock resolution against the authoritative in-lock read.

    An ABORT here is not a refusal of the claim: nothing is written, and the operator
    re-runs — which converges, because the re-run both plans and re-validates against the
    new state. That is why a manifest that has become absent or unreadable aborts rather
    than degrading: degrading would write a record justified by an authority that no
    longer exists, while aborting costs one re-run and can never record something false.
    """
    shape = _landing_shape(text, target_id, hdir, plan.get("used", ()))
    if shape == plan["shape"]:
        return plan["record"]
    _die(
        "%s changed between the evidence check and the write — it was resolved as %s "
        "and the board now reads %s. Nothing was written; re-run. (Evidence is resolved "
        "before the lock is taken so network probes cannot starve other writers; this is "
        "the guard that stops a record resolved for one slice set landing on another.)"
        % (target_id, _shape_str(plan["shape"]), _shape_str(shape))
    )


def _set_status_text_transform(target_id, status, plan=None):
    """Build a TEXT transform that changes ONLY the target's status value.

    Unlike a parse → mutate → re-serialize round-trip (which reformats every
    line to `json.dumps(indent=2)` shape and thus rewrites unrelated entries —
    e.g. collapsing/expanding sibling inline arrays), this edits the original
    text in place: it replaces just the target object's status VALUE token and
    leaves all surrounding bytes untouched. The caller still json.loads + schema-
    validates the RESULT before the atomic replace, so an invalid outcome (bad
    id, illegal status, sliced-done invariant) still fail-stops (R4).

    `plan` is the PRE-LOCK landing resolution (`_landing_plan`). Everything this
    transform does is pure and local — no child process, no network — so the lock is
    held only for the re-read → patch → validate → replace it always covered.
    """

    def transform(text):
        _refuse_if_parked(text, target_id)  # E06-F07: a park outranks a transition
        # The record was resolved BEFORE the lock; here we only re-validate that it
        # still answers for the board being written, so a refusal leaves the board
        # byte-identical and no external call runs in-lock.
        landed = (
            _check_plan_still_applies(text, target_id, plan, _harness_dir())
            if plan is not None
            else None
        )
        span = _find_status_span(text, target_id)
        if span is None:
            _die("id %r not found in board" % target_id)
        start, end, _old = span
        patched = text[:start] + status + text[end:]
        if landed is not None:
            patched = _write_landed(patched, target_id, landed)
        return patched

    return transform


def _mutator_text_transform(mutate):
    """Wrap a data-level `mutate(data) -> data` as a text transform.

    External mutators (the `apply --mutator` path) may change arbitrary
    structure, so there is no meaningful original-text token to surgically
    patch; we parse, mutate, and re-serialize with the canonical `indent=2`
    representation (unchanged behaviour for that path).
    """

    def transform(text):
        data = json.loads(text)
        data = mutate(data)
        return json.dumps(data, indent=2) + "\n"

    return transform


# ---------------------------------------------------------------------------
# Frontmatter synchronisation (E99-F14).
#
# `store/local.md` has always said a status write must "keep the feature's `.spec.md`
# frontmatter `status` in sync" (and the epic's `epic.md`). Nothing did it — the contract
# was an instruction to a human reader, and the documents drifted for months.
#
# Arming `init.sh`'s consistency gate WITHOUT this would have made every sanctioned
# transition fail the next mandatory gate: `/sdd-drill` running `set-status <epic> planned`,
# or any Orchestrator feature move, would leave the document behind and halt all agent work
# until someone made an undocumented second edit. A gate that enforces a contract nothing
# maintains does not make the contract true — it breaks the workflow. So the ONE supported
# write path now maintains it.
#
# Scope, deliberately narrow. This syncs a `status:` that is ALREADY declared; it never adds
# a frontmatter block, never creates a file, and never touches a spec that declares a
# different feature's `id` (that spec belongs to someone else, and the gate reports it).
# Absent frontmatter stays absent, matching the gate's own "keep in sync, not must declare".


def _rewrite_status(text, new_status):
    """Return `text` with its frontmatter `status:` set to `new_status`, or None.

    None means "nothing to do": no frontmatter block, or no `status:` key in it. The inline
    comment and its column are preserved, because every `epic.md` writes
    `status: done             # draft -> planned -> ...` and reflowing that on every
    transition would turn a one-word change into a noisy diff.
    """
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    head, tail = text[:end], text[end:]
    lines = head.split("\n")
    for i, line in enumerate(lines):
        m = re.match(r"^status:[ \t]*(.*)$", line)
        if not m:
            continue
        raw = m.group(1)
        hash_at = raw.find("#")
        if hash_at != -1:
            column = len("status: ") + hash_at
            body = "status: " + new_status
            pad = max(1, column - len(body))
            lines[i] = body + " " * pad + raw[hash_at:]
        else:
            lines[i] = "status: " + new_status
        return "\n".join(lines) + tail
    return None


def _write_contained(vb, root_real, path, text):
    """Write `text` to `path`, refusing when it resolves outside `root_real`.

    The write-side twin of `vb._read_contained`, and deliberately a separate function
    rather than a reuse of it: the read helper answers "may I open this", and a writer
    that borrowed it would be asking the wrong question a moment before doing something
    the answer does not cover. Containment is re-established HERE rather than inherited
    from the read, because a write is a second resolution of the same name and the whole
    lesson of this rule is that a path is contained at the moment it is resolved, not
    once and forever.
    """
    if not vb._contains(root_real, os.path.realpath(path)):
        raise ValueError(
            "refusing to sync %s — it resolves outside the harness root" % path
        )
    with io.open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def _frontmatter_targets(vb, hdir, data, target_id, status):
    """[(path, original_text, new_text)] for the documents this status write must carry
    along. The ORIGINAL text is carried out of here because it was already read through
    the choke point — re-reading it in the writer would be a read site the containment
    rule never sees."""
    targets = []
    root_real = os.path.realpath(hdir)
    is_epic = "-" not in target_id
    for ep in data.get("epics") or []:
        if not isinstance(ep, dict):
            continue
        if is_epic:
            if ep.get("id") != target_id:
                continue
            dirs = sorted(
                glob.glob(os.path.join(glob.escape(hdir), "specs", "epics",
                                       "%s-*" % target_id))
            )
            dirs = [d for d in dirs if os.path.isdir(d)]
            if len(dirs) != 1:
                continue          # ambiguous or absent — the gate skips it too
            candidates = [os.path.join(dirs[0], "epic.md")]
        else:
            match = None
            for ft in ep.get("features") or []:
                if isinstance(ft, dict) and ft.get("id") == target_id:
                    match = ft
                    break
            if match is None:
                continue
            spec_path = match.get("spec_path")
            if not isinstance(spec_path, str) or not spec_path:
                continue
            fdir = vb._resolve_under_root(hdir, spec_path)
            if fdir is None or not os.path.isdir(fdir):
                continue          # sdd:false / not authored yet — nothing to carry
            candidates = vb._spec_files(fdir)

        for path in candidates:
            if not os.path.isfile(path):
                continue
            # Read through the SAME choke point the gate reads through, once, and keep the
            # text: this is both the containment check (never write THROUGH a symlink that
            # leaves the repository — the directory having passed containment does not make
            # each file in it contained) and the only read of this file, so the rewrite
            # below cannot reach a path the check never saw.
            text = vb._read_contained(root_real, path)
            if text is vb._ESCAPED:
                raise ValueError(
                    "refusing to sync %s — it resolves outside the harness root" % path
                )
            front = text if text is vb._UNREADABLE else vb._parse_frontmatter(text)
            if front is vb._UNREADABLE:
                # Refuse rather than guess. Rewriting a file we could not parse risks
                # corrupting it, and silently skipping it would leave the divergence the
                # caller is about to be blamed for at the next gate.
                raise ValueError(
                    "cannot read %s to keep its frontmatter status in sync" % path
                )
            # A key declared twice has no effective value to agree ON. Picking one is how
            # the writer and the gate came to disagree; refusing is the only answer that
            # cannot manufacture a divergence, and it aborts before the board moves.
            if front.get("status") is vb._AMBIGUOUS or front.get("id") is vb._AMBIGUOUS:
                raise ValueError(
                    "refusing to sync %s — it declares 'status' or 'id' more than once, "
                    "so which value is effective is ambiguous" % path
                )
            declared_id = front.get("id") or None
            if not is_epic and declared_id is not None and declared_id != target_id:
                continue          # another feature's spec — not ours to rewrite
            if not front.get("status"):
                continue          # declares none; the gate does not require one
            if front.get("status") == status:
                continue          # already in agreement
            new_text = _rewrite_status(text, status)
            if new_text is not None and new_text != text:
                targets.append((path, text, new_text))
    return targets


def _apply_frontmatter(vb, root_real, targets):
    """Write each target, returning [(path, original_text)] for rollback.

    A failure part-way through rolls back what THIS call already wrote before re-raising.
    Without that, the exception escaped before `written` was ever returned, so the caller
    held nothing to undo: a directory with two eligible specs and a read-only second one
    left the first document advanced while the board stayed put — precisely the divergence
    this synchronisation exists to prevent, manufactured by the thing preventing it.
    """
    written = []
    try:
        for path, original, new_text in targets:
            _write_contained(vb, root_real, path, new_text)
            written.append((path, original))
    except Exception:
        _rollback_frontmatter(vb, root_real, written)
        raise
    return written


def _rollback_frontmatter(vb, root_real, written):
    for path, original in written:
        try:
            _write_contained(vb, root_real, path, original)
        except (OSError, ValueError):
            pass


def run(transform, timeout, sync_id=None, sync_status=None):
    hdir = _harness_dir()
    tasks_path = os.path.join(hdir, TASKS_REL)
    lock_path = os.path.join(hdir, LOCK_REL)
    schema_path = os.path.join(hdir, SCHEMA_REL)

    if not os.path.exists(tasks_path):
        _die("board not found at %s (HARNESS_DIR=%s)" % (tasks_path, hdir))

    vb = _load_shared_validator(want_module=True)
    validate = vb.validate
    schema = _load_schema(schema_path)

    # Open (creating if needed) the sibling lockfile. It only ever anchors the
    # advisory lock; it never holds board data.
    lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        _acquire(lock_fd, lock_path, timeout)  # R3, R5
        try:
            # RE-READ from disk INSIDE the lock (R2) — never a pre-lock copy.
            # Read the RAW TEXT (not just the parsed object): the minimal-diff
            # set-status path patches this text in place, preserving every byte of
            # unrelated entries (inline vs multiline arrays, indentation, trailing
            # newline) so a serial write stays byte-equivalent to a plain
            # read-modify-write (R6) and does not enlarge Git diffs.
            with open(tasks_path) as fh:
                original_text = fh.read()

            serialized = transform(original_text)  # the single mutation (R1)

            # Validate the mutated content BEFORE replacing the file (R4), using
            # the SAME shared validator init.sh runs. Any error → fail-stop, board
            # untouched (raised here, caught by main() → non-zero, clear message).
            reparsed = json.loads(serialized)  # parse check
            errs = validate(reparsed, schema)  # schema check (shared with init.sh)
            if errs:
                raise ValueError("; ".join(errs))

            # Carry the frontmatter along, INSIDE the lock and BEFORE the board is
            # replaced (E99-F14). Ordering is deliberate: a failure here must leave the
            # board untouched, because a board that moved without its document is exactly
            # the divergence `init.sh` now fail-stops on. Anything written here is rolled
            # back if the board replace itself fails, so the two records move together or
            # not at all.
            fm_written = []
            if sync_id is not None:
                fm_targets = _frontmatter_targets(
                    vb, hdir, reparsed, sync_id, sync_status
                )
                fm_written = _apply_frontmatter(
                    vb, os.path.realpath(hdir), fm_targets
                )

            # Atomic write: temp in the same dir, then os.replace (R4 — no torn
            # file). If the process dies mid-write, the original is untouched.
            tmp_path = tasks_path + ".tmp.%d" % os.getpid()
            try:
                with open(tmp_path, "w") as out:
                    out.write(serialized)
                    out.flush()
                    os.fsync(out.fileno())
                # Preserve the board's permission bits across the replace: a
                # fresh temp file is created per the process umask (e.g. 0644),
                # so os.replace would otherwise silently widen a 0600 board to
                # 0644 (exposing data) or narrow a shared 0664 board (breaking
                # another account's later writes). Copy the ORIGINAL board's
                # mode onto the temp file before the replace, inside the lock,
                # preserving fail-stop semantics.
                if os.path.exists(tasks_path):
                    _st = os.stat(tasks_path)
                    os.chmod(tmp_path, stat.S_IMODE(_st.st_mode))
                    # Also carry the board's OWNERSHIP across the replace. In a
                    # multi-account checkout the board is group-owned so several
                    # accounts can write it via the 0664 group bit; without
                    # setgid inheritance on the directory the temp file picks up
                    # the CURRENT writer's group, so os.replace would silently
                    # re-group the board and lock the other accounts out of the
                    # mandatory write path. Best-effort by construction: chown is
                    # privileged in the general case, so a refusal (EPERM) or a
                    # platform without it must NOT fail the write — the mode copy
                    # above already covers the common single-owner case.
                    try:
                        os.chown(tmp_path, _st.st_uid, _st.st_gid)
                    except (OSError, AttributeError):
                        pass
                os.replace(tmp_path, tasks_path)
            except Exception:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
                _rollback_frontmatter(vb, os.path.realpath(hdir), fm_written)
                raise
        finally:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)  # release before returning (R3)
    finally:
        os.close(lock_fd)


def main(argv):
    parser = argparse.ArgumentParser(
        prog="tasks-lock.py",
        description="Advisory-locked read-modify-write on state/tasks.json.",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_set = sub.add_parser("set-status", help="set a feature/epic status")
    p_set.add_argument("id")
    p_set.add_argument("status")
    p_set.add_argument(
        "--evidence",
        action="append",
        default=None,
        help=(
            "landing evidence for a `done` transition (E99-F102): any reference "
            "(recorded verbatim and marked unchecked — this half verifies nothing), "
            "or none:<why> for work with no commit. A SLICED feature takes the bound "
            "form --evidence <repo>=<ref>, REPEATED once per slice repository"
        ),
    )
    p_set.add_argument(
        "--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS
    )

    p_apply = sub.add_parser("apply", help="run an external mutator")
    p_apply.add_argument("--mutator", required=True)
    p_apply.add_argument(
        "--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS
    )

    args = parser.parse_args(argv)

    # Bounded-acquisition contract (R5): argparse's float() accepts `nan`/`inf`,
    # which would poison the deadline arithmetic in _acquire — `nan` makes the
    # `time.monotonic() >= deadline` comparison ALWAYS False (unbounded wait
    # against a contended lock), and `+inf` is an infinite bound. Reject any
    # non-finite or negative timeout up front, before the poll loop, so the
    # acquisition is provably bounded.
    if not (math.isfinite(args.timeout) and args.timeout >= 0):
        _die(
            "--timeout must be a finite, non-negative number of seconds "
            "(got %r); a non-finite bound would wait forever, violating the "
            "bounded-acquisition contract" % args.timeout
        )

    if args.cmd == "set-status":
        # Minimal-diff text transform: patches only the target's status token.
        # Resolve the landing BEFORE any lock is taken: evidence verification makes
        # bounded NETWORK calls, and holding the sole write lock across them starved
        # concurrent writers out of their own transitions. The transform re-validates
        # the resolution against the in-lock re-read.
        plan = _landing_plan(
            args.id, args.status, args.evidence or [], _harness_dir()
        )
        transform = _set_status_text_transform(args.id, args.status, plan)
    elif args.cmd == "apply":
        # External mutators may change arbitrary structure → parse+re-serialize.
        transform = _mutator_text_transform(_import_mutator(args.mutator))
    else:  # pragma: no cover - argparse enforces
        parser.error("unknown command")

    try:
        # Only `set-status` carries the frontmatter: it is the one path that knows WHICH
        # object moved and to what. `apply --mutator` may rewrite arbitrary structure, so
        # there is no single (id, status) to follow, and guessing would be worse than the
        # gate reporting the divergence.
        if args.cmd == "set-status":
            run(transform, args.timeout,
                sync_id=args.id, sync_status=args.status)
        else:
            run(transform, args.timeout)
    except SystemExit:
        raise
    except json.JSONDecodeError as exc:
        _die("mutated board is not valid JSON: %s" % exc)
    except Exception as exc:  # validation / mutator failures → fail-stop (R4)
        _die("aborting write, original board left intact: %s" % exc)


if __name__ == "__main__":
    main(sys.argv[1:])
