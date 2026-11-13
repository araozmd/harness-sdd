#!/usr/bin/env python3
"""doc-cite-check — every citation of a harness doc resolves: the file, and its heading.

Usage:

    doc-cite-check.py [--root <dir>] [<file> ...]
    doc-cite-check.py -h | --help

With no files it scans the default citing set under the root: AGENTS.md CLAUDE.md README.md
agents/*.md docs/**/*.md harness-install.sh init.sh tools/* (the ones that exist).  Named
files are taken relative to the root unless absolute.  The root defaults to the current
directory.

A citation is a harness-doc path -- `docs/<UPPER>.md`, `docs/agents/<name>.md` or
`docs/history/<name>.md`, with or without a leading `.harness/` -- optionally followed by
`#<slug>`, or, on the same line within four characters, by one of

    -> "<title>"      ->  *<title>*      -> "<title>"      § <title>

(the first two spelt with the arrow U+2192).  For `§` the title runs to the first of `.`,
`,`, `;`, `)` or a backtick, or the end of the line.  Per citation it prints, sorted by file
then line, one line

    CITE <file>:<line> <citation> -- <reason>        (the dash is U+2014)

when the file does not exist, when the slug matches no heading of that file, or when the
title is not a prefix of any heading, then one summary line

    doc-cite-check: <N> findings, <F> files scanned

Slug rule (GitHub's): lowercase the heading text, drop every character outside
[a-z0-9 _-], turn spaces into hyphens; a repeated heading gets a -1, -2 ... suffix.  Title
rule: lowercase, backticks and asterisks removed, whitespace collapsed; the cited title must
be a PREFIX of some heading's text in the cited file (citations omit heading suffixes).

Exit: 0 no findings, 1 findings, 2 usage error (`doc-cite-check: error: <what>` on stderr:
an unknown flag, a missing flag value, a --root that is not a directory, a named file that
does not exist).  Stdlib only; reads files, writes nothing.

Known limits: a title cited across a line break is not seen; a citation inside a fenced
block of a Markdown file is skipped by design (a fence holds example text); a lowercase
`docs/x.md` is an external doc by convention and never a citation; a relative Markdown link
that does not spell the `docs/` prefix is not a citation; non-Markdown files are scanned
line by line with no fence rule.
"""
import glob
import os
import re
import sys

CITE_RE = re.compile(
    r"(?<![A-Za-z0-9_])((?:\.harness/)?docs/"
    r"(?:[A-Z0-9][A-Z0-9.-]*\.md|agents/[A-Za-z0-9._-]+\.md|history/[A-Za-z0-9._-]+\.md))"
    r"(?:#([A-Za-z0-9._-]+))?"
)
JUNK = "`)]*_ \t"
ARROW_RE = re.compile(r"^[`)\]*_ \t]{0,4}(?:→|->)\s*(?:\"([^\"]+)\"|\*([^*]+)\*)")
SECT_RE = re.compile(r"^[`)\]*_ \t]{0,4}§\s*[\"“*]?([^.,;)`\"”*]+)")
DASH = "—"

USAGE = ("usage: doc-cite-check.py [--root <dir>] [<file> ...]\n"
         "       doc-cite-check.py -h | --help")


class Usage(Exception):
    pass


def iter_unfenced(lines):
    """Yield (1-based line number, line) for every line outside fenced code (CommonMark
    4.5: backtick or tilde runs of 3+, indented at most 3, closed by a run of the same
    character at least as long and with no info string)."""
    fence = False
    f_char, f_len = "", 0
    for n, line in enumerate(lines, 1):
        line = line.rstrip("\n")
        ind = 0
        while ind < 4 and line[ind:ind + 1] == " ":
            ind += 1
        delim = False
        if ind <= 3:
            ch = line[ind:ind + 1]
            if ch and ch in "`~":
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
        yield n, line


def read_lines(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read().split("\n")


def slug(text):
    """GitHub's heading anchor."""
    text = norm_title(text)
    text = "".join(c for c in text if c in "abcdefghijklmnopqrstuvwxyz0123456789 _-")
    return text.replace(" ", "-")


def norm_title(text):
    text = text.lower().replace("`", "").replace("*", "")
    return " ".join(text.split())


_HEADING_CACHE = {}


def headings(path):
    """(slugs, normalised titles) of every ATX heading outside fenced code in `path`."""
    if path in _HEADING_CACHE:
        return _HEADING_CACHE[path]
    slugs, titles, seen = set(), [], {}
    for _, line in iter_unfenced(read_lines(path)):
        m = re.match(r"^ {0,3}#{1,6}[ \t]+(.*?)[ \t]*#*[ \t]*$", line)
        if not m:
            continue
        base = slug(m.group(1))
        k = seen.get(base, 0)
        slugs.add(base if k == 0 else "%s-%d" % (base, k))
        seen[base] = k + 1
        titles.append(norm_title(m.group(1)))
    _HEADING_CACHE[path] = (slugs, titles)
    return slugs, titles


def citations(line):
    """Yield (path, slug-or-None, title-or-None, shown) for each citation on the line."""
    for m in CITE_RE.finditer(line):
        path, sl = m.group(1), m.group(2)
        rest = line[m.end():]
        title = None
        a = ARROW_RE.match(rest)
        if a:
            title = a.group(1) or a.group(2)
        else:
            s = SECT_RE.match(rest)
            if s:
                title = s.group(1)
        shown = path + ("#" + sl if sl else "")
        yield path, sl, title, shown


def check_one(root, path, sl, title):
    rel = path[len(".harness/"):] if path.startswith(".harness/") else path
    target = os.path.join(root, rel)
    if not os.path.isfile(target):
        return "no such file"
    slugs, titles = headings(target)
    if sl is not None and sl.lower() not in slugs:
        return "no heading matches #%s" % sl
    if title is not None:
        t = norm_title(title)
        if t and not any(h.startswith(t) for h in titles):
            return 'no heading matches "%s"' % title.strip()
    return None


def default_files(root):
    out = []
    for name in ("AGENTS.md", "CLAUDE.md", "README.md", "harness-install.sh", "init.sh"):
        if os.path.isfile(os.path.join(root, name)):
            out.append(name)
    for pat in ("agents/*.md", "docs/**/*.md", "tools/*"):
        for p in sorted(glob.glob(os.path.join(root, pat), recursive=True)):
            if os.path.isfile(p):
                out.append(os.path.relpath(p, root))
    seen, uniq = set(), []
    for f in out:
        if f not in seen:
            seen.add(f)
            uniq.append(f)
    return uniq


def check(root, files):
    """Return (findings, files_scanned); findings are (file, line, shown, reason)."""
    findings = []
    for rel in files:
        path = rel if os.path.isabs(rel) else os.path.join(root, rel)
        shown_rel = os.path.relpath(path, root)
        lines = read_lines(path)
        if rel.endswith(".md"):
            numbered = iter_unfenced(lines)
        else:
            numbered = ((n, l.rstrip("\n")) for n, l in enumerate(lines, 1))
        for n, line in numbered:
            for cpath, sl, title, shown in citations(line):
                reason = check_one(root, cpath, sl, title)
                if reason:
                    findings.append((shown_rel, n, shown, reason))
    findings.sort(key=lambda f: (f[0], f[1]))
    return findings, len(files)


def parse(argv):
    root, files, i = ".", [], 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            return None
        if a == "--root":
            if i + 1 >= len(argv):
                raise Usage("--root needs a value")
            root = argv[i + 1]
            i += 2
            continue
        if a.startswith("-") and a != "-":
            raise Usage("unknown flag %s" % a)
        files.append(a)
        i += 1
    return root, files


def main(argv):
    try:
        parsed = parse(argv)
        if parsed is None:
            print(USAGE)
            return 0
        root, files = parsed
        if not os.path.isdir(root):
            raise Usage("--root %s is not a directory" % root)
        root = os.path.abspath(root)
        if files:
            for f in files:
                p = f if os.path.isabs(f) else os.path.join(root, f)
                if not os.path.isfile(p):
                    raise Usage("no such file: %s" % f)
        else:
            files = default_files(root)
        findings, scanned = check(root, files)
    except Usage as e:
        sys.stderr.write("doc-cite-check: error: %s\n%s\n" % (e, USAGE))
        return 2
    for f, n, shown, reason in findings:
        print("CITE %s:%d %s %s %s" % (f, n, shown, DASH, reason))
    print("doc-cite-check: %d findings, %d files scanned" % (len(findings), scanned))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
