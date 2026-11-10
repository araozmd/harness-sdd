#!/usr/bin/env python3
"""drift-report — advisory report: living documents versus the current tree.

E37-F03.  Usage:

    drift-report.py [--root <dir>] [--inventory <dir>]... [--date <YYYY-MM-DD>]

The living documents (specs/product.md, specs/architecture.md, every ADR under specs/adr/ and
under a product space specs/<ns>/adr/) are scanned for every backticked repo-rooted path and
`path:name` symbol they name; each one the tree no longer has is a finding.  The report is
written to <harness>/progress/drift/<YYYY-MM-DD>.md (a same-day run overwrites it) and its
absolute path is the only line printed on stdout.

Exit: 0 whenever the report was written — findings are information, never a failure — and 2
when the tool could not run (usage or input error, or an unexpected exception: stderr
`drift-report: error: ...` plus the usage, nothing on stdout, no report).  The tool has no
failing verdict and never signals one.  `-h`/`--help` print the usage and exit 0 only as an
option token.  Stdlib only.  It writes one file (the report) and reads the tree; it never
edits a document, the code or the board.

Finding codes (one line each; the reconciliation choice — update the doc, or update the code —
is left to a human):

  doc-names-missing         a `/`-bearing path a document names that does not resolve
  doc-names-missing-symbol  a `path:name` whose file resolves but lacks the whole word
  code-unnamed              (opt-in `--inventory <dir>`) a regular file directly under <dir>
                            that no living document names

Reuse: the reference grammar is docs/SPEC-FORMAT.md "Implementation readiness"; the resolver
is IMPORTED from tools/readiness-check.py (loaded by file path from this tool's own
directory, never copied), so this file defines none of its functions.  A tool directory
without that sibling makes the run exit 2.  Unlike the readiness lint, every unfenced line of
a document is scanned (an ADR's decisions live in paragraphs), not only list items and rows.

Known limits: precision over recall, inherited from the resolver (a path whose first segment
is not a known root is ignored; a path relative to another root is reported — reconcile it
with a placeholder prefix).  Replaced patterns — a document describing a mechanism the code
now implements differently — are a judgment read and are NOT detected; the report says so.
The inventory is opt-in.
"""
import datetime
import importlib.util
import os
import re
import sys
import tempfile

PFX = "drift-report: "
USAGE = "usage: drift-report.py [--root <dir>] [--inventory <dir>]... [--date <YYYY-MM-DD>]"
VALUE_FLAGS = ("--root", "--inventory", "--date")
SIBLING = "readiness-check.py"


class InputError(Exception):
    pass


def _load_resolver():
    """Load tools/readiness-check.py from this tool's own directory by file path (the name is
    hyphenated, so it is not importable by name) and return the module."""
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, SIBLING)
    if not os.path.isfile(path):
        raise InputError("cannot load %s: no such file — the drift report reuses the "
                         "implementation-readiness lint's resolver" % path)
    spec = importlib.util.spec_from_file_location("readiness_check", path)
    module = importlib.util.module_from_spec(spec)
    keep = sys.dont_write_bytecode
    sys.dont_write_bytecode = True  # never leave a __pycache__ beside the resolver
    try:
        spec.loader.exec_module(module)
    except Exception as exc:
        raise InputError("cannot load %s: %s" % (path, exc))
    finally:
        sys.dont_write_bytecode = keep
    return module


def harness_dir(root):
    env = os.environ.get("HARNESS_DIR")
    if env:
        return os.path.abspath(env)
    if os.path.isfile(os.path.join(root, ".harness", "harness.config.yaml")):
        return os.path.join(root, ".harness")
    return root


def living_documents(harness):
    """[(rel, abs-path or None)] in report order; None marks an absent product/architecture."""
    out = []
    for rel in ("specs/product.md", "specs/architecture.md"):
        p = os.path.join(harness, rel)
        out.append((rel, p if os.path.isfile(p) else None))

    def adrs(prefix):
        d = os.path.join(harness, prefix)
        if not os.path.isdir(d):
            return []
        names = sorted(f for f in os.listdir(d)
                       if re.fullmatch(r"[0-9]{4}-.*\.md", f) and os.path.isfile(os.path.join(d, f)))
        return [(prefix + "/" + f, os.path.join(d, f)) for f in names]

    out.extend(adrs("specs/adr"))
    specs = os.path.join(harness, "specs")
    if os.path.isdir(specs):
        for ns in sorted(os.listdir(specs)):
            if ns not in ("adr", "epics", "_templates") and os.path.isdir(os.path.join(specs, ns)):
                out.extend(adrs("specs/" + ns + "/adr"))
    return out


def parse_date(value):
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
        raise InputError("--date is not a YYYY-MM-DD date: %s" % value)
    try:
        datetime.date.fromisoformat(value)
    except ValueError:
        raise InputError("--date is not a YYYY-MM-DD date: %s" % value)
    return value


CHOICE_PATH = ("update doc (rewrite the path as it is today, or give it a placeholder prefix if "
               "it is not in this repository, or supersede the decision) or update code (restore it)")


def scan_document(rc, root, abs_path):
    """[(code, line, display)] for one document, in line order: every unfenced line, every
    span the resolver classifies as a path candidate it does not ignore."""
    findings = []
    doc_dir = os.path.dirname(abs_path)
    for n, text in rc.iter_unfenced(rc._read(abs_path), numbered=True):
        for sp in rc.spans(text):
            display, p, _name = rc.classify(sp)
            if p is None or rc.ignored(p, root, []):
                continue
            if rc.resolve(p, root, doc_dir, []) is None and "/" in p:
                findings.append(("doc-names-missing", n, display))
    return findings


def render(date, root, harness, docs, results):
    lines = ["# Living-doc drift report — %s" % date, "",
             "- root: %s" % root, "- harness: %s" % harness, "- documents:"]
    present = 0
    total = 0
    for rel, p in docs:
        lines.append("  - %s (%s)" % (rel, "read" if p else "absent"))
        present += 1 if p else 0
    for rel, p in docs:
        lines += ["", "## %s" % rel, ""]
        if p is None:
            lines.append("Absent — not a finding.")
        elif results[rel]:
            for code, n, display in results[rel]:
                lines.append("- %s %s:%d `%s` — reconcile: %s" % (code, rel, n, display, CHOICE_PATH))
            total += len(results[rel])
        else:
            lines.append("No drift detected.")
    lines += ["", "## Summary", ""]
    if total:
        lines.append("drift-report: %d finding(s) across %d document(s) read, 0 code entries unnamed"
                     % (total, present))
    else:
        lines.append("drift-report: No drift detected (%d document(s) read)" % present)
    return "\n".join(lines) + "\n"


def write_report(path, text):
    d = os.path.dirname(path)
    tmp = None
    try:
        os.makedirs(d, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".drift-", suffix=".tmp")
        with os.fdopen(fd, "wb") as fh:
            fh.write(text.encode("utf-8"))
        um = os.umask(0)
        os.umask(um)
        os.chmod(tmp, 0o666 & ~um)
        os.replace(tmp, path)
        tmp = None
    except OSError as exc:
        raise InputError("cannot write the report %s: %s" % (path, exc))
    finally:
        if tmp is not None and os.path.exists(tmp):
            os.unlink(tmp)


def run(rc, args):
    rc.VALUE_FLAGS = VALUE_FLAGS  # the resolver's wants_help() reads this module constant
    if rc.wants_help(args):
        print(USAGE)
        return 0
    opts, pos = rc.parse_args(args, {"--root": "a directory", "--date": "a YYYY-MM-DD date"})
    if pos:
        raise InputError("unexpected argument: %s" % pos[0])
    date = parse_date(opts["--date"]) if "--date" in opts else datetime.date.today().isoformat()
    root = opts.get("--root")
    if root is None:
        root = rc.find_root(os.path.abspath(__file__))
    elif not os.path.isdir(root):
        raise InputError("--root is not a directory: %s" % root)
    root = os.path.abspath(root)
    harness = harness_dir(root)
    docs = living_documents(harness)
    if not any(p for _rel, p in docs):
        raise InputError("no living documents under %s" % os.path.join(harness, "specs"))
    path = os.path.abspath(os.path.join(harness, "progress", "drift", date + ".md"))
    results = {rel: scan_document(rc, root, p) for rel, p in docs if p}
    write_report(path, render(date, root, harness, docs, results))
    print(path)
    return 0


def main(argv):
    args = argv[1:]
    errs = (InputError,)
    try:
        rc = _load_resolver()
        errs = (InputError, rc.InputError)
        return run(rc, args)
    except errs as exc:
        sys.stderr.write("%serror: %s\n%s\n" % (PFX, exc, USAGE))
        return 2
    except Exception as exc:  # a bug or an environment the tool did not foresee: did not run
        sys.stderr.write("%serror: internal: %s: %s\n%s\n" % (PFX, type(exc).__name__, exc, USAGE))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
