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
    - Peak detection identifies the most prominent frequencies (top 5 per frame).
- **Hashing**: Pairs of peaks $[f1, f2, \Delta t]$ are combined into a unique 32-bit hash.
- **Inverted Index**: Saved fingerprints are indexed by hash for $O(1)$ lookup during scans.
- **Matching**:
    - **Global Offset Histogram**: For every match, $Offset = T_{long\_file} - T_{query}$ is calculated. A true match produces a massive "cluster" at the same offset.
    - **Match Ratio**: Skips require a minimum percentage of intro hashes to be present (default 25%) to filter false positives from similar music.
- **Search Strategy**: **Probabilistic Sub-sampling**. Instead of a linear scan, the script extracts short bursts (e.g., 12s) at regular intervals (e.g., 15s).

## Performance Patterns
- **Concurrent Worker Pool**: Audio scanning uses multiple parallel FFmpeg subprocesses (configurable via `audio_concurrency`) to maximize CPU utilization.
- **Ordered Result Processing**: Asynchronous workers pipe results into a buffer that is processed in chronological order to maintain gradient-based early stopping.
- **Gradient-Based Early Stopping**: Scans terminate immediately after a high-confidence match is detected and the match strength subsequently drops.
- **LuaJIT FFI**: Critical for performance. Uses C-structs and arrays to avoid Lua garbage collection overhead when handling millions of data points.
- **Async Subprocesses**: `mp.command_native_async` and coroutines ensure the MPV interface remains responsive during scans.

## Data Flow
1. **User Input** (Keybind) $\rightarrow$ **MPV Command**
2. **FFmpeg Subprocess** $\rightarrow$ **Raw Data Pipe (stdout)**
3. **FFI Logic** $\rightarrow$ **Hash Generation & Matching**
4. **MPV Property Set** (`time-pos`) $\rightarrow$ **Seek**
