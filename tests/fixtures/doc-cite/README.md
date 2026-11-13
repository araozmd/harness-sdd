# doc-cite fixture

`<repo>` is `tests/fixtures/doc-cite/repo/`. The suite runs `tools/doc-cite-check.py --root`
on it. Every planted defect, with its line in `<repo>/agents/role.md`:

| Line | Citation | Expected |
|---|---|---|
| 3 | `docs/GOOD.md#staying-current--the-update-check-e38-f01` | ok (em dash gives `--`) |
| 4 | `docs/GOOD.md § Per-role model routing` | ok (title is a prefix of a longer heading) |
| 5 | `.harness/docs/GOOD.md` → "Staying current" | ok (prefix stripped, title prefix) |
| 6 | `docs/security.md#project-trust` | ignored (lowercase name is an external doc) |
| 9 | `docs/NOPE.md` | ignored (inside a fenced block) |
| 12 | `docs/MISSING.md` | finding: no such file |
| 13 | `docs/GOOD.md#no-such-slug` | finding: no heading matches the slug |
| 14 | `docs/GOOD.md -> "Retired section"` | finding: no heading matches the title |
| 15 | `docs/agents/GOOD.md` | ok |

Exactly three findings, in that order.
