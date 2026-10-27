#!/usr/bin/env python3
"""plan-cite-check — lint a feature .plan.md: every table row cites an R-id or an ADR.

E36-F04 / ADR-0009 decision 4 ("an uncited plan row is a defect").  Usage:

    plan-cite-check.py <feature.plan.md> [--spec <feature.spec.md>] [--specs-dir <dir>]
    plan-cite-check.py --sweep <specs-dir>
    plan-cite-check.py --grandfathered <feature.plan.md> [--base <ref>]

Exit: 0 ok, 1 violation(s) / finding(s) / grandfather reject, 2 usage or input error (stderr
`plan-cite-check: error: ...` plus the usage, nothing on stdout) — exit 2 is "the check did
not run", never a pass.  Stdlib only; a pure function of the paths named on argv, taken
verbatim (no shlex, glob or ~ expansion).

The grammar is E36-F03's, copied byte-exactly from docs/SPEC-FORMAT.md "Plan rows cite an
R-id or an ADR" — this tool lints it, it never redefines it.  Where the grammar is silent the
readings below are the tool's own contract (E36-F04.plan.md, Data model):

  * checked sections: `## Data model`, `## API / interface`, `## Files to change`,
    `## Deferred` (a suffix after the name is ignored); a section runs to the next level-1 or
    level-2 heading; `###` lines stay inside it.  Any other heading is never parsed.
  * fenced code is invisible.  iter_unfenced() is a DELIBERATE second copy of the CommonMark
    rule tests/lib/fence.awk encodes (as tools/tasks-pair-check.py carries one); the suite
    feeds one edge corpus to both and requires identical output (R11_fence_parity).
  * a table is a run of consecutive `^|` lines; its separator row has cells that are each
    empty or `:?-+:?` (at least one not empty); the header row is the row right before a
    separator; every other row is a data row.  Cells split on unescaped `|`.
  * tokens: `R[0-9]+` from a non-alphanumeric left boundary (`PR304` is no citation) and
    `ADR-[0-9]{4}`, after stripping the `*` `` ` `` `"` `'` wrappers.
  * ADR namespaces are init.sh 2c's: every directory named `adr` under the specs tree (token
    = parent basename, `platform` for <specs-dir>/adr; `*.md` directly inside, numbered by
    leading digits).  `<ns>/ADR-NNNN` (or a known `<ns> ADR-NNNN`) resolves there only, an
    unknown `<ns>/` never, a bare id in any namespace.  The specs tree is --specs-dir, else
    the plan's nearest ancestor named `specs`.
  * every file is read as strict UTF-8 and each line's trailing `\r` (CRLF) is stripped first.

Lint violations (one line each, file order, then `FAIL <n> violation(s)`): `uncited-row
<plan>:<line> <heading>`, `unknown-rid <plan>:<line> R<n>` (only with --spec),
`unresolved-adr <plan>:<line> <cite> <reason>`, and for `## Deferred` (a `| Bolt-on |
Deferred by | Trigger |` table whose rows' second cell cites a resolving `Status: deferred` ADR
with a non-empty `Trigger:`, or exactly one `Deferred: none — <why>` line):
`deferred-section-missing`, `deferred-form both|neither|<n>-none-lines`,
`deferred-table-empty`, `deferred-row-no-adr`, `deferred-by-not-deferred`,
`deferred-adr-no-trigger`.

--sweep: `deferred-no-trigger <adr>` for a deferred ADR with no `Trigger:` line, and
`stage-unrecognized <product.md>:<line> <text>` for a `stage:` line in product.md's first
`---` block that is not `^stage: (discovery|pilot|production)$`.

--grandfathered: grandfather() below is a DELIBERATE second copy of tasks-pair-check's
merge-time rule, keyed on THIS tool's paths (see its docstring).
"""
import os
import re
import subprocess
import sys

PFX = "plan-cite-check: "
USAGE = ("usage: plan-cite-check.py <feature.plan.md> [--spec <feature.spec.md>] [--specs-dir <dir>]\n"
         "       plan-cite-check.py --sweep <specs-dir>\n"
         "       plan-cite-check.py --grandfathered <feature.plan.md> [--base <ref>]")
TOOL_PATHS = ("tools/plan-cite-check.py", ".harness/tools/plan-cite-check.py")
BASE_FALLBACKS = ("origin/main", "main", "origin/master", "master", "origin/trunk", "trunk")

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
# The ADR-citation extractor, as init.sh 2c spells it: an optional `<qualifier><space-or-/>`
# before the id.  A `|` is appended to every id first so a qualifier can never eat the
# PREVIOUS citation (`ADR-0002 ADR-0001` is two citations, not one qualified by `ADR-0002`).
ADR_CITE_RE = re.compile(r"(?:([A-Za-z0-9_-]+)([ /]))?ADR-([0-9]{4})")
# `## Deferred` (grammar item 4 / item 2, bytes from docs/SPEC-FORMAT.md).
BOLT_ON_HEADER = ["Bolt-on", "Deferred by", "Trigger"]
NONE_LINE_RE = re.compile(r"^Deferred: none — \S")
STATUS_DEFERRED_RE = re.compile(r"^- \*\*Status:\*\* deferred")
TRIGGER_RE = re.compile(r"^- \*\*Trigger:\*\* \S")
STAGE_RE = re.compile(r"^stage: (discovery|pilot|production)$")
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
    if not os.path.isfile(path):
        raise InputError("cannot read %s: %s" % (
            path, "not a regular file" if os.path.exists(path) else "no such file"))
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


def specs_dir_for(plan):
    """The nearest ancestor of the plan whose basename is `specs`.

    Walked on the path as given (made absolute, symlinks NOT resolved) so the ADR paths the
    tool prints read under the same prefix the caller passed.
    """
    d = os.path.dirname(os.path.abspath(plan))
    while True:
        if os.path.basename(d) == "specs":
            return d
        parent = os.path.dirname(d)
        if parent == d:
            raise InputError("no ancestor of %s is named specs; pass --specs-dir" % plan)
        d = parent


def discover_namespaces(specs_dir):
    """{token: {number: [adr paths]}} for every directory named `adr` under specs_dir.

    The token is the adr/ dir's parent basename, `platform` for <specs-dir>/adr; only regular
    `*.md` files directly inside count, numbered by the leading digits of the filename.
    """
    if not os.path.isdir(specs_dir):
        raise InputError("specs dir is not a directory: %s" % specs_dir)

    def onerror(exc):
        raise InputError("cannot read specs dir %s: %s" % (specs_dir, exc))

    root_adr = os.path.realpath(os.path.join(specs_dir, "adr"))
    index = {}
    for d, subdirs, files in os.walk(specs_dir, onerror=onerror):
        subdirs.sort()
        if os.path.basename(d) != "adr":
            continue
        token = "platform" if os.path.realpath(d) == root_adr else \
            os.path.basename(os.path.dirname(d))
        ns = index.setdefault(token.lower(), {})
        for f in sorted(files):
            p = os.path.join(d, f)
            m = re.match(r"[0-9]+", f)
            if not f.endswith(".md") or not m or not os.path.isfile(p):
                continue
            ns.setdefault(m.group(0), []).append(p)
    return index


def adr_citations(row, index):
    """[(display, ns-or-None, number)] for one row; ns None = bare (any namespace)."""
    text = ADR_TOKEN_RE.sub(lambda m: m.group(0) + "|", strip_wrappers(row))
    out = []
    for m in ADR_CITE_RE.finditer(text):
        qual, sep, num = m.group(1), m.group(2), m.group(3)
        if qual and (sep == "/" or qual.lower() in index):
            c = ("%s/ADR-%s" % (qual, num), qual, num)
        else:
            c = ("ADR-%s" % num, None, num)
        if c not in out:
            out.append(c)
    return out


def resolve_adr(ns, num, index):
    """Return (paths, reason): paths empty = unresolved, with the reason word(s)."""
    if ns is None:
        order = sorted(index, key=lambda tok: (tok != "platform", tok))  # platform first
        paths = [p for tok in order for p in index[tok].get(num, [])]
        return paths, "not-in-any-namespace"
    if ns.lower() not in index:
        return [], "unknown-namespace %s" % ns
    return list(index[ns.lower()].get(num, [])), "not-in-namespace %s" % ns


def adr_state(path):
    """'ok' (deferred with a trigger), 'no-trigger' (deferred, no Trigger:) or 'not-deferred'."""
    lines = _read(path)
    if not any(STATUS_DEFERRED_RE.match(ln) for ln in lines):
        return "not-deferred"
    return "ok" if any(TRIGGER_RE.match(ln) for ln in lines) else "no-trigger"


def check_deferred(plan, sections, index):
    """Pure but for reading cited ADR files: [(line, finding)] for grammar item 4."""
    secs = [s for s in sections if s["name"] == "Deferred"]
    if not secs:
        return [(float("inf"), "deferred-section-missing %s" % plan)], None
    out = []
    bolt_tables = []
    none_lines = 0
    for sec in secs:
        none_lines += sum(1 for _n, t in sec["body"] if NONE_LINE_RE.match(t))
        for table in sec["tables"]:
            header = [r for r in table if r[2] == "header"]
            if header and cells(header[0][1]) == BOLT_ON_HEADER:
                bolt_tables.append((header[0][0], [r for r in table if r[2] == "data"]))
    form = "table" if bolt_tables and not none_lines else \
        "none" if none_lines == 1 and not bolt_tables else None
    head = secs[0]["line"]
    if bolt_tables and none_lines:
        out.append((head, "deferred-form %s both" % plan))
    elif not bolt_tables and not none_lines:
        out.append((head, "deferred-form %s neither" % plan))
    elif none_lines > 1:
        out.append((head, "deferred-form %s %d-none-lines" % (plan, none_lines)))
    for hline, rows in bolt_tables:
        if not rows:
            out.append((hline, "deferred-table-empty %s:%d" % (plan, hline)))
        for n, text, _k in rows:
            cs = cells(text)
            by = cs[1] if len(cs) > 1 else ""
            if not ADR_TOKEN_RE.search(strip_wrappers(by)):
                out.append((n, "deferred-row-no-adr %s:%d" % (plan, n)))
                continue
            for display, ns, num in adr_citations(by, index):
                paths, _reason = resolve_adr(ns, num, index)
                if not paths:
                    continue  # the row rule already reported unresolved-adr
                states = [(adr_state(p), p) for p in paths]
                if any(st == "ok" for st, _p in states):
                    continue
                trig = [p for st, p in states if st == "no-trigger"]
                if trig:
                    out.append((n, "deferred-adr-no-trigger %s:%d %s %s" % (plan, n, display, trig[0])))
                else:
                    out.append((n, "deferred-by-not-deferred %s:%d %s %s" % (plan, n, display, paths[0])))
    return out, form


def data_rows(sections):
    for sec in sections:
        for table in sec["tables"]:
            for n, text, kind in table:
                if kind == "data":
                    yield sec, n, text


def check_plan(plan, sections, spec_rids=None, index=None):
    """Pure: return [(line, finding)] in file order (finding without the prefix).

    spec_rids None = no --spec: R-id existence is not checked.
    """
    index = index or {}
    out = []
    for sec, n, text in data_rows(sections):
        rids, has_adr = cites(text)
        if not rids and not has_adr:
            out.append((n, "uncited-row %s:%d %s" % (plan, n, sec["name"])))
        if spec_rids is not None:
            for rid in rids:
                if rid not in spec_rids:
                    out.append((n, "unknown-rid %s:%d %s" % (plan, n, rid)))
        for display, ns, num in adr_citations(text, index):
            paths, reason = resolve_adr(ns, num, index)
            if not paths:
                out.append((n, "unresolved-adr %s:%d %s %s" % (plan, n, display, reason)))
    deferred, form = check_deferred(plan, sections, index)
    out.extend(deferred)
    out.sort(key=lambda v: v[0])
    return out, form


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
    opts, pos = parse_args(args, {"--spec": "a path", "--specs-dir": "a path"})
    if len(pos) != 1:
        raise InputError("expected exactly one <feature.plan.md>")
    plan = pos[0]
    spec = opts.get("--spec")
    sections = parse_sections(_read(plan))
    spec_rids = None if spec is None else read_rids(spec)
    specs_dir = opts.get("--specs-dir")
    index = discover_namespaces(specs_dir if specs_dir is not None else specs_dir_for(plan))
    violations, form = check_plan(plan, sections, spec_rids, index)
    if violations:
        for _n, v in violations:
            print(PFX + v)
        print("%sFAIL %d violation(s)" % (PFX, len(violations)))
        return 1
    rows = sum(1 for _ in data_rows(sections))
    print("%sok %s: %d row(s) cited, deferred: %s, spec: %s" % (
        PFX, plan, rows, form, "not checked" if spec_rids is None else "%d R-ids" % len(spec_rids)))
    return 0


def sweep(specs_dir):
    """[(finding)], stage value-or-'absent', ADR count — the two sweeps F03 handed over."""
    index = discover_namespaces(specs_dir)
    adrs = sorted(p for tok in index for paths in index[tok].values() for p in paths)
    out = []
    for p in adrs:
        lines = _read(p)
        if any(STATUS_DEFERRED_RE.match(ln) for ln in lines) and \
                not any(TRIGGER_RE.match(ln) for ln in lines):
            out.append("deferred-no-trigger %s" % p)
    stage = "absent"
    product = os.path.join(specs_dir, "product.md")
    if os.path.lexists(product):
        lines = _read(product)
        if lines and lines[0] == "---":
            for n, ln in enumerate(lines[1:], 2):
                if ln == "---":
                    break
                if ln.startswith("stage:"):
                    m = STAGE_RE.match(ln)
                    if m:
                        stage = m.group(1)
                    else:
                        out.append("stage-unrecognized %s:%d %s" % (product, n, ln))
    return out, stage, len(adrs)


def main_sweep(args):
    _opts, pos = parse_args(args, {})
    if len(pos) != 1:
        raise InputError("--sweep expects exactly one <specs-dir>")
    findings, stage, n_adrs = sweep(pos[0])
    if findings:
        for f in findings:
            print(PFX + f)
        print("%sFAIL %d finding(s)" % (PFX, len(findings)))
        return 1
    print("%sok sweep %d ADR(s), stage: %s" % (PFX, n_adrs, stage))
    return 0


def _git(repo, *args):
    """Run git in repo; return (rc, stdout, stderr).  Pathspecs are literal (a plan named
    `it*s.plan.md` is that file, never a glob)."""
    try:
        r = subprocess.run(["git", "--literal-pathspecs", "-C", repo] + list(args),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as exc:
        raise InputError("cannot run git: %s" % exc)
    return r.returncode, os.fsdecode(r.stdout), os.fsdecode(r.stderr)


def _git_ok(repo, *args):
    """Run git; any non-zero exit is an InputError carrying git's stderr — never a verdict."""
    rc, out, err = _git(repo, *args)
    if rc != 0:
        raise InputError("git %s failed (exit %d): %s" % (args[0], rc, err.strip()))
    return out


def _resolves(repo, ref):
    return _git(repo, "rev-parse", "--verify", "--quiet", ref + "^{commit}")[0] == 0


def default_branch(repo):
    rc, out, _err = _git(repo, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
    head = out.strip() if rc == 0 else ""
    for ref in ((head,) if head else ()) + BASE_FALLBACKS:
        if _resolves(repo, ref):
            return ref
    return None


def grandfather(plan_path, base=None):
    """Return (flag, reason): flag True = grandfathered (advisory), False = reject class.

    A DELIBERATE second copy of tools/tasks-pair-check.py's grandfather(), keyed on THIS
    tool's paths: the two tools install and run independently, and keying on the sibling's
    merge would ambush every plan written between the two merges.
    """
    path = os.path.realpath(plan_path)
    if not os.path.isfile(path):
        raise InputError("cannot read %s: not a regular file" % plan_path)
    rc, out, _err = _git(os.path.dirname(path), "rev-parse", "--show-toplevel")
    if rc != 0 or not out.strip():
        raise InputError("%s is not inside a git work tree" % plan_path)
    top = out.strip()  # git prints the toplevel symlink-resolved, like `path` above
    if base is None:
        base = default_branch(top)
        if base is None:
            raise InputError("no default branch resolves (origin/HEAD, %s); pass --base"
                             % " ".join(BASE_FALLBACKS))
    elif not _resolves(top, base):
        raise InputError("--base does not resolve: %s" % base)
    out = _git_ok(top, "log", "--first-parent", "--reverse", "--format=%ct", base, "--",
                  *TOOL_PATHS)
    stamps = out.split()
    if not stamps:
        return True, "tool not on default branch %s yet" % base
    merged = int(stamps[0])
    rel = os.path.relpath(path, top)
    out = _git_ok(top, "log", "--diff-filter=A", "--format=%at", "HEAD", "--", rel)
    authored = [int(x) for x in out.split()]
    if not authored:
        return False, "%s has no commit on HEAD; tool merged into %s at %d" % (rel, base, merged)
    first = min(authored)
    if first < merged:
        return True, "%s authored %d, before tool merged into %s at %d" % (rel, first, base, merged)
    return False, "%s authored %d, not before tool merged into %s at %d" % (rel, first, base, merged)


def main_grandfathered(args):
    opts, pos = parse_args(args, {"--base": "a ref"})
    if len(pos) != 1:
        raise InputError("--grandfathered expects exactly one <feature.plan.md>")
    flag, reason = grandfather(pos[0], opts.get("--base"))
    print("%sgrandfather %s: %s" % (PFX, "flag" if flag else "reject", reason))
    return 0 if flag else 1


def main(argv):
    args = argv[1:]
    if any(a in ("-h", "--help") for a in args):
        print(USAGE)
        return 0
    try:
        if "--grandfathered" in args and "--sweep" in args:
            raise InputError("--grandfathered and --sweep are separate modes")
        if "--sweep" in args:
            return main_sweep([a for a in args if a != "--sweep"])
        if "--grandfathered" in args:
            return main_grandfathered([a for a in args if a != "--grandfathered"])
        return main_lint(args)
    except InputError as exc:
        sys.stderr.write("%serror: %s\n%s\n" % (PFX, exc, USAGE))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
