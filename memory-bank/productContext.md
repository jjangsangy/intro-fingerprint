# Product Context

## Why this project exists?
When watching TV series or any episodic content, intro sequences are often identical across episodes. Manually seeking past them is repetitive and imprecise.

`intro-fingerprint` solves this by allowing a user to "teach" the script what an intro looks like or sounds like once, and then automatically finding that same point in other files.

## Problems it solves
- **Repetitive Manual Seeking**: Users no longer need to manually seek 90 seconds forward for every episode.
- **Inconsistent Intro Times**: Some intros vary slightly in position or length; fingerprinting finds the exact match regardless of minor timestamp variations.
- **Performance**: Scanning high-resolution video can be slow; this script uses low-resolution grayscale hashes and optimized audio FFTs to make scanning fast enough for real-time use.

## How it works
1. **Marking**: The user navigates to the end of an intro and presses `Ctrl+i`.
2. **Fingerprinting**: The script extracts a "fingerprint" of the video frame and the preceding 10 seconds of audio.
3. **Storage**: Fingerprints are stored in the system temp directory.
4. **Matching**: When a "Skip" command is issued in a different video, the script scans the new file's streams to find a match for the saved fingerprint.
5. **Jumping**: Once a match is found, MPV seeks directly to that timestamp.
