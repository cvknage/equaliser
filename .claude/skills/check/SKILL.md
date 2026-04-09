---
name: check
description: Run build, tests, and quality checks before committing
disable-model-invocation: true
allowed-tools: Bash(swift*), Read, Glob, Grep
---

Run the full pre-submit quality check.

## Step 1: Build

Run `swift build` and report any compilation errors.

## Step 2: Test

Run `swift test` and report any test failures.

## Step 3: British English Spelling

Check all Swift source files for American English spellings. Search for:
- `equalizer` (should be `equaliser`)
- `behavior` (should be `behaviour`)
- `optimized` (should be `optimised`)
- `color` in code context (should be `colour` — but note "meter" is acceptable for audio meters)
- `center` (should be `centre`)
- `initialize` (should be `initialise`)
- `summarize` (should be `summarise`)
- `categorize` (should be `categorise`)

Use Grep to search for these patterns in `src/` and `tests/`.

## Step 4: Debug Statements

Check for debug `print()` statements in production code (not tests):
- Search for `print(` in `src/` files
- Report any that are not behind a debug flag or conditional

## Step 5: TODO/FIXME Markers

Check for newly introduced `TODO` or `FIXME` markers in changed files.

## Step 6: Pre-Submit Checklist

Verify:
- [ ] **Single Responsibility**: Does each type have one clear reason to change?
- [ ] **Protocol Dependencies**: Are dependencies on protocols, not concrete types?
- [ ] **No Duplication**: Is each constant/piece of logic in one place?
- [ ] **Pure Domain Logic**: Does new domain code avoid I/O and dependencies?

## Output

Produce a summary:

- **Build**: pass/fail (with errors if any)
- **Tests**: pass/fail (with failures if any)
- **Spelling**: clean/violations (with specific files and words)
- **Debug statements**: clean/violations (with specific files)
- **Checklist**: all items pass/fail with notes