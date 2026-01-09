# Active Context

## Current Status
The script is in a functional and feature-complete state for its primary goal of skipping intros using video or audio fingerprinting.

## Recent Changes
- **Refactored Audio Scanning**: Implemented probabilistic sub-sampling with bursts and global offset histogram matching.
- **Implemented Concurrency**: Parallelized audio scanning using a worker pool of FFmpeg subprocesses.
- **Improved Skip Reliability**: Added match ratio filtering and high-confidence optimal stopping thresholds to eliminate false positives.
- **Cleanup**: Removed obsolete linear scan logic and configurations.
- Successfully implemented MinGW-w64 cross-compilation for FFTW in `Dockerfile`.

## Current Focus
- Stabilizing the new probabilistic audio scan logic across different media types.

## Active Decisions
- **FFT Implementation**: Currently supports both a fallback Stockham Radix-4 (FFI) and a high-performance FFTW3 library via FFI.
- **Search Logic**: Video uses a centered expanding window; Audio uses **probabilistic sub-sampling** with ordered result processing.

## Next Steps
- Potentially add support for persistent fingerprint databases (instead of temp files).
- Improve error messages for missing FFmpeg or invalid paths.
- Explore automatic skip (without manual keybind) on file load.
