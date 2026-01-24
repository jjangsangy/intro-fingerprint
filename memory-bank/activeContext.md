# Active Context

## Current Status
**Stable / Maintenance Mode**
The script is feature-complete and highly optimized. It successfully handles cross-platform differences (Windows/Linux/macOS), varying MPV environments (LuaJIT vs. Standard Lua), and high-performance requirements.

## Recent Major Milestones

### 1. Architectural Refactor
- **Modularization**: Split monolithic `main.lua` into `modules/` (actions, audio, video, ffmpeg, etc.).
- **Standards**: Enforced strict coding practices (Local Tables, Documentation) via `.clinerules`.
- **Abstraction**: Created `ffmpeg.lua` for command profiling and `fingerprint_io.lua` for storage management.

### 2. Algorithmic Upgrades
- **Video**: Migrated from simple pHash to **PDQ Hash** (Meta's algorithm). Implemented 16x64 DCT matrix logic and Jarosz filter approximation for robust frame matching.
- **Audio**: Implemented **Concurrent Linear Scanning** with global offset histogram matching. Added "Neighbor Bin Summing" to handle timing jitter and `dynaudnorm` for volume invariance.

### 3. Performance Engineering
- **LuaJIT FFI**: Implemented zero-allocation paths using C-structs for FFT and Hash generation.
- **Pure Lua Optimization**: Optimized fallbacks for non-JIT environments (precomputed tables, flat arrays, loop unrolling), achieving ~2.5x speedup in audio and ~4x in video processing.
- **Infrastructure**: Removed `pocketfft` dependency in favor of custom, optimized internal FFT implementations (Stockham/Cooley-Tukey).

### 4. Ecosystem & Tooling
- **DevContainer**: Built a custom Ubuntu 24.04 container with a compiled `mpv-luajit` binary for robust testing.
- **CI/CD**: Added installer scripts (Powershell/Shell) and comprehensive test suites (`tests/`) with full MPV API mocking.

## Active Decisions
- **FFT Strategy**: Maintain two distinct FFT implementations (Stockham FFI for speed, Optimized Cooley-Tukey for compatibility) rather than external dependencies.
- **Search Strategy**: Audio uses concurrent linear scan (100% coverage); Video uses an expanding window centered on the saved timestamp.
- **Storage**: Currently using system temp files for fingerprints. Moving to persistent storage is a future goal.

## Current Focus
- Monitoring stability and user feedback.
- Ensuring documentation stays synchronized with the modular structure.

## Next Steps
- **Persistent Storage**: Move fingerprints from temp to a user-defined database directory.
- **Fingerprint Management**: Add UI/Commands to list and delete saved fingerprints.
- **Auto-Scan**: Implement option to automatically scan for intros when a file loads.
