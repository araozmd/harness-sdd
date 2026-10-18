# Builder notes: E31-F03 (OpenCode 2.x compatibility)

Mutation campaign (T14), run in scratch clones under `/var/tmp/E31-F03-builder/camp`, each mutant
backed up with `cp -p` and restored from the backup (cmp + mode verified), applied diff printed.
Hermetic mutants ran with `opencode` off PATH; live mutants ran with 2.0.32 (R8* with 1.18.35 first).

| id | R | mutation | result |
|---|---|---|---|
| R2a-f | R2 | 2 skips; >=2 routes v2; rc ignored; parse before rc; v1 routes v2; last X.Y.Z not first | all killed (gate table rows) |
| R5a-d | R5 | single-shot poll; no AssertionError on always-[]; message loses `cold-start`; fetch exception propagated | all killed |
| R5e-h | R5 | start 30 / warm 60 / api 15 / term-grace 10 defaults perturbed | all killed (`inspect.signature` pin) |
| R5i,j,k,l,m | R5 | poll(exit) branch off; start deadline off; `min(api_timeout, remaining)` off; deadline +100; deadline never fires | all killed (R5k first survived; test added) |
| R6a,a2,a3 | R6 | `killpg`->`p.kill()`; TERM to leader only; SIGKILL escalation off | all killed (R6a2 first survived; TERM-handling child added) |
| R6b,b2 | R6 | service-status problem dropped; status call replaced | killed |
| R6c,d,e,f | R6 | cleanup skipped on failure; `debug agents` call added; `--port 0` removed; no new session | all killed |
| R6g,h | R6 | group-gone report dropped; cleanup problem not raised on a green probe | killed (both first survived/void; success-path + swallowed-KILL cases added) |
| R7a-f | R7 | XDG var dropped; OPENCODE* kept; run dir 0755; serve/api/status without isolated env | all killed |
| R7h | R7 | 2.x probe cwd=src | SURVIVED: 2.x serve writes nothing into cwd (observed); the tripwire is live on 1.x |
| R8z,w | R7 | 1.x probe cwd=src (`.opencode/.gitignore` is git-ignored) | killed only after the porcelain check gained `--ignored` for the OpenCode write paths |
| R8y | R7 | 1.x `oc()` bypasses `ocenv()` | round 1 claimed killed; that was WRONG (it only killed the recorded env, not the one the binary received). Round 2: `oc1_run` is driven by a fake 1.x that logs HOME/XDG_*, so deleting `env=` or passing `os.environ` is killed (B2a/B2b) |
| R1a,b,c | R1 | emitter `agent`->`agents`; `prompt`->`system`; extra `.opencode/commands` dir (scratch clone of harness-install.sh) | all killed |
| R3a,c,f | R3 | broken `{file:}`; stem dropped; extra literal stem | killed |
| R3d | R3 | broken `{file:}` + live system compare removed | killed anyway by the hermetic blank-system case (compare pinned twice) |
| R3e | R3 | pr-fixer body tampered in the copy | INVALID: expected value is read from the same tampered file |
| R4a,b,d | R4 | broken `{file:}` in copy; `sdd-next.md` deleted from the copy; `sdd-triage.md` deleted from the copy | killed |
| R4c | R4 | expected stems shrunk to `sdd-next` | green (control, shows the repo-derived stems carry R4d) |
| R8a,b2 | R8 | pr-fixer not emitted; sdd-next only in an agent prompt | killed (parsed `command` map) |
| R8b | R8 | same fixture with a raw-substring check | green (control; the substring check cannot tell) |
| R9a-j | R9 | always/never `--standalone`; rc ignored; quoted flag; digits not semver; no `cut`; `''`/`0`/`1` arms dropped; `tail` for `head` | all killed |
| R10a | R10 | 2.x-only prefix strip | killed |
| R10b | R10 | `classify_model` pattern edit | out of scope (DO NOT TOUCH), survives by design |
| R11a-j | R11 | each token / section removed | all killed |
| R12a-g | R12 | VERSION 0.96.3 / 0.96.4; heading renamed; each required entry token removed | all killed |

Notes:
- First campaign pass had false HANG kills (timeout 240 s with 10 parallel suites): discarded, rerun at W=5, timeout 900.
- Mutant runs of a broken `kill_group` leaked fake `opencode serve` shells (my fakes, never the real binary); swept by pid.
- The live suites left no `opencode.exe serve` before/after any run (pgrep empty on both majors).

Round 2 (reviewer B1-B4), scratch-clone mutants, hermetic with XDG_* unset in the host env:
B1 (`--version` without env=; with os.environ), B2a/B2b (oc1_run without env / with os.environ),
B3 (narrowed except; also narrowed + ValueError), B4 (pr-fixer expected = served system),
A1 (ocenv drops XDG_DATA_HOME, now a named assertion), A2 (OPENCODE* kept): all killed.
