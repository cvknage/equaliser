---
name: refactor
description: Analyse code for SOLID and DRY violations and produce a concrete refactoring plan
context: fork
agent: solid-analyst
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, LSP
---

Analyse the following for SOLID and DRY violations: $ARGUMENTS

## Before You Start

Read these knowledge files for context:

- docs/dev/project-patterns.md
- docs/dev/swift-concurrency.md

## Analysis Framework

Analyse the code for:

1. **Single Responsibility**: Does each type have one reason to change? Are unrelated concerns mixed?
2. **Open/Closed**: Can new behaviour be added without modifying existing code?
3. **Liskov Substitution**: Do protocol implementations violate contracts?
4. **Interface Segregation**: Are protocols focused? This project uses `-ing` suffix (Enumerating, VolumeControlling, etc.)
5. **Dependency Inversion**: Do high-level modules depend on abstractions? Inject `-ing` protocols, not concrete services.
6. **DRY**: Are constants in AudioConstants/MeterConstants? Are utilities in AudioMath/MeterMath? Is logic duplicated?

## Output

Produce a refactoring plan with:

- **Goal**: What the refactoring achieves
- **Problems**: Each violation with file path, type/function name, and principle violated
- **Approach**: High-level improved structure
- **Files to modify**: Explicit paths
- **Steps**: Incremental, each leaving the project compiling

Each step should be small, safe, and preserve existing behaviour.