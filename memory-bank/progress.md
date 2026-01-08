# Progress

## Completed Features
- [x] **Video Fingerprinting**: dHash implementation for frame matching.
- [x] **Audio Fingerprinting**: Constellation hashing with FFT-based peak detection.
- [x] **Async Processing**: Use of MPV coroutines and async subprocesses.
- [x] **Configurable Options**: Exposure of thresholds, windows, and processing flags via MPV options.
- [x] **FFI Optimization**: Zero-allocation (or low-allocation) paths for data-intensive operations.
- [x] **FFTW Integration**: Ability to use `libfftw3` for faster FFTs.

## In Progress
- [x] Initial Memory Bank Documentation.

## Future Roadmap
- [ ] **Persistent Fingerprints**: Moving beyond temp files to a user-specified database or local directory.
- [ ] **Automatic Scanning**: Auto-scan for matches when a new file starts.
- [ ] **UI/OSD Improvements**: Better visual feedback for scan progress and match confidence.
