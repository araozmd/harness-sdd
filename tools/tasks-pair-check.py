#!/usr/bin/env python3
"""tasks-pair-check — lint a feature .tasks.md for per-requirement red/green pair shape.

E36-F01 / ADR-0008 decision 2.  Usage:

    tasks-pair-check.py <feature.tasks.md> --spec <feature.spec.md>
    tasks-pair-check.py --grandfathered <feature.tasks.md> [--base <ref>]

The lint is a pure function of two files; stdlib only.  Grammar (identical to docs/SPEC-FORMAT.md
"Tasks — red/green pairs per requirement"):

  * Fenced code is skipped in BOTH files.  The fence rule is the CommonMark one that
    tests/lib/fence.awk encodes (backtick or tilde run >= 3, indented 0-3 spaces; a closer is
    the same char, at least as long, no info string; a backtick opener has no backtick in its
    info string).  iter_unfenced() is a DELIBERATE second copy of that rule, not a hidden one:
    tests/test_tasks_pairs.sh R5_fence_parity feeds one edge corpus to both copies and
    requires identical unfenced output; deleting any one clause of either copy fails it.
  * spec R-id: a line `- **R<n>** ...`; first appearance order, duplicates collapse.
  * task: `- [ ] **T<n><suffix>** (R#, R#) -- text` (or `- [x]`); the `T` and the suffix
    letters match in either case.  Suffix `a`/`A` = test task, `b`/`B` = code task; no suffix,
    any other letter, or more than one letter (`T1c`, `T1ab`) = "other" -- reported, never
    dropped.  The T-id is printed as written.  Cited R-ids are the
    explicit R<n> tokens in the parentheses; a range R1-R4 is NOT expanded.
  * violations: `first-task-not-test <R-id> <T-id>`, `no-task <R-id>`, `write-tests-task <T-id>`
    (an un-cited task whose text matches \\bwrite\\b.*\\btests\\b, wherever it sits).

Exit: 0 ok, 1 violation(s), 2 usage/input error (stderr `tasks-pair-check: error: ...`).

--grandfathered (Reviewer check 7's grandfather rule; reads git, nothing else):
  * the tool's date is its MERGE into the default branch -- the committer time of the first
    first-parent commit on <base> that touches tools/tasks-pair-check.py or
    .harness/tools/tasks-pair-check.py (source repo / installed target).  <base> is --base,
    else what `refs/remotes/origin/HEAD` names, else the first of origin/main main
    origin/master master origin/trunk trunk that resolves (tools/change-size.sh's order).
  * the .tasks.md date is the AUTHOR time of the earliest commit on HEAD that added it
    (a rebase rewrites committer time, not author time).
  * flag (exit 0) when the tool is not on <base> yet, or the .tasks.md date is strictly
    older than the tool's merge; otherwise reject class (exit 1) -- including a .tasks.md
    with no commit yet.  Exit 2 when the file is not in a git work tree or no <base> resolves.
"""
import os
import subprocess
import re
import sys

PFX = "tasks-pair-check: "
USAGE = ("usage: tasks-pair-check.py <feature.tasks.md> --spec <feature.spec.md>\n"
         "       tasks-pair-check.py --grandfathered <feature.tasks.md> [--base <ref>]")
TOOL_PATHS = ("tools/tasks-pair-check.py", ".harness/tools/tasks-pair-check.py")
BASE_FALLBACKS = ("origin/main", "main", "origin/master", "master", "origin/trunk", "trunk")

RID_RE = re.compile(r"^[ \t]*-[ \t]+\*\*(R[0-9]+)\*\*")
TASK_RE = re.compile(
    r"^[ \t]*-[ \t]+\[[ xX]\][ \t]+\*\*([Tt][0-9]+)([A-Za-z]+)?\*\*"
    r"(?:[ \t]*\(([^)]*)\))?[ \t]*(?:—|–|-)?[ \t]*(.*)$"
)
WRITE_TESTS_RE = re.compile(r"\bwrite\b.*\btests\b", re.IGNORECASE)


class InputError(Exception):
    pass


def iter_unfenced(lines):
    """Yield the lines outside fenced code blocks (delimiters excluded)."""
    fence = False
    f_char = ""
    f_len = 0
    for line in lines:
        line = line.rstrip("\n")
        ind = 0
        while ind < 4 and line[ind:ind + 1] == " ":
            ind += 1
        delim = False
        if ind <= 3:
            ch = line[ind:ind + 1]
            if ch and ch in "`~":  # guard: "" in "`~" is True
                run = 0
                while line[ind + run:ind + run + 1] == ch:
                    run += 1
                if run >= 3:
                    tail = line[ind + run:]
                    if fence:
                        if ch == f_char and run >= f_len and not tail.strip(" \t"):
                            fence = False
                            delim = True
                    elif not (ch == "`" and "`" in tail):
                        fence = True
                        f_char, f_len = ch, run
                        delim = True
        if delim or fence:
            continue
        yield line


def _read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.readlines()
    except (OSError, UnicodeDecodeError) as exc:
        raise InputError("cannot read %s: %s" % (path, exc))


def read_rids(path):
    rids = []
    for line in iter_unfenced(_read(path)):
        m = RID_RE.match(line)
        if m and m.group(1) not in rids:
            rids.append(m.group(1))
    return rids


def read_tasks(path):
    """Return [(t_id, kind, cited_rids, text)] in file order; kind in test/code/other."""
    tasks = []
    for line in iter_unfenced(_read(path)):
        m = TASK_RE.match(line)
        if not m:
            continue
        suffix = m.group(2)
        norm = (suffix or "").lower()
        kind = "test" if norm == "a" else "code" if norm == "b" else "other"
        cited = re.findall(r"R[0-9]+", m.group(3) or "")
        tasks.append((m.group(1) + (suffix or ""), kind, cited, m.group(4)))
    return tasks


def check(rids, tasks):
    """Pure: return the list of violation strings (without the prefix)."""
    out = []
    for rid in rids:
        first = next((t for t in tasks if rid in t[2]), None)
        if first is None:
            out.append("no-task %s" % rid)
        elif first[1] != "test":
            out.append("first-task-not-test %s %s" % (rid, first[0]))
    for t_id, _kind, cited, text in tasks:
        if not cited and WRITE_TESTS_RE.search(text):
            out.append("write-tests-task %s" % t_id)
    return out


def _git(repo, *args):
    try:
        r = subprocess.run(["git", "-C", repo] + list(args), stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, universal_newlines=True)
    except OSError as exc:
        raise InputError("cannot run git: %s" % exc)
    return r.returncode, r.stdout


def _resolves(repo, ref):
    return _git(repo, "rev-parse", "--verify", "--quiet", ref + "^{commit}")[0] == 0


def default_branch(repo):
    rc, out = _git(repo, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
    head = out.strip() if rc == 0 else ""
    for ref in ((head,) if head else ()) + BASE_FALLBACKS:
        if _resolves(repo, ref):
            return ref
    return None


def grandfather(tasks_path, base=None):
    """Return (flag, reason): flag True = grandfathered (advisory), False = reject class."""
    path = os.path.realpath(tasks_path)
    if not os.path.isfile(path):
        raise InputError("cannot read %s" % tasks_path)
    rc, out = _git(os.path.dirname(path), "rev-parse", "--show-toplevel")
    if rc != 0 or not out.strip():
        raise InputError("%s is not inside a git work tree" % tasks_path)
    top = out.strip()  # git prints the toplevel symlink-resolved, like `path` above
    if base is None:
        base = default_branch(top)
        if base is None:
            raise InputError("no default branch resolves (origin/HEAD, %s); pass --base"
                             % " ".join(BASE_FALLBACKS))
    elif not _resolves(top, base):
        raise InputError("--base does not resolve: %s" % base)
    _rc, out = _git(top, "log", "--first-parent", "--reverse", "--format=%ct", base, "--",
                    *TOOL_PATHS)
    stamps = out.split()
    if not stamps:
        return True, "tool not on default branch %s yet" % base
    merged = int(stamps[0])
    rel = os.path.relpath(path, top)
    _rc, out = _git(top, "log", "--diff-filter=A", "--format=%at", "HEAD", "--", rel)
    authored = [int(x) for x in out.split()]
    if not authored:
        return False, "%s has no commit on HEAD; tool merged into %s at %d" % (rel, base, merged)
    first = min(authored)
    if first < merged:
        return True, "%s authored %d, before tool merged into %s at %d" % (rel, first, base, merged)
    return False, "%s authored %d, not before tool merged into %s at %d" % (rel, first, base, merged)


def main_grandfathered(args):
    base = None
    pos = []
    i = 0
    while i < len(args):
        if args[i] == "--base":
            if i + 1 >= len(args):
                raise InputError("--base needs a ref")
            base = args[i + 1]
            i += 2
        elif args[i].startswith("--base="):
            base = args[i][len("--base="):]
            i += 1
        else:
            pos.append(args[i])
            i += 1
    if len(pos) != 1:
        raise InputError("--grandfathered expects exactly one <feature.tasks.md>")
    flag, reason = grandfather(pos[0], base)
    print("%sgrandfather %s: %s" % (PFX, "flag" if flag else "reject", reason))
    return 0 if flag else 1


def main(argv):
    args = argv[1:]
    if any(a in ("-h", "--help") for a in args):
        print(USAGE)
        return 0
    if "--grandfathered" in args:
        try:
            return main_grandfathered([a for a in args if a != "--grandfathered"])
        except InputError as exc:
            sys.stderr.write("%serror: %s\n%s\n" % (PFX, exc, USAGE))
            return 2
    try:
        spec = None
        pos = []
        i = 0
        while i < len(args):
            if args[i] == "--spec":
                if i + 1 >= len(args):
                    raise InputError("--spec needs a path")
                spec = args[i + 1]
                i += 2
            elif args[i].startswith("--spec="):
                spec = args[i][len("--spec="):]
                i += 1
            else:
                pos.append(args[i])
                i += 1
        if spec is None:
            raise InputError("--spec <feature.spec.md> is required")
        if len(pos) != 1:
            raise InputError("expected exactly one <feature.tasks.md>")
        rids = read_rids(spec)
        tasks = read_tasks(pos[0])
        if not rids:
            raise InputError("no R-ids found in %s" % spec)
    except InputError as exc:
        sys.stderr.write("%serror: %s\n%s\n" % (PFX, exc, USAGE))
        return 2
    violations = check(rids, tasks)
    if violations:
        for v in violations:
            print(PFX + v)
        print("%sFAIL %d violation(s)" % (PFX, len(violations)))
        return 1
    print("%sok %d R-ids, %d tasks" % (PFX, len(rids), len(tasks)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
