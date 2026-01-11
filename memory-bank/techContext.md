# Tech Context

## Technology Stack
- **Language**: Lua (targeted for LuaJIT 2.1+)
- **Host Application**: [MPV Media Player](https://mpv.io/)
- **External Dependencies**:
    - **FFmpeg**: Must be available in the system PATH. Used for frame and audio extraction.
    - **Docker**: Used for cross-compiling the `libfftw3f` shared objects. The build system uses an Arch Linux base to cross-compile for Windows (MinGW-w64) and macOS M-series (`zig cc`).
- **Libraries**:
    - `ffi`: LuaJIT Foreign Function Interface for C-level performance.
    - `bit`: Lua bitwise operations (provided by LuaJIT).
    - `utils`: MPV utility library.
    - `fftw3f` (Optional): Fast Fourier Transform library for optimized audio processing.

## Development Environment
- **Operating System**: Windows 10 (based on environment details)
- **Shell**: PowerShell (specified in `.clinerules`)
- **Package Management**: `uv` for Python-related tools (though not used in this Lua-centric project).

## Technical Constraints
- **LuaJIT Dependency**: The script heavily utilizes FFI and bitwise operations. While fallback paths exist for standard Lua, performance will degrade significantly.
- **FFmpeg Path**: FFmpeg must be executable from the command line.
- **File System**: Requires write access to the system temp directory to store fingerprint files.

## Optimization Decisions
- **dHash (9x8)**: Chosen for its speed and invariance to brightness/contrast changes.
- **Spectrogram Parameters**:
    - Sample Rate: 11025 Hz (sufficient for frequency peaks while minimizing data size).
    - FFT Size: 2048 (balanced frequency resolution).
- **Probabilistic Scanning**:
    - Burst Duration: 12s (covers the default 10s intro clip).
    - Burst Interval: 15s (80% duty cycle for reliable capture).
- **Concurrency**:
    - Default: 4 concurrent FFmpeg workers to utilize multicore CPUs.
- **Planar FFT**: Split-complex layout used in the manual FFT implementation for better cache locality.
