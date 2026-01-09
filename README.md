# intro-fingerprint

An MPV script to skip intro sequences in videos by fingerprinting audio and video.

When you mark an intro in one episode, the script can search for that same intro in other episodes (using either video or audio matching) and skip it automatically.

## Features

- **Video Fingerprinting**: Uses Gradient Hashing (dHash) to find visually similar intros.
- **Audio Fingerprinting**: Uses Constellation Hashing to find identical audio patterns, robust to video variations.
- **High Performance**: 
  - Uses **LuaJIT FFI** for zero-allocation data processing to handle large audio/video datasets efficiently.
  - Optional **libfftw3** support for accelerated FFT calculations.
- **Async Execution**: Scans run in the background using mpv coroutines and async subprocesses, ensuring the player remains responsive.
- **Cross-Platform**: Supports Windows, Linux, and macOS (with appropriate dependencies).

## Requirements

- **ffmpeg** must be in your system `PATH`.
- **LuaJIT** is highly recommended (standard in most mpv builds).
- **libfftw3** (optional): Provides faster FFT processing for audio scans (Only windows/linux).

## Installation

1.  **Clone or Download** this repository.
2.  **Install the script**: Copy the entire directory into your mpv `scripts` folder. The folder **must** be named `intro-fingerprint`.
    - **Windows**: `%APPDATA%\mpv\scripts\intro-fingerprint\`
    - **Linux/macOS**: `~/.config/mpv/scripts/intro-fingerprint/`

    > **Important**: The script depends on the `libs/` subdirectory to load `libfftw` for high-performance audio fingerprinting.

3.  **(Optional) Configuration**: 
    - Copy `intro-fingerprint.conf` to your mpv `script-opts` directory.
    - To enable the optimized FFTW paths, edit `script-opts/intro-fingerprint.conf` and set `audio_use_fftw=yes`.

## Key Bindings

- `Ctrl+i`: **Save Intro**. Captures the current timestamp as the intro fingerprint (saves video frame and audio data to temp files).
- `Ctrl+s`: **Skip Intro (Video)**. Scans the current video for a match based on the saved video fingerprint.
- `Ctrl+Shift+s`: **Skip Intro (Audio)**. Scans the audio stream for a match based on the saved audio fingerprint.

## How it Works

### Video Fingerprinting (Gradient Hash / dHash)
- Resizes a frame to 9x8 grayscale and compares adjacent pixels to generate a 64-bit hash.
- **Matching**: Uses Hamming Distance (count of differing bits).
- **Strategy**: Uses an expanding window search starting from the timestamp where the intro was originally captured. This minimizes ffmpeg decoding time, which is the primary bottleneck.

### Audio Fingerprinting (Constellation Hashing)
- Performs FFT on an audio segment to identify peak frequencies in time-frequency bins.
- Pairs peaks to form robust hashes: `[f1][f2][delta_time]`.
- **Matching**: Uses a histogram of time offsets. The offset with the most matches indicates the synchronization point.
- **Strategy**: Performs a linear scan or large window search. Audio extraction is relatively cheap, so the focus is on efficient hash matching in Lua.

## Configuration

You can customize the script by creating `intro-fingerprint.conf` in your mpv `script-opts` folder.

| Option | Default | Description |
| :--- | :--- | :--- |
| `debug` | `no` | Enable console debug printing for performance stats and scan info. |
| `audio_use_fftw` | `no` | Use `libfftw3` for faster audio FFT processing. |
| `video_threshold` | `12` | Tolerance for Hamming Distance (0-64). Lower is stricter. |
| `video_interval` | `0.20` | Time interval (seconds) between checked frames during video scan. |
| `video_search_window` | `10` | Initial seconds before/after saved timestamp to search. |
| `video_max_search_window`| `300` | Maximum seconds to expand the search window. |
| `audio_threshold` | `10` | Minimum magnitude for frequency peaks and minimum matches for a valid skip. |
| `audio_scan_limit` | `900` | Maximum seconds of the file to scan for audio matches. |
| `audio_sample_rate` | `11025`| Sample rate for audio extraction. |

## Troubleshooting

- **"FFmpeg failed during scan"**: Ensure `ffmpeg` is in your system PATH and accessible by mpv.
- **No match found**: 
  - For Video: Try increasing `video_threshold` or ensure the intro is visually similar.
  - For Audio: Ensure the intro has consistent music/audio.
- **Slow Scans**: Enable `audio_use_fftw` and ensure you are using LuaJIT (standard in most mpv builds).

## Building FFTW Libraries

The project includes a `Dockerfile` for building the required shared libraries (`libfftw3f.so` for Linux and `libfftw3f-3.dll` for Windows).

```bash
docker build --output type=local,dest=. .
```

This will populate the `libs/` directory with the appropriate binaries.

## License

MIT
