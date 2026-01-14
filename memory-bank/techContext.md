# Tech Context

## Technology Stack
- **Language**: Lua (targeted for LuaJIT 2.1+)
- **Host Application**: [MPV Media Player](https://mpv.io/)
- **External Dependencies**:
    - **FFmpeg**: Must be available in the system PATH. Used for frame and audio extraction.
    - **Docker**: Used for cross-compiling the `libfftw3f` shared objects. The build system uses a multi-stage Dockerfile (`manylinux2014` for Linux, Arch for Windows/macOS) to ensure broad compatibility.
    - **DevContainer**: A VS Code DevContainer (Ubuntu 24.04) is available for local development and testing of the MPV environment. It includes a custom-built `mpv-luajit` binary.
- **Libraries**:
    - `ffi`: LuaJIT Foreign Function Interface for C-level performance.
    - `bit`: Lua bitwise operations (provided by LuaJIT).
    - `utils`: MPV utility library.
    - `fftw3f` (Optional): Fast Fourier Transform library for optimized audio processing. Note: On macOS, this is currently supported only on ARM64 (Apple Silicon) architectures.

## Development Environment
- **Operating System**: Windows 10 (based on environment details)
- **Shell**: PowerShell (specified in `.clinerules`)

## Technical Constraints
- **LuaJIT Dependency**: The script heavily utilizes FFI and bitwise operations. While fallback paths exist for standard Lua, an optimized in-place Cooley-Tukey implementation with precomputed tables provides a ~2.5x speedup over naive Lua code, ensuring the script remains usable in environments without LuaJIT.
- **FFmpeg Path**: FFmpeg must be executable from the command line.
- **File System**: Requires write access to the system temp directory to store fingerprint files.

## Optimization Decisions
- **dHash (9x8)**: Chosen for its speed and invariance to brightness/contrast changes.
- **Audio Normalization**: Uses mandatory `dynaudnorm` to ensure spectral consistency regardless of source volume.
- **Spectrogram Parameters**:
    - Sample Rate: 11025 Hz (sufficient for frequency peaks while minimizing data size).
    - FFT Size: 2048 (balanced frequency resolution).
- **Concurrency**:
    - Default: 4 concurrent FFmpeg workers to utilize multicore CPUs.
- **Planar FFT**: Split-complex layout used in the manual FFT implementation for better cache locality.
