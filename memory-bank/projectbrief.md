# Intro Fingerprint Project Brief

A high-performance MPV script designed to automatically skip intro sequences by "fingerprinting" audio and video patterns.

## Core Mission
To provide a seamless, set-it-and-forget-it experience for skipping intros in episodic content, utilizing robust perceptual hashing algorithms that work across minor encoding or timestamp variations.

## Key Features
- **Audio Skip (Default)**: Uses **Constellation Hashing** (spectrogram peak pairing) to identify intros even with noise or volume differences.
- **Video Skip (Fallback)**: Uses **PDQ Hash** (perceptual 256-bit hash) to identify visually similar frames (e.g., logo shots) when audio varies.
- **Performance**: Optimized for **LuaJIT FFI** (Zero-Allocation) with high-speed **Pure Lua fallbacks** (~2.5x faster than standard) for broad compatibility.
- **Async & Concurrent**: Non-blocking scanning using MPV coroutines and parallel FFmpeg worker pools.
