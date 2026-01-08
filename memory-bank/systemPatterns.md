# System Patterns

## Architecture Overview
The script is a monolithic Lua script (`main.lua`) that integrates with MPV. It relies on external processes (`ffmpeg`) for heavy lifting (decoding) and internal FFI logic for data processing.

## Key Algorithms

### 1. Video Fingerprinting: Gradient Hash (dHash)
- **Extraction**: Resizes frame to 9x8 grayscale using FFmpeg `vf=scale=9:8,format=gray`.
- **Hashing**: Compares adjacent pixels (9 horizontal pixels lead to 8 comparison bits per row).
- **Result**: A 64-bit integer (8 bytes).
- **Matching**: Hamming distance. A distance $\le 12$ (configurable) is considered a match.
- **Search Strategy**: Sliding window centered on the original timestamp, expanding outwards to balance speed and accuracy.

### 2. Audio Fingerprinting: Constellation Hashing
- **Extraction**: FFmpeg extracts raw PCM (`s16le`, mono, 11025Hz).
- **Processing**:
    - FFT (Stockham Radix-4 or FFTW3) converts time-domain to frequency-domain.
    - Peak detection identifies the most prominent frequencies.
- **Hashing**: Pairs of peaks $[f1, f2, \Delta t]$ are combined into a unique 32-bit hash.
- **Matching**: Uses a histogram of time offsets. The offset with the highest frequency of matches indicates the sync point.
- **Search Strategy**: Linear scan from the beginning of the file (up to a limit), as audio decoding is relatively cheap.

## Performance Patterns
- **LuaJIT FFI**: Critical for performance. Uses C-structs and arrays to avoid Lua garbage collection overhead when handling millions of data points.
- **Async Subprocesses**: `mp.command_native_async` and coroutines ensure the MPV interface remains responsive during scans.
- **Memory Management**: Pre-allocated FFI buffers for FFT and hashing.

## Data Flow
1. **User Input** (Keybind) $\rightarrow$ **MPV Command**
2. **FFmpeg Subprocess** $\rightarrow$ **Raw Data Pipe (stdout)**
3. **FFI Logic** $\rightarrow$ **Hash Generation & Matching**
4. **MPV Property Set** (`time-pos`) $\rightarrow$ **Seek**
