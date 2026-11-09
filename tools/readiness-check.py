#!/usr/bin/env python3
"""readiness-check — lint a feature's spec files: every path and symbol they name resolves.

E37-F01.  Usage:

    readiness-check.py <feature-dir | feature.plan.md> [--root <dir>]
    readiness-check.py --grandfathered <feature.plan.md> [--base <ref>]

Exit: 0 ok, 1 finding(s) / grandfather reject, 2 usage or input error (stderr
`readiness-check: error: ...` plus the usage, nothing on stdout) or an unexpected exception
(stderr `readiness-check: error: internal: <type>: <msg>`, no traceback) — exit 2 is "the
check did not run", never a pass.  `-h`/`--help` print the usage and exit 0 only as an option
token: the word after --root or --base is that flag's value, never help.  Stdlib only; a pure
function of the paths named on argv (taken verbatim: no shlex, glob or ~ expansion) and the
tree under the root.

The reference grammar is docs/SPEC-FORMAT.md "Implementation readiness — every named path
resolves"; this tool lints it, it never redefines it.  In short:

  * units: every data row of a table under the plan's `## Files to change` heading; every
    list item of `<stem>.tasks.md`; every table data row and list item of `<stem>.tests.md`.
    Prose, blockquotes and headings are never scanned; the .spec.md is never read.
  * a reference is a single-backtick span with no whitespace.  `::<name>` (a test reference)
    is dropped, then a trailing `:<digits>[-<digits>]` (a line reference), then a trailing
    `:<identifier>` (the symbol form), then a leading `./`; what remains is a path candidate
    when it holds a `/` or its last segment has a dotted extension.  In a plan row, paths are
    read from the FIRST cell only; symbol forms from every cell.
  * the created set: the first-cell paths of every row whose Change cell's first word is
    `create`.  A reference resolves when it is created (or under a created directory), exists
    at the root, exists through the `.harness/` remap (either direction), or — bare — exists
    in the feature directory.
  * the root is --root, else the nearest ancestor of the plan's directory holding `.git` (a
    directory or a file), walked on the absolute path without resolving symlinks and never
    into a GIT_CEILING_DIRECTORIES entry (git's own discovery bound).

The section/table/fence grammar is plan-cite-check's: iter_unfenced(), _read(), cells(),
is_separator(), parse_sections() and strip_wrappers() are a DELIBERATE second copy of
tools/plan-cite-check.py's (CHECKED_RE reduced to the one heading), not an import — the two
tools install and run independently and a consumer may delete either.  The copies are pinned
by tests/test_readiness_check.sh's R10_fence_parity (against tests/lib/fence.awk) and
R10_table_grammar_parity (against plan-cite-check's parse_sections()).

Findings (one line each, plan then tasks then tests, by line): `unresolved-path
<file>:<line> <path>` and `unresolved-symbol <file>:<line> <path>:<name>`, then `FAIL <n>
finding(s)`.

Known limits: precision over recall.  A path whose first segment is not a known root (an
existing directory at the root or under `.harness/`, or the first segment of a created path)
is ignored, so a first-segment typo (`tols/x.py`) is not caught; v1 symbol forms are `name()`
and `path:name` only.
"""
import os
import re
import sys

PFX = "readiness-check: "
USAGE = ("usage: readiness-check.py <feature-dir | feature.plan.md> [--root <dir>]\n"
         "       readiness-check.py --grandfathered <feature.plan.md> [--base <ref>]")
HELP_FLAGS = ("-h", "--help")
# Every flag that takes a value, across the two modes: the word after one is its value.
VALUE_FLAGS = ("--root", "--base")

CHECKED_RE = re.compile(r"^## (Files to change)(\s|$)")
CLOSE_RE = re.compile(r"^##? ")
SEP_CELL_RE = re.compile(r"^:?-+:?$")
CELL_SPLIT_RE = re.compile(r"(?<!\\)\|")
WRAPPERS = "*`\"'"
BOM = "﻿"  # one is stripped from the head of every file read (_read)

SPAN_RE = re.compile(r"`([^`\n]+)`")
TESTREF_RE = re.compile(r"::.*$")
LINEREF_RE = re.compile(r":[0-9]+(-[0-9]+)?$")
SYMFORM_RE = re.compile(r":([A-Za-z_][A-Za-z0-9_]*)$")
EXT_RE = re.compile(r"\.[A-Za-z0-9]{1,5}$")
CALL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)$")  # symbol form 1: `name()`, no args
ITEM_RE = re.compile(r"^[ \t]*- ")
CONT_RE = re.compile(r"^[ \t]{2,}\S")
VERB_RE = re.compile(r"[A-Za-z]+")
IGNORE_CHARS = "<>*?[]{}$~|"
BARE_EXT_RE = re.compile(r"^\.[A-Za-z0-9.]+$")
RUNTIME_ROOTS = ("scratchpad/", "progress/")
HARNESS = ".harness/"
# A tasks/tests unit that says `create` in any inflection is exempt as a whole (the Builder is
# being told to make the thing); `recreate` and `created_x` are not the word.
CREATE_RE = re.compile(r"(?i)(?<![A-Za-z0-9_])creat(e|es|ed|ing)(?![A-Za-z0-9_])")


class InputError(Exception):
    pass


def iter_unfenced(lines, numbered=False):
    """Yield the lines outside fenced code blocks (delimiters excluded).

    With numbered=True yield (1-based line number, line) pairs instead; the fence state
    machine is the same one either way, so the parity test pins the numbered form too.
    """
    fence = False
    f_char = ""
    f_len = 0
    for n, line in enumerate(lines, 1):
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
        yield (n, line) if numbered else line


def _read(path):
    """Return the file's lines: strict UTF-8, ONE leading BOM stripped, each line's trailing
    \\r then \\n stripped.  The BOM (U+FEFF) is stripped before any parsing so a line-1
    heading, R-id line or `---` stays what it is (review round 1, A1)."""
    if not os.path.isfile(path):
        raise InputError("cannot read %s: %s" % (
            path, "not a regular file" if os.path.exists(path) else "no such file"))
    try:
        with open(path, "rb") as fh:
            data = fh.read()
        text = data.decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise InputError("cannot read %s: %s" % (path, exc))
    if text.startswith(BOM):
        text = text[1:]
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return [ln[:-1] if ln.endswith("\r") else ln for ln in lines]


def cells(row):
    parts = CELL_SPLIT_RE.split(row)
    parts = parts[1:]  # the leading pipe
    if not parts[-1].strip():
        parts = parts[:-1]  # the trailing pipe
    return [c.strip() for c in parts]


def is_separator(row):
    cs = cells(row)
    return all(c == "" or SEP_CELL_RE.match(c) for c in cs) \
        and any(SEP_CELL_RE.match(c) for c in cs)


def parse_sections(lines):
    """Return [{name, line, body: [(n, text)], tables: [[(n, text, kind)]]}] in file order.

    kind is 'header', 'separator' or 'data'.  Only the four checked headings open a section.
    """
    sections = []
    cur = None
    for n, text in iter_unfenced(lines, numbered=True):
        if CLOSE_RE.match(text):
            cur = None
            m = CHECKED_RE.match(text)
            if m:
                cur = {"name": m.group(1), "line": n, "body": [], "tables": []}
                sections.append(cur)
            continue
        if cur is not None:
            cur["body"].append((n, text))
    for sec in sections:
        run = []
        for n, text in sec["body"] + [(None, "")]:
            if text.startswith("|"):
                run.append((n, text))
                continue
            if run:
                kinds = ["data"] * len(run)
                for i, (_n, t) in enumerate(run):
                    if is_separator(t):
                        kinds[i] = "separator"
                        if i > 0:
                            kinds[i - 1] = "header"
                sec["tables"].append([(r[0], r[1], k) for r, k in zip(run, kinds)])
                run = []
    return sections


def strip_wrappers(text):
    for ch in WRAPPERS:
        text = text.replace(ch, "")
    return text


def list_items(numbered):
    """Group unfenced (n, text) lines into list items: [(first_line, [(n, text)])].

    A line matching `^[ \\t]*- ` opens an item; a following line matching `^[ \\t]{2,}\\S`
    (and physically next — a fence or a blank line between closes it) continues it."""
    items = []
    cur = None
    prev = None
    for n, text in numbered:
        if ITEM_RE.match(text):
            cur = (n, [(n, text)])
            items.append(cur)
        elif cur is not None and prev is not None and n == prev + 1 and CONT_RE.match(text):
            cur[1].append((n, text))
        else:
            cur = None
        prev = n
    return items


def table_rows(numbered):
    """Every table data row of the unfenced (n, text) lines: plan-cite's run grammar
    (a run of `^|` lines; the separator, and the row before it, are not data)."""
    out = []
    run = []
    for n, text in list(numbered) + [(None, "")]:
        if text.startswith("|"):
            run.append((n, text))
            continue
        if run:
            kinds = ["data"] * len(run)
            for i, (_n, t) in enumerate(run):
                if is_separator(t):
                    kinds[i] = "separator"
                    if i > 0:
                        kinds[i - 1] = "header"
            out.extend((r[0], r[1]) for r, k in zip(run, kinds) if k == "data")
            run = []
    return out


def spans(text):
    """The whitespace-free single-backtick spans of one line."""
    return [m.group(1) for m in SPAN_RE.finditer(text) if not re.search(r"\s", m.group(1))]


def classify(span):
    """Return (display, path, name): display = the span minus a `::` tail; path = the path
    candidate or None; name = the symbol-form name or None."""
    display = TESTREF_RE.sub("", span)
    p = display
    p = LINEREF_RE.sub("", p)
    name = None
    m = SYMFORM_RE.search(p)
    if m:
        name = m.group(1)
        p = p[:m.start()]
    if p.startswith("./"):
        p = p[2:]
    last = p.rstrip("/").rsplit("/", 1)[-1]
    if "/" not in p and not EXT_RE.search(last):
        return display, None, name
    return display, p, name


def shape_ignored(path):
    """The ignore rules that need no tree: placeholders, globs, variables, URLs, absolute
    paths, flags, bare extensions and the run-time roots roles write under."""
    return any(ch in path for ch in IGNORE_CHARS) or "…" in path or "://" in path \
        or path.startswith(("/", "-")) or BARE_EXT_RE.match(path) is not None \
        or path.startswith(RUNTIME_ROOTS)


def ignored(path, root, created):
    """True when a candidate is not a reference: shape_ignored(), or a `/` path whose first
    segment is not a known root — an existing directory at the root or under `.harness/`, or
    the first segment of a created path (computed after the created set)."""
    if shape_ignored(path):
        return True
    if "/" not in path:
        return False
    rest = path
    if path.startswith(HARNESS):
        rest = path[len(HARNESS):]
        if not rest.strip("/"):
            return True  # `.harness/` itself names the install directory, never a file
    first = rest.split("/", 1)[0]
    known = os.path.isdir(os.path.join(root, first)) \
        or os.path.isdir(os.path.join(root, HARNESS, first)) \
        or any(c.startswith(first + "/") for c in created)
    return not known


def plan_verb(change_cell):
    m = VERB_RE.match(strip_wrappers(change_cell).strip())
    return m.group(0).lower() if m else ""


def created_set(rows):
    """First-cell candidates of every `## Files to change` data row whose verb is create."""
    created = []
    for _n, text in rows:
        cs = cells(text)
        if plan_verb(cs[1] if len(cs) > 1 else "") != "create":
            continue
        for sp in spans(cs[0]):
            _d, p, _name = classify(sp)
            if p is not None and not shape_ignored(p) and p not in created:
                created.append(p)
    return created


def resolve(path, root, feature_dir, created):
    """Return the filesystem path the reference resolves to, "created" for a created one,
    or None when it does not resolve."""
    for c in created:
        if path == c or (c.endswith("/") and (path.startswith(c) or path + "/" == c)):
            return "created"
    is_dir = path.endswith("/")
    q = path.rstrip("/")

    def hit(p):
        return isinstance(p, str) and (os.path.isdir(p) if is_dir else os.path.exists(p))

    cand = os.path.join(root, q)
    if hit(cand):
        return cand
    # the two layouts: source (`tools/x`) and installed target (`.harness/tools/x`)
    cand = os.path.join(root, q[len(HARNESS):]) if q.startswith(HARNESS) \
        else os.path.join(root, HARNESS, q)
    if hit(cand):
        return cand
    if "/" not in q:
        cand = os.path.join(feature_dir, q)
        if hit(cand):
            return cand
    return None


def symbol_present(path, name):
    """True when `name` occurs in the file as a whole word.  A file that is not valid UTF-8
    is not searched (True: no finding) — a binary target must not block a spec."""
    try:
        with open(path, "rb") as fh:
            text = fh.read().decode("utf-8")
    except UnicodeDecodeError:
        return True
    return re.search(r"(?<![A-Za-z0-9_])" + name + r"(?![A-Za-z0-9_])", text) is not None


def find_root(plan):
    ceilings = {os.path.abspath(c) for c in
                os.environ.get("GIT_CEILING_DIRECTORIES", "").split(os.pathsep) if c}
    d = os.path.dirname(os.path.abspath(plan))
    while True:
        if os.path.exists(os.path.join(d, ".git")):
            return d
        parent = os.path.dirname(d)
        if parent == d or parent in ceilings:
            raise InputError("no ancestor of %s holds .git; pass --root" % plan)
        d = parent


def locate(positional):
    """(plan, tasks-or-None, tests-or-None) for a feature directory or a *.plan.md path."""
    if os.path.isdir(positional):
        plans = sorted(f for f in os.listdir(positional) if f.endswith(".plan.md"))
        if len(plans) != 1:
            raise InputError("expected exactly one *.plan.md in %s, found %d"
                             % (positional, len(plans)))
        plan = os.path.join(positional, plans[0])
    elif positional.endswith(".plan.md"):
        plan = positional
    else:
        raise InputError("expected a feature directory or a *.plan.md: %s" % positional)
    stem = plan[:-len(".plan.md")]
    sibs = []
    for suffix in (".tasks.md", ".tests.md"):
        p = stem + suffix
        sibs.append(p if os.path.lexists(p) else None)
    return plan, sibs[0], sibs[1]


def check_feature(plan, tasks, tests, root):
    """Return (findings, n_resolved, n_created); findings are (file_rank, line, text)."""
    feature_dir = os.path.dirname(plan) or "."
    plan_lines = _read(plan)
    tasks_lines = _read(tasks) if tasks else None
    tests_lines = _read(tests) if tests else None
    rows = []
    for sec in parse_sections(plan_lines):
        for table in sec["tables"]:
            rows.extend((n, t) for n, t, k in table if k == "data")
    created = created_set(rows)
    findings = []
    resolved = [0]

    def emit(rank, fname, n, text):
        key = (rank, n, text)
        if key not in findings:
            findings.append(key)

    def ref(path):
        if resolve(path, root, feature_dir, created) is not None:
            resolved[0] += 1
            return True
        return False

    def target(p):
        """The existing regular file a symbol is searched in, else None (unresolved, created,
        a directory)."""
        t = resolve(p, root, feature_dir, created)
        return t if t not in (None, "created") and os.path.isfile(t) else None

    def symbol_form(rank, fname, n, display, p, name):
        t = target(p)
        if t is not None and not symbol_present(t, name):
            emit(rank, fname, n, "unresolved-symbol %s:%d %s" % (fname, n, display))

    for n, text in rows:
        cs = cells(text)
        verb = plan_verb(cs[1] if len(cs) > 1 else "")
        if verb == "create":
            continue
        firsts = []
        for sp in spans(cs[0]):
            display, p, _name = classify(sp)
            if p is not None and not ignored(p, root, created):
                firsts.append(p)
                if not ref(p):
                    emit(0, plan, n, "unresolved-path %s:%d %s" % (plan, n, display))
        if verb == "add":
            continue  # you add TO a file that exists: path checked, symbols not
        t = target(firsts[0]) if len(firsts) == 1 else None
        for cell in cs:
            for sp in spans(cell):
                m = CALL_RE.match(sp)
                if m and t is not None and not symbol_present(t, m.group(1)):
                    emit(0, plan, n, "unresolved-symbol %s:%d %s:%s" % (plan, n, firsts[0], m.group(1)))
                display, p, name = classify(sp)
                if name is not None and p is not None and not ignored(p, root, created):
                    symbol_form(0, plan, n, display, p, name)
    for rank, fname, lines in ((1, tasks, tasks_lines), (2, tests, tests_lines)):
        if lines is None:
            continue
        numbered = list(iter_unfenced(lines, numbered=True))
        units = [ln for _f, ln in list_items(numbered)]
        if rank == 2:
            units += [[r] for r in table_rows(numbered)]
        for unit in units:
            if CREATE_RE.search(" ".join(t for _n, t in unit)):
                continue  # the Builder is told to make it: the whole unit is exempt
            for n, text in unit:
                for sp in spans(text):
                    display, p, name = classify(sp)
                    if p is None or ignored(p, root, created):
                        continue
                    if "/" not in p:
                        ref(p)  # a bare basename found nowhere is prose, never a finding
                    elif not ref(p):
                        emit(rank, fname, n, "unresolved-path %s:%d %s" % (fname, n, display))
                    if name is not None:
                        symbol_form(rank, fname, n, display, p, name)
    findings.sort(key=lambda f: (f[0], f[1]))  # stable: order of discovery within a line
    return findings, resolved[0], len(created)


def parse_args(args, flags):
    """Walk argv as given (no shlex, glob or ~ expansion): ({flag: value}, [positionals]).

    `--flag value` and `--flag=value` are both accepted; any other `-`-led word is an error.
    """
    opts = {}
    pos = []
    i = 0
    while i < len(args):
        a = args[i]
        name, eq, val = a.partition("=")
        if name in flags and eq:
            opts[name] = val
            i += 1
        elif a in flags:
            if i + 1 >= len(args):
                raise InputError("%s needs %s" % (a, flags[a]))
            opts[a] = args[i + 1]
            i += 2
        elif a.startswith("-"):
            raise InputError("unknown flag: %s" % a)
        else:
            pos.append(a)
            i += 1
    return opts, pos


def main_lint(args):
    opts, pos = parse_args(args, {"--root": "a directory"})
    if len(pos) != 1:
        raise InputError("expected exactly one <feature-dir | feature.plan.md>")
    plan, tasks, tests = locate(pos[0])
    root = opts.get("--root")
    if root is None:
        root = find_root(plan)
    findings, n_resolved, n_created = check_feature(plan, tasks, tests, root)
    if findings:
        for _rank, _n, text in findings:
            print(PFX + text)
        print("%sFAIL %d finding(s)" % (PFX, len(findings)))
        return 1
    print("%sok %s: %d reference(s) resolved, %d created, tasks: %s, tests: %s" % (
        PFX, plan, n_resolved, n_created, "read" if tasks else "absent",
        "read" if tests else "absent"))
    return 0


def wants_help(args):
    """True iff `-h`/`--help` is an OPTION token: the argv walk steps over the word after each
    value-taking flag (VALUE_FLAGS, `--flag value` form), so a flag's value is never help
    (review round 1, A4).  `--flag=value` is one token and consumes nothing after it."""
    i = 0
    while i < len(args):
        if args[i] in HELP_FLAGS:
            return True
        i += 2 if args[i] in VALUE_FLAGS else 1
    return False


def main(argv):
    args = argv[1:]
    if wants_help(args):
        print(USAGE)
        return 0
    try:
        return main_lint(args)
    except InputError as exc:
        sys.stderr.write("%serror: %s\n%s\n" % (PFX, exc, USAGE))
        return 2
    except Exception as exc:  # a bug or an environment the tool did not foresee: did not run
        sys.stderr.write("%serror: internal: %s: %s\n" % (PFX, type(exc).__name__, exc))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
