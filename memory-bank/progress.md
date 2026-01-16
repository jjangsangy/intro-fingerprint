# Progress

## Completed Features
- [x] **Robust Library Discovery**: Implemented resilient cross-platform PocketFFT discovery (Local `libs/` -> System fallback).
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
- [x] **PocketFFT Integration**: Implemented a lightweight, header-only library. Created a C-compatible wrapper for LuaJIT FFI.
- [x] **Renamed to PocketFFT**: Completed a total renaming of the build artifacts and exported functions to `pocketfft`.
- [x] **Migrated main.lua**: Updated script logic to use PocketFFT libraries and naming.
- [x] **Dockerized Build System**: Multi-stage Dockerfile for **PocketFFT shim** (Linux, Windows, and macOS M-series cross-compilation). Optimized Linux build using `manylinux2014` for broad compatibility.
- [x] **DevContainer**: VS Code DevContainer for Ubuntu 24.04 with a custom-built `mpv-luajit` (v0.38.0) environment. Supports both X11 and Wayland (`wlshm`) video outputs for compatibility with WSLg.
- [x] **Code Quality**: Refactored monolithic script to reduce branching and indentation depth using guard clauses.

## In Progress
- [x] Initial Memory Bank Documentation.
- [x] Expanded troubleshooting documentation for LuaJIT support.

## Future Roadmap
- [ ] **Migrate `main.lua` to PocketFFT**: Update the main script to utilize the new `pocketfft` library naming and API.
- [ ] **Persistent Fingerprints**: Moving beyond temp files to a user-specified database or local directory.
- [ ] **Automatic Scanning**: Auto-scan for matches when a new file starts.
- [ ] **UI/OSD Improvements**: Better visual feedback for scan progress and match confidence.
