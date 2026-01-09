# Active Context

## Current Status
The script is in a functional and feature-complete state for its primary goal of skipping intros using video or audio fingerprinting.

## Recent Changes
- Initial project analysis and documentation (Memory Bank creation).
- Implementation of a Docker-based multi-stage build system for `libfftw3f` shared objects.
- Replaced Windows FFTW3 compilation with pre-compiled binaries in `Dockerfile` to fix build failures.

## Current Focus
- Maintenance and final verification of the build system.

## Active Decisions
- **FFT Implementation**: Currently supports both a fallback Stockham Radix-4 (FFI) and a high-performance FFTW3 library via FFI.
- **Search Logic**: Video uses a centered expanding window; Audio uses a linear scan with early exit based on score gradient.

## Next Steps
- Potentially add support for persistent fingerprint databases (instead of temp files).
- Improve error messages for missing FFmpeg or invalid paths.
- Explore automatic skip (without manual keybind) on file load.
