# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

**See `AGENTS.md` for complete documentation** including:
- Build and test commands
- Project structure
- Code style guidelines
- Architecture notes (dual HAL, ring buffer, manual rendering)
- Core Audio learnings and error codes

## Quick Reference

```bash
cd EqualizerApp
swift build        # Build
swift test         # Test
swift run          # Run
```

macOS menu bar equalizer: Input Device -> Ring Buffer -> EQ (up to 64 bands) -> Output Device

Key files: `EqualizerStore.swift` (state), `RenderPipeline.swift` (audio orchestration), `EQConfiguration.swift` (band settings).
