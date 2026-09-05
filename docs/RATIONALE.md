# Why this harness exists

## Why a harness

An agent harness is the context, tools, durable state, workflow, and verification
that surround a coding model. This repository supplies that operating environment
for spec-driven work that may cross sessions, roles, branches, and repositories.
It is for newcomers deciding whether to adopt the workflow and for maintainers
deciding which controls still earn their cost.

A capable model can often complete a bounded task from one prompt, but prompting alone
is not a complete control plane for this project's target work: an instruction does
not itself preserve intent across a fresh session, authorize a state transition,
serialize concurrent writers, prove a behavior, or leave an auditable decision
trail. The harness makes those properties explicit and repeatable.

Some scaffolding exists because particular models and runtimes still lose context,
misread prose, overreach scope, or stop before verification. Those failure modes can
change. Other controls protect human authorization, durable intent, independent
challenge, and objective evidence; model capability does not make those needs
disappear. Therefore, as models improve, the value of this harness can shift away
from capability support and toward specification, verification, and trust. This is
a scoped engineering claim about long-running, repository-changing work under this
project's quality and governance requirements—not a claim that every task or team
needs this harness.

## Two layers, one decision rule

**Capability compensation** is a mechanism whose primary purpose is to reduce an
observed model or runtime failure, such as losing coherence on a long task or
interpreting a routing table inconsistently. It is a candidate for a controlled
retest when the model, runtime, or failure evidence materially changes. It is not
deprecated and is not safe to remove merely because a newer model exists.

**Durable trust and intent** is a mechanism whose primary purpose is to preserve an
engineering or governance property: explicit intent, authorization, integrity,
accountability, portability, isolation, or independently checkable evidence. A
durable mechanism can be redesigned or replaced, but a stronger model alone does
not satisfy the protected property.

Classify a mixed mechanism by its **primary purpose**, then state any property that
must survive its replacement. Neither label means immutable. Before changing a
classification or removing a mechanism, use representative tasks and compare the
current and proposed harness in repeatable runs. Predeclare acceptable quality,
safety, completion time, and cost thresholds. If the required evidence is absent, retain the mechanism.

## Design principles — the ablation doctrine (2026-09)

Adopted 2026-09-05 from the v0.69.0 ablation campaign, which was driven by two external
session reports and by the Claude Code team's published practice (delete the system
prompt on every model release; bring lines back one at a time; "describe the task, the
guardrails, the exit criteria — then let the model cook"). These are standing design
principles for every future harness change:

1. **Code over prose for anything deterministic.** A step that must happen identically
   every time is a tool, never an instruction to an agent. The empirical rule from two
   full sessions: every mechanism that earned its keep was code; every one that failed
   was prose asking an agent to behave. If a rule keeps being re-implemented by hand,
   that is the signal to ship it as a tool (severity classification, board seeding,
   telemetry all made this exact journey).
2. **Ablate on every model generation; never accrete.** Prompt text is written against a
   model that will not exist next quarter. The default motion is delete → run → measure →
   restore only the line whose absence caused a *repeated, observed* failure
   (`docs/ABLATION.md` is the protocol). Prose that explains *how to think* is a
   hobbling candidate; prose that states a non-guessable fact or a guardrail earns its
   place.
3. **Verification is the constant; prompts and harness code are disposable.** Task +
   guardrails + exit criteria + a way for the work to check itself outlive every prompt
   revision. Tests and gates are the layer that is never ablated — and every gate fails
   CLOSED, because a receipt that fails open is worse than no receipt.
4. **Structural over compliance-dependent.** Any property the system needs must be a
   property of a choke point (the board lock, the installer, a gate), not of an agent
   remembering an instruction — observed prompt-stamp compliance under context pressure
   was ~0%.
5. **A board row is work, not a note.** Findings must clear a bar (recurring | blocking |
   fail-open) to cost a build→review→PR cycle; everything else is one dated line in
   `progress/lessons.md`, which every role reads. Lessons compound; unbounded backlogs
   tax every future session.
6. **Float, don't pin.** Anything version-shaped (model ids, command names) either
   tracks upstream automatically (floating tier aliases) or is checked at install time
   and named loudly when stale (the stale-reference warning). A pinned value that rots
   silently is the same defect as a prompt written for a dead model.

## Deletion ledger

This is a retention ledger, despite the deliberately challenging name. Each row
states why a mechanism exists and what evidence would justify reconsidering it.
The evidence is specific to that mechanism; meeting one row's criterion says
nothing about another row.

| Mechanism | Layer | Why it exists now | Evidence to reconsider or remove | Repository pointers |
|---|---|---|---|---|
| C1 — `init.sh` structural preflight | Capability compensation | Gives each fresh agent session a known structural baseline before it plans or edits. | Repeated representative runs on a materially different runtime detect no unique pre-work failure after equivalent checks are proven to run earlier or to be guaranteed. Retest source and freshly installed layouts; otherwise retain it. | [`init.sh`](../init.sh) |
| C2 — Curated clean contexts, `context_reset_threshold`, and file handoffs | Capability compensation | Limits irrelevant history and carries only explicit state when long work crosses context boundaries. | Long-task runs across a materially newer model/runtime must meet predeclared completion, coherence, and handoff-recovery thresholds without resets. Retest interrupted and multi-session work; durable file state remains even if resets go. | [`harness.config.yaml`](../harness.config.yaml) and [`progress/`](../progress/) |
| C3 — Role-scoped `DO NOT TOUCH` and minimal-tool instructions | Capability compensation | Reduces accidental scope expansion and unnecessary tool use while a role executes a bounded assignment. | Remove only after representative runs without these prompts keep scope-violation and tool-misuse rates below predeclared thresholds. Retest overlapping dirty-worktree assignments; enforceable authorization boundaries must remain. | [`agents/builder.md`](../agents/builder.md) |
| C4 — Read-only Scout discovery | Capability compensation | Lets a clean-context agent map unfamiliar code without mixing discovery with mutation. | Cold-start repository task runs without a separate Scout must match predeclared path-selection, context-recall, and unnecessary-read thresholds. Retest large and unfamiliar repositories; retain read-only discovery while it adds unique accuracy. | [`agents/scout.md`](../agents/scout.md) |
| C5 — Doc-critic advisory checkpoint | Capability compensation | Surfaces ambiguity, contradiction, missing evidence, excess scope, and YAGNI risk before implementation. | Controlled-run data from specs that omit the checkpoint must show no material increase, under predeclared defect thresholds, in those issues reaching Builder or Reviewer. Retest multiple feature types; keep the pass if it still catches unique defects. | [`agents/doc-critic.md`](../agents/doc-critic.md) |
| C6 — Reviewer cross-file consistency audit | Capability compensation | Catches contradictions between specs, implementation, tests, configuration, and repository contracts that isolated checks may miss. | Independent review data must show simpler deterministic checks or another retained control catches the same contradiction classes at the predeclared escape-rate threshold. Retest installed-body and cross-file changes before removal. | [`agents/reviewer.md`](../agents/reviewer.md) |
| C7 — Multi-round Builder↔Reviewer correction | Capability compensation | Turns independent findings into bounded repair rounds instead of accepting the first plausible implementation. | Representative changes must sustain predeclared first-pass approval and escaped-defect rates without correction rounds. Retest complex and risky changes; independent verification remains required. | [`docs/WORKFLOW.md`](WORKFLOW.md) |
| C8 — Model interpretation of prose `next()` routing | Capability compensation | A model currently interprets status, dependency, ownership, gate, and slice rules to select work. | Keep this mechanism until E16-F03's deterministic selector is reviewed and shipped, parity-tested, and consumed by the Orchestrator as required by [ADR-0001](../specs/adr/0001-deterministic-next-selection.md). Remove only model interpretation of routing; preserve the human-readable gate policy as its specification. | [ADR-0001](../specs/adr/0001-deterministic-next-selection.md) and [`agents/orchestrator.md`](../agents/orchestrator.md) |
| D1 — EARS specs and R-id traceability | Durable trust and intent | Makes intended behavior explicit and maps each requirement to planned work and evidence. | Remove only after a governance decision says explicit intent-to-evidence mapping is no longer needed, or repeated audits prove a replacement preserves complete, reviewable traceability. Retest missing and contradictory requirements. | [`docs/SPEC-FORMAT.md`](SPEC-FORMAT.md) |
| D2 — File-backed TaskStore, specs, progress, and history | Durable trust and intent | Preserves resumable, reviewable, tool-neutral state outside any model session. | Remove only if the team no longer requires durable audit history, or a migration and recovery exercise proves a replacement preserves authoritative state, resumability, reviewability, and history. | [`state/tasks.json`](../state/tasks.json) and [`progress/history.md`](../progress/history.md) |
| D3 — Role separation and independent review | Durable trust and intent | Separates implementation authority from independent challenge and the final verification judgment. | Remove only if accountability and independent challenge are no longer required, or blinded review data proves another control supplies equivalent independence and records the responsible decision. | [`agents/builder.md`](../agents/builder.md) and [`agents/reviewer.md`](../agents/reviewer.md) |
| D4 — Human approval and autonomous gates | Durable trust and intent | Records who may authorize implementation and when explicit delegation permits autonomous progress. | Remove only through an explicit governance decision changing authorization, with adversarial and audit checks proving equivalent approval boundaries and attribution. | [`docs/WORKFLOW.md`](WORKFLOW.md) |
| D5 — Deterministic tests, lint/type checks, and behavioral evidence | Durable trust and intent | Supplies repeatable evidence about correctness beyond an agent's confidence or prose report. | Remove only if objective correctness evidence is no longer required, or mutation/failure-injection runs prove a replacement detects the same behavior, regression, lint, and type failures. | [`harness.config.yaml`](../harness.config.yaml) |
| D6 — Board write locking and isolated Git worktrees | Durable trust and intent | Prevents lost TaskStore updates and isolates concurrent branch changes. | Remove only when concurrent mutation and checkout overlap cannot occur, or stress runs prove another mechanism preserves atomic writes, exact branch identity, and filesystem isolation under failure. | [`tools/tasks-lock.py`](../tools/tasks-lock.py) and [`tools/fix-worktree.sh`](../tools/fix-worktree.sh) |
| D7 — Dependency diagnostics and deterministic selection | Durable trust and intent | Gives blocked work and routing decisions named, reproducible, testable outcomes instead of silent ambiguity. | Remove only if dependency and routing ambiguity cannot occur, or exhaustive fixture tests prove a simpler replacement preserves cycle witnesses, reason codes, and deterministic selection. | [`tools/task-diagnostics.py`](../tools/task-diagnostics.py) and [ADR-0001](../specs/adr/0001-deterministic-next-selection.md) |
| D8 — Architecture/ADR alignment and epic drift checks | Durable trust and intent | Keeps implementation aligned with accepted decisions and revalidates plans when lower-level work changes assumptions. | Remove only if design decisions and rolling-plan validity are no longer governed, or audit fixtures prove a replacement preserves decision provenance, citation resolution, and drift detection. | [`specs/adr/`](../specs/adr/) and [`agents/scout.md`](../agents/scout.md) |
| D9 — Telemetry | Durable trust and intent | Records phase duration, correction rounds, and approval-gate latency so maintainers can inspect process behavior. | Remove only if maintainers explicitly stop using those observations, or report parity checks prove another record preserves phase, round, and gate evidence without adding cost/token surveillance. | [`tools/telemetry-report.py`](../tools/telemetry-report.py) |
| D10 — Ownership and scoped selection | Durable trust and intent | Prevents shared work from being silently claimed outside its assigned owner or requested scope. | Remove only if shared allocation is no longer needed, or negative-scope tests prove another source of truth preserves fail-closed identity resolution and owner filtering. | [`docs/WORKFLOW.md`](WORKFLOW.md) and [`harness.config.yaml`](../harness.config.yaml) |
| D11 — Umbrella contracts, slice rollups, and integration gates | Durable trust and intent | Coordinates one feature across repositories while retaining per-slice evidence, merge state, and a final stack-level proof. | Remove only if cross-repository work is unsupported, or disposable multi-repo runs prove a replacement preserves one coordination seam, exact slice rollups, merged state, and integration evidence. | [`docs/UMBRELLA.md`](UMBRELLA.md) |
| D12 — Store/execution/mirror seams with local truth | Durable trust and intent | Keeps authoritative local state distinct from replaceable storage, execution, and visibility adapters, with fail-safe directionality. | Remove only if portability and replaceability cease to be goals, or adapter outage and migration tests prove a replacement preserves authoritative-state direction, local recovery, and safe failure. | [`store/README.md`](../store/README.md) and [`harness.config.yaml`](../harness.config.yaml) |
| D13 — Repository portability, config layering, and versioned install | Durable trust and intent | Lets the harness move across coding CLIs and repositories while preserving project/personal ownership and upgrade compatibility. | Remove only if the harness ceases to be shared or upgraded, or cross-CLI fresh-install and upgrade tests prove a replacement preserves entrypoints, configuration ownership, version compatibility, and user files. | [`docs/CONFIG-LAYERING.md`](CONFIG-LAYERING.md) and [`harness-install.sh`](../harness-install.sh) |

## How to use the ledger

Revisit a row when a materially different model or runtime ships, or when observed
failure data changes—not on a calendar alone. Select a representative task set that
includes normal, long-running, interrupted, and failure-path work relevant to that
mechanism. Compare the retained and simplified variants under the same conditions.

Before running the comparison, record thresholds for:

- requirement and behavioral quality;
- authorization, isolation, and data-safety failures;
- completion and recovery time; and
- runtime or model cost.

A benchmark movement, vendor launch, anecdote, or one successful task is not removal
evidence. A compensating control may be deleted only after the comparison meets its
row's thresholds, normal Reviewer evidence passes, and a human approves the change.
A durable control may be simplified too, but its protected property must either be
explicitly retired by governance or preserved by the replacement.

## Evidence and limits

These sources motivate observations, not a shared doctrine. They are bounded reports, not evidence of universal consensus,
universal causality, or guaranteed results in this repository:

- [Anthropic: effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
  reports experiments with Opus 4.5 on the Claude Agent SDK in which high-level
  prompting across context windows benefited from an initializer, incremental work,
  progress artifacts, and explicit end-to-end verification. Its authors describe one
  full-stack web-application setting and leave broader generalization open.
- [Anthropic: harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps)
  reports that context resets were important with Sonnet 4.5 in an earlier harness,
  while Opus 4.5 allowed that component to be removed in the later experiment. The
  same report describes planner/generator/evaluator separation, file-based contracts,
  and application checks within its long-running frontend/full-stack setting. That is
  evidence for retesting model-compensation components, not for removing independent
  engineering controls by default.
- [OpenAI: harness engineering in an agent-first repository](https://openai.com/index/harness-engineering/)
  describes one Codex-built internal repository using a short repository map, deeper
  versioned knowledge, structural constraints, tests, review loops, and per-worktree
  application observability. OpenAI explicitly cautions that its autonomy depended on
  that repository's specific structure and tooling, so this ledger does not treat the
  account as a general performance guarantee.
- [LangChain: improving Deep Agents with harness engineering](https://www.langchain.com/blog/improving-deep-agents-with-harness-engineering)
  reports a Terminal Bench 2.0 experiment using GPT-5.2-Codex in which trace analysis,
  context delivery, verification prompts, and middleware were changed while the model
  was held fixed. This is benchmark- and harness-specific evidence that surrounding
  controls can matter and that model-compensation guardrails should be retested, not a
  causal claim about every coding workflow.
- [Thoughtworks: feedback sensors for coding agents](https://www.thoughtworks.com/en-us/radar/techniques/feedback-sensors-for-coding-agents)
  offers practitioner guidance to expose compilers, linters, structural checks, and
  tests as timely feedback, including through reviewer agents or companion processes.
  It is guidance, not a controlled comparison or a claim that one review architecture
  fits every team.
- [METR: early-2025 AI and experienced open-source developer productivity](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/)
  is an early-2025 randomized controlled trial snapshot of 16
  experienced open-source developers working in repositories they knew well, mostly using Cursor Pro with
  Claude 3.5/3.7 Sonnet on assigned issues. METR itself frames the result as one
  relevant setting and discusses representativeness and tool-learning limits. It
  does not show that AI universally slows developers, does not evaluate this autonomous
  harness, and does not establish that any one harness design is universally correct.
