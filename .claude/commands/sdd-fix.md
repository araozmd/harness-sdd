---
description: Lightweight fix lane as Fixer — seed an sdd:false fix under the reserved maintenance epic (brief only, no spec/drill) and hand it to the existing Builder → Reviewer loop (interactive)
---

Act as **Fixer** (`agents/fixer.md`). That role file is the durable contract; this
command carries the interactive front-end.

The free-text fix description is in `$ARGUMENTS`. If `$ARGUMENTS` is **empty**, STOP and
**ask** the human what to fix rather than seeding an empty fix.

1. Run `./init.sh`. If it exits non-zero, STOP and report — do not seed into a broken
   environment.
2. Read `harness.config.yaml` and the TaskStore (`state/tasks.json`, per `store/local.md`).
3. Run a short, **adaptive** Q&A with the human to settle the fix's shape: what's broken,
   the intended fix, how to verify, and a non-empty `## Files expected to change` list
   of normalized repo-relative paths. Remove one leading `./`, then reject absolute
   paths, empty/`.`/`..` components, repeated/trailing separators, control characters,
   wildcards, and ambiguous prose. Where the shape forks, offer **at most 3** options
   as **text-only** (markdown/ASCII) mockups — never images. Keep it short.
4. **Maintenance epic (create-on-first-use / reuse-by-id).** Look up epic `E99` in
   `state/tasks.json`. If **absent**, create it with `id: "E99"`, slug `maintenance`,
   title `"Maintenance (hotfixes & minor fixes)"`, `status: "planned"`, `features: []`,
   and write `specs/epics/E99-maintenance/epic.md` (title + one-paragraph brief only — no
   feature spec). If **present**, reuse that same epic **by id `E99`** — never create a
   second maintenance epic and never renumber its existing fixes.
5. **Seed** one fix: append a feature to `E99`'s `features` array with `sdd: false`,
   `status: "pending"`, a one-line `title`, a `spec_path`
   (`specs/epics/E99-maintenance/F<NN>-<slug>/`, **directory not created**), and an `id`
   allocated next-sequential strictly **above** the epic's max `F##` (append-only, no
   reuse). Stamp it `autonomous: true` by **default**; if the human passes a `--gated`
   opt-out, stamp it `autonomous: false` instead (it then parks at the normal gate).
6. Write **exactly one** fix-oriented inbox brief at `progress/inbox/<id>.md` (problem +
   intended fix + how to verify + `## Files expected to change`) from
   `specs/_templates/inbox-brief.md`. Do **NOT** create
   any feature `.spec.md`/`.plan.md`/`.tasks.md`/`.tests.md`, do **NOT** create the
   `spec_path` directory, and do **NOT** spawn the Architect — brief-only, never a spec.
7. **Re-validate** `state/tasks.json` against `store/tasks.schema.json` after the epic
   create and after the fix append. If it fails, report the failure and do NOT claim a
   successful seed.
8. **Hand off in-session.** After seeding + re-validation, **hand the seeded fix off to
   the existing `sdd: false → Builder → Reviewer` loop in-session** — do not stop at
   seeding. Trigger the existing Orchestrator routing (`pending + sdd: false → Builder →
   Reviewer`, the same behaviour `/sdd-next` drives) on the just-seeded fix; **reuse** that
   routing, do not re-implement it. The Fixer writes no production code (the Builder does).
9. **Report** the maintenance-epic state (created/reused `E99`), the seeded fix (id +
   title + `spec_path` + `autonomous` value), the inbox brief at `progress/inbox/<id>.md`,
   that no spec / `spec_path` directory / Architect was created or spawned, and that the
   fix was handed off to the existing `sdd: false` loop in-session.
