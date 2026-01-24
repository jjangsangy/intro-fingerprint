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
- [x] **Video Fingerprinting**: PDQ Hash implementation for robust 256-bit frame matching.
- [x] **Jarosz Filter**: Implemented Jarosz filter chain for robust video preprocessing (Verified correct against official PDQ C++ implementation).
- [x] **Audio Fingerprinting**: Constellation hashing with FFT-based peak detection.
- [x] **Async Processing**: Use of MPV coroutines and async subprocesses.
- [x] **Configurable Options**: Exposure of thresholds, windows, and processing flags via MPV options.
- [x] **FFI Optimization**: Zero-allocation (or low-allocation) paths for data-intensive operations.
- [x] **Standard Lua Optimization**: Significant performance gains for non-LuaJIT environments:
    - ~2.5x speedup for audio (FFT optimization).
    - Reduced function call overhead in audio pipeline (Pure Lua).
    - ~4x speedup for video (Partial Direct DCT pHash optimization).
- [x] **FFT Implementation**: Reverted to optimized internal Lua/FFI implementation as it outperformed PocketFFT.
- [x] **DevContainer**: VS Code DevContainer for Ubuntu 24.04 with a custom-built `mpv-luajit` (v0.38.0) environment. Supports both X11 and Wayland (`wlshm`) video outputs for compatibility with WSLg.
- [x] **Code Quality**: Refactored monolithic script to reduce branching and indentation depth using guard clauses.
- [x] **CI/CD Fix**: Fixed GitHub Action and devcontainer setup script by removing `libs` references after `pocketfft` removal.
- [x] **Fingerprint I/O Abstraction**: Extracted file operations into `modules/fingerprint_io.lua` for clean separation of concerns.
- [x] **FFmpeg Abstraction Layer**: Refactored codebase to use a dedicated `modules/ffmpeg.lua` for all external process interactions.
- [x] **Lua Modules & Standards**: Successfully refactored the project into a modular directory structure under `modules/`. Consolidated all architectural standards and coding best practices into `.clinerules/mpv-lua-practices.md` for consistent project enforcement.
- [x] **Frame Quality Rejection**: Implemented a two-stage validation system (Spatial + DCT) to reject low-quality frames.
- [x] **Sound Quality Rejection**: Added RMS and sparsity validation for audio fingerprints, plus "low complexity" rejection for samples with too few hashes.
- [x] **Comprehensive Test Suite**: Implemented a full test suite covering audio/video processing, FFI/Lua FFT paths, FFmpeg command construction, and configuration, including a custom test runner with mocking support.
- [x] **Modular Architecture Documentation**: Updated memory bank to include detailed module responsibilities and project structure.
- [x] **PDQ Optimization**: Optimized pure Lua implementation to approach pHash performance parity.
- [x] **Installer Scripts**: Write installer scripts for Win/MacOS/Linux
  - [x] **Linux/macOS**: Created POSIX-compliant shell script with XDG/Flatpak/Snap support.
  - [x] **Windows**: Created PowerShell installer script with Docker tests.

## In Progress
*(No active tasks)*

## Future Roadmap
- [ ] **Audio Fingerprint Compression**: Improve fingerprint density and retreival
  - [ ] **Sub Sampling and Density Control**: Picker only chooses top N peaks per segment, keep raising threshold until it is met
  - [ ] **Bit Packing**: Keep storage low by storing peaks as a 64-bit integer
  - [ ] **Inverted Index**: Only process files that have share the the hashes
- [ ] **Persistent Fingerprints**: Moving beyond temp files to a user-specified database or local directory.
  - [x] **Detect Bad Fingerprints**: Pre-filter low entropy images using DCT energy and audio with long silences/low complexity.
  - [ ] **Add Fingerprint Tagging**: Save metadata about media into fingerprint file for better cataloging.
  - [ ] **Removal Mechanism**: Have the ability to remove specific fingerprints if they are causing mismatches.
  - [ ] **Logging Fingerprint Match**: Log which fingerprint from which file is being matched.
  - [ ] **Deduplication**: Ensure we don't save duplicate fingerprints for the same section multiple times.
  - [x] **Move Fingerprints**: Move the fingerprint directory from temp to somewhere permanent.
- [ ] **Automatic Scanning**: Auto-scan for matches when a new file starts.
- [ ] **UI/OSD Improvements**: Better visual feedback for scan progress and match confidence.
- [ ] **Fingerprint Interoperability**: Ensure both lua and luajit fingerprints can be used interchangeably.
