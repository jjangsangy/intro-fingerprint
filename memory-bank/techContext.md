# Tech Context

## Technology Stack
- **Language**: Lua (targeted for LuaJIT 2.1+)
- **Host Application**: [MPV Media Player](https://mpv.io/)
- **External Dependencies**:
    - **FFmpeg**: Must be available in the system PATH. Used for frame and audio extraction.
    - **DevContainer**: A VS Code DevContainer (Ubuntu 24.04) is available for local development and testing of the MPV environment. It includes a custom-built `mpv-luajit` binary.
- **Libraries**:
    - `mp`: Core MPV API.
    - `mp.utils` (`utils`): MPV utility functions (e.g., subprocesses, path joining).
    - `mp.msg` (`msg`): MPV logging and console output.
    - `mp.options`: MPV configuration and script-opts handling.
    - `ffi`: LuaJIT Foreign Function Interface for C-level performance.
    - `bit`: Lua bitwise operations (provided by LuaJIT).

## Development Environment
- **Operating System**: Windows 10 (based on environment details)
- **Shell**: PowerShell (specified in `.clinerules`)

## Technical Constraints
- **Modular Structure**: The project follows a modular architecture as defined in `.clinerules/mpv-lua-practices.md`. This includes the "Local Table Pattern," "Strict Locals," and a single-responsibility directory structure (`modules/`).
- **LuaJIT Dependency**: The script heavily utilizes FFI and bitwise operations. While fallback paths exist for standard Lua, significant optimizations have been implemented for non-FFI environments:
    - **Audio**: An optimized in-place Cooley-Tukey FFT implementation with precomputed tables provides a ~2.5x speedup over naive Lua code.
    - **Video**: A **Partial Direct DCT** implementation provides a **~4x speedup** for pHash generation by computing only required coefficients and using a zero-allocation buffer model.
- **FFmpeg Path**: FFmpeg must be executable from the command line.
- **File System**: Requires write access to the system temp directory to store fingerprint files.

## Optimization Decisions
- **pHash (32x32 -> 8x8 DCT)**: Chosen for its superior robustness and invariance to brightness/contrast changes.
- **Audio Normalization**: Uses mandatory `dynaudnorm` (default settings) to ensure spectral consistency regardless of source volume.
- **Spectrogram Parameters**:
    - Sample Rate: 11025 Hz (sufficient for frequency peaks while minimizing data size).
    - FFT Size: 2048 (balanced frequency resolution).
- **Concurrency**:
    - Default: 4 concurrent FFmpeg workers to utilize multicore CPUs.
- **Planar FFT**: Split-complex layout used in the manual FFT implementation for better cache locality.
