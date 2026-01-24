# Product Context

## Problem
- **Repetitive Manual Seeking**: Users must manually find the end of the intro for every episode in a series.
- **Inconsistent Timestamps**: Intros often vary by a few seconds or frames, making simple "skip 90s" scripts unreliable.
- **Performance Overhead**: Traditional video scanning is too CPU-intensive for seamless background execution during playback.

## Solution: "Teach Once, Skip Everywhere"
`intro-fingerprint` allows the user to mark an intro *once*. The script creates a lightweight digital fingerprint that can instantly recognize that same sequence in any future episode, regardless of minor timing or quality differences.

## User Experience
1.  **Mark**: At the end of an intro, press `Ctrl+i`.
    *   *System saves a 256-bit video hash and 10s audio spectrogram.*
2.  **Watch**: Open the next episode.
3.  **Skip**: Press `Ctrl+s` (Audio) or `Ctrl+Shift+s` (Video).
    *   *System scans the file asynchronously and jumps to the match.*

## Core Value Proposition
- **Robustness**: Uses perceptual hashing (PDQ) and audio constellation hashing, not just exact byte matching.
- **Speed**: Optimized algorithms allow scanning entire files in seconds without blocking playback.
- **Flexibility**: Works on both high-end systems (LuaJIT FFI) and standard installs (Optimized Pure Lua).
