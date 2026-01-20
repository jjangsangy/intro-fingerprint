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
    - **Audio**: An optimized Stockham FFT implementation with precomputed tables, 1-based indexing, and incremental arithmetic provides a ~4x speedup over naive Lua code (ZFFT).
    - **Video**: A matrix-based **DCT implementation** provides high-performance PDQ Hash generation by computing the 16x16 DCT region directly from the 64x64 input using matrix multiplication.
- **FFmpeg Path**: FFmpeg must be executable from the command line.
- **File System**: Requires write access to the system temp directory to store fingerprint files.

## Project Structure
The project follows a modular structure where `main.lua` orchestrates specialized logic contained within the `modules/` directory.

```text
intro-fingerprint/
├── main.lua                # Orchestrator & entry point
├── intro-fingerprint.conf  # Default configuration file
├── modules/                # Core logic modules
│   ├── actions.lua         # High-level scan/capture handlers
│   ├── audio.lua           # Audio fingerprinting logic
│   ├── config.lua          # Configuration & defaults
│   ├── ffmpeg.lua          # FFmpeg command wrapper
│   ├── fft.lua             # FFT algorithms (Lua & FFI)
│   ├── pdq_matrix.lua      # PDQ Hash DCT matrix constants
│   ├── state.lua           # Shared runtime state
│   ├── ui.lua              # OSD feedback abstraction
│   ├── utils.lua           # Low-level async/FFI utilities
│   └── video.lua           # Video fingerprinting logic
└── memory-bank/            # Project documentation
```

## Testing Strategy
The project maintains a comprehensive test suite in the `tests/` directory, using `luaunit` as the test runner.
- **Framework**: [LuaUnit](https://github.com/bluebird75/luaunit) (automatically downloaded by `run_tests.lua`).
- **Mocking**: The `mp` API (properties, commands, OSD, messages) is fully mocked in `tests/mocks.lua` and `tests/run_tests.lua`, enabling tests to run in a standalone Lua environment without MPV.
- **Coverage**:
    - **Unit Tests**: Cover core algorithms (FFT, PDQ Hash, Hamming distance), validation logic, and utility functions.
    - **Integration Tests**: Verify high-level workflows (capture, scan, skip) and FFmpeg command construction.
- **Execution**: Run via `lua tests/run_tests.lua` (supports standard Lua 5.1+) or `luajit tests/run_tests.lua`.

## Optimization Decisions
- **PDQ Hash (64x64 -> 16x16 DCT)**: Chosen for its superior robustness to geometric distortions and compression artifacts compared to standard pHash.
- **Audio Normalization**: Uses mandatory `dynaudnorm` (default settings) to ensure spectral consistency regardless of source volume.
- **Spectrogram Parameters**:
    - Sample Rate: 11025 Hz (sufficient for frequency peaks while minimizing data size).
    - FFT Size: 2048 (balanced frequency resolution).
- **Concurrency**:
    - Default: 4 concurrent FFmpeg workers to utilize multicore CPUs.
- **Planar FFT**: Split-complex layout used in the manual FFT implementation for better cache locality.
