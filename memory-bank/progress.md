# Progress

## Completed

### Core Algorithms
- [x] **Constellation Hashing (Audio)**: FFT-based peak pairing, global offset histogram matching, neighbor bin summing, `dynaudnorm` normalization.
- [x] **PDQ Hash (Video)**: Jarosz filter approximation, 16x64 DCT matrix projection, 256-bit hashing, quality validation (gradient sum, entropy).

### Performance
- [x] **LuaJIT FFI**: Zero-allocation paths for FFT and hashing.
- [x] **Pure Lua Optimization**: ~2.5x faster FFT (precomputed tables) and ~4x faster PDQ (flat arrays) for non-JIT builds.
- [x] **Concurrency**: Parallel FFmpeg worker pool for audio scanning.
- [x] **Efficiency**: Ordered result processing with gradient-based early stopping.

### Infrastructure & Tooling
- [x] **Modular Architecture**: Split monolithic script into `modules/`.
- [x] **Testing**: Comprehensive `luaunit` suite with MPV API mocking.
- [x] **DevContainer**: Custom Ubuntu 24.04 environment with `mpv-luajit`.
- [x] **Installers**: PowerShell (Windows) and Shell (Linux/macOS) scripts.

## Future Roadmap
- [ ] **Audio Fingerprint Compression**: Improve fingerprint density and retrieval
  - [ ] **Sub Sampling and Density Control**: Picker only chooses top N peaks per segment, keep raising threshold until it is met
  - [ ] **Bit Packing**: Keep storage low by storing peaks as a 64-bit integer
  - [ ] **Inverted Index**: Only process files that have share the the hashes
- [ ] **Persistent Fingerprints**: Moving beyond temp files to a user-specified database or local directory.
  - [x] **Detect Bad Fingerprints**: Pre-filter low entropy images using DCT energy and audio with long silences/low complexity.
  - [ ] **Add Fingerprint Tagging**: Save metadata about media into fingerprint file for better cataloging.
  - [ ] **Removal Mechanism**: Have the ability to remove specific fingerprints if they are causing mismatches.
  - [ ] **Logging Fingerprint Match**: Log which fingerprint from which file is being matched.
  - [ ] **Deduplication**: Ensure we don't save duplicate fingerprints for the same section multiple times.
  - [x] **Move Fingerprints**: Move the fingerprint directory from temp to somewhere permanent.
- [ ] **Automatic Scanning**: Auto-scan for matches when a new file starts.
- [ ] **UI/OSD Improvements**: Better visual feedback for scan progress and match confidence.
- [ ] **Fingerprint Interoperability**: Ensure both lua and luajit fingerprints can be used interchangeably.
