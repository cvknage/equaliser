# Code Size Analysis

Cross-project comparison and investigation plan for reducing code volume.

## Cross-Project Comparison (Swift only)

| Project | Source Files | Source Lines | Test Files | Test Lines | Total |
|---------|-------------|-------------|------------|------------|-------|
| Equaliser | 87 | 13,968 | 23 | 5,268 | 19,236 |
| Radioform | 32 | 8,011 | 0 | 0 | 8,011* |
| FineTune | 90 | 17,915 | 12 | 5,698 | 23,613 |

\* Radioform also has a C++ DSP engine and Objective-C++ audio driver that are not reflected in these Swift counts. Its real code volume is somewhere between the Swift-only figure and Equaliser's total.

## Equaliser Breakdown by Area

| Area | Files | Lines | % of Source |
|------|-------|-------|-------------|
| UI | 22 | 3,855 | 28% |
| Pipeline | 13 | 3,378 | 24% |
| Device | 15 | 2,314 | 17% |
| App orchestration | 5 | 1,884 | 13% |
| DSP | 13 | 1,777 | 13% |
| Presets | 6 | 1,663 | 12% |
| Driver | 9 | 1,135 | 8% |
| Meters | 4 | 613 | 4% |

These overlap because some files contribute to multiple areas. Raw totals exceed 100% for this reason.

## Observations

- **File-to-line ratio:** 87 files for ~14k source lines gives an average of ~160 lines per file. This is the protocol-segregation pattern producing many small, focused types. Worth asking whether every abstraction is earning its keep.
- **Orchestration weight:** The app-level coordination layer accounts for ~1,600 lines across two main types. These are large by this project's standards and may carry mixed responsibilities.
- **Pipeline concentration:** The render pipeline and HAL IO layer together are the single largest area. CoreAudio interop is inherently complex, but some of this may be incidental rather than essential.
- **UI volume:** At 28% of source, the UI layer is the biggest contributor. Some views may be doing work that belongs in view models or services.
- **Test distribution:** Test lines are ~38% of source lines overall, but coverage is uneven. Some modules have thorough test coverage; others have little or none.

## Investigation Plan

### 1. Orchestration Bloat

The app-level coordination types are the largest individual units in the codebase. Explore:

- Whether responsibilities can be redistributed to the feature groups they coordinate.
- Whether state management can be simplified — are there redundant signals or over-communicated state changes?
- Whether lifecycle management (start/stop/reconfigure) can be made more declarative rather than imperative sequences.

### 2. Protocol and Abstraction Overhead

The project follows a strict protocol-per-service pattern. Explore:

- Whether all protocols are actually needed for testability or whether some are pure passthrough.
- Whether small service types that delegate entirely to a single other type add value.
- Whether the indirection layers between views and services can be thinned.

### 3. Pipeline Complexity

The audio pipeline is the domain's core but also its heaviest area. Explore:

- Whether HAL setup/teardown can be collapsed into simpler state machines.
- Whether the render callback context and its supporting types carry responsibilities that overlap with the pipeline itself.
- Whether shared memory capture and the main render path share code that could be unified.

### 4. UI Decomposition

The UI is the largest area by line count. Explore:

- Whether views are directly calling service-layer APIs rather than going through view models.
- Whether view helpers and shared components are pulling their weight or can be inlined.
- Whether state derived at view layer (computed colours, formatting) should live in pure domain types instead.

### 5. Cross-Feature Duplication

Feature groups are self-contained, which is good for independence but can lead to repeated patterns. Explore:

- Whether device-change detection logic is duplicated across the device, pipeline, and app layers.
- Whether error handling patterns are reimplemented per feature rather than shared.
- Whether constants and configuration are centralised or scattered.

### 6. Test Coverage Balance

Overall ratio is healthy but distribution is uneven. Explore:

- Which modules have high source-to-test ratios and whether that reflects difficulty or neglect.
- Whether test helpers and fixtures can be shared across feature groups to reduce test boilerplate.
- Whether pure types that are easy to test are actually being tested, or whether only the service layer gets coverage.

## Benchmark Targets

Based on the comparison projects, rough targets to aim for during refactoring:

- Radioform achieves a similar feature set in ~8k lines of Swift (plus C++ DSP). It pays for fewer abstractions but also has no tests.
- FineTune has more features (per-app volume, AutoEQ, Bluetooth, DDC) at ~18k lines. Equaliser's 14k lines for fewer features suggests room to tighten.
- A reasonable target might be **reducing source lines by 10–15%** (to around 12k) without losing functionality or test coverage, primarily by collapsing abstractions that don't carry their weight and moving logic closer to where it's used.