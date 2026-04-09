---
name: commit
description: Commit staged changes with a clear, natural message
allowed-tools: Bash(git diff*), Bash(git log*), Bash(git commit*)
---

Commit the currently staged changes.

## Style

Start with a capital. Use a type prefix when it helps readability, skip it when the subject speaks for itself. British English spelling. No trailing period.

Common prefixes: `Fix`, `Refactor`, `Add`, `Remove`, `Update`, `Optimise`

No Claude attribution or co-authored-by lines.

## Steps

1. Run `git diff --stat --staged` to see what is staged.
2. If nothing is staged, reply: "No staged changes."
3. Otherwise, draft a commit message and run:

```
git commit -m "<message>"
```