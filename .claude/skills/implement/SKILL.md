---
name: implement
description: Implement a feature or fix following project patterns and expert knowledge
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(swift build*), Bash(swift test*), LSP
---

Implement the following: $ARGUMENTS

## Step 1: Load Relevant Knowledge

Determine which knowledge files are relevant based on the task:

- Audio/DSP work: read `docs/dev/coreaudio.md` and `docs/dev/realtime-safety.md`
- Device/routing work: read `docs/dev/coreaudio.md` and `docs/dev/known-issues.md`
- Concurrency work: read `docs/dev/swift-concurrency.md` and `docs/dev/memory-safety.md`
- Refactoring work: read `docs/dev/project-patterns.md`
- Any task: read `docs/dev/known-issues.md` if you encounter unexpected behaviour

Read the relevant files using the Read tool before starting implementation.

## Step 2: Understand the Codebase

- Use Glob to find related files
- Use Grep to find existing patterns and conventions
- Use Read to understand current implementations
- Use LSP for type definitions and references

## Step 3: Implement

Follow these project conventions:

### Naming
- Types/Protocols: UpperCamelCase (`AudioDevice`, `DeviceEnumerating`)
- Functions: lowerCamelCase (`refreshDevices`, `start`)
- Protocols: `-ing` suffix (`Enumerating`, `VolumeControlling`)
- Concrete services: Domain + Service (`DeviceEnumerationService`)
- Constants: lowerCamelCase (`let smoothingInterval`)

### Architecture
- Pure types go in `src/domain/` (zero dependencies)
- Services go in `src/services/` (one responsibility each)
- Coordinators orchestrate, delegates do the work
- View models hold `unowned` store references

### Concurrency
- `@MainActor` for UI-bound classes
- `actor` for thread-safe isolated state
- `nonisolated(unsafe)` for audio thread access (with safety proof)
- `@Observable` for view models

### Spelling
- Use British English: equaliser, behaviour, optimised
- "meter" means audio level meters (not length unit)

### Audio Thread Safety
- No allocation on audio thread
- No locks on audio thread
- No blocking on audio thread
- Use ManagedAtomic for lock-free communication
- Pre-allocate all buffers and setups at init

## Step 4: Verify

After implementation:
1. Run `swift build` to verify compilation
2. Run `swift test` to verify no regressions
3. Check for British English spelling
4. Verify the implementation follows SOLID/DRY principles