# Epic lifecycle: draft/planned states + next() gating — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom,
> one at a time. Each task names the R-id(s) it satisfies. Check off when done.

- [x] **T1** (R1, R2, R3) — Edit `store/tasks.schema.json`: add `"draft"` and
  `"planned"` to the **epic** `status` enum only (feature and slice enums
  untouched). Add a `$comment` on the epic status property:
  lifecycle `draft → planned → in-progress → done`; `pending` = legacy alias of
  `planned`.
- [x] **T2** (R4) — Edit `init.sh`: in the embedded fallback validator, change
  `EPIC_STATUS = {"pending", "in-progress", "done"}` to also include `"draft"`
  and `"planned"`.
- [x] **T3** (R12) — Edit `init.sh`: immediately after `data` is loaded (before the
  `jsonschema` branch, so it runs on both validation paths), add a warn-only scan:
  for each epic with `status == "draft"`, for each of its features with
  `status != "pending"`, print a `⚠️`-prefixed warning to stderr naming the epic
  and feature ids. Do **not** append to `errors`; exit code is unaffected.
- [x] **T4** (R5, R6, R8) — Edit `agents/orchestrator.md` step 3 ("Read state"):
  add the epic gate — never select a feature whose parent epic is `draft`,
  regardless of the feature's `status`/`sdd`/`autonomous`/`depends_on`
  (`autonomous: true` skips the *human* gate, not the planning gate); `planned`
  epics' features are treated exactly like `pending` epics' features.
- [x] **T5** (R5, R6, R7, R11) — Edit `store/local.md`: (a) extend the **next()**
  bullet with the epic gate (features of a `draft` epic are never actionable;
  `pending`/`planned`/`in-progress`/`done` epics impose no new gate); (b) add a
  short "Epic lifecycle" note: `draft → planned → in-progress → done`, with
  `pending` kept indefinitely as a legacy alias of `planned`, gating-equivalent.
- [x] **T6** (R9) — Edit `docs/WORKFLOW.md`: add a short "Epic lifecycle" section
  documenting `draft → planned → in-progress → done`, the `pending` legacy alias,
  and that the Orchestrator never selects work from a `draft` epic.
- [x] **T7** (R10) — Edit `specs/_templates/epic.md`: update the frontmatter status
  comment to `# draft → planned → in-progress → done (pending = legacy alias of
  planned; rollup of its features)`.
- [x] **T8** (R13) — Edit `store/board-mirror.md`: add a one-paragraph note that
  the mirror projects **feature** statuses onto columns; epic statuses (including
  the new `draft`/`planned`) never map to columns, so `status_map` needs no new
  entries.
- [x] **T9** (R1–R13) — Create `tests/test_epic_lifecycle.sh` per
  `F01-epic-lifecycle.tests.md` (POSIX sh; grep + python3 fixtures + one sandboxed
  `init.sh` run). Constraints: read `VERSION` dynamically (never assert a literal
  version), never `git diff` against `main`, zero new dependencies.
- [x] **T10** (wiring) — Edit `harness.config.yaml`: append
  `&& sh tests/test_epic_lifecycle.sh` to `verification.test_command` and extend
  its trailing comment with `+ epic lifecycle`.
- [x] **T11** (R14) — Bump `VERSION` by one MINOR (current value + MINOR — do not
  hard-code; read the file first). Add a `CHANGELOG.md` entry under
  `## [<new version>]` describing: epic `draft`/`planned` states (additive enum),
  the `next()` draft gate, the warn-only `init.sh` check, and the docs/template
  updates.
- [x] **T12** — Run `./init.sh` and the full `verification.test_command`; ensure
  green before hand-off. Do **not** change any status in `state/tasks.json`.
