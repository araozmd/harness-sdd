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

import json
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
    if len(argv) != 2:
        print(
            "usage: validate-board.py <data.json> <schema.json>", file=sys.stderr
        )
        return 2
    data_path, schema_path = argv
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
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
