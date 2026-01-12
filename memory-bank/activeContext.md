# Active Context

## Current Status
The script is in a functional and feature-complete state for its primary goal of skipping intros using video or audio fingerprinting.

## Recent Changes
- **DevContainer Integration**: Added a VS Code DevContainer (Ubuntu 22.04) with pre-installed `mpv`, `ffmpeg`, and automated environment setup (symlinking scripts and config).
- **AnyLinux Compatibility**: Updated the Linux build process to use `manylinux2014` (CentOS 7 base) for maximum binary compatibility across distributions.
- **macOS M-series Support**: Added experimental cross-compilation for Apple Silicon (ARM64) to the Dockerfile using `zig cc`.
- **UX Update**: Swapped default key bindings. Audio skip is now the primary method (`Ctrl+s`) due to speed, while Video skip (`Ctrl+Shift+s`) is the robust fallback.
- **Configuration**: Made key bindings fully configurable in `intro-fingerprint.conf`.
- **Refactored Audio Scanning**: Implemented concurrent linear scan with chunked segments and global offset histogram matching. Replaced probabilistic sub-sampling to ensure 100% coverage while maintaining performance.
- **Implemented Concurrency**: Parallelized audio scanning using a worker pool of FFmpeg subprocesses.
- **Improved Skip Reliability**: Added match ratio filtering and high-confidence optimal stopping thresholds to eliminate false positives.
- **Robust Resource Management**: Documented and verified the `abort_scan` mechanism using `mp.abort_async_command` to ensure no orphan processes remain on file close.

## Current Focus
- User feedback and stability improvements.
- Verifying experimental macOS support.

## Active Decisions
- **FFT Implementation**: Currently supports both a fallback Stockham Radix-4 (FFI) and a high-performance FFTW3 library via FFI.
- **Search Logic**: Video uses a centered expanding window; Audio uses **concurrent linear scan** with chunked segments and ordered result processing.

## Next Steps
- Verify macOS `libfftw3f.dylib` on real hardware.
- Potentially add support for persistent fingerprint databases (instead of temp files).
- Improve error messages for missing FFmpeg or invalid paths.
- Explore automatic skip (without manual keybind) on file load.
