# Intro Fingerprint Project Brief

A high-performance MPV script designed to automatically skip intro sequences in video files by using audio and video fingerprinting techniques.

## Core Goals
- Provide a seamless way to skip repetitive intros across different episodes of a series.
- Implement efficient video fingerprinting using Perceptual Hashing (pHash).
- Implement robust audio fingerprinting using Constellation Hashing.
- Minimize performance overhead using LuaJIT FFI with an optimized internal FFT implementation, optimized pure-Lua fallbacks, and FFmpeg for data extraction.

## Key Features
- **Audio Skip (`Ctrl+s`)**: Scans for a match based on audio spectrogram peaks and time-offset histograms. (Recommended/Default)
- **Video Skip (`Ctrl+Shift+s`)**: Scans for a match based on a 64-bit pHash of a video frame.
- **Intro Capture (`Ctrl+i`)**: Saves the current frame and preceding audio segment as reference fingerprints.
- **Async Execution**: Non-blocking scans using mpv coroutines and async subprocesses.
