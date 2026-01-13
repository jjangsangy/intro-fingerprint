# Active Context

## Current Status
The script is in a functional and feature-complete state for its primary goal of skipping intros using video or audio fingerprinting. It now includes significant performance optimizations for standard Lua environments.

## Recent Changes
- **FFT Performance Optimization (Non-LuaJIT)**: Optimized the standard Lua fallback path for audio fingerprinting, achieving a ~2.5x speedup. Changes include zero-allocation processing with reusable buffers, precomputed trigonometric and bit-reversal lookup tables, and an optimized in-place Cooley-Tukey algorithm.
- **DevContainer Integration**: Added a VS Code DevContainer (Ubuntu 24.04) with pre-installed `mpv`, `ffmpeg`, and automated environment setup (symlinking scripts and config). Fixed hardware-related errors in the container by adding software rendering libraries (`mesa-utils`, `libgl1`) and configuring `mpv.conf` to use headless-friendly defaults (`ao=null`).
- **Custom MPV-LuaJIT Build**: Implemented a custom build of `mpv` (v0.38.0) with LuaJIT enabled inside the devcontainer. This provides a high-performance environment for testing the script's FFI paths. The build is integrated into the Dockerfile and co-exists with the system `mpv` as `/usr/local/bin/mpv-luajit`.
- **Ubuntu 24.04 Upgrade**: Upgraded the devcontainer base image from 22.04 to 24.04 to satisfy modern dependency requirements (Wayland 1.21+, modern Libplacebo/FFmpeg) for building recent `mpv` versions.
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
- **FFT Implementation**: Supports three tiers of performance:
    1.  **FFTW3 (FFI)**: Highest performance using the external C library.
    2.  **Stockham Radix-4 (FFI)**: High performance fallback for LuaJIT when FFTW3 is missing.
    3.  **Optimized Cooley-Tukey (Standard Lua)**: Optimized fallback for builds without LuaJIT, using precomputed tables and zero-allocation buffers.
- **Search Logic**: Video uses a centered expanding window; Audio uses **concurrent linear scan** with chunked segments and ordered result processing.

## Next Steps
- Verify macOS `libfftw3f.dylib` on real hardware.
- Potentially add support for persistent fingerprint databases (instead of temp files).
- Improve error messages for missing FFmpeg or invalid paths.
- Explore automatic skip (without manual keybind) on file load.
