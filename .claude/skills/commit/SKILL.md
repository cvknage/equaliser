---
name: commit
description: Commit staged changes with a clear, natural message
allowed-tools: Bash(git diff*), Bash(git log*), Bash(git commit*)
---

Commit the currently staged changes.

## Style

One line only. No body, no bullet points, no multi-line descriptions. Keep it concise but descriptive — aim for clarity over brevity.

Start with a capital. Use a type prefix when it helps readability, skip it when the subject speaks for itself. British English spelling. No trailing period.

Common prefixes: `Fix`, `Refactor`, `Add`, `Remove`, `Update`, `Optimise`

Examples from this repo:
- `Refactor device selection: replace isVirtual/isRealDevice checks with isValidForSelection`
- `Fix HAL input startup: delay after sample rate sync for CoreAudio propagation`
- `Fix shared memory capture: consume at output rate to prevent overflow artefacts`
- `Fix volume sync: add settling window and drift detection for device switches`
- `Refactor shared memory capture: eliminate double buffering for direct capture mode`

No Claude attribution or co-authored-by lines.

## Steps

1. Run `git diff --stat --staged` to see what is staged.
2. If nothing is staged, reply: "No staged changes."
3. Otherwise, draft a commit message and run:

```
git commit -m "<message>"
```