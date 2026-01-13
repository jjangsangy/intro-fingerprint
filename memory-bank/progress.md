# Progress

## Completed Features
- [x] **Robust Library Discovery**: Implemented resilient cross-platform FFTW3 discovery (Local `libs/` -> System fallback).
- [x] **Concurrent Linear Audio Scanning**: Replaced probabilistic bursts with a chunked linear scan for 100% coverage and maximum reliability.
- [x] **Concurrent Execution**: Parallel FFmpeg worker pool for multi-core audio processing.
- [x] **Offset Histogram Matching**: Robust time-offset clustering logic for precise sync.
- [x] **Ratio-Based Filtering**: Density-based confidence scoring to eliminate false positives.
- [x] **Optimal Stopping**: Gradient-based early termination for efficient scanning.
- [x] **Video Fingerprinting**: dHash implementation for frame matching.
- [x] **Audio Fingerprinting**: Constellation hashing with FFT-based peak detection.
- [x] **Async Processing**: Use of MPV coroutines and async subprocesses.
- [x] **Configurable Options**: Exposure of thresholds, windows, and processing flags via MPV options.
- [x] **FFI Optimization**: Zero-allocation (or low-allocation) paths for data-intensive operations.
- [x] **Standard Lua Optimization**: Achieved ~2.5x speedup for non-LuaJIT environments via precomputed tables and optimized in-place FFT logic.
- [x] **FFTW Integration**: Ability to use `libfftw3` for faster FFTs.
- [x] **Dockerized Build System**: Multi-stage Dockerfile for `libfftw3f` (Linux, Windows, and macOS M-series cross-compilation from source). Optimized Linux build using `manylinux2014` for broad compatibility.
- [x] **DevContainer**: VS Code DevContainer for Ubuntu 24.04 with a custom-built `mpv-luajit` (v0.38.0) environment. Supports both X11 and Wayland (`wlshm`) video outputs for compatibility with WSLg.

## In Progress
- [x] Initial Memory Bank Documentation.
- [x] Expanded troubleshooting documentation for LuaJIT support.

## Future Roadmap
- [ ] **Persistent Fingerprints**: Moving beyond temp files to a user-specified database or local directory.
- [ ] **Automatic Scanning**: Auto-scan for matches when a new file starts.
- [ ] **UI/OSD Improvements**: Better visual feedback for scan progress and match confidence.
