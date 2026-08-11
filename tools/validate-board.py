#!/usr/bin/env python3
# validate-board.py — the single canonical TaskStore validator (E15-F01).
#
# ONE validator, TWO consumers:
#   * init.sh runs it as a CLI at the environment gate:
#         python3 tools/validate-board.py <data.json> <schema.json>
#     with the same non-zero-on-invalid + stderr-message contract init.sh has
#     always relied on (draft-epic warning, then jsonschema errors OR the
#     zero-dependency fallback errors, each prefixed with two spaces).
#   * tasks-lock.py imports `validate(data, schema) -> list[str]` and calls it
#     IN-PROCESS while holding the advisory lock, before the atomic os.replace,
#     so the guarded write fail-stops on the SAME rules init.sh enforces.
#
# Before this file existed the validation logic was DUPLICATED — a full copy in
# init.sh's embedded heredoc and a partial hand-rolled copy in tasks-lock.py.
# The partial copy silently accepted boards init.sh's full pass rejected (wrong
# `sdd` type, malformed slices, …). Extracting one shared validator removes the
# drift at its root: both paths now share the exact same acceptance surface.
#
# Behaviour is preserved verbatim in substance from init.sh's former heredoc:
#   (a) when `jsonschema` imports, validate with Draft7Validator and surface each
#       error as "<location>: <message>";
#   (b) otherwise run the SAME complete zero-dependency structural checks
#       (required keys, types, id patterns, enums, owner defaults, slices rules,
#       and the cross-field "sliced feature may be done only when every slice is
#       done+merged" invariant).
#
# The `validate()` function returns error strings only (empty list = valid); it
# does NOT print and does NOT enforce the warn-only draft-epic invariant — that
# is a caller-side warning (init.sh emits it), never a validation error, because
# the next() draft gate already neutralizes it.

import glob
import io
import json
import os
import re
import sys

# Enum sets mirror store/tasks.schema.json. Kept as literals (as init.sh did) so
# the zero-dependency path needs no schema-shape spelunking to know the enums;
# the schema remains the source of truth and the jsonschema path reads it directly.
EPIC_STATUS = {"draft", "planned", "pending", "in-progress", "done"}
FEAT_STATUS = {"pending", "spec-ready", "in-progress", "in-review", "done"}
SLICE_STATUS = {"pending", "spec-ready", "in-progress", "in-review", "done", "failed"}


def validate(data, schema):
    """Validate `data` against `schema`. Return a list of error strings (empty = valid).

    Prefers `jsonschema.Draft7Validator` when importable; otherwise runs the
    complete zero-dependency structural check. Same acceptance surface either way.
    """
    try:
        import jsonschema  # type: ignore

        errs = sorted(
            jsonschema.Draft7Validator(schema).iter_errors(data),
            key=lambda e: list(e.path),
        )
        out = []
        for e in errs:
            loc = "/".join(str(p) for p in e.path) or "(root)"
            out.append("%s: %s" % (loc, e.message))
        return out
    except ImportError:
        return _fallback_errors(data)


def _fallback_errors(data):
    """The zero-dependency structural check — a verbatim port of init.sh's fallback."""
    errors = []

    def need(obj, key, where):
        if key not in obj:
            errors.append("%s: missing required field '%s'" % (where, key))
            return False
        return True

    if not isinstance(data, dict):
        errors.append("(root): expected object")
        return errors

    if need(data, "project", "(root)") and not isinstance(data["project"], str):
        errors.append("project: expected string")
    if need(data, "epics", "(root)"):
        epics = data["epics"]
        if not isinstance(epics, list):
            errors.append("epics: expected array")
            epics = []
        for ei, ep in enumerate(epics):
            ew = "epics[%d]" % ei
            if not isinstance(ep, dict):
                errors.append("%s: expected object" % ew)
                continue
            for k in ("id", "title", "status", "features"):
                need(ep, k, ew)
            if "id" in ep:
                if not isinstance(ep["id"], str):
                    errors.append("%s.id: expected string" % ew)
                elif not re.match(r"^E[0-9]+$", ep["id"]):
                    errors.append("%s.id %r: must match ^E[0-9]+$" % (ew, ep["id"]))
            if "title" in ep and not isinstance(ep["title"], str):
                errors.append("%s.title: expected string" % ew)
            # Optional (additive, E10-F01) coarse ownership: reject a non-string
            # owner so the zero-dependency path matches the JSON schema. Absent
            # ⇒ unowned, which stays valid (backward-compatible).
            if "owner" in ep and not isinstance(ep["owner"], str):
                errors.append("%s.owner: expected string" % ew)
            if ep.get("status") not in EPIC_STATUS and "status" in ep:
                errors.append(
                    "%s.status '%s': not one of %s"
                    % (ew, ep["status"], sorted(EPIC_STATUS))
                )
            feats = ep.get("features", [])
            if not isinstance(feats, list):
                errors.append("%s.features: expected array" % ew)
                feats = []
            for fi, ft in enumerate(feats):
                fw = "%s.features[%d]" % (ew, fi)
                if not isinstance(ft, dict):
                    errors.append("%s: expected object" % fw)
                    continue
                for k in ("id", "title", "status", "sdd", "spec_path"):
                    need(ft, k, fw)
                if "id" in ft:
                    if not isinstance(ft["id"], str):
                        errors.append("%s.id: expected string" % fw)
                    elif not re.match(r"^E[0-9]+-F[0-9]+$", ft["id"]):
                        errors.append(
                            "%s.id %r: must match ^E[0-9]+-F[0-9]+$" % (fw, ft["id"])
                        )
                if "title" in ft and not isinstance(ft["title"], str):
                    errors.append("%s.title: expected string" % fw)
                # Optional (additive, E10-F01) fine ownership: reject a non-string
                # owner so the zero-dependency path matches the JSON schema. Absent
                # ⇒ falls back to the epic owner, which stays valid.
                if "owner" in ft and not isinstance(ft["owner"], str):
                    errors.append("%s.owner: expected string" % fw)
                if ft.get("status") not in FEAT_STATUS and "status" in ft:
                    errors.append(
                        "%s.status '%s': not one of %s"
                        % (fw, ft["status"], sorted(FEAT_STATUS))
                    )
                if "sdd" in ft and not isinstance(ft["sdd"], bool):
                    errors.append("%s.sdd: expected boolean" % fw)
                if "autonomous" in ft and not isinstance(ft["autonomous"], bool):
                    errors.append("%s.autonomous: expected boolean" % fw)
                if "spec_path" in ft and not isinstance(ft["spec_path"], str):
                    errors.append("%s.spec_path: expected string" % fw)
                if "depends_on" in ft:
                    dep = ft["depends_on"]
                    if not isinstance(dep, list) or not all(
                        isinstance(x, str) for x in dep
                    ):
                        errors.append("%s.depends_on: expected array of strings" % fw)
                # Optional (additive, E06-F07) feature park. Mirrored here so a machine
                # WITHOUT jsonschema does not accept a board the schema rejects — two
                # validators disagreeing is worse than either one being strict. `reason`
                # is required and non-empty because presence means parked, and a park
                # with no legible reason is the exact defect the field exists to fix.
                if "parked" in ft:
                    park = ft["parked"]
                    if not isinstance(park, dict):
                        errors.append("%s.parked: expected object" % fw)
                    else:
                        reason = park.get("reason")
                        if not isinstance(reason, str) or not reason:
                            errors.append(
                                "%s.parked.reason: expected a non-empty string" % fw
                            )
                        unblocked = park.get("unblocked_by")
                        if "unblocked_by" in park and (
                            not isinstance(unblocked, str) or not unblocked
                        ):
                            errors.append(
                                "%s.parked.unblocked_by: expected a non-empty string" % fw
                            )
                    # A park means "not yet workable"; `done` means finished. Unreachable
                    # via set-status (which refuses a transition while parked), so it can
                    # only be hand-edited in — and left legal it defeats the targeting
                    # contract, because select() short-circuits a done target to
                    # `target-complete` before any blocker is computed.
                    if ft.get("status") == "done":
                        errors.append("%s: a done feature cannot be parked" % fw)
                # Umbrella mode (optional): mirror the slice checks from the JSON
                # schema so corrupted cross-repo state is rejected even without
                # jsonschema installed. Absent `slices` ⇒ single-repo, unaffected.
                if "slices" in ft:
                    slices = ft["slices"]
                    if not isinstance(slices, list):
                        errors.append("%s.slices: expected array" % fw)
                        slices = []
                    elif len(slices) == 0:
                        errors.append(
                            "%s.slices: must have at least 1 item "
                            "(omit the field for single-repo)" % fw
                        )
                    for si, sl in enumerate(slices):
                        sw = "%s.slices[%d]" % (fw, si)
                        if not isinstance(sl, dict):
                            errors.append("%s: expected object" % sw)
                            continue
                        for k in ("id", "repo", "status"):
                            need(sl, k, sw)
                        if "id" in sl:
                            if not isinstance(sl["id"], str):
                                errors.append("%s.id: expected string" % sw)
                            elif not re.match(
                                r"^E[0-9]+-F[0-9]+@[a-z0-9-]+$", sl["id"]
                            ):
                                errors.append(
                                    "%s.id %r: must match ^E[0-9]+-F[0-9]+@[a-z0-9-]+$"
                                    % (sw, sl["id"])
                                )
                        if "repo" in sl and not isinstance(sl["repo"], str):
                            errors.append("%s.repo: expected string" % sw)
                        if sl.get("status") not in SLICE_STATUS and "status" in sl:
                            errors.append(
                                "%s.status '%s': not one of %s"
                                % (sw, sl["status"], sorted(SLICE_STATUS))
                            )
                        if "merged" in sl and not isinstance(sl["merged"], bool):
                            errors.append("%s.merged: expected boolean" % sw)
                        if "spec_path" in sl and not isinstance(sl["spec_path"], str):
                            errors.append("%s.spec_path: expected string" % sw)
                        if "pr" in sl and not isinstance(sl["pr"], str):
                            errors.append("%s.pr: expected string" % sw)
                        if "depends_on" in sl:
                            sdep = sl["depends_on"]
                            if not isinstance(sdep, list) or not all(
                                isinstance(x, str) for x in sdep
                            ):
                                errors.append(
                                    "%s.depends_on: expected array of strings" % sw
                                )
                    # Cross-field: a sliced feature may only be `done` when every slice
                    # is done AND merged. Guards a hand-edited/partial store from
                    # dispatching dependents (which gate on the stored feature status).
                    if ft.get("status") == "done":
                        for si, sl in enumerate(slices):
                            if not isinstance(sl, dict):
                                continue
                            if sl.get("status") != "done" or sl.get("merged") is not True:
                                errors.append(
                                    "%s.slices[%d]: feature is 'done' but slice is "
                                    "not done+merged" % (fw, si)
                                )

    return errors


# ---------------------------------------------------------------------------
# Spec consistency (E99-F14) — the board vs. what is on disk.
#
# DELIBERATELY NOT PART OF validate(). validate() is imported by tasks-lock.py
# and called IN-PROCESS while the advisory write lock is held, so it must stay a
# pure function of (data, schema). Two reasons it must not touch the filesystem:
#   * a board write can originate from a LINKED WORKTREE, and tasks-lock remaps
#     the write onto the primary checkout's board — a relative `spec_path`
#     resolved from that process's cwd would be resolved against the WRONG tree
#     and fail-stop a legitimate write;
#   * a fail-stop mid-write is a far worse failure mode than a fail-stop at the
#     gate, where the operator is already reading output.
# So these run ONLY from the CLI path init.sh invokes, and only when the caller
# passes an explicit --spec-root. There is no cwd fallback: a validator handed a
# throwaway fixture board must never resolve that board's paths against whatever
# repository happens to be the working directory.
#
# WHAT IS CHECKED, AND WHAT ABSENCE MEANS (each rule states its own precondition;
# there is deliberately no global "skip everything if specs/ is missing" bypass,
# because a blanket escape hatch is exactly the fail-open seam this feature exists
# to close):
#   * spec_path must resolve, and hold a readable spec, ONLY for `sdd: true`
#     features past `pending`. `sdd: false` is the quick-fix lane, which skips the
#     Architect and has no spec by construction (13 done E99 features, and
#     E22-F01/NOTES.md documents the choice); `sdd: true` + `pending` has not been
#     authored yet. Neither is drift.
#   * frontmatter `status` is compared whenever a spec file is actually there and
#     actually declares one. A spec with no frontmatter, or none with a `status:`
#     key, is NOT an error — store/local.md's contract is "keep them in sync", not
#     "must declare a status".
#   * epics carry the IDENTICAL contract, stated in the same sentence pair of
#     store/local.md ("keep the epic's `epic.md` frontmatter `status` in sync"),
#     so `epic.md` is checked too. The board records no epic path, so the epic
#     directory is resolved by the `specs/epics/<id>-*/` convention and skipped
#     unless exactly one directory matches — guessing is not a contract.


# A file that could not be read or decoded. Deliberately a DISTINCT answer from "declares
# nothing": an omitted `status` is a documented skip, while a spec that cannot be opened is
# the exact failure the existence rule exists to catch. Collapsing the two let an
# undecodable spec satisfy a contract whose whole content is "a Reviewer can read this".
_UNREADABLE = object()

# A key declared MORE THAN ONCE in one frontmatter block. Which occurrence is "effective"
# is not a question with a right answer, and the two halves of this feature answered it
# differently: the parser below keeps the LAST match, while the writer in tasks-lock.py
# rewrote the FIRST and stopped. A sanctioned transition therefore advanced the board and
# left the value the gate reads unchanged — manufacturing the very divergence both sides
# exist to prevent. Neither side picks a winner now; the ambiguity is reported and the
# write refuses.
_AMBIGUOUS = object()

# A path that resolves OUTSIDE the harness root. Distinct from `_UNREADABLE`: the file is
# perfectly readable, and that is the problem — reading it would let the gate certify a
# document that is not in this repository.
_ESCAPED = object()


def _read_contained(root_real, path):
    """Resolve `path`, refuse it when it leaves `root_real`, and only then read it.

    THE one entry point for reading a spec or epic document. Returns the file's text, or
    `_ESCAPED` when the resolved path lands outside the root, or `_UNREADABLE` when it
    cannot be opened or decoded.

    It exists because containment kept being added per read SITE. `tools/validate-board.py`
    grew four of them across four consecutive review rounds of PR #124 — the `spec_path`
    itself, the spec directory, the matched `*.spec.md`, and finally `epic.md` reached
    through a symlinked `specs/epics/<id>-*` directory — and each was found by review
    rather than prevented by design, because nothing about adding a read site made a
    containment check necessary. Now something does: `root_real` is the FIRST REQUIRED
    argument of the only function that opens these documents, so a new read site cannot be
    written without saying what is supposed to contain it, and cannot be written to skip
    the check without deleting this helper.

    `root_real` must already be resolved (`os.path.realpath`). Resolving BOTH sides is not
    optional: on macOS `/tmp` is itself a symlink to `/private/tmp`, so resolving only the
    target would report an escape for every tree under a temporary directory.
    """
    real = os.path.realpath(path)
    if not _contains(root_real, real):
        return _ESCAPED
    try:
        with io.open(real, encoding="utf-8") as fh:
            return fh.read()
    except (OSError, UnicodeDecodeError, ValueError):
        return _UNREADABLE


def _frontmatter(root_real, path):
    """Parse a contained document's leading `---` block into `{key: value}`.

    Returns `_ESCAPED` / `_UNREADABLE` straight from `_read_contained`, `{}` when there is
    no frontmatter, and otherwise the declared scalars. Every read of a spec/epic file goes
    through here, so both failure cases are handled in ONE place rather than once per
    caller — two callers each with their own `except` is how the two answers drifted apart
    in the first place.
    """
    text = _read_contained(root_real, path)
    if text is _ESCAPED or text is _UNREADABLE:
        return text
    return _parse_frontmatter(text)


def _parse_frontmatter(text):
    """The pure parse, split out so the writer in `tasks-lock.py` can reuse the text it
    already read through the choke point instead of opening the file a second time."""
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    block = text[3:end] if end != -1 else text[3:]
    out = {}
    for m in re.finditer(r"^([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(.*)$", block, re.M):
        key = m.group(1)
        out[key] = _AMBIGUOUS if key in out else _scalar(m.group(2))
    return out


def _scalar(raw):
    """One YAML scalar: quotes unwrapped, an inline comment stripped.

    Inline comments matter because EVERY epic.md in this repo writes
    `status: done             # draft -> planned -> in-progress -> done`. Comparing against
    the raw line reports 19 divergences where 6 exist, and a false positive at a MANDATORY
    gate halts all agent work.
    """
    raw = raw.strip()
    if raw[:1] in ('"', "'"):
        # Quoted: the value is what is inside the quotes, '#' included.
        closing = raw.find(raw[0], 1)
        return raw[1:closing] if closing != -1 else raw[1:]
    return re.sub(r"\s+#.*$", "", raw).strip()


def _declared(front, key):
    """The declared value of `key`, None when nothing was declared, `_AMBIGUOUS` when it
    was declared more than once."""
    if front is _UNREADABLE or front is _ESCAPED:
        return None
    value = front.get(key)
    if value is _AMBIGUOUS:
        return _AMBIGUOUS
    return value or None


def _contains(root_real, target_real):
    """True when an already-resolved `target_real` lies at or under `root_real`."""
    return target_real == root_real or target_real.startswith(root_real + os.sep)


def _resolve_under_root(root, spec_path):
    """The absolute spec directory for `spec_path`, or None when it escapes `root`.

    `os.path.join(root, spec_path)` silently DISCARDS `root` when `spec_path` is absolute,
    and walks out of it when `spec_path` contains `..`. Either way a hand-edited or migrated
    board can aim the gate at a directory outside the harness: with a matching spec there,
    `init.sh` certifies the board as consistent while the Reviewer reads a spec that is not
    in this repository at all.

    Containment is to the HARNESS ROOT, deliberately not to `<root>/specs`. Leaving the
    repository is the defect; sitting somewhere other than `specs/` is a convention, and
    `store/tasks.schema.json` has never constrained `spec_path` beyond `"type": "string"`.
    Enforcing the convention here would fail-stop schema-valid boards that predate this rule
    — two shipped suites use short in-repo paths like `a/` — and at a MANDATORY gate an
    unstated convention that halts all agent work is a worse failure than the odd layout it
    would have tidied. A spec outside `specs/` is still inside the repository, still has to
    declare this feature's id, and still has to agree with the board.

    Containment is compared on RESOLVED paths (`realpath`), on both sides. An earlier
    version compared lexically, reasoning that the question was "what did the board ask
    for" and that no legitimate harness layout symlinks a spec tree. Both halves of that
    were beside the point: a lexical test accepts `specs/epics/<F>/ -> /tmp/elsewhere`,
    which is IN-root by spelling and outside the repository in fact, so the gate certifies
    a Reviewer-facing spec that is not in this repo — the very escape this rule exists to
    stop. What matters is where the read actually lands, not how it is written.

    Resolving the root too is not optional: on macOS `/tmp` is itself a symlink to
    `/private/tmp`, so resolving only one side would report an escape for every tree under
    a temporary directory.
    """
    if os.path.isabs(spec_path):
        return None
    # realpath, NOT normpath: init.sh passes `--spec-root .`, and `normpath(".")` is `"."`,
    # which no joined relative path is ever prefixed by — so a normpath comparison calls
    # every path an escape in the one configuration that actually ships.
    base = os.path.realpath(root)
    target = os.path.realpath(os.path.join(base, spec_path))
    return target if _contains(base, target) else None


def _spec_files(directory):
    """Every `*.spec.md` in `directory`, sorted.

    Globbed rather than assuming `<ID>.spec.md`: 18 feature directories predate
    that convention and use `<slug>.spec.md` (`installer.spec.md`,
    `umbrella-coordinator.spec.md`, ...). Assuming the ID form silently skips every
    one of them — a guard that reports nothing on two thirds of the board.
    """
    return sorted(glob.glob(os.path.join(glob.escape(directory), "*.spec.md")))


def spec_consistency_errors(data, root):
    """Board-vs-disk errors for `data`, resolving relative paths under `root`.

    Returns a list of error strings (empty = consistent). Every message names the
    file and BOTH values, because the reader is looking at a halted gate and has to
    decide which of the two records is the wrong one.
    """
    errors = []
    if not isinstance(data, dict):
        return errors

    # Resolved ONCE. Every path this function reports is derived from `_resolve_under_root`,
    # which returns a realpath — so displaying it relative to an UNRESOLVED root prints
    # `../../../private/var/...` on any platform where the root sits under a symlink (macOS
    # /var, every mktemp fixture). A gate's message is the thing an operator acts on.
    root_real = os.path.realpath(root)

    for ep in data.get("epics") or []:
        if not isinstance(ep, dict):
            continue
        eid = ep.get("id")
        estatus = ep.get("status")

        # --- epic.md, resolved by convention (the board records no epic path) ---
        if isinstance(eid, str) and isinstance(estatus, str):
            edirs = sorted(
                glob.glob(os.path.join(glob.escape(root), "specs", "epics", "%s-*" % eid))
            )
            edirs = [d for d in edirs if os.path.isdir(d)]
            if len(edirs) == 1:
                epic_md = os.path.join(edirs[0], "epic.md")
                if os.path.isfile(epic_md):
                    front = _frontmatter(root_real, epic_md)
                    if front is _ESCAPED:
                        # The board records no epic path, so this one is resolved by
                        # CONVENTION from `specs/epics/<id>-*` — which makes it look
                        # in-repo by construction and is exactly why it was the read site
                        # that stayed unguarded longest. A symlinked epic directory puts
                        # the document outside the repository while the glob that found it
                        # never left.
                        errors.append(
                            "%s: epic.md escapes the harness root: %s — it resolves "
                            "outside the repository, so the gate would certify an epic "
                            "document that is not in it"
                            % (eid, os.path.relpath(epic_md, root_real))
                        )
                        front = {}
                    if front is _UNREADABLE:
                        errors.append(
                            "%s: epic.md cannot be read or decoded (%s) — its status "
                            "could not be compared against the board"
                            % (eid, os.path.relpath(epic_md, root_real))
                        )
                        front = {}
                    declared = _declared(front, "status")
                    if declared is _AMBIGUOUS:
                        errors.append(
                            "%s: epic.md declares 'status' more than once (%s) — which "
                            "one is effective is ambiguous, so it cannot be compared "
                            "with the board"
                            % (eid, os.path.relpath(epic_md, root_real))
                        )
                        declared = None
                    if declared is not None and declared != estatus:
                        errors.append(
                            "%s: epic.md frontmatter status '%s' disagrees with board "
                            "status '%s' (%s)"
                            % (
                                eid,
                                declared,
                                estatus,
                                os.path.relpath(epic_md, root_real),
                            )
                        )

        for ft in ep.get("features") or []:
            if not isinstance(ft, dict):
                continue
            fid = ft.get("id")
            fstatus = ft.get("status")
            spec_path = ft.get("spec_path")
            # A missing or NON-STRING spec_path is a genuine schema error (`"type":
            # "string"`), so re-reporting it here would double every message.
            if not isinstance(spec_path, str):
                continue
            if not isinstance(fid, str) or not isinstance(fstatus, str):
                continue

            # `authored` is needed before the empty-path check below, so it is computed
            # here rather than after it.
            #
            # A DRAFT epic is an inception sketch. The harness already declares that a
            # non-`pending` feature inside one is WARN-ONLY (see _emit_draft_warnings:
            # the next() draft gate keeps it unselectable), so demanding an authored
            # spec for it here would hard-fail through a side door the exact board state
            # the harness has decided to tolerate. The status-agreement rule below still
            # applies — a spec that DOES exist and disagrees is real drift either way.
            authored = (
                ft.get("sdd") is True
                and fstatus != "pending"
                and estatus != "draft"
            )

            if not spec_path:
                # An EMPTY spec_path is NOT a schema error — `"type": "string"` accepts
                # `""` — so skipping it here let an authored feature opt out of every rule
                # below by naming nothing at all. The comment this replaced asserted the
                # schema already caught it; it did not.
                if authored:
                    errors.append(
                        "%s: spec_path is empty — an sdd feature at status '%s' must name "
                        "a spec directory a Reviewer can open" % (fid, fstatus)
                    )
                continue

            fdir = _resolve_under_root(root, spec_path)
            if fdir is None:
                # Unconditional — not gated on `authored`. An escaping spec_path is not
                # "no spec yet", it is a malformed pointer, and it is exactly as wrong on
                # an sdd:false or pending entry as on an authored one.
                errors.append(
                    "%s: spec_path escapes the harness root: %s — it must be a relative "
                    "path inside the repository, or the gate would certify a spec that "
                    "is not in it" % (fid, spec_path)
                )
                continue

            if not os.path.isdir(fdir):
                if authored:
                    errors.append(
                        "%s: spec_path does not exist: %s — an sdd feature at status "
                        "'%s' must have an authored spec a Reviewer can open"
                        % (fid, spec_path, fstatus)
                    )
                continue

            specs = _spec_files(fdir)
            if not specs:
                if authored:
                    # The outcome that matters is "the spec is readable", not "the
                    # path stats". A directory that exists but holds no spec passes
                    # any existence check and still leaves the Reviewer with nothing
                    # to read — which is the failure this rule is about.
                    errors.append(
                        "%s: spec_path has no *.spec.md: %s — an sdd feature at status "
                        "'%s' must have an authored spec a Reviewer can open"
                        % (fid, spec_path, fstatus)
                    )
                continue

            # `owned` counts specs that PROVE they belong to this board entry by declaring
            # the feature's id. Without it, a spec_path pointing at a SIBLING feature's
            # directory whose spec happens to carry the same status passes every check
            # above — the path resolves, a *.spec.md is there, the statuses agree — and the
            # gate reports a consistent environment while the Reviewer opens and implements
            # the wrong feature's spec. Resolving is not the same as belonging.
            owned = 0
            misowned = False
            for spec_file in specs:
                # Containment is re-checked per FILE, not inherited from the directory —
                # a matched `*.spec.md` is free to be a symlink whose target is outside the
                # repository, in-repo by listing and external in fact. The check is no
                # longer written HERE, though: it is what `_frontmatter` does before it
                # opens anything, so this site gets it by construction.
                front = _frontmatter(root_real, spec_file)
                if front is _ESCAPED:
                    errors.append(
                        "%s: spec file escapes the harness root: %s — it resolves outside "
                        "the repository, so the gate would certify a spec that is not in it"
                        % (fid, os.path.relpath(spec_file, root_real))
                    )
                    continue
                if front is _UNREADABLE:
                    # The glob already satisfied the "an authored spec exists" rule, so
                    # without this the file's unreadability would be indistinguishable
                    # from it simply declaring no status — and the gate would pass a spec
                    # no Reviewer can open, which is the whole contract.
                    errors.append(
                        "%s: spec file cannot be read or decoded: %s — the contract is "
                        "that a Reviewer can open it"
                        % (fid, os.path.relpath(spec_file, root_real))
                    )
                    continue

                declared_id = _declared(front, "id")
                if declared_id is _AMBIGUOUS:
                    errors.append(
                        "%s: spec declares 'id' more than once (%s) — which one is "
                        "effective is ambiguous, so ownership cannot be proven"
                        % (fid, os.path.relpath(spec_file, root_real))
                    )
                    misowned = True
                    continue
                declared_status = _declared(front, "status")
                if declared_status is _AMBIGUOUS:
                    errors.append(
                        "%s: spec declares 'status' more than once (%s) — which one is "
                        "effective is ambiguous, so it cannot be compared with the board"
                        % (fid, os.path.relpath(spec_file, root_real))
                    )
                    continue
                if declared_id is not None and declared_id != fid:
                    # This file belongs to a different feature. Report the ownership
                    # failure and do NOT compare its status: a status drawn from another
                    # feature's spec is meaningless either way it comes out.
                    errors.append(
                        "%s: spec declares id '%s' (%s) — spec_path points at another "
                        "feature's spec, which a Reviewer would open and implement"
                        % (fid, declared_id, os.path.relpath(spec_file, root_real))
                    )
                    misowned = True
                    continue
                if declared_id == fid:
                    owned += 1

                if declared_status is not None and declared_status != fstatus:
                    errors.append(
                        "%s: spec frontmatter status '%s' disagrees with board status "
                        "'%s' (%s)"
                        % (
                            fid,
                            declared_status,
                            fstatus,
                            os.path.relpath(spec_file, root_real),
                        )
                    )

            if authored and owned == 0 and not misowned:
                # Nothing under the path claims this feature. Suppressed when a misowned
                # spec was already reported, because that message says the same thing more
                # precisely and naming it twice makes the gate output harder to act on.
                errors.append(
                    "%s: no spec under %s declares id '%s' — the directory is not proven "
                    "to belong to this board entry" % (fid, spec_path, fid)
                )

    return errors


def _emit_draft_warnings(data):
    """init.sh's warn-only draft-epic invariant (stderr, non-fatal).

    A `draft` epic is an inception sketch, so its features should still be
    `pending`. A violation is NOT a validation error — the next() draft gate
    already neutralizes it — so we warn and continue. Preserved verbatim from
    init.sh so the CLI's stderr output is byte-identical.
    """
    if isinstance(data, dict):
        for ep in data.get("epics") or []:
            if isinstance(ep, dict) and ep.get("status") == "draft":
                for ft in ep.get("features") or []:
                    if isinstance(ft, dict) and ft.get("status") != "pending":
                        print(
                            "⚠️  draft epic %s has feature %s with status '%s' "
                            "(expected 'pending'; the draft gate keeps it unselectable)"
                            % (ep.get("id"), ft.get("id"), ft.get("status")),
                            file=sys.stderr,
                        )


def _main(argv):
    # `--spec-root <dir>` is OPT-IN. Omitted, the spec-consistency pass does not
    # run at all and this CLI behaves exactly as it did before E99-F14 — which is
    # what every fixture caller that validates a throwaway board from the repo root
    # relies on. There is no cwd default on purpose: silently resolving some other
    # board's spec_paths against the current repository would report drift that
    # does not exist.
    spec_root = None
    positional = []
    rest = list(argv)
    while rest:
        arg = rest.pop(0)
        if arg == "--spec-root":
            if not rest:
                print("--spec-root requires a directory", file=sys.stderr)
                return 2
            spec_root = rest.pop(0)
        elif arg.startswith("--spec-root="):
            spec_root = arg.split("=", 1)[1]
        else:
            positional.append(arg)

    if len(positional) != 2:
        print(
            "usage: validate-board.py <data.json> <schema.json> "
            "[--spec-root <dir>]",
            file=sys.stderr,
        )
        return 2
    data_path, schema_path = positional
    try:
        data = json.load(open(data_path))
    except (ValueError, OSError) as e:
        print("  not valid JSON: %s" % e, file=sys.stderr)
        return 1
    try:
        schema = json.load(open(schema_path))
    except (ValueError, OSError) as e:
        print("  schema not readable: %s" % e, file=sys.stderr)
        return 1

    # Warn-only draft-epic invariant runs on BOTH paths, before validation
    # (matches init.sh's former ordering exactly).
    _emit_draft_warnings(data)

    errs = validate(data, schema)
    for e in errs:
        print("  %s" % e, file=sys.stderr)
    if errs:
        # Schema failure is primary: the board's SHAPE is wrong, so any disagreement
        # with disk is downstream noise. Report it alone, as this CLI always has.
        return 1

    if spec_root is not None:
        spec_errs = spec_consistency_errors(data, spec_root)
        for e in spec_errs:
            print("  %s" % e, file=sys.stderr)
        if spec_errs:
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
