# mpv-intro-fingerprint

An MPV script to skip intro sequences in videos by fingerprinting audio and video.

When you mark an intro in one episode, the script can search for that same intro in other episodes (using either video or audio matching) and skip it automatically.

## Requirements

- **ffmpeg** must be in your system `PATH`.
- **LuaJIT** is highly recommended (standard in most mpv builds).
- **libfftw3** (optional): If available and configured, it provides faster FFT processing for audio scans.

## Installation

1. Copy `main.lua` and the library files (`libfftw3f-3.dll` or `libfftw3f.so`) to your mpv scripts directory:
   - **Windows**: `%APPDATA%\mpv\scripts\intro-fingerprint\`
   - **Linux/macOS**: `~/.config/mpv/scripts/intro-fingerprint/`

## Key Bindings

- `Ctrl+i`: **Save Intro**. Captures the current timestamp as the intro fingerprint (saves video frame and audio data to temp files).
- `Ctrl+s`: **Skip Intro (Video)**. Scans the current video for a match based on the saved video fingerprint.
- `Ctrl+Shift+s`: **Skip Intro (Audio)**. Scans the audio stream for a match based on the saved audio fingerprint.

## How it Works

### Video Fingerprinting (Gradient Hash / dHash)
- Resizes a frame to 9x8 grayscale and compares adjacent pixels to generate a 64-bit hash.
- Matching uses Hamming Distance.
- Best for intros that are visually identical across episodes.

### Audio Fingerprinting (Constellation Hashing)
- Performs FFT on an audio segment to identify peak frequencies.
- Pairs peaks to form robust hashes.
- Matching uses a histogram of time offsets to find the synchronization point.
- Best for intros with consistent music or sound effects, even if the video varies.

## Performance & Optimization

- Uses **LuaJIT FFI** for zero-allocation data processing to ensure high performance during scans.
- Implements asynchronous subprocesses to prevent the player from freezing while scanning.
- Supports **libfftw3** for maximum FFT performance.

## License

MIT
