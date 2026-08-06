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


def _frontmatter_status(path):
    """Return a spec/epic file's frontmatter `status`, or None if there is none.

    None means "nothing to compare" — not "invalid". Callers treat it as a skip.

    Inline comments are stripped because EVERY epic.md in this repo writes
    `status: done             # draft -> planned -> in-progress -> done`. Comparing
    against the raw line reports 19 drifts where 7 exist, and a false positive at a
    MANDATORY gate halts all agent work.
    """
    try:
        with io.open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError):
        return None
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    block = text[3:end] if end != -1 else text[3:]
    m = re.search(r"^status:[ \t]*(.*)$", block, re.M)
    if not m:
        return None
    raw = m.group(1).strip()
    if raw[:1] in ('"', "'"):
        # Quoted: the value is what is inside the quotes, '#' included.
        closing = raw.find(raw[0], 1)
        value = raw[1:closing] if closing != -1 else raw[1:]
    else:
        value = re.sub(r"\s+#.*$", "", raw).strip()
    return value or None


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
                    declared = _frontmatter_status(epic_md)
                    if declared is not None and declared != estatus:
                        errors.append(
                            "%s: epic.md frontmatter status '%s' disagrees with board "
                            "status '%s' (%s)"
                            % (
                                eid,
                                declared,
                                estatus,
                                os.path.relpath(epic_md, root),
                            )
                        )

        for ft in ep.get("features") or []:
            if not isinstance(ft, dict):
                continue
            fid = ft.get("id")
            fstatus = ft.get("status")
            spec_path = ft.get("spec_path")
            # A missing/non-string spec_path or status is already a schema error;
            # re-reporting it here would double every message.
            if not isinstance(spec_path, str) or not spec_path:
                continue
            if not isinstance(fid, str) or not isinstance(fstatus, str):
                continue

            fdir = os.path.join(root, spec_path)
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

            for spec_file in specs:
                declared = _frontmatter_status(spec_file)
                if declared is not None and declared != fstatus:
                    errors.append(
                        "%s: spec frontmatter status '%s' disagrees with board status "
                        "'%s' (%s)"
                        % (
                            fid,
                            declared,
                            fstatus,
                            os.path.relpath(spec_file, root),
                        )
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
