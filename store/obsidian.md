# Store backend: `obsidian`

Obsidian is just markdown folders, YAML frontmatter, and `[[wikilinks]]`. So this
backend is almost free: point an Obsidian vault at the repo (or at `specs/`) and you
get graph view, backlinks, and search over your specs with **no migration**. The
files are the same ones the `local` backend uses.

## Setup
1. In Obsidian: *Open folder as vault* → select the `harness-sdd` repo (or `specs/`).
2. Recommended community plugins (optional): **Dataview** (query frontmatter),
   **Kanban** (a board view over feature `status`).

## TaskStore → feature frontmatter
With `tasks: obsidian`, the source of truth for status is each feature's
`.spec.md` **frontmatter** (`status`, `sdd`, `depends_on`), not `tasks.json`.

- **list()/next()/get()** — read frontmatter across `specs/epics/**/**.spec.md`.
  A Dataview query can render the board:
  ```dataview
  table status, sdd, epic from "specs/epics" where id sort id asc
  ```
- **set_status(id, status)** — edit the addressed object's frontmatter `status`: a
  **feature id** edits that feature's `.spec.md` frontmatter; an **epic id** edits that
  epic's `specs/epics/<epic>/epic.md` frontmatter `status`. The epic case is required —
  the epic-done rollup and drift-check demotion (`store/local.md`) write epic status
  through this same operation.

Keep `state/tasks.json` as an optional mirror if you also want the `local` view;
otherwise frontmatter is canonical.

## DocStore → Obsidian-flavored markdown
- Same files as `local`.
- Use `[[feature-name]]` / `[[glossary#term]]` wikilinks to cross-reference specs,
  epics, and glossary terms — backlinks make the spec set navigable as a knowledge
  base (the same linking convention used elsewhere in your notes).
- Frontmatter stays machine-readable for the Orchestrator.

## Notes
- No daemon, no API, no auth. Obsidian reads the files; the agents read/write the
  same files. They never conflict because both treat markdown as the source.
