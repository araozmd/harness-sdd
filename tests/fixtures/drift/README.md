# Fixtures for tests/test_drift_report.sh (E37-F03)

`repo/` is a clean mini repository: every reference its living documents name resolves, so a
run of `tools/drift-report.py --root <copy>` yields `No drift detected` (4 documents).
The suite copies it per row to `$T/<row>/repo` (`<repo>/` below), so each row has one cause.
Fixture-internal paths below are written `<repo>/...`.

`<repo>/tools/` holds `real.py` and `unnamed.py` as its only regular non-hidden files
(`.hidden.py` and `sub/inner.py` are not inventory entries); `<repo>/agents/` holds `scout.md`
(named) and `unnamed.md` (unnamed). `<repo>/specs/product.md` carries one `Ignored shapes:`
line naming the 13 tokens the resolver ignores; `<repo>/specs/architecture.md` names the
directory `tools/` (names no file inside it).

`defects/0002-bad.md` is the negative ADR the rows copy to `<repo>/specs/adr/0002-bad.md`.
Each planted defect, by file and line (the suite asserts each line with `grep -n`):

| Defect | Kind | Token |
|---|---|---|
| 0002-bad.md:2 | fenced decoy, invisible (the fence opens on line 1, the first byte) | `tools/fenced-decoy.py` |
| 0002-bad.md:4 | doc-names-missing, in a heading | `docs/gone.md` |
| 0002-bad.md:6 | doc-names-missing, in a paragraph | `tools/missing.py` |
| 0002-bad.md:8 | doc-names-missing-symbol, in a blockquote | `tools/real.py:nothere` |
| 0002-bad.md:10 | doc-names-missing (path only; the symbol is not also reported), in a table row | `tools/nope.py:x` |
