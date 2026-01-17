# MPV Lua Script Best Practices

## Performance
- **Non-Blocking I/O**: ALWAYS use `mp.command_native_async` or `mp.utils.subprocess` (with async callback) for external commands. NEVER block the main MPV thread.
- **LuaJIT FFI**: Prefer `ffi` for computationally intensive tasks (e.g., image/audio processing) but ALWAYS provide a pure Lua fallback for compatibility.
- **FFI Memory**: Use `ffi.new` for fixed buffers to avoid Lua GC overhead in tight loops.

## Lifecycle & State
- **Cleanup**: Register an event handler for `end-file` to abort running scans and clean up subprocesses using `mp.abort_async_command`.
- **Async Tokens**: Track `current_scan_token` for all async commands to enable reliable abortion.
- **Global State**: Minimize global state. Use local variables or encapsulated state tables where possible.

## Logging & User Feedback
- **Logging**: Use `mp.msg.info`, `mp.msg.warn`, and `mp.msg.error` instead of `print`.
- **OSD**: Use `mp.osd_message` for immediate user feedback (e.g., "Scan started", "Intro skipped").

## Paths & Compatibility
- **Path Handling**: Use `mp.utils.join_path` for file system operations.
- **Dependencies**: Gracefully handle missing dependencies (e.g., `ffmpeg`, `ffi`, `bit`) by checking their presence at startup and warning the user via `msg.warn`.
