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

## Documentation Standards
All functions in mpv Lua scripts MUST include LuaDoc-style documentation using the following format:

```lua
--- Brief description of what the function does in the context of mpv
-- Additional details about mpv-specific behavior if needed
-- @param param_name type - description
-- @return type - description of return value
-- @note Any important implementation details or mpv API calls used (e.g., mp.set_property)
-- @note Side effects: (e.g., OSD messages, property changes, event triggers)
function my_function(param_name)
    -- implementation
end
```

Additionally, scripts MUST include:
- A top-level file header describing the overall purpose of the script.
- Documentation for global variables using `--- @var name type - description` or `--- @table name - description`.
- Documentation for key bindings (`mp.add_key_binding`) and property observers (`mp.observe_property`) describing their triggers and effects.

## Modular Structure & Standards
- **Directory Structure**: All logic modules MUST be placed in the `modules/` directory. `main.lua` acts as the orchestrator.
- **Local Table Pattern**: Every module file MUST start with `local M = {}` and end with `return M`. All exports MUST be attached to `M`.
- **Strict Locals**: Use `local` for every variable and function. Do NOT pollute the global environment.
- **Dependency Management**: Use dot-notation for requirements (e.g., `local utils = require "modules.utils"`).
- **State Management**: Use a dedicated `state.lua` module for shared state.
- **Single Responsibility**: Each module should focus on one logical area.
