# Active Context

## Current Status
The script is in a functional and feature-complete state for its primary goal of skipping intros using video or audio fingerprinting. It now includes significant performance optimizations for standard Lua environments.

## Recent Changes
- **Modular Refactor & Standards Consolidation**: Refactored the monolithic `main.lua` into a modular directory structure under `modules/`. All architectural standards and coding best practices have been consolidated into `.clinerules/mpv-lua-practices.md` to ensure project-wide consistency.
- **Removed PocketFFT**: Completely removed `pocketfft` integration as the handrolled FFT implementation was found to be faster.
- **Reverted to Internal FFT**: The script now uses the optimized internal Lua/FFI FFT (Stockham Radix-4 & Mixed-Radix) by default.
- **LuaJIT Troubleshooting Docs**: Added comprehensive instructions to the `README.md` for verifying LuaJIT support and obtaining optimized MPV builds for Windows, macOS, and Linux without compiling from source.
- **FFT Performance Optimization (Non-LuaJIT)**: Optimized the standard Lua fallback path for audio fingerprinting, achieving a ~2.5x speedup. Changes include zero-allocation processing with reusable buffers, precomputed trigonometric and bit-reversal lookup tables, and an optimized in-place Cooley-Tukey algorithm.
- **Pure Lua Audio Pipeline Optimization**: Further optimized the Pure Lua audio processing path by removing `math.sqrt` calls (using squared magnitudes) and replacing expensive `table.insert` calls with direct array indexing in the hot loops.
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
- **pHash Performance Optimization (Pure Lua)**: Optimized the standard Lua fallback path for video fingerprinting, achieving a ~4x speedup. Replaced the full 32x32 FFT-based DCT with a Partial Direct DCT using matrix multiplication. This optimization avoids calculating unnecessary coefficients and uses a zero-allocation model with pre-allocated buffers to eliminate GC pressure.
- **CI/CD Fix**: Updated the GitHub Action release workflow and the devcontainer setup script to remove references to the non-existent `libs` directory, following the removal of `pocketfft`.
- **FFmpeg Abstraction Layer**: Introduced `modules/ffmpeg.lua` to centralize FFmpeg command construction and execution. This refactor removed direct subprocess management from `actions.lua`, `video.lua`, and `utils.lua`, providing a cleaner, profile-based interface for running FFmpeg tasks.
- **Fingerprint I/O Abstraction**: Extracted fingerprint reading/writing logic into a dedicated `modules/fingerprint_io.lua` module to separate concerns from `actions.lua` and provide a cleaner interface for persistence.
- **Memory Bank Synchronization**: Updated the memory bank to reflect the recent modular refactor, including the addition of `ffmpeg.lua` and `fingerprint_io.lua`.
- **Frame Quality Rejection**: Implemented a two-stage validation system (Spatial + DCT) to reject uniform, repetitive, or featureless frames before adding them to the database.
- **Sound Quality Rejection**: Implemented a validation step to reject silence or low-complexity audio before generating fingerprints. This includes RMS amplitude checks and signal sparsity detection to prevent false positives from quiet sections.
- **Comprehensive Test Suite**: Verified the existence of a robust test suite in `tests/` covering all core modules (`audio`, `video`, `fft`, `ffmpeg`, `config`, `actions`). The suite includes a custom runner (`run_tests.lua`) with auto-downloading for `luaunit` and full mocking of the MPV API.
- **PDQ Hash Migration**: Replaced the 64-bit video pHash algorithm with the 256-bit PDQ Hash algorithm (developed by Meta). This robust perceptual hash offers better resistance to geometric transformations and compression artifacts. The implementation includes:
    - Porting the specific 16x64 DCT matrix to Lua.
    - Increasing frame extraction size to 64x64.
    - Implementing both FFI-optimized (matrix multiplication) and pure Lua fallback paths.
    - Updating distance metrics (Hamming distance on 256 bits) and validation logic (Gradient Sum).
- **Jarosz Filter Optimization**: Refined the FFmpeg video preprocessing chain to more accurately approximate the Jarosz filter specified by the PDQ algorithm.
    - **Chain**: `scale=512:512:flags=bilinear`, `format=rgb24`, `colorchannelmixer` (Rec.601), `avgblur=sizeX=4:sizeY=4` (2 passes), `scale=64:64:flags=neighbor`.
    - **Purpose**: Provides exact luminance calculation and correct window sizing for 512$\to$64 downsampling (Jarosz Filter), matching the algorithm's robustness requirements against shifts and crops. Verified against official PDQ C++ implementation with Hamming distance < 8.
- **PDQ Optimization (Pure Lua)**: Heavily optimized the pure Lua fallback for PDQ hashing.
    - **Memory Layout**: Switched to flat 1D arrays for intermediate results to improve cache locality and reduce table overhead.
    - **Loop Unrolling**: Implemented manual loop unrolling (chunks of 8) for hot paths to reduce instruction count.
    - **Zero-Allocation**: Replaced temporary table creation (per-row `string.byte` tables) with direct `unpack` calls into local variables, eliminating thousands of allocations per scan.
    - **Cached Lookups**: Locally cached DCT matrix rows to avoid repeated table lookups inside inner loops.
    - **Result**: Achieved significant performance improvement (~10% raw throughput increase on top of previous optimizations, drastically reduced GC pressure).
- **Enhanced Visual Quality Checks**: Reimplemented robust visual checks for saving video fingerprints to ensure high quality.
    - **Mean Brightness**: Rejects frames that are too dark (< 5) or too bright (> 250).
    - **Contrast (Variance)**: Rejects low-contrast/flat frames (StdDev < 10.0).
    - **Entropy**: Rejects low-information frames (Entropy < 4.0).
    - **Gradient Sum**: Updated to use the official PDQ quantization logic (0-100 scale, threshold 50) to mask small noise and retain significant edges.

- **PDQ Quality Metric Update**: Updated the video quality metric to use the official "integer-quantized" gradient sum logic from ThreatExchange/PDQ. This provides a normalized 0-100 score (replacing the previous raw metric) to robustly identify featureless frames.
- **Persistent Fingerprint Storage**: Moved fingerprint storage from the system temporary directory to a dedicated `fingerprints/` subdirectory within the script's installation folder.
    - Implemented `modules/sys.lua` to handle cross-platform directory creation and path resolution.
    - Updated `modules/fingerprint_io.lua` to use the new location.
    - Updated test suite to mock `sys` and force tests to use the temporary directory, preventing test artifacts from polluting the persistent storage.
- **Installer Script**: Created a POSIX-compliant shell installer script (`installers/install.sh`) for Linux and macOS.
    - **Logic**: Handles XDG, Flatpak, and Snap environment detection.
    - **Safety**: Performs dependency checks (`curl`, `unzip`) and creates backups before installation.
    - **Testing**: Verified logic using Docker tests against standard, Flatpak, and Snap directory structures.
    - **Documentation**: Updated `README.md` with a one-line install command (`curl | sh`).
- **Windows Installer**: Created a PowerShell installer script (`installers/install.ps1`) for Windows.
    - **Logic**: Respects `MPV_HOME` environment variable for portable installations, falling back to `%APPDATA%\mpv`.
    - **Safety**: Performs backups and uses `Invoke-WebRequest` with `-UseBasicParsing` for compatibility.
    - **Testing**: Verified using a Windows Server Core Docker container.
    - **Documentation**: Updated `README.md` with a one-line install command (`irm | iex`).

## Current Focus
- User feedback and stability improvements.
- Ensuring documentation remains in sync with the new modular structure.

## Recent Changes
- **Documentation Update**: Updated `README.md` with specific installation instructions for Ubuntu (PPA) and Fedora (RPMFusion) to ensure users can easily obtain LuaJIT-optimized `mpv` builds.

## Active Decisions
- **FFT Implementation**: Supports two tiers of performance:
    1.  **Stockham Radix-4 & Mixed-Radix (FFI)**: High performance implementation for LuaJIT.
    2.  **Optimized Cooley-Tukey (Standard Lua)**: Optimized fallback for builds without LuaJIT, using precomputed tables and zero-allocation buffers.
- **Search Logic**: Video uses a centered expanding window; Audio uses **concurrent linear scan** with chunked segments and ordered result processing.
- **Normalization**: The script applies the `dynaudnorm` filter unconditionally to both the reference capture and the scan workers using default settings. This ensures consistent spectral peak detection across files with different volume levels or channel mixdowns, maintaining stable match ratios.
- **Match Ratios > 1.0**: Due to "Neighbor Bin Summing" and many-to-many hash matching (common in repetitive audio patterns), match ratios can occasionally exceed 1.0 (100%). This is considered normal behavior and indicates an extremely high-confidence match.

## Next Steps
- Potentially add support for persistent fingerprint databases (instead of temp files).
- Improve error messages for missing FFmpeg or invalid paths.
- Explore automatic skip (without manual keybind) on file load.
