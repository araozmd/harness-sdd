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
import math
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

    validate = _load_shared_validator()
    schema = _load_schema(schema_path)

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

            # Validate the mutated content BEFORE replacing the file (R4), using
            # the SAME shared validator init.sh runs. Any error → fail-stop, board
            # untouched (raised here, caught by main() → non-zero, clear message).
            serialized = json.dumps(data, indent=2) + "\n"
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
