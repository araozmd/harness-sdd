# E22-F01 — no spec set, by construction

This directory exists so `E22-F01`'s `spec_path` in `state/tasks.json` resolves to
something a reader can open. It deliberately holds **no** `.spec` / `.plan` /
`.tasks` / `.tests` files.

`E22-F01` is `sdd: false`. It was built through the quick-fix lane, which skips the
Architect and has no spec to gate — so there never were four spec files, and writing
them now would be inventing a requirements record after the fact and back-dating it.
The Reviewer's "every R-id has a passing test" rule has nothing to check here because
no R-ids were ever authored.

**What actually happened**, in the order it happened:

| | |
|---|---|
| Merged as | PR #85, commit `3faa24c`, 2026-07-29 |
| VERSION | 0.47.0 |
| Board entry at the time | **none** — no `E22` epic existed in `state/tasks.json` |
| Backfilled | 2026-08-02, by the `/sdd-next` board audit |

The board gap is the point worth remembering: the work shipped, the installer
changed, `VERSION` moved, and the TaskStore said nothing had happened. Anything
reading the board rather than the changelog — `tools/next-task.mjs`, a board mirror,
a human auditing coverage — saw an installed capability with no record behind it.

For what the feature does and why, see [`../epic.md`](../epic.md). For the change
itself, read the commit.
