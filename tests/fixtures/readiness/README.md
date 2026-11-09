# Readiness-check fixtures (E37-F01)

`repo/` is a miniature repository that `tests/test_readiness_check.sh` copies into a fresh
temp directory per row (`fresh <row>`) and lints with `--root` pointing at the copy. Every
path below is fixture-internal and written with the `<repo>/` placeholder prefix (the house
convention: a path that is not in this repository carries a placeholder, so the readiness
lint ignores it). Fixture files are LF; the suite derives CRLF, BOM and every other variant.

## Tree

- `<repo>/tools/real.py` — defines `helper` and `other` (the symbol targets).
- `<repo>/tests/test_real.sh`, `<repo>/docs/NOTES.md`, `<repo>/README.md` — existing files.
- `<repo>/tests/lib/.keep`, `<repo>/scratchpad/.keep`, `<repo>/progress/.keep` — keep the
  directories, so `scratchpad/` and `progress/` are known roots that only the run-time-path
  rule ignores.
- `<repo>/specs/epics/E01-x/F01-good/E01-F01.{spec,plan,tasks,tests}.md` — the POSITIVE
  feature: every scanned reference resolves (exit 0). Its plan carries a `modify` row naming
  `helper()`, `create` rows for `<repo>/tools/new.py`, `<repo>/tests/fixtures/new/` and
  `<repo>/tests/test_new.sh`, an `add` row whose cell says "add a note, then create the
  index", a two-path row naming a missing `nothere()` (skipped), a `## Data model` row and a
  `## DO NOT TOUCH` pipe row naming `<repo>/tools/nowhere.md` (unscanned sections) and a
  fenced row naming `<repo>/tools/decoy.py`. Its tasks name every ignored token shape.
- `<repo>/specs/epics/E01-x/F02-bad/E01-F02.{spec,plan,tasks,tests}.md` — the NEGATIVE
  feature, one planted defect per line (exit 1, nine findings).

## Planted defects (negative feature)

| File:line | Token | Finding |
|---|---|---|
| E01-F02.plan.md:7 | `<repo>/tools/missing.py` | unresolved-path (modify row) |
| E01-F02.plan.md:8 | `REDME.md` | unresolved-path (bare first cell) |
| E01-F02.plan.md:9 | `gone()` on `<repo>/docs/NOTES.md` | unresolved-symbol |
| E01-F02.plan.md:10 | `<repo>/tools/real.py:nothere` | unresolved-symbol (Change cell) |
| E01-F02.plan.md:11 | `<repo>/tests/test_gone.sh` | unresolved-path (`add` row, "then create" later) |
| E01-F02.tasks.md:4 | `<repo>/tests/test_missing.sh` | unresolved-path (continuation line) |
| E01-F02.tasks.md:5 | `<repo>/tools/real.py:absent` | unresolved-symbol |
| E01-F02.tests.md:5 | `<repo>/tests/test_missing2.sh::R1` | unresolved-path (`::R1` stripped) |
| E01-F02.tests.md:7 | `<repo>/docs/gone.md` | unresolved-path (list item) |

The suite asserts each `File:line` above against `grep -n` of the planted token, so an edit
that moves a defect fails setup instead of silently moving a finding.
