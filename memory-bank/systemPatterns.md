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
    - FFT:
        - **LuaJIT FFI**: Uses FFTW3 (if available) or an FFI-optimized Stockham Radix-4 & Mixed-Radix implementation.
        - **Standard Lua**: Uses an optimized in-place Cooley-Tukey implementation with precomputed trig tables and bit-reversal caches to minimize GC overhead.
    - Peak detection identifies the most prominent frequencies (top 5 per frame).
- **Hashing**: Pairs of peaks $[f1, f2, \Delta t]$ are combined into a unique 32-bit hash.
- **Inverted Index**: Saved fingerprints are indexed by hash for $O(1)$ lookup during scans.
- **Matching**:
    - **Global Offset Histogram**: For every match, $Offset = T_{long\_file} - T_{query}$ is calculated. A true match produces a massive "cluster" at the same offset.
    - **Neighbor Bin Summing**: To handle timing jitter and "bin splitting," the script sums the counts of three adjacent time bins ($bin_{i-1} + bin_{i} + bin_{i+1}$) when calculating match strength. This ensures robustness against minor alignment variations.
    - **Match Ratio**: Skips require a minimum percentage of intro hashes to be present (default 25%) to filter false positives from similar music. The ratio is calculated based on the summed neighbor peaks.
- **Search Strategy**: **Concurrent Linear Scan**. The timeline is divided into contiguous segments (default 15s). Each segment is processed by a concurrent worker with sufficient padding to ensure no matches are lost at segment boundaries. Hashes are filtered to prevent double-counting in overlapping regions.

## Performance Patterns
- **Concurrent Worker Pool**: Audio scanning uses multiple parallel FFmpeg subprocesses (configurable via `audio_concurrency`) to maximize CPU utilization.
- **Ordered Result Processing**: Asynchronous workers pipe results into a buffer that is processed in chronological order to maintain gradient-based early stopping.
- **Gradient-Based Early Stopping**: Scans terminate immediately after a high-confidence match is detected and the match strength subsequently drops.
- **LuaJIT FFI**: Critical for peak performance. Uses C-structs and arrays to avoid Lua garbage collection overhead when handling millions of data points.
- **Zero-Allocation Fallback**: Standard Lua path uses pre-allocated buffers and lookup tables for FFT to achieve ~2.5x speedup over naive implementations, ensuring usability on builds without LuaJIT.
- **Async Subprocesses**: `mp.command_native_async` and coroutines ensure the MPV interface remains responsive during scans.

## Lifecycle Management
- **Scan Abortion**: To prevent race conditions and orphan processes, the script listens for the `end-file` event. It uses `mp.abort_async_command` with a stored `current_scan_token` to immediately terminate any running FFmpeg workers and reset the `scanning` state.

## Data Flow
1. **User Input** (Keybind) $\rightarrow$ **MPV Command**
2. **FFmpeg Subprocess** $\rightarrow$ **Raw Data Pipe (stdout)**
3. **FFI Logic** $\rightarrow$ **Hash Generation & Matching**
4. **MPV Property Set** (`time-pos`) $\rightarrow$ **Seek**
