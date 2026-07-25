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
#   tasks-lock.py set-status <id> <status> [--timeout SECONDS]
#       Set the status of the object <id> addresses (feature id `E06-F06` or
#       epic id `E06`) in state/tasks.json, under the lock.
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
import importlib.util
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


def _load_shared_validator():
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
    return module.validate


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


def _set_status_text_transform(target_id, status):
    """Build a TEXT transform that changes ONLY the target's status value.

    Unlike a parse → mutate → re-serialize round-trip (which reformats every
    line to `json.dumps(indent=2)` shape and thus rewrites unrelated entries —
    e.g. collapsing/expanding sibling inline arrays), this edits the original
    text in place: it replaces just the target object's status VALUE token and
    leaves all surrounding bytes untouched. The caller still json.loads + schema-
    validates the RESULT before the atomic replace, so an invalid outcome (bad
    id, illegal status, sliced-done invariant) still fail-stops (R4).
    """

    def transform(text):
        span = _find_status_span(text, target_id)
        if span is None:
            _die("id %r not found in board" % target_id)
        start, end, _old = span
        return text[:start] + status + text[end:]

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


def run(transform, timeout):
    hdir = _harness_dir()
    tasks_path = os.path.join(hdir, TASKS_REL)
    lock_path = os.path.join(hdir, LOCK_REL)
    schema_path = os.path.join(hdir, SCHEMA_REL)

    if not os.path.exists(tasks_path):
        _die("board not found at %s (HARNESS_DIR=%s)" % (tasks_path, hdir))

    validate = _load_shared_validator()
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
        transform = _set_status_text_transform(args.id, args.status)
    elif args.cmd == "apply":
        # External mutators may change arbitrary structure → parse+re-serialize.
        transform = _mutator_text_transform(_import_mutator(args.mutator))
    else:  # pragma: no cover - argparse enforces
        parser.error("unknown command")

    try:
        run(transform, args.timeout)
    except SystemExit:
        raise
    except json.JSONDecodeError as exc:
        _die("mutated board is not valid JSON: %s" % exc)
    except Exception as exc:  # validation / mutator failures → fail-stop (R4)
        _die("aborting write, original board left intact: %s" % exc)


if __name__ == "__main__":
    main(sys.argv[1:])
