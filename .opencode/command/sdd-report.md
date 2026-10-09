---
description: File one harness-feedback report through tools/harness-report.sh for one of the four triggers
---

File **exactly one** harness-feedback report for a **harness defect**, then return to the caller. This
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
3. **Pass at least one harness-owned `--file`, as a concrete body path.** Use `init.sh` for
   the `init.sh`-failure path; otherwise supply the failing harness tool's own tracked body
   path — for example `tools/harness-report.sh`, `init.sh`, or `harness-install.sh`. Never
   pass an `sdd-*` command basename such as `sdd-next` as `--file`: F02 accepts only real
   tracked harness-body paths, so a command basename is dropped and the report falls to the
   local-only copy when it is the sole file. F02 rejects the whole report to a local copy
   when no supplied path is harness-owned, so a report with no accepted `--file` never files
   upstream.
4. **Draft and inspect public details, then mint the session token once and call.**
   Compose a fresh UTF-8 JSON object in a local file, never convert raw notes or logs.
   Required strings: `summary` (20–240 characters), `observed`, `expected`,
   `reproduction`, `evidence` (20–1500 each). `context` has exactly these keys,
   each a 20–1000 character string:
   - `harness-malfunction`: `failure`, `project_health`;
   - `contradictory-instruction`: `instruction_a`, `instruction_b`;
   - `workaround`: `documented_path`, `failed_because`, `alternative`;
   - `missing-capability`: `occurrences`, `workflow_gap`, `impact`.
   Total JSON must be at most 16,384 bytes; no duplicate or extra keys. Evidence
   must reference an accepted `--file` as a complete path token, optionally `:line`.
   Inspect the draft against direct evidence for factual meaning and confidentiality.
   Describe both incompatible obligations with source references for a conflict,
   and at least two concrete observed occasions for a missing capability. Reject
   generic filler, metadata-only text and placeholders; never invent missing facts,
   recurrence, reproduction steps or exit statuses. A concrete source inspection
   procedure is valid evidence when execution is unavailable or inappropriate.
   Compose only verified harness facts and synthetic examples. Exclude project
   contents, customer names, private repository identifiers, environment dumps,
   credentials and unrelated logs. Defined filters reject known secrets, emails,
   URLs, foreign paths, controls and marker syntax; they cannot prove arbitrary
   prose is confidential or factually correct. If uncertain, retain local-only.
   Never execute, source, evaluate or shell-interpolate any public field. Missing
   evidence produces local field diagnostics, without a user question; complete it
   later using the same session token. Raw `--notes-file` content stays local.

   Call automatically at the next control opportunity without a permission prompt;
   inspect new ledger entries on delegation returns, then resume authorized work.
   Use the existing single session identity:

   ```sh
   # --- harness-session-id:begin ---
   # ONE token per session: the exported value if the session owner set it, else the
   # current session's telemetry `session-start` marker (deterministic, so every call in
   # the session reuses the same token), else a `date` stamp minted ONCE and persisted in
   # the feedback dir, read back on later calls. Re-running `date` per call would give
   # reports >1s apart different ids and reset F02's per-session cap ledger.
   # Resolve the telemetry log EXACTLY as the writer/reader do: a `telemetry.log`
   # override from harness.config.yaml (relative values resolve under the harness dir,
   # absolute values are used as-is), else the default log. A hard-coded default path
   # would miss the marker under a documented override and re-mint `date` on every
   # report, resetting the per-session cap.
   _hf_session="${HARNESS_FEEDBACK_SESSION_ID:-}"
   _hf_dir=
   _hf_cfg="${_hf_dir}harness.config.yaml"
   _hf_log="${_hf_dir}telemetry.jsonl"
   if [ -f "$_hf_cfg" ]; then
     _hf_log_override="$(awk '
       /^telemetry:[[:space:]]*(#.*)?$/ { t=1; next }
       t && /^[^[:space:]#]/ { t=0 }
       t && /^[[:space:]]+log:/ {
         sub(/^[[:space:]]+log:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "")
         gsub(/^"|"$|^'\''|'\''$/, ""); print; exit
       }
     ' "$_hf_cfg" 2>/dev/null || true)"
     if [ -n "$_hf_log_override" ]; then
       case "$_hf_log_override" in
         /*) _hf_log="$_hf_log_override" ;;
         *)  _hf_log="${_hf_dir}$_hf_log_override" ;;
       esac
     fi
   fi
   if [ -z "$_hf_session" ] && [ -f "$_hf_log" ]; then
     _hf_session="$(grep -E '"type"[[:space:]]*:[[:space:]]*"session-start"' "$_hf_log" 2>/dev/null \
       | tail -n 1 \
       | python3 -c 'import json,re,sys;r=json.loads(sys.stdin.read() or "{}");sys.stdout.write(re.sub(r"[^A-Za-z0-9._-]","",r.get("started_at","")))' 2>/dev/null || true)"
   fi
   if [ -z "$_hf_session" ]; then
     # No export and no `session-start` marker: telemetry is disabled (or its best-effort
     # write failed), so the telemetry-derived path above yielded nothing. Mint the `date`
     # fallback ONCE and persist it in the feedback dir; every later call in the session
     # reads it back. Recomputing `date` per call would give reports >1s apart different
     # ids, resetting F02's `.session-count` ledger and bypassing `max_per_session`.
     _hf_fallback="${_hf_dir}progress/feedback/.session-id"
     if [ -f "$_hf_fallback" ]; then
       _hf_session="$(cat "$_hf_fallback" 2>/dev/null || true)"
       # Re-validate on READ: a corrupt or foreign `.session-id` must never be returned
       # verbatim. F02's `_valid_session` rejects a token outside `^[A-Za-z0-9._-]{1,64}$`
       # and drops the WHOLE report to a local copy, so one bad line here would silently
       # degrade EVERY later report in this repo. Ignore it and re-mint below. `case`, not
       # `grep`: a glob class also matches an embedded newline that a line-based grep misses.
       case "$_hf_session" in
         ''|*[!A-Za-z0-9._-]*) _hf_session="" ;;
       esac
       [ "${#_hf_session}" -le 64 ] || _hf_session=""
     fi
     if [ -z "$_hf_session" ]; then
       _hf_session="$(date -u +%Y%m%dT%H%M%SZ)"
       mkdir -p "${_hf_fallback%/*}" 2>/dev/null || true
       printf '%s\n' "$_hf_session" > "$_hf_fallback" 2>/dev/null || true
     fi
   fi
   # --- harness-session-id:end ---

   sh tools/harness-report.sh \
     --trigger  <the trigger> \
     --symptom  <the symptom code> \
     --file     <a concrete harness-owned body path> \
     --command  <harness command name; omit when no command applies> \
     --exit-code <a real exit status; omit the flag when no process exited> \
     --role     <role> \
     --phase    <one of inception|architect|builder|reviewer|scout|slice-dispatch|handoff|install; omit when none applies> \
     --session-id "$_hf_session" \
     --details-file <verified-public-json-file> \
     --notes-file <optional-local-notes-file>
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
   `session-start` marker exists, it mints the `date -u +%Y%m%dT%H%M%SZ` fallback **once**
   and persists it in the feedback dir, reading it back on later calls — so two reports more
   than a second apart still share one token. That fallback is grammar-safe, and a value read
   back from the file is re-validated against the same grammar before reuse: a corrupt or
   foreign `.session-id` is ignored and re-minted, so the token is never left unset, no later
   report is dropped for want of a valid token, and the cap is never bypassed.
5. **Raw notes are local-only.** Optional raw notes passed via
   `--notes-file` reach the local `progress/feedback/` copy; this content is never an
   upstream field and is never sent to `gh`. Accepted details alone supply public prose.
6. **Report and return.** The reporter never fails the task: a missing or unauthenticated
   `gh`, a duplicate, a capped session, or a bad field degrades to the local copy and exits
   0. State the outcome and resume the caller's authorized workflow. Do not ask for
   confirmation or wait for task completion. On a non-zero init harness malfunction,
   this is the at-most-one reporting-only exception: missing details means local-only;
   then hard stop with no repair, no board write, and no continued work.
