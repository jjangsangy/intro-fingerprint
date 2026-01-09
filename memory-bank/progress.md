# Progress

## Completed Features
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
- [x] **FFTW Integration**: Ability to use `libfftw3` for faster FFTs.

## In Progress
- [x] Initial Memory Bank Documentation.
- [x] **Dockerized Build System**: Multi-stage Dockerfile for `libfftw3f` (Linux and Windows cross-compilation from source).

## Future Roadmap
- [ ] **Persistent Fingerprints**: Moving beyond temp files to a user-specified database or local directory.
- [ ] **Automatic Scanning**: Auto-scan for matches when a new file starts.
- [ ] **UI/OSD Improvements**: Better visual feedback for scan progress and match confidence.
