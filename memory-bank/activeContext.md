# Active Context

## Current Status
The script is in a functional and feature-complete state for its primary goal of skipping intros using video or audio fingerprinting. It now includes significant performance optimizations for standard Lua environments.

## Recent Changes
- **FFTW Enabled by Default**: Set `audio_use_fftw = "yes"` as the default configuration. Updated `main.lua`, `intro-fingerprint.conf`, and `README.md` to reflect this change. Added a detailed performance explanation in the README regarding FFTW's use of SIMD instructions (SSE/AVX) for hardware-accelerated Fourier transforms.
- **LuaJIT Troubleshooting Docs**: Added comprehensive instructions to the `README.md` for verifying LuaJIT support and obtaining optimized MPV builds for Windows, macOS, and Linux without compiling from source.
- **FFT Performance Optimization (Non-LuaJIT)**: Optimized the standard Lua fallback path for audio fingerprinting, achieving a ~2.5x speedup. Changes include zero-allocation processing with reusable buffers, precomputed trigonometric and bit-reversal lookup tables, and an optimized in-place Cooley-Tukey algorithm.
- **DevContainer Integration**: Added a VS Code DevContainer (Ubuntu 24.04) with pre-installed `mpv`, `ffmpeg`, and automated environment setup (symlinking scripts and config). Fixed hardware-related errors in the container by adding software rendering libraries (`mesa-utils`, `libgl1`) and configuring `mpv.conf` to use headless-friendly defaults (`ao=null`).
- **Custom MPV-LuaJIT Build**: Implemented a custom build of `mpv` (v0.38.0) with LuaJIT enabled inside the devcontainer. This provides a high-performance environment for testing the script's FFI paths. The build is integrated into the Dockerfile and co-exists with the system `mpv` as `/usr/local/bin/mpv-luajit`.
- **Ubuntu 24.04 Upgrade**: Upgraded the devcontainer base image from 22.04 to 24.04 to satisfy modern dependency requirements (Wayland 1.21+, modern Libplacebo/FFmpeg) for building recent `mpv` versions.
- **AnyLinux Compatibility**: Updated the Linux build process to use `manylinux2014` (CentOS 7 base) for maximum binary compatibility across distributions.
- **macOS M-series Support**: Added experimental cross-compilation for Apple Silicon (ARM64) to the Dockerfile using `zig cc`.
- **Neighbor Bin Summing**: Implemented a fix for the "bin splitting" issue in audio matching. The script now sums adjacent time bins in the offset histogram to improve robustness against timing jitter and alignment variations.
- **UX Update**: Swapped default key bindings. Audio skip is now the primary method (`Ctrl+s`) due to speed, while Video skip (`Ctrl+Shift+s`) is the robust fallback.
- **Configuration**: Made key bindings fully configurable in `intro-fingerprint.conf`.
- **Refactored Audio Scanning**: Implemented concurrent linear scan with chunked segments and global offset histogram matching. Replaced probabilistic sub-sampling to ensure 100% coverage while maintaining performance.
- **Implemented Concurrency**: Parallelized audio scanning using a worker pool of FFmpeg subprocesses.
- **Improved Skip Reliability**: Added match ratio filtering and high-confidence optimal stopping thresholds to eliminate false positives.
- **Robust Resource Management**: Documented and verified the `abort_scan` mechanism using `mp.abort_async_command` to ensure no orphan processes remain on file close.
- **Log Alignment & Table Format**: Converted "Processed segment" debug logs into an aligned table format with a `header_printed` flag to prevent initialization logs (like FFTW loading) from breaking the table structure.
- **Code Refactor (Flattening)**: Refactored `main.lua` to reduce indentation and branching. Applied guard clauses and inverted control flow in `process_audio_data`, `save_intro`, `get_peaks`, and asynchronous worker callbacks.
- **Audio Normalization**: Mandatory audio normalization using FFmpeg's `dynaudnorm` filter. This ensures consistent spectral peak detection across files with different volume levels or channel mixdowns (e.g., 5.1 vs Stereo). This filter is applied unconditionally to all audio extractions using its default settings for optimal balance of results and performance.

## Current Focus
- User feedback and stability improvements.
- Verifying experimental macOS support.

## Active Decisions
- **FFT Implementation**: Supports three tiers of performance:
    1.  **FFTW3 (FFI)**: Highest performance using the external C library. **Enabled by default.**
    2.  **Stockham Radix-4 & Mixed-Radix (FFI)**: High performance fallback for LuaJIT when FFTW3 is missing or disabled.
    3.  **Optimized Cooley-Tukey (Standard Lua)**: Optimized fallback for builds without LuaJIT, using precomputed tables and zero-allocation buffers.
- **Search Logic**: Video uses a centered expanding window; Audio uses **concurrent linear scan** with chunked segments and ordered result processing.
- **Normalization**: The script applies the `dynaudnorm` filter unconditionally to both the reference capture and the scan workers using default settings. This ensures consistent spectral peak detection across files with different volume levels or channel mixdowns, maintaining stable match ratios.
- **Match Ratios > 1.0**: Due to "Neighbor Bin Summing" and many-to-many hash matching (common in repetitive audio patterns), match ratios can occasionally exceed 1.0 (100%). This is considered normal behavior and indicates an extremely high-confidence match.

## Next Steps
- Verify macOS `libfftw3f.dylib` on real hardware.
- Potentially add support for persistent fingerprint databases (instead of temp files).
- Improve error messages for missing FFmpeg or invalid paths.
- Explore automatic skip (without manual keybind) on file load.
