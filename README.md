# intro-fingerprint

![intro-fingerprint](assets/header.svg)
![CI](https://github.com/jjangsangy/intro-fingerprint/actions/workflows/ci.yml/badge.svg) ![Lint](https://github.com/jjangsangy/intro-fingerprint/actions/workflows/lint.yml/badge.svg) [![GitHub release (latest by date)](https://img.shields.io/github/v/release/jjangsangy/intro-fingerprint)](https://github.com/jjangsangy/intro-fingerprint/releases/latest) [![GitHub last commit](https://img.shields.io/github/last-commit/jjangsangy/intro-fingerprint)](https://github.com/jjangsangy/intro-fingerprint/commits) [![Platform: mpv](https://img.shields.io/badge/platform-mpv-green.svg)](https://mpv.io/) [![LuaJIT Optimized](https://img.shields.io/badge/LuaJIT-Optimized-blueviolet.svg)](https://luajit.org/) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

An MPV script to skip intro sequences in media by fingerprinting audio and video.

When you mark an intro in one episode, the script can search for that same intro in other episodes (using either video or audio matching) and skip it automatically.

# Features

- **Audio Fingerprinting**: Uses Constellation Hashing to find identical audio patterns, robust to noise and distortion. **(Recommended/Default)**
- **Video Fingerprinting**: Uses PDQ Hash (Perceptual Hashing) to find visually similar intros.
- **High Performance**:
  - Uses **LuaJIT FFI** for zero-allocation data processing to handle large audio/video datasets efficiently.
  - Optimized **Pure-Lua Fallback** for environments without LuaJIT (e.g., some Linux builds), achieving ~2.5x faster FFTs than standard implementations.
- **Async Execution**: Scans run in the background using mpv coroutines and async subprocesses, ensuring the player remains responsive.
- **Cross-Platform**: Supports Windows, Linux, and macOS (with appropriate dependencies).

# Requirements

- **ffmpeg** (required) must be in your system `PATH`. ([Install Instructions](#install-ffmpeg))
- **LuaJIT** (optional) is highly recommended. The script uses FFI C-arrays for audio processing to avoid massive Garbage Collection overhead (standard in mpv). ([Install Instructions](#verifying-luajit-support))
- **'bit' library** (optional): Standard in LuaJIT. Used for faster processing if available.

# Installation
1.  **Download** the ([Latest Release](https://github.com/jjangsangy/intro-fingerprint/releases/latest/download/intro-fingerprint.zip))
2.  **Extract** the contents directly into your mpv configuration directory:
    - **Windows**: `%APPDATA%\Roaming\mpv\`
    - **Linux/macOS**: `~/.config/mpv/`

# Usage

1. **Open a video** that contains the intro you want to skip.
2. **Seek** to the very end of the intro.
3. **Press `Ctrl+i`** to save the fingerprint. This captures both video frame and audio spectrogram data to temporary files.
4. **Open another video** (e.g., the next episode).
5. **Press `Ctrl+s`** (Audio scan) or **`Ctrl+Shift+s`** (Video scan) to find and skip the intro.

# Key Bindings

- `Ctrl+i`: **Save Intro**. Captures the current timestamp as the intro fingerprint (saves video frame and audio data to temp files).
- `Ctrl+s`: **Skip Intro (Audio)**. Scans the audio stream for a match based on the saved audio fingerprint.
  - *Note: Audio fingerprinting is significantly faster and is the default method. However, if the intro music changes between episodes while the video remains the same, use Video Skip instead.*
- `Ctrl+Shift+s`: **Skip Intro (Video)**. Scans the current video for a match based on the saved video fingerprint.

## Customizing Key Bindings

You can customize the key bindings using either `intro-fingerprint.conf` file or `input.conf`.

### 1. Using `intro-fingerprint.conf`
You can change the default key bindings by setting the following options in your `intro-fingerprint.conf` file:

```properties
key_save_intro=Ctrl+i
key_skip_audio=Ctrl+s
key_skip_video=Ctrl+Shift+s
```

### 2. Using `input.conf`
You can map any key to the script's named bindings in your `input.conf` file. The internal binding names are:

- `save-intro`
- `skip-intro-audio`
- `skip-intro-video`

**Example `input.conf`:**
```properties
Alt+i script-binding save-intro
Alt+s script-binding skip-intro-audio
Alt+Shift+s script-binding skip-intro-video
```

# Configuration

You can customize the script by creating `intro-fingerprint.conf` in your mpv `script-opts` folder.

## General
| Option  | Default | Description                                                        |
| :------ | :------ | :----------------------------------------------------------------- |
| `debug` | `no`    | Enable console debug printing for performance stats and scan info. |

## Audio Options
| Option                       | Default | Description                                                                 |
| :--------------------------- | :------ | :-------------------------------------------------------------------------- |
| `audio_threshold`            | `10`    | Minimum magnitude for frequency peaks and minimum matches for a valid skip. |
| `audio_min_match_ratio`      | `0.30`  | Minimum ratio of matching hashes required (0.0 - 1.0).                      |
| `audio_concurrency`          | `4`     | Number of parallel FFmpeg workers for audio scanning.                       |
| `audio_scan_limit`           | `900`   | Maximum seconds of the file to scan for audio matches.                      |
| `audio_sample_rate`          | `11025` | Sample rate for audio extraction.                                           |
| `audio_segment_duration`     | `15`    | Duration (seconds) of each audio scan segment for the linear scan.          |
| `audio_fingerprint_duration` | `10`    | Duration (seconds) of the audio fingerprint to capture.                     |
| `audio_fft_size`             | `2048`  | FFT size for audio processing.                                              |
| `audio_hop_size`             | `1024`  | Hop size (overlap) between FFT frames.                                      |
| `audio_target_t_min`         | `10`    | Minimum delay in frames for peak pairs in constellation hashing.            |
| `audio_target_t_max`         | `100`   | Maximum delay in frames for peak pairs in constellation hashing.            |

## Video Options
| Option                    | Default | Description                                                       |
| :------------------------ | :------ | :---------------------------------------------------------------- |
| `video_hash_size`         | `64`    | Hash size (64x64 input -> 16x16 DCT -> 256 bit hash).             |
| `video_threshold`         | `50`    | Tolerance for Hamming Distance (0-256). Lower is stricter.        |
| `video_interval`          | `0.20`  | Time interval (seconds) between checked frames during video scan. |
| `video_search_window`     | `10`    | Initial seconds before/after saved timestamp to search.           |
| `video_max_search_window` | `300`   | Maximum seconds to expand the search window.                      |
| `video_window_step`       | `30`    | Step size (seconds) when expanding the video search window.       |

## File Paths
| Option                | Default                       | Description                      |
| :-------------------- | :---------------------------- | :------------------------------- |
| `audio_temp_filename` | `mpv_intro_skipper_audio.dat` | Name of temp file used for audio |
| `video_temp_filename` | `mpv_intro_skipper_video.dat` | Name of temp file used for video |

## Key Bindings
| Option           | Default        | Description                                     |
| :--------------- | :------------- | :---------------------------------------------- |
| `key_save_intro` | `Ctrl+i`       | Key binding to save the intro fingerprint.      |
| `key_skip_video` | `Ctrl+Shift+s` | Key binding to skip using video fingerprinting. |
| `key_skip_audio` | `Ctrl+s`       | Key binding to skip using audio fingerprinting. |

# How it Works

The script uses two primary methods for fingerprinting:

## 1. Audio Fingerprinting (Constellation Hashing)

![Constellation Hashing](assets/constellation-hashing.svg)

- **Algorithm**: Extracts audio using FFmpeg (s16le, mono) and performs FFT to identify peak frequencies in time-frequency bins.
- **Hashing**: Pairs peaks to form hashes: `[f1][f2][delta_time]`.
- **Matching**: Uses a **Global Offset Histogram**. Every match calculates $Offset = T_{file} - T_{query}$, and the script looks for the largest cluster (peak) of consistent offsets.
- **Filtering**: Implements **Match Ratio** filtering (default 30%) to ensure the match is an exact fingerprint overlap rather than just similar-sounding music.
- **Search Strategy**: **Concurrent Linear Scan**. The timeline is divided into contiguous segments (e.g., 10s). Each segment is processed by a concurrent worker with sufficient padding to ensure no matches are lost at segment boundaries. Hashes are filtered to prevent double-counting in overlapping regions.
- **Optimization**:
    - **Concurrency**: Launches multiple parallel FFmpeg workers to utilize all CPU cores.
    - **Inverted Index**: Uses an $O(1)$ hash-map for near-instant lookup of fingerprints during the scan.
    - **Optimal Stopping**: Scans terminate immediately once a high-confidence match is confirmed and the signal gradient drops.

## 2. Video Fingerprinting (PDQ Hash)

![Perceptual Hashing](assets/gradient-hashing.svg)

- **Algorithm**: Resizes frames to 64x64 grayscale and computes the Discrete Cosine Transform (DCT) of the rows and columns. A 256-bit hash (32 bytes) is generated from the low-frequency 16x16 coefficients by comparing each coefficient against the median value.
- **Matching**: Uses Hamming Distance (count of differing bits). It is robust against color changes, small aspect ratio variations, and high-frequency noise.
- **Search Strategy**: The search starts around the timestamp of the saved fingerprint and expands outward.
- **Optimization**: FFmpeg video decoding is the most expensive part of the pipeline. By assuming the intro is at a similar location (common in episodic content), we avoid decoding the entire stream, resulting in much faster scans.

# Quality Validation

To prevent false positives and wasted scans, the script validates media quality before creating a fingerprint. If a fingerprint is rejected, you will see an "Audio Rejected" or "Frame Rejected" message.

- **Audio Rejection**:
    - **Silence Detected**: Audio is too quiet (RMS < 0.005).
    - **Signal Too Sparse**: Audio is mostly silence (< 10% active samples).
    - **Low Complexity**: Audio lacks distinct frequency peaks (< 50 hashes generated).

- **Video Rejection**:
    - **Low Quality**: The frame lacks sufficient detail or structure (Gradient Sum Quality < 0.01). This typically rejects black screens, solid colors, and very smooth gradients.

### Understanding Frame Rejection

To ensure robust matching, the system rejects frames that lack distinct **structural information**. This includes:

1.  **Low Quality Scenes**: Solid colors, black screens, or smooth gradients. These contain almost no information, making the hash purely random noise.

#### **Why?**

PDQ Hash works by analyzing the image's spatial gradients.
-   If an image is **too simple** (solid color), there are no gradients.
-   If an image is **too complex** (dense text), the fine details disappear when resized to 64x64.

#### 1. Good Frame (Accepted)
| Original Frame | What PDQ Hash Sees (64x64 -> 16x16 Low Freq) |
| :---: | :---: |
| ![Accepted](assets/samuel.webp) | ![Accepted pHash](assets/samuel_phash.webp) |

The image has **high contrast and distinct structure**. You can clearly see shapes that remain stable even after resizing and compression.

#### 2. Bad Frame (Noisy/Low-Contrast)
| Original Frame | What PDQ Hash Sees |
| :---: | :---: |
| ![Rejected](assets/interstellar.webp) | ![Rejected pHash](assets/interstellar_phash.webp) |

**Reason: Low Quality.**
The image is too dark and uniform. It lacks distinct gradients or edges needed for a stable hash.

#### 3. Bad Frame (Gradient/Waves)
| Original Frame | What PDQ Hash Sees |
| :---: | :---: |
| ![Waves](assets/waves.webp) | ![Waves pHash](assets/waves_phash.webp) |

**Reason: Low Quality.**
The image relies on simple gradients without sharp transitions. This results in a low gradient sum, making the fingerprint unstable.

#### 4. Bad Frame (Low Texture)
| Original Frame | What PDQ Hash Sees |
| :---: | :---: |
| ![Betrayal](assets/betrayal.webp) | ![Betrayal pHash](assets/betrayal_phash.webp) |

**Reason: Low Quality.**
The image is blurry and washed out, dominated by the background color rather than distinct structural details.

**Always choose a frame with clear shapes, high contrast, and distinct objects.**

If you encounter these errors, try moving the playback position slightly forward or backward to a more complex part of the intro (e.g., a scene with action or music).

# Performance & Technical Details

The script is heavily optimized for LuaJIT and high-performance processing.

## 1. LuaJIT FFI & Memory Management
- **Zero-Allocation Data Processing**: Critical hot paths use **LuaJIT FFI** C-arrays (`double[]`, `int16_t[]`) instead of Lua tables. This prevents massive Garbage Collection (GC) pauses that would occur if creating millions of small table objects for audio samples and hashes.
- **Flattened Data Structures**: 2D data (like spectrogram peaks) is flattened into 1D C-arrays to ensure memory contiguity and cache friendliness.
- **Direct Memory Access**: Raw audio and video buffers from FFmpeg are cast directly to C-structs using FFI, avoiding any copying or string manipulation in Lua.

## 2. Audio FFT Processing

The script uses highly optimized internal FFT implementations:

### For LuaJIT (FFI-Optimized)
- **Stockham Auto-Sort Algorithm**: Avoids the expensive bit-reversal permutation step, maximizing FFI performance.
- **Radix-4 & Mixed-Radix**: Processes 4 points at a time to reduce complex multiplications, with Radix-2 fallback passes to handle non-power-of-4 sizes (e.g., 2048).
- **Cache-Aware Loop Tiling**: Ensures **unit-stride memory access** for maximum memory throughput.

#### For Standard Lua (Interpreter-Optimized)
- **Zero-Allocation Processing**: Replaces table churn with reusable buffers to minimize Garbage Collection overhead.
- **Fused Scrambling**: Combines Hann windowing and bit-reversal into a single pass.
- **Precomputed Lookups**: Uses pre-calculated trig tables and bit-reversal maps to avoid redundant math inside hot loops.
- **Speedup**: Achieves approximately **2.5x faster processing** compared to naive Lua implementations.

## 3. Algorithmic Optimizations
- **Inverted Index Matching**: Fingerprints are stored in a hash map ($O(1)$ lookup), allowing the scanner to instantly find potential matches without iterating through the reference data.
- **Precomputed Population Count**: A 256-entry lookup table is used to calculate Hamming distances for video hashes, replacing bit-twiddling loops with a single table lookup per byte.
- **Gradient-Based Early Stopping**: The scanner monitors the "match strength" gradient. Once a peak is found and the signal begins to fade, the scan aborts immediately, saving CPU time.
- **Asynchronous Concurrency**: Uses `mpv` coroutines and multiple parallel FFmpeg workers to utilize all CPU cores without blocking the player UI.

# Install FFmpeg

This script relies on `ffmpeg` being available in your system's `PATH`.

## Windows
Using a package manager (recommended):

**Winget**:
```powershell
winget install ffmpeg
```

**Chocolatey**:
```powershell
choco install ffmpeg
```

**Scoop**:
```powershell
scoop install ffmpeg
```

## macOS
Using Homebrew:
```bash
brew install ffmpeg
```

## Linux
**Debian/Ubuntu**:
```bash
sudo apt update && sudo apt install ffmpeg
```

**Fedora**:
```bash
sudo dnf install ffmpeg
```

**Arch Linux**:
```bash
sudo pacman -S ffmpeg
```
# Troubleshooting

- **"Audio Rejected" / "Frame Rejected"**:
    - **Cause**: The scene is too simple (silence, black screen, featureless background) to generate a unique fingerprint.
    - **Solution**: Seek forward or backward by a few seconds to a scene with clear audio (dialogue/music) or visual detail, then press `Ctrl+i` again.

- **"FFmpeg failed during scan"**:
    - **Cause**: `ffmpeg` is missing or not in system PATH.
    - **Solution**: Install FFmpeg and verify it runs from a terminal.

- **No match found**:
    - **Video**: Try increasing `video_threshold` in config, or ensure the intro is visually identical.
    - **Audio**: Ensure the intro music is consistent. If the intro has variable music but same video, use Video Skip (`Ctrl+Shift+s`).

## Verifying LuaJIT Support

This script is highly optimized for **LuaJIT**. While it includes a fallback for standard Lua (5.1/5.2), using LuaJIT provides significantly faster performance, especially for audio scanning.

To check if your mpv build uses LuaJIT, run the following command in your terminal:

**Windows**:
```powershell
mpv --version -v | findstr luajit
```

**macOS / Linux**:
```bash
mpv --version -v | grep luajit
```

If the command returns a line containing `luajit`, you are good to go. If it returns nothing, you are likely using standard Lua.

**If `luajit` is missing:**

-   **Windows**: Download the official builds from [mpv.io](https://mpv.io/installation/) (e.g., shinchiro builds). These include LuaJIT by default.
-   **macOS**: Install via Homebrew: `brew install mpv`.
-   **Linux**:
    -   Some distribution packages (Ubuntu/Debian) ship with standard Lua instead of LuaJIT.
    -   **Recommended**: Install via **Flatpak** from [Flathub](https://flathub.org/apps/io.mpv.Mpv), which includes LuaJIT.

# Development & Testing
You can use the provided VS Code DevContainer to test the script in a pre-configured Linux environment:
1. Open the project in VS Code.
2. Click **Reopen in Container** when prompted.
3. The container comes with `mpv`, `ffmpeg`, and `xvfb` pre-installed.
4. To test: `xvfb-run mpv --script=main.lua videos`
   - *Note: Place your test videos in the `videos/` folder in the project root to have them available inside the container.*

---

<a href="https://www.buymeacoffee.com/sanghan">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" width="200" height="50" alt="Buy Me A Coffee">
</a>
