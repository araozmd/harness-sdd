# E32-F06 Builder

- Init passed before work; board and approved spec are in-progress, autonomous.
- T1–T2: bounded stdlib validator and reporter integration added. Missing details test failed against pre-change reporter (gh reached), passes after gate. Adversarial matrix and all existing feedback guards pass: `TMPDIR=/var/tmp/scratchpad/E32-F06-builder sh tests/test_feedback_report.sh` (log in external namespaced scratch).
- New tests cover public schema, completeness, four context schemas, unsafe corpus, exact marker, details fingerprint, notes isolation and executable shell canary. No live GitHub calls.
- Helper ships through existing `HARNESS_BODY_LOCAL=... tools ...` directory inventory, no additional inventory entry required.
- Init self-check passed after T1–T2 and canonical command/role edits. Configured full suite will run against the coherent regenerated contract at T8; old prompt assertions are being replaced as required by T3–T6.

- T3–T5: canonical report command composes bounded details and resumes caller; owner reporting duty now automatic at next control opportunity; subagent ledger carries evidence candidates. Current README/workflow/install/config comments describe deterministic filter limits and owner responsibility. Updated reporting-rule suite passes, including fresh installs for all hosts.
