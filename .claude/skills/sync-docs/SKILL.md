---
name: sync-docs
description: Update CLAUDE.md, ARCHITECTURE.md, and knowledge files to reflect current codebase state
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Edit
---

Synchronise documentation with the current codebase state.

## Step 1: Check Directory Structure

Use Glob and Bash to get the current file structure of:
- `src/domain/` — verify domain types match what's documented
- `src/services/` — verify service files match what's documented
- `src/store/` — verify coordinators and managers match what's documented
- `src/viewmodels/` — verify view models match what's documented
- `src/views/` — verify view directories match what's documented
- `tests/` — verify test structure matches what's documented

## Step 2: Check Knowledge Files

Read each knowledge file and verify its claims against the current code:

- `.claude/knowledge/coreaudio.md` — are the architecture diagrams still accurate?
- `.claude/knowledge/realtime-safety.md` — are the patterns still used?
- `.claude/knowledge/swift-concurrency.md` — are the concurrency patterns current?
- `.claude/knowledge/memory-safety.md` — are the memory patterns still followed?
- `.claude/knowledge/project-patterns.md` — do the patterns still match the code?
- `.claude/knowledge/known-issues.md` — are the known issues still relevant?

## Step 3: Check ARCHITECTURE.md

Verify:
- Directory structure tables are current
- Key files table matches actual files
- Layered architecture diagram is current
- Coordinator pattern is current
- Protocol list is current
- State management table is current

## Step 4: Check CLAUDE.md

Verify:
- Project overview table is current
- Build commands are correct
- Naming conventions table is current
- Spelling table is current
- Knowledge file cross-references are accurate

## Step 5: Update

For each discrepancy found:
1. Note the specific file and section
2. Describe what changed in the codebase
3. Update the documentation to match

**Important**: Never add new content without verifying it matches the code. Only update existing sections that are stale or inaccurate.

## Output

Produce a summary:
- **Files checked**: list of documentation files reviewed
- **Discrepancies found**: list of mismatches between docs and code
- **Updates made**: list of changes applied
- **Updates needed but skipped**: any changes that require manual verification