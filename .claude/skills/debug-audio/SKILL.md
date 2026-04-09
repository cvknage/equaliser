---
name: debug-audio
description: Investigate audio glitches, artefacts, device routing failures, and CoreAudio issues
context: fork
agent: audio-debugger
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, LSP, Bash(swift build*), Bash(swift test*)
---

Investigate the audio issue described in: $ARGUMENTS

## Before You Start

Read these knowledge files for context:

- .claude/knowledge/coreaudio.md
- .claude/knowledge/realtime-safety.md
- .claude/knowledge/known-issues.md

## Investigation Steps

1. **Understand the symptom**: What exactly is happening? (clicks, pops, silence, distortion, wrong device, latency, crash, permission issue)
2. **Identify the subsystem**: capture, DSP, output, device management, or permissions
3. **Read the relevant source files**: Use Glob and Read to trace the code path
4. **Check against known issues**: Compare with known gotchas in the knowledge files
5. **Check real-time safety**: Verify no allocation, locking, or blocking on the audio thread
6. **Produce a structured diagnosis**: symptom, root cause, affected files, suggested fix

## Output

Produce a diagnosis with:
- **Symptom**: What's happening
- **Subsystem**: Which part of the pipeline
- **Root cause**: Why it's happening, with file paths and line numbers
- **Suggested fix**: Concrete code change
- **Related knowledge**: References to known-issues or real-time safety rules