# Progress

## Completed Features
- [x] **Concurrent Linear Audio Scanning**: Replaced probabilistic bursts with a chunked linear scan for 100% coverage and maximum reliability.
- [x] **Concurrent Execution**: Parallel FFmpeg worker pool for multi-core audio processing.
- [x] **Offset Histogram Matching**: Robust time-offset clustering logic for precise sync.
- [x] **Ratio-Based Filtering**: Density-based confidence scoring to eliminate false positives.
- [x] **Matching Robustness**: Implemented **Neighbor Bin Summing** to prevent "bin splitting" failures and improve reliability under timing jitter.
- [x] **Audio Normalization**: Added volume-invariant fingerprinting using FFmpeg's `dynaudnorm` (default settings) to fix inconsistent match ratios across different file encodes while maintaining performance.
- [x] **Optimal Stopping**: Gradient-based early termination for efficient scanning.
- [x] **Aligned Debug Tables**: Converted per-segment scanning logs into an aligned table format for better readability.
- [x] **Video Fingerprinting**: pHash implementation for frame matching.
- [x] **Audio Fingerprinting**: Constellation hashing with FFT-based peak detection.
- [x] **Async Processing**: Use of MPV coroutines and async subprocesses.
- [x] **Configurable Options**: Exposure of thresholds, windows, and processing flags via MPV options.
- [x] **FFI Optimization**: Zero-allocation (or low-allocation) paths for data-intensive operations.
- [x] **Standard Lua Optimization**: Significant performance gains for non-LuaJIT environments:
    - ~2.5x speedup for audio (FFT optimization).
    - ~4x speedup for video (Partial Direct DCT pHash optimization).
- [x] **FFT Implementation**: Reverted to optimized internal Lua/FFI implementation as it outperformed PocketFFT.
- [x] **DevContainer**: VS Code DevContainer for Ubuntu 24.04 with a custom-built `mpv-luajit` (v0.38.0) environment. Supports both X11 and Wayland (`wlshm`) video outputs for compatibility with WSLg.
- [x] **Code Quality**: Refactored monolithic script to reduce branching and indentation depth using guard clauses.
- [x] **CI/CD Fix**: Fixed GitHub Action and devcontainer setup script by removing `libs` references after `pocketfft` removal.
- [x] **Lua Modules & Standards**: Successfully refactored the project into a modular directory structure under `modules/`. Consolidated all architectural standards and coding best practices into `.clinerules/mpv-lua-practices.md` for consistent project enforcement.

## In Progress
- [x] Initial Memory Bank Documentation.
- [x] Expanded troubleshooting documentation for LuaJIT support.

## Future Roadmap
- [ ] **Persistent Fingerprints**: Moving beyond temp files to a user-specified database or local directory.
  - [ ] **Detect Bad Fingerprints**: Ensure uniform frames and audio with long silences are rejected as fingerprints.
  - [ ] **Add Fingerprint Tagging**: Save metadata about media into fingerprint file for better cataloging.
  - [ ] **Removal Mechanism**: Have the ability to remove specific fingerprints if they are causing mismatches.
  - [ ] **Logging Fingerprint Match**: Log which fingerprint from which file is being matched.
  - [ ] **Deduplication**: Ensure we don't save duplicate fingerprints for the same section multiple times.
- [ ] **Automatic Scanning**: Auto-scan for matches when a new file starts.
- [ ] **UI/OSD Improvements**: Better visual feedback for scan progress and match confidence.
- [ ] **Fingerprint Interoperability**: Ensure both lua and luajit fingerprints can be used interchangeably.
- [ ] **Add Tests**: Test critical paths and set up a test runner in CI
