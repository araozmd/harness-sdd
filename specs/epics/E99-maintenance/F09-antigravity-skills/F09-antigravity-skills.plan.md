# E99-F09: Update Antigravity integration to use Skills architecture - Plan

## Approach
1. **Update `harness-install.sh` (Installation):**
   - Locate the Antigravity section in `harness-install.sh` (Section 5c).
   - Change the target directories from `.agents/workflows` and `.agents/agents` to `.agents/skills`.
   - Modify the file generation logic for commands to create directories for each skill (e.g., `.agents/skills/sdd-next/SKILL.md`).
   - Inject YAML frontmatter (`name` and `description`) into the generated `SKILL.md` files, pulling descriptions from a predefined mapping or the command source if available.
   - Remove the code that generates persona files (e.g., `coder.md`).

2. **Update `harness-install.sh` (Uninstallation/Deselect):**
   - Locate the deselect logic for Antigravity (Section 7).
   - Update `remove_if_pristine` calls to target the new `.agents/skills/` paths instead of `.agents/workflows/` and `.agents/agents/`.

3. **Update `tests/test_install.sh`:**
   - Modify the test assertions that check for Antigravity installation artifacts.
   - Assert the existence of `.agents/skills/<skill_name>/SKILL.md`.
   - Assert the absence of `.agents/workflows/` and `.agents/agents/`.
   - Assert the correct parsing of YAML frontmatter in the generated skill files.
   - Update deselect tests to ensure clean removal of the new paths.

## Impact Analysis
- **harness-install.sh:** The core installation script will be updated. This affects users installing or updating the harness with Antigravity enabled.
- **tests/test_install.sh:** The test suite will be updated to reflect the new expected behavior.
- **Other CLIs:** No impact. The changes are strictly confined to the Antigravity-specific blocks in the installer and tests.
