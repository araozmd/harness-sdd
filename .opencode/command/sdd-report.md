---
description: File one harness-feedback report through tools/harness-report.sh for one of the four triggers
---

File **exactly one** harness-feedback report for a **harness defect**, then stop. This
command drafts the report and calls the reporter; `tools/harness-report.sh` owns
every filing mechanic (allow-list, marker, duplicate search, per-session cap, redaction) —
never re-implement any of them here.
Resolve every relative path against the repository root.

1. **Identify the trigger, or refuse.** Read `progress/feedback/notes.md` and the
   direct evidence. The trigger MUST be exactly one of `harness-malfunction`,
   `contradictory-instruction`, `workaround`, or `missing-capability`. A failure of the
   project's own code or tests, a transient network or auth error, or an agent mistake the
   harness correctly caught is **not** a trigger — report nothing and STOP.
2. **Pick the symptom** from the fixed vocabulary: `init-failure`, `install-failure`,
   `tool-failure`, `board-write-failure`, `gate-unsatisfiable`, `instruction-conflict`,
   `doc-conflict`, `workflow-gap`, `state-corruption`. An `init.sh` failure maps to
   `init-failure`. Never invent a code.
3. **Pass at least one harness-owned `--file`.** Use `init.sh` for the `init.sh`-failure
   path; otherwise the failing harness tool/path (for example `tools/harness-report.sh`, or
   the named `--command`). F02 rejects the whole report to a local copy when no supplied
   path is harness-owned, so a report with no accepted `--file` never files upstream.
4. **Call the reporter** with the allow-listed upstream fields only:

   ```sh
   sh tools/harness-report.sh \
     --trigger  <the trigger> \
     --symptom  <the symptom code> \
     --file     <a harness-owned path> \
     --command  <harness command name> \
     --exit-code <a real exit status; omit the flag when no process exited> \
     --role     <role> \
     --phase    <one of inception|architect|builder|reviewer|scout|slice-dispatch|handoff|install; omit when none applies> \
     --session-id "${HARNESS_FEEDBACK_SESSION_ID:-$(date -u +%Y%m%dT%H%M%SZ)}" \
     --notes-file <temp-file>
   ```

   The `--exit-code` flag is optional: pass the real process exit status (one to three
   digits) only when a process actually exited, and omit the flag entirely when none did —
   never leave a placeholder such as `<n>`, which fails F02's `_valid_exit_code` and
   downgrades the whole report to the local fallback.

   The `--phase` flag is optional: pass only one of the enumerated phases, and omit it
   entirely when none applies. F02's `_valid_phase` rejects any other nonempty value and
   downgrades the whole report to the local fallback.

   The session token is `HARNESS_FEEDBACK_SESSION_ID`, minted once per session and matching
   `[A-Za-z0-9._-]{1,64}` (on the `init.sh` hard-stop path, where no `session-start` marker
   exists, mint it from `date -u +%Y%m%dT%H%M%SZ`). The `date -u +%Y%m%dT%H%M%SZ` fallback in
   the call above is grammar-safe, so the token is never left unset and the per-session cap
   ledger is never bypassed.
5. **Free-form text is local-only.** Write the prose summary to a temp file and pass it via
   `--notes-file`; it reaches the local `progress/feedback/` copy, is never an
   upstream field, and is never sent to `gh`.
6. **Report and stop.** The reporter never fails the task: a missing or unauthenticated
   `gh`, a duplicate, a capped session, or a bad field degrades to the local copy and exits
   0. State the outcome and stop.
