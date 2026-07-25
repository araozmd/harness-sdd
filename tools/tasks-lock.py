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
# HARNESS_DIR (env) selects the board root; when unset it is derived from this
# helper's own path — the file lives at <HARNESS_DIR>/tools/tasks-lock.py, so the
# harness dir is the parent of the parent of __file__. Deriving from __file__ (not
# cwd) makes the documented invocation correct from ANY cwd, in BOTH the source
# layout (tools/tasks-lock.py, board at state/tasks.json) and the installed layout
# (.harness/tools/tasks-lock.py, board at .harness/state/tasks.json).

import argparse
import errno
import fcntl
import importlib.util
import json
import os
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


def _harness_dir():
    """Resolve the board root.

    Highest precedence is an explicit HARNESS_DIR env override (an escape hatch
    for unusual layouts). Otherwise derive it from this helper's own location:
    the file lives at <HARNESS_DIR>/tools/tasks-lock.py, so the harness dir is the
    parent of the parent of __file__. This is robust to any cwd and works in both
    the source layout and the installed `.harness/tools/` layout — no caller ever
    needs to hand-set HARNESS_DIR just to run the documented command.
    """
    override = os.environ.get("HARNESS_DIR")
    if override:
        return override
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


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


def _load_schema_validator(schema_path):
    """Return a callable(data)->None that raises on schema violation.

    Prefers `jsonschema` if available; otherwise falls back to a minimal
    structural check derived from store/tasks.schema.json (enum + required +
    id-pattern) so the fail-stop guarantee (R4) holds with zero extra deps.
    """
    with open(schema_path) as fh:
        schema = json.load(fh)
    try:
        import jsonschema  # type: ignore

        def _validate(data):
            jsonschema.validate(data, schema)

        return _validate
    except Exception:
        return _make_minimal_validator(schema)


def _make_minimal_validator(schema):
    import re

    feat_status = set(
        schema["properties"]["epics"]["items"]["properties"]["features"]["items"][
            "properties"
        ]["status"]["enum"]
    )
    epic_status = set(
        schema["properties"]["epics"]["items"]["properties"]["status"]["enum"]
    )
    epic_id_re = re.compile(
        schema["properties"]["epics"]["items"]["properties"]["id"]["pattern"]
    )
    feat_id_re = re.compile(
        schema["properties"]["epics"]["items"]["properties"]["features"]["items"][
            "properties"
        ]["id"]["pattern"]
    )

    def _validate(data):
        if not isinstance(data, dict):
            raise ValueError("board root is not an object")
        if "project" not in data or "epics" not in data:
            raise ValueError("board missing required 'project'/'epics'")
        if not isinstance(data["epics"], list):
            raise ValueError("'epics' is not an array")
        for epic in data["epics"]:
            for req in ("id", "title", "status", "features"):
                if req not in epic:
                    raise ValueError("epic missing required field '%s'" % req)
            if not epic_id_re.match(epic["id"]):
                raise ValueError("epic id %r fails id pattern" % epic.get("id"))
            if epic["status"] not in epic_status:
                raise ValueError(
                    "epic %s has invalid status %r (not in %s)"
                    % (epic["id"], epic["status"], sorted(epic_status))
                )
            for feat in epic["features"]:
                for req in ("id", "title", "status", "sdd", "spec_path"):
                    if req not in feat:
                        raise ValueError(
                            "feature missing required field '%s'" % req
                        )
                if not feat_id_re.match(feat["id"]):
                    raise ValueError(
                        "feature id %r fails id pattern" % feat.get("id")
                    )
                if feat["status"] not in feat_status:
                    raise ValueError(
                        "feature %s has invalid status %r (not in %s)"
                        % (feat["id"], feat["status"], sorted(feat_status))
                    )
                # Mirror the schema's cross-field `slices` invariant (allOf/if-then):
                # a sliced feature may be `done` ONLY when every slice is itself
                # `done` AND `merged: true`. Without this, the zero-dependency
                # fallback would let `set-status <sliced-feature> done` persist a
                # board that init.sh's full jsonschema pass later rejects — and
                # would prematurely unblock dependents. Single-repo features (no
                # `slices`) are unaffected: the guard only fires when slices exist.
                if feat["status"] == "done" and feat.get("slices"):
                    for sl in feat["slices"]:
                        if sl.get("status") != "done" or sl.get("merged") is not True:
                            raise ValueError(
                                "feature %s is 'done' but slice %s is not "
                                "done+merged (status=%r, merged=%r); a sliced "
                                "feature may be done only when every slice is "
                                "done and merged"
                                % (
                                    feat["id"],
                                    sl.get("id"),
                                    sl.get("status"),
                                    sl.get("merged"),
                                )
                            )

    return _validate


def _import_mutator(path):
    spec = importlib.util.spec_from_file_location("_tasks_lock_mutator", path)
    if spec is None or spec.loader is None:
        _die("could not load mutator module from %s" % path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not hasattr(module, "mutate"):
        _die("mutator %s does not define mutate(data) -> data" % path)
    return module.mutate


def _set_status_mutator(target_id, status):
    """Build a mutator that sets the status of the object <target_id> addresses."""
    is_feature = "-F" in target_id

    def mutate(data):
        for epic in data.get("epics", []):
            if is_feature:
                for feat in epic.get("features", []):
                    if feat.get("id") == target_id:
                        feat["status"] = status
                        return data
            else:
                if epic.get("id") == target_id:
                    epic["status"] = status
                    return data
        _die("id %r not found in board" % target_id)

    return mutate


def run(mutator, timeout):
    hdir = _harness_dir()
    tasks_path = os.path.join(hdir, TASKS_REL)
    lock_path = os.path.join(hdir, LOCK_REL)
    schema_path = os.path.join(hdir, SCHEMA_REL)

    if not os.path.exists(tasks_path):
        _die("board not found at %s (HARNESS_DIR=%s)" % (tasks_path, hdir))

    validate = _load_schema_validator(schema_path)

    # Open (creating if needed) the sibling lockfile. It only ever anchors the
    # advisory lock; it never holds board data.
    lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        _acquire(lock_fd, lock_path, timeout)  # R3, R5
        try:
            # RE-READ from disk INSIDE the lock (R2) — never a pre-lock copy.
            with open(tasks_path) as fh:
                data = json.load(fh)

            data = mutator(data)  # the single mutation (R1)

            # Validate the mutated content BEFORE replacing the file (R4).
            serialized = json.dumps(data, indent=2) + "\n"
            reparsed = json.loads(serialized)  # parse check
            validate(reparsed)  # schema check

            # Atomic write: temp in the same dir, then os.replace (R4 — no torn
            # file). If the process dies mid-write, the original is untouched.
            tmp_path = tasks_path + ".tmp.%d" % os.getpid()
            try:
                with open(tmp_path, "w") as out:
                    out.write(serialized)
                    out.flush()
                    os.fsync(out.fileno())
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

    if args.cmd == "set-status":
        mutator = _set_status_mutator(args.id, args.status)
    elif args.cmd == "apply":
        mutator = _import_mutator(args.mutator)
    else:  # pragma: no cover - argparse enforces
        parser.error("unknown command")

    try:
        run(mutator, args.timeout)
    except SystemExit:
        raise
    except json.JSONDecodeError as exc:
        _die("mutated board is not valid JSON: %s" % exc)
    except Exception as exc:  # validation / mutator failures → fail-stop (R4)
        _die("aborting write, original board left intact: %s" % exc)


if __name__ == "__main__":
    main(sys.argv[1:])
