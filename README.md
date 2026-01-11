# intro-fingerprint

![intro-fingerprint](assets/header.svg)

An MPV script to skip intro sequences in media by fingerprinting audio and video.

When you mark an intro in one episode, the script can search for that same intro in other episodes (using either video or audio matching) and skip it automatically.

## Features

- **Audio Fingerprinting**: Uses Constellation Hashing to find identical audio patterns, robust to video variations. **(Recommended/Default)**
- **Video Fingerprinting**: Uses Gradient Hashing (dHash) to find visually similar intros.
- **High Performance**: 
  - Uses **LuaJIT FFI** for zero-allocation data processing to handle large audio/video datasets efficiently.
  - Optional **libfftw3** support for accelerated FFT calculations.
- **Async Execution**: Scans run in the background using mpv coroutines and async subprocesses, ensuring the player remains responsive.
- **Cross-Platform**: Supports Windows, Linux, and macOS (with appropriate dependencies).

## Requirements

- **ffmpeg** must be in your system `PATH`. ([Install instructions](#install-ffmpeg))
- **LuaJIT** is highly recommended. The script uses FFI C-arrays for audio processing to avoid massive Garbage Collection overhead (standard in mpv).
- **'bit' library** (optional): Standard in LuaJIT. Used for faster processing if available.
- **libfftw3** (optional): Provides faster FFT processing for **audio scans only** (Windows/Linux). It does not affect video fingerprinting performance. (provided in repo, or [build it yourself](#building-fftw-libraries))

## Installation

1.  **Clone or Download** this repository.
2.  **Install the script**: Copy the entire directory into your mpv `scripts` folder. The folder **must** be named `intro-fingerprint`.
    - **Windows**: `%APPDATA%\mpv\scripts\intro-fingerprint\`
    - **Linux/macOS**: `~/.config/mpv/scripts/intro-fingerprint/`

3.  **(Optional) Configuration**: 
    - Copy `intro-fingerprint.conf` to your mpv `script-opts` directory.
    - To enable the optimized FFTW paths, edit `script-opts/intro-fingerprint.conf` and set `audio_use_fftw=yes`.

## Usage

1. **Open a video** that contains the intro you want to skip.
2. **Seek** to the very end of the intro.
3. **Press `Ctrl+i`** to save the fingerprint. This captures both video frame and audio spectrogram data to temporary files.
4. **Open another video** (e.g., the next episode).
5. **Press `Ctrl+s`** (Audio scan) or **`Ctrl+Shift+s`** (Video scan) to find and skip the intro.

## Key Bindings

- `Ctrl+i`: **Save Intro**. Captures the current timestamp as the intro fingerprint (saves video frame and audio data to temp files).
- `Ctrl+s`: **Skip Intro (Audio)**. Scans the audio stream for a match based on the saved audio fingerprint.
  - *Note: Audio fingerprinting is significantly faster and is the default method. However, if the intro music changes between episodes while the video remains the same, use Video Skip instead.*
- `Ctrl+Shift+s`: **Skip Intro (Video)**. Scans the current video for a match based on the saved video fingerprint.

## How it Works

The script uses two primary methods for fingerprinting:

### 1. Video Fingerprinting (Gradient Hash / dHash)
- **Algorithm**: Resizes frames to 9x8 grayscale and compares adjacent pixels: if `P(x+1) > P(x)`, the bit is 1, else 0. This generates a 64-bit hash (8 bytes).
- **Matching**: Uses Hamming Distance (count of differing bits). It is robust against color changes and small aspect ratio variations.
- **Search Strategy**: The search starts around the timestamp of the saved fingerprint and expands outward.
- **Optimization**: FFmpeg video decoding is the most expensive part of the pipeline. By assuming the intro is at a similar location (common in episodic content), we avoid decoding the entire stream, resulting in much faster scans.

### 2. Audio Fingerprinting (Constellation Hashing)
- **Algorithm**: Extracts audio using FFmpeg (s16le, mono) and performs FFT to identify peak frequencies in time-frequency bins.
- **Hashing**: Pairs peaks to form hashes: `[f1][f2][delta_time]`.
- **Matching**: Uses a **Global Offset Histogram**. Every match calculates $Offset = T_{long\_file} - T_{query}$, and the script looks for the largest cluster (peak) of consistent offsets.
- **Filtering**: Implements **Match Ratio** filtering (default 25%) to ensure the match is an exact fingerprint overlap rather than just similar-sounding music.
- **Search Strategy**: **Concurrent Linear Scan**. The timeline is divided into contiguous segments (e.g., 10s). Each segment is processed by a concurrent worker with sufficient padding to ensure no matches are lost at segment boundaries. Hashes are filtered to prevent double-counting in overlapping regions.
- **Optimization**: 
    - **Concurrency**: Launches multiple parallel FFmpeg workers to utilize all CPU cores.
    - **Inverted Index**: Uses an $O(1)$ hash-map for near-instant lookup of fingerprints during the scan.
    - **Optimal Stopping**: Scans terminate immediately once a high-confidence match is confirmed and the signal gradient drops.

## Performance & Technical Details

The script is heavily optimized for LuaJIT and high-performance processing:

- **Zero-Allocation Data Processing**: Uses **LuaJIT FFI** and custom C-structs for hash generation and spectrogram storage to eliminate millions of Lua table allocations during scanning.
- **Asynchronous Subprocesses**: Uses coroutines to prevent blocking the player during scanning, allowing for graceful cancellation.
- **Optimized Audio FFT**:
    - **libfftw3 Support**: Maximum performance for audio FFT calculations. (Note: This acceleration is specific to the audio fingerprinting path).
    - **Custom FFI Fallback**: If `libfftw3` is unavailable, it uses an optimized **Stockham Radix-4 Autosort** algorithm (avoiding bit-reversal permutations) and **Mixed-Radix** handling for power-of-2 sizes.
    - **Cache Optimization**: Uses a planar (split-complex) data layout for efficient memory access.
    - **Twiddle Caching**: Precomputed trigonometric tables eliminate runtime `sin`/`cos` calls.

## Configuration

You can customize the script by creating `intro-fingerprint.conf` in your mpv `script-opts` folder.

| Option | Default | Description |
| :--- | :--- | :--- |
| `debug` | `no` | Enable console debug printing for performance stats and scan info. |
| `audio_use_fftw` | `no` | Use `libfftw3` for faster audio FFT processing. |
| `video_threshold` | `12` | Tolerance for Hamming Distance (0-64). Lower is stricter. |
| `video_interval` | `0.20` | Time interval (seconds) between checked frames during video scan. |
| `video_search_window` | `10` | Initial seconds before/after saved timestamp to search. |
| `video_max_search_window` | `300` | Maximum seconds to expand the search window. |
| `video_window_step` | `30` | Step size (seconds) when expanding the video search window. |
| `audio_threshold` | `10` | Minimum magnitude for frequency peaks and minimum matches for a valid skip. |
| `audio_min_match_ratio` | `0.25` | Minimum ratio of matching hashes required (0.0 - 1.0). |
| `audio_concurrency` | `4` | Number of parallel FFmpeg workers for audio scanning. |
| `audio_scan_limit` | `900` | Maximum seconds of the file to scan for audio matches. |
| `audio_sample_rate` | `11025` | Sample rate for audio extraction. |
| `audio_segment_duration` | `15` | Duration (seconds) of each audio scan segment for the linear scan. |
| `audio_fingerprint_duration`| `10` | Duration (seconds) of the audio fingerprint to capture. |
| `audio_fft_size` | `2048` | FFT size for audio processing. |
| `audio_hop_size` | `1024` | Hop size (overlap) between FFT frames. |
| `key_save_intro` | `Ctrl+i` | Key binding to save the intro fingerprint. |
| `key_skip_video` | `Ctrl+Shift+s` | Key binding to skip using video fingerprinting. |
| `key_skip_audio` | `Ctrl+s` | Key binding to skip using audio fingerprinting. |

## Troubleshooting

- **"FFmpeg failed during scan"**: Ensure `ffmpeg` is in your system PATH and accessible by mpv.
- **No match found**: 
  - For Video: Try increasing `video_threshold` or ensure the intro is visually similar.
  - For Audio: Ensure the intro has consistent music/audio.
- **Slow Scans**: Enable `audio_use_fftw` and ensure you are using LuaJIT (standard in most mpv builds).

## Install FFmpeg

This script relies on `ffmpeg` being available in your system's `PATH`.

### Windows
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

### macOS
Using Homebrew:
```bash
brew install ffmpeg
```

### Linux
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

## Building FFTW Libraries

The project includes a `Dockerfile` for building the required shared libraries (`libfftw3f.so` for Linux and `libfftw3f-3.dll` for Windows).

```bash
docker build --output type=local,dest=. .
```

This will populate the `libs/` directory with the appropriate binaries.


## License

MIT
