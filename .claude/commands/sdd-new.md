---
description: Seed a new idea into the TaskStore as Inception (interactive intake → pending entry + inbox brief)
---

Act as **Inception** (`agents/inception.md`). That role file is the durable contract;
this command carries the interactive front-end.

The free-text idea is in `$ARGUMENTS`. If it is empty, ask the human for it.

1. Run `./init.sh`. If it exits non-zero, STOP and report — do not seed into a broken
   environment.
2. Read `harness.config.yaml` and the TaskStore (`state/tasks.json`, per
   `store/local.md`).
3. Run a short, **adaptive** Q&A with the human to clarify: the problem and who it is
   for, the success outcome, the scope/boundaries, and any constraints. Where the
   shape forks, offer **at most 3** options as **text-only** (markdown/ASCII) mockups
   — never images. Keep it short; ask only what you need to triage and brief.
4. **Triage** the idea to exactly one altitude, per `agents/inception.md`:
   (1) new task on an existing feature / (2) new feature under an existing
   epic / (3) new epic + `epic.md` + `F01`. The write step is **altitude-dependent** —
   fork here. For altitudes 2 and 3, **allocate** a next-sequential id; for altitude 1,
   do NOT allocate a new id (you reuse the existing feature's id).
5. **Write** — branch by altitude:
   - **Altitude 1 (new task on an existing feature):** do NOT allocate a new id and do
     NOT insert a new feature into `state/tasks.json`. Branch on the existing
     feature's status (the inbox brief is read by the Architect only while a feature
     is `pending`):
     - **If it is still `pending`:** **append** a task-level note (and any dependency)
       to the EXISTING feature's `progress/inbox/<existing-feature-id>.md` brief —
       creating that brief from the `specs/_templates/inbox-brief.md` template if the
       feature predates the inbox convention. Per `agents/inception.md`, do not invent
       a competing feature. Then skip to step 8 (steps 6–7 cover only the new-entry
       path).
     - **If it is already `spec-ready`, `in-progress`, `in-review`, or `done`:** do
       NOT append to the brief — it has already been consumed, so the note would be a
       silent no-op. STOP and tell the human the addition must go back through
       specification: either raise it with the Architect to re-spec / update that
       feature's spec & task list, or re-run `/sdd-new` to seed it as a NEW feature
       (altitude 2) that `depends_on` the existing one. Do not write a no-op note.
   - **Altitudes 2 & 3:** write the `pending` feature entry into `state/tasks.json`
     (and, for a new epic, the epic entry + `specs/epics/<slug>/epic.md` + first
     `F01`), then continue to steps 6–7.
6. **Re-validate** `state/tasks.json` against `store/tasks.schema.json` (altitudes 2
   & 3, after the new entry). If it fails, report the failure and do NOT claim a
   successful seed.
7. **Write** the intent brief to `progress/inbox/<feature-id>.md` (frontmatter +
   sections), copying `specs/_templates/inbox-brief.md` as the template.
8. **Report** the `<feature-id>` (for altitude 1, the EXISTING feature's id), the
   relevant `state/tasks.json` entry, the `progress/inbox/<feature-id>.md` path, and
   tell the human to **run `/sdd-next`** next. Do NOT spawn the Architect and do NOT
   change any status — Inception seeds, never specs, and never moves a feature past
   `pending`.
