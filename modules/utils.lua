local mp = require 'mp'
local msg = require 'mp.msg'
local mp_utils = require 'mp.utils'
local config = require 'modules.config'
local state = require 'modules.state'

local M = {}

-- Attempt to load FFI (LuaJIT only) and Bit library
--- @var ffi_status boolean - True if LuaJIT ffi library is loaded
M.ffi_status, M.ffi = pcall(require, "ffi")
--- @var bit_status boolean - True if bitwise operations library is loaded
M.bit_status, M.bit = pcall(require, "bit")

if not M.ffi_status then
    msg.warn("LuaJIT FFI not detected! Falling back to standard Lua (slower).")
end
if not M.bit_status then
    msg.warn("BitOp library not detected! Falling back to arithmetic operations (slower).")
end

if M.ffi_status then
    --- Define C structures for FFT and Fingerprinting
    -- @note Uses ffi.cdef
    M.ffi.cdef [[
        typedef unsigned char uint8_t;
        typedef struct { double r; double i; } complex_t;
        typedef int16_t int16;
        typedef struct { uint32_t h; uint32_t t; } hash_entry;
    ]]
end

--- Log debug information if debug mode is enabled
-- @param str string - The message to log
-- @note Uses mp.msg.info
function M.log_info(str)
    if config.options.debug == "yes" then
        msg.info(str)
    end
end

--- Abort the current scan and cleanup state
-- @note Registered to 'end-file' event via mp.register_event()
-- @note Uses mp.abort_async_command() to terminate active subprocesses
function M.abort_scan()
    if state.current_scan_token then
        mp.abort_async_command(state.current_scan_token)
        state.current_scan_token = nil
    end
    state.scanning = false
    M.log_info("Scan aborted.")
end

--- Run a function in a coroutine for async execution
-- @param func function - The function to run in a coroutine
-- @note Essential for non-blocking UI during long-running scans
function M.run_async(func)
    local co = coroutine.create(func)
    local function resume(...)
        local status, res = coroutine.resume(co, ...)
        if not status then
            msg.error("Coroutine error: " .. tostring(res))
            state.scanning = false
        end
    end
    resume()
end

--- Get the system temporary directory
-- @return string - Path to the temp directory
function M.get_temp_dir()
    return os.getenv("TEMP") or os.getenv("TMP") or os.getenv("TMPDIR") or "/tmp"
end

--- Get the full path for the video fingerprint file
-- @return string - Full path to the video fingerprint file
-- @note Uses mp.utils.join_path()
function M.get_video_fingerprint_path()
    local temp_dir = M.get_temp_dir()
    return mp_utils.join_path(temp_dir, config.options.video_temp_filename)
end

--- Get the full path for the audio fingerprint file
-- @return string - Full path to the audio fingerprint file
-- @note Uses mp.utils.join_path()
function M.get_audio_fingerprint_path()
    local temp_dir = M.get_temp_dir()
    return mp_utils.join_path(temp_dir, config.options.audio_temp_filename)
end

return M
