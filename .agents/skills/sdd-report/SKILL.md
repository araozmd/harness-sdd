---
name: sdd-report
description: File one harness-feedback report through tools/harness-report.sh for one of the four triggers
---

## Invocation adapter

In Codex, invoke `$sdd-report` and write arguments after the skill mention; in OpenCode, invoke `/sdd-report`. In both hosts, treat all accompanying text as `$ARGUMENTS` in the workflow below. Wherever that workflow writes a portable `/sdd-<name>` reference, the Codex invocation is `$sdd-<name>` and the OpenCode invocation is `/sdd-<name>`.

## Canonical workflow
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
4. **Mint the session token once, then call the reporter** with the allow-listed upstream
   fields only:

   ```sh
   # --- harness-session-id:begin ---
   # ONE token per session: the exported value if the session owner set it, else the
   # current session's telemetry `session-start` marker (deterministic, so every call in
   # the session reuses the same token), else the `init.sh` hard-stop stamp. Re-running
   # `date` per call would reset F02's per-session cap ledger.
   _hf_session="${HARNESS_FEEDBACK_SESSION_ID:-}"
   if [ -z "$_hf_session" ] && [ -f telemetry.jsonl ]; then
     _hf_session="$(grep -E '"type"[[:space:]]*:[[:space:]]*"session-start"' telemetry.jsonl 2>/dev/null \
       | tail -n 1 \
       | python3 -c 'import json,re,sys;r=json.loads(sys.stdin.read() or "{}");sys.stdout.write(re.sub(r"[^A-Za-z0-9._-]","",r.get("started_at","")))' 2>/dev/null || true)"
   fi
   [ -n "$_hf_session" ] || _hf_session="$(date -u +%Y%m%dT%H%M%SZ)"
   # --- harness-session-id:end ---

   sh tools/harness-report.sh \
     --trigger  <the trigger> \
     --symptom  <the symptom code> \
     --file     <a harness-owned path> \
     --command  <harness command name; omit when no command applies> \
     --exit-code <a real exit status; omit the flag when no process exited> \
     --role     <role> \
     --phase    <one of inception|architect|builder|reviewer|scout|slice-dispatch|handoff|install; omit when none applies> \
     --session-id "$_hf_session" \
     --notes-file <temp-file>
   ```

   The `--command` flag is optional: pass the harness command name that failed or is
   implicated, and omit the flag entirely when no command applies — for example a
   `doc-conflict` or `instruction-conflict` report, where no harness command ran. Never
   leave a placeholder such as `<harness command name>`: it fails F02's `_valid_command`
   and downgrades the whole report to the local fallback.

   The `--exit-code` flag is optional: pass the real process exit status (one to three
   digits) only when a process actually exited, and omit the flag entirely when none did —
   never leave a placeholder such as `<n>`, which fails F02's `_valid_exit_code` and
   downgrades the whole report to the local fallback.

   The `--phase` flag is optional: pass only one of the enumerated phases, and omit it
   entirely when none applies. F02's `_valid_phase` rejects any other nonempty value and
   downgrades the whole report to the local fallback.

   The session token matches `[A-Za-z0-9._-]{1,64}` and is minted **once per session**: the
   block above reuses `HARNESS_FEEDBACK_SESSION_ID` when the session owner exported it, and
   otherwise derives one token deterministically from the telemetry `session-start` marker —
   so no export is required, and repeated calls in one session share the token instead of
   resetting F02's per-session cap ledger. On the `init.sh` hard-stop path, where no
   `session-start` marker exists, it falls back to `date -u +%Y%m%dT%H%M%SZ`; that fallback
   is grammar-safe, so the token is never left unset and the cap is never bypassed.
5. **Free-form text is local-only.** Write the prose summary to a temp file and pass it via
   `--notes-file`; it reaches the local `progress/feedback/` copy, is never an
   upstream field, and is never sent to `gh`.
6. **Report and stop.** The reporter never fails the task: a missing or unauthenticated
   `gh`, a duplicate, a capped session, or a bad field degrades to the local copy and exits
   0. State the outcome and stop.
