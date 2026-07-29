# E99-F09: Update Antigravity integration to use Skills architecture - Tasks

1. **Update `harness-install.sh` for Antigravity Installation**
   - Modify Section 5c to create `.agents/skills/` instead of `.agents/workflows/`.
   - Update the loop that copies commands to create a directory for each command (e.g., `.agents/skills/<cmd>/`) and write the command content into `SKILL.md` within that directory.
   - Inject YAML frontmatter into the `SKILL.md` files containing the `name` (the command name) and a `description`.
   - Remove the logic that creates `.agents/agents/coder.md` and other persona files.

2. **Update `harness-install.sh` for Antigravity Deselection**
   - Modify Section 7 (the `deselect` loop) for Antigravity.
   - Change the `remove_if_pristine` calls to target the `.agents/skills/` directories for the installed commands.

3. **Update `tests/test_install.sh`**
   - Find tests related to Antigravity (`test_antigravity_files`, etc.).
   - Update assertions to check for `.agents/skills/<cmd>/SKILL.md`.
   - Verify that the YAML frontmatter is correctly formatted.
   - Update the deselection tests to verify the removal of `.agents/skills/`.

4. **Run Tests and Verify**
   - Execute `sh tests/test_install.sh` locally.
   - Ensure all tests pass.
