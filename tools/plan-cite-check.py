#!/usr/bin/env python3
"""plan-cite-check — lint a feature .plan.md: every table row cites an R-id or an ADR.

E36-F04 / ADR-0009 decision 4 ("an uncited plan row is a defect").  Usage:

    plan-cite-check.py <feature.plan.md> [--spec <feature.spec.md>] [--specs-dir <dir>]

Stdlib only; a pure function of the files named on argv.  The grammar is E36-F03's, copied
byte-exactly from docs/SPEC-FORMAT.md "Plan rows cite an R-id or an ADR" — this tool lints it,
it never redefines it:

  * checked sections: `## Data model`, `## API / interface`, `## Files to change`,
    `## Deferred` (a suffix after the name is ignored); a section runs to the next level-1 or
    level-2 heading; `###` lines stay inside it.
  * fenced code is invisible.  iter_unfenced() is a DELIBERATE second copy of the CommonMark
    rule tests/lib/fence.awk encodes (as tools/tasks-pair-check.py carries one); the suite
    feeds one edge corpus to both and requires identical output (R11_fence_parity).
  * a table is a run of consecutive `^|` lines; its separator row has cells that are empty
    or `:?-+:?`; the header row is the row right before a separator; every other row is a
    data row.
  * every line is read as strict UTF-8 and a trailing `\\r` (CRLF) is stripped first.
"""
import os
import re
import sys

PFX = "plan-cite-check: "
USAGE = ("usage: plan-cite-check.py <feature.plan.md> [--spec <feature.spec.md>] [--specs-dir <dir>]")

CHECKED_RE = re.compile(r"^## (Data model|API / interface|Files to change|Deferred)(\s|$)")
CLOSE_RE = re.compile(r"^##? ")
SEP_CELL_RE = re.compile(r"^:?-+:?$")
CELL_SPLIT_RE = re.compile(r"(?<!\\)\|")
# The grammar's tokens.  `R[0-9]+` read from a non-alphanumeric left boundary (the tool's
# reading where the grammar is silent): `PR304` / `CR12` are not citations.
RID_TOKEN_RE = re.compile(r"(?<![A-Za-z0-9])R[0-9]+")
ADR_TOKEN_RE = re.compile(r"ADR-[0-9]{4}")
# A spec R-id line, copied from tools/tasks-pair-check.py's RID_RE: `- **R<n>** ...` or the
# bold-title form `- **R<n> — Title.** ...`, outside fenced code.
RID_RE = re.compile(r"^[ \t]*-[ \t]+\*\*(R[0-9]+)(?:\*\*|[ \t]+(?:—|–|-))")
WRAPPERS = "*`\"'"


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
    """Return the file's lines: strict UTF-8, each line's trailing \\r then \\n stripped."""
    try:
        with open(path, "rb") as fh:
            data = fh.read()
        text = data.decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise InputError("cannot read %s: %s" % (path, exc))
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return [ln[:-1] if ln.endswith("\r") else ln for ln in lines]


def read_rids(path):
    """The spec's declared R-ids, first-appearance order, a repeated id counted once."""
    rids = []
    for line in iter_unfenced(_read(path)):
        m = RID_RE.match(line)
        if m and m.group(1) not in rids:
            rids.append(m.group(1))
    if not rids:
        raise InputError("no R-ids found in %s" % path)
    return rids


def cells(row):
    parts = CELL_SPLIT_RE.split(row)
    parts = parts[1:]  # the leading pipe
    if parts and not parts[-1].strip():
        parts = parts[:-1]  # the trailing pipe
    return [c.strip() for c in parts]


def is_separator(row):
    cs = cells(row)
    return bool(cs) and all(c == "" or SEP_CELL_RE.match(c) for c in cs) \
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
                        if i > 0 and kinds[i - 1] == "data":
                            kinds[i - 1] = "header"
                sec["tables"].append([(r[0], r[1], k) for r, k in zip(run, kinds)])
                run = []
    return sections


def strip_wrappers(text):
    for ch in WRAPPERS:
        text = text.replace(ch, "")
    return text


def cites(row):
    """Return (r_tokens, has_adr_token) for one data row (wrappers stripped first)."""
    text = strip_wrappers(row)
    rids = []
    for tok in RID_TOKEN_RE.findall(text):
        if tok not in rids:
            rids.append(tok)
    return rids, bool(ADR_TOKEN_RE.search(text))


def data_rows(sections):
    for sec in sections:
        for table in sec["tables"]:
            for n, text, kind in table:
                if kind == "data":
                    yield sec, n, text


def check_plan(plan, sections, spec_rids=None):
    """Pure: return [(line, finding)] in file order (finding without the prefix).

    spec_rids None = no --spec: R-id existence is not checked.
    """
    out = []
    for sec, n, text in data_rows(sections):
        rids, has_adr = cites(text)
        if not rids and not has_adr:
            out.append((n, "uncited-row %s:%d %s" % (plan, n, sec["name"])))
        if spec_rids is not None:
            for rid in rids:
                if rid not in spec_rids:
                    out.append((n, "unknown-rid %s:%d %s" % (plan, n, rid)))
    out.sort(key=lambda v: v[0])
    return out


def main(argv):
    args = argv[1:]
    if any(a in ("-h", "--help") for a in args):
        print(USAGE)
        return 0
    try:
        spec = specs_dir = None
        pos = []
        i = 0
        while i < len(args):
            a = args[i]
            if a in ("--spec", "--specs-dir"):
                if i + 1 >= len(args):
                    raise InputError("%s needs a path" % a)
                if a == "--spec":
                    spec = args[i + 1]
                else:
                    specs_dir = args[i + 1]
                i += 2
            else:
                pos.append(a)
                i += 1
        if len(pos) != 1:
            raise InputError("expected exactly one <feature.plan.md>")
        plan = pos[0]
        sections = parse_sections(_read(plan))
        spec_rids = None if spec is None else read_rids(spec)
    except InputError as exc:
        sys.stderr.write("%serror: %s\n%s\n" % (PFX, exc, USAGE))
        return 2
    violations = check_plan(plan, sections, spec_rids)
    if violations:
        for _n, v in violations:
            print(PFX + v)
        print("%sFAIL %d violation(s)" % (PFX, len(violations)))
        return 1
    rows = sum(1 for _ in data_rows(sections))
    print("%sok %s: %d row(s) cited, spec: %s" % (
        PFX, plan, rows, "not checked" if spec_rids is None else "%d R-ids" % len(spec_rids)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
