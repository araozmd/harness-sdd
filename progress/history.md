# History

The durable changelog of what the agents did, across all runs. The Orchestrator and
Reviewer append one line per meaningful step. Newest at the bottom.

Format: `YYYY-MM-DD | <agent> | <feature-id> | <what happened>`

---

2026-05-28 | harness | — | harness-sdd scaffolded (local + obsidian stores, jira stubbed)
2026-05-30 | architect+builder | E00-F01 | Installer spec (4 files) + harness-install.sh + tests/test_install.sh co-authored; init.sh made self-locating; VERSION added. Tests green. Set in-review for the Reviewer dogfood.
2026-05-30 | reviewer | E00-F01 | Verified via PR #3 (merged 876ca48): R1–R11 traced to passing assertions in tests/test_install.sh (green under sh and dash); Codex review cycle closed (1 stale P1 + 4 P2 addressed across f4e2dca/e85192a/8711412). → done. Epic E00 → done.
- 2026-05-30 — E03 created (Multi-repo coordination). Architect wrote 4-file spec for E03-F01 (Umbrella coordinator) → spec-ready. PAUSED at human gate.
- 2026-05-30 — E03-F01 approved by human → in-progress; dispatching Builder. Registered E03-F02 (Cascade installer, pending, depends_on E03-F01) from install-cascade discussion.
- 2026-05-30 — E03-F01 Reviewer APPROVED (R1–R19 covered, tests green, pure-superset + no-fork verified) → done. Wired test_umbrella.sh into verification.test_command.
- 2026-05-31 — E03-F01 merged to main (PR #6, 4 Codex rounds), tagged v0.2.0. Starting E03-F02 (Cascade installer) on feat/cascade-installer.
- 2026-05-31 — E03-F02 Reviewer APPROVED (R1–R24, all suites green, non-regression + migration smoke-tested) → done. Epic E03 done. VERSION → 0.3.0.
- 2026-06-01 E04-F01 — Architect wrote 4-file spec (R1–R16) from intent brief → status spec-ready ⏸ human gate.
- 2026-06-01 E04-F01 — Builder implemented (T1–T14), Reviewer APPROVED (R1–R16, all suites green), nit fixed → done. Epic E04 done. VERSION → 0.4.0.
- 2026-06-06 E05 seeded (Inception): epic "Harness observability & review quality" + E05-F01 (reviewer cross-file, autonomous) + E05-F02 (telemetry, parks at gate).
- 2026-06-06 E05-F01 — Architect spec (R1–R13) → Builder (T1–T9, VERSION 0.6.0, new tests/test_reviewer.sh) → Reviewer APPROVED round 1 (all 5 suites green, cross-file check self-applied) → done.
- 2026-06-06 E05-F02 — Architect spec (R1–R21) + session-summary amendment (R22–R27 portable end-of-session summary) → spec-ready ⏸ human gate.
- 2026-06-06 E05-F02 — Reviewer APPROVED round 1: all 6 suites green; R1–R27 each traced to a passing test; report exercised against independent fixtures (durations/rounds/mean+median latency correct, session scoping excludes pre-marker records, best-effort no-op on absent/empty/unwritable, no token/USD surfaced); both gitignore layouts proven (source git check-ignore + end-to-end installer seed, seed-once); DO NOT TOUCH honored (schema/init.sh untouched, status enum intact); VERSION 0.7.0 (MINOR ✨) + CHANGELOG per policy → done.
- 2026-06-06 E05-F02 — gate-approved (storage gitignored-under-.harness, AGENTS.md pointer); Architect reconciled spec → Builder (T1–T20, VERSION 0.7.0, tools/telemetry-report.py + tests/test_telemetry.sh) → Reviewer APPROVED (R1–R27, report exercised across all granularities + session view, gitignore proven in both layouts) → done. Epic E05 done.
- 2026-06-10 E06-F01 — Architect wrote 4-file spec (R1–R14, D1–D3 decisions) from intent brief → status spec-ready ⏸ human gate.
- 2026-06-10 E06-F01 — gate-approved by human (D1–D3 accepted) → in-progress; dispatching Builder.
- 2026-06-10 E06-F01 — Builder round 1 (T1–T12, VERSION 0.14.0, new tests/test_epic_lifecycle.sh, all 8 suites green; flagged test_inception.sh diff-vs-main removal) → in-review.
- 2026-06-10 E06-F01 — Reviewer APPROVED round 1: init.sh + all 8 suites green (run independently); R1–R14 each traced to a passing check; zero-dep fallback path exercised with jsonschema shadowed (warn-only invariant + rejection both proven); cross-file story coherent (draft → planned → in-progress → done, pending = legacy alias); feature/slice enums byte-identical; test_inception.sh diff-vs-main removal ACCEPTED (documented permanent-suite anti-pattern, surgical); VERSION 0.14.0 (one MINOR ✨) + CHANGELOG per policy → recommend done.
- 2026-06-10 E06-F01 — done (Reviewer verdict persisted). Epic E06 → in-progress (F02–F06 roadmap deliberately unseeded, rolling-wave).
- 2026-06-12T04:43:33Z  E07-F01  pending → spec-ready (Architect: 4-file spec, 12 R-ids) — PAUSED at human gate
- 2026-06-12T05:01:33Z  E08-F01  pending → spec-ready (Architect: 4-file spec, 15 R-ids) — PAUSED at human gate
- 2026-06-12T05:12:17Z  E08-F01  spec-ready → in-progress (human approved, gate latency 644s) — spawning Builder (round 1)
- 2026-06-12T05:22:43Z  E08-F01  in-progress → in-review (Builder: T1–T13, full suite green, round 1)
- 2026-06-12T05:27:52Z  E08-F01  in-review → approve (round 1) — Reviewer verified suite + behavior
- 2026-06-12T05:27:52Z  E08-F01  in-review → done; E08 epic rolled up → done
- 2026-06-12T05:27:52Z  drift-check (trigger: E08 done): NO-OP — no specs/architecture.md / specs/adr to re-validate against (graceful degradation); no epic demoted
- 2026-06-12T14:18:39Z  E07-F01  spec-ready → in-progress (human approved spec, 4 open questions accepted as-specced, gate latency 34506s) — spawning Builder (round 1)
- 2026-06-12T14:27:14Z  E07-F01  in-progress → in-review (Builder round 1: T1–T11, §5c Antigravity glue, VERSION→0.22.0, deselect→scoped removal, all 13 suites green)
- 2026-06-12T14:31:21Z  E07-F01  in-review → approve (round 1) — Reviewer verified all 13 suites green, R1–R12 traced, both deviations (VERSION→0.22.0, deselect→scoped removal) verified sound + data-loss safe
- 2026-06-12T14:31:21Z  E07-F01  in-review → done (Reviewer verdict persisted); E07 epic rolled up → done
- 2026-06-12T14:31:21Z  drift-check (trigger: E07 done): NO-OP — no remaining draft/planned/pending epics (all epics done); no Scout spawned, no demotion
- 2026-06-12T15:39:15Z  E07-F01  in-review/round-3 → HELD (Codex r3 P2 #3404422700: .agent/ vs .agents/ + persona registration). PR #31 NOT merged, labeled needs-human.
- 2026-06-12T15:39:15Z  E07-F01  done → pending; E07 epic done → pending (premature rollup reverted — PR unmerged + re-spec). Human chose: re-spec via Architect.
- 2026-06-12T15:44:29Z  E07-F01  pending → spec-ready (Architect re-spec: R1–R13, .agents/ plural + confirmed-primitives persona model) — PAUSED at human gate
- 2026-06-12T16:36:52Z  E07-F01  spec-ready → in-progress (re-spec approved; .agents/ plural, primitives model, skills out-of-scope; gate latency 3143s) — Builder round 2 on PR #31 branch
- 2026-06-12T16:44:24Z  E07-F01  in-progress → in-review (Builder round 2: .agent/→.agents/ rename, strengthened tests, VERSION held 0.22.0, all 13 suites green; commit d78e40f)
- 2026-06-12T16:49:38Z  E07-F01  in-review → approve (round 2, re-spec) — Reviewer verified rename complete, deselect-safety preserved, persona-model honest; holding done until PR #31 merges
