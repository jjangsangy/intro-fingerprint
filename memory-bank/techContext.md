# Tech Context

## Stack
- **Language**: Lua 5.1 / LuaJIT 2.1+
- **Host**: MPV Media Player (v0.33+, v0.38+ recommended)
- **Dependency**: FFmpeg (Must be in PATH)

## Environment Constraints
- **Dual-Path Execution**:
    - **LuaJIT FFI**: Preferred. Uses C-structs/arrays and `bit` library for max speed.
    - **Standard Lua**: Fallback. Uses optimized pure Lua algorithms (tables, arithmetic bit-ops).
- **FileSystem**: Requires write access to system `TEMP` (or configured directory) for intermediate fingerprint storage.
- **Operating System**: Cross-platform (Windows, Linux, macOS).

## Testing Strategy
- **Framework**: `luaunit`.
- **Mocking**: Full mock of `mp` API (`tests/mocks.lua`) allows running tests via standalone `lua` binary, without an MPV instance.
- **Coverage**:
    - **Unit**: FFT correctness (Sine wave checks), PDQ hash consistency, Hamming distance logic.
    - **Integration**: FFmpeg command generation, Action workflows (Save/Skip).
    - **Performance**: `tests/test_fft_perf.lua` verifies FFI vs Lua speedups.

## Development Setup
- **DevContainer**: Ubuntu 24.04 with custom `mpv-luajit` build.
- **Linting**: Lua Language Server.
- **Pre-commit**: Enforces tests and linting before commit.
