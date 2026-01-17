local mp = require 'mp'
local mp_utils = require 'mp.utils'
local config = require 'modules.config'
local state = require 'modules.state'

local M = {}

--- @table ffmpeg_profiles - Table-based configuration for FFmpeg commands
-- @field fn function - The mpv function to call (mp.command_native, mp.command_native_async, or mp_utils.subprocess)
-- @field build_args function - Function to build the final argument list from params
-- @field capture_stdout boolean|nil - Whether to capture stdout
-- @field capture_stderr boolean|nil - Whether to capture stderr
-- @field is_async boolean|nil - Whether the command is asynchronous
local ffmpeg_profiles = {
    -- Profile: Extract a single video frame for fingerprinting (Sync)
    extract_video = {
        fn = mp_utils.subprocess,
        build_args = function(p)
            local vf_str = string.format("scale=%d:%d:flags=bilinear,format=gray",
                config.options.video_phash_size, config.options.video_phash_size)
            return {
                "ffmpeg", "-hide_banner", "-loglevel", "fatal", "-hwaccel", "auto",
                "-ss", tostring(p.time), "-i", p.path, "-map", "v:0",
                "-vframes", "1", "-vf", vf_str, "-f", "rawvideo", "-y", "-"
            }
        end,
        capture_stdout = true,
        capture_stderr = true
    },
    -- Profile: Extract audio clip for fingerprinting (Sync)
    extract_audio = {
        fn = mp_utils.subprocess,
        build_args = function(p)
            return {
                "ffmpeg", "-hide_banner", "-loglevel", "fatal", "-vn", "-sn",
                "-ss", tostring(p.start), "-t", tostring(p.duration),
                "-i", p.path, "-map", "a:0",
                "-ac", "1", "-ar", tostring(config.options.audio_sample_rate),
                "-af", "dynaudnorm",
                "-f", "s16le", "-y", "-"
            }
        end,
        capture_stdout = true,
        capture_stderr = true
    },
    -- Profile: Scan video segment (Async)
    scan_video = {
        fn = mp.command_native_async,
        build_args = function(p)
            local vf_str = string.format("fps=1/%s,scale=%d:%d:flags=bilinear,format=gray",
                config.options.video_interval, config.options.video_phash_size, config.options.video_phash_size)
            return {
                "ffmpeg", "-hide_banner", "-loglevel", "fatal", "-hwaccel", "auto",
                "-ss", tostring(p.start), "-t", tostring(p.duration),
                "-skip_frame", "bidir", "-skip_loop_filter", "all",
                "-i", p.path, "-map", "v:0", "-vf", vf_str, "-f", "rawvideo", "-"
            }
        end,
        capture_stdout = true,
        capture_stderr = true,
        is_async = true
    },
    -- Profile: Scan audio segment (Async)
    scan_audio = {
        fn = mp.command_native_async,
        build_args = function(p)
            return {
                "ffmpeg", "-hide_banner", "-loglevel", "fatal", "-vn", "-sn",
                "-ss", tostring(p.start), "-t", tostring(p.duration),
                "-i", p.path, "-map", "a:0",
                "-ac", "1", "-ar", tostring(config.options.audio_sample_rate),
                "-af", "dynaudnorm",
                "-f", "s16le", "-y", "-"
            }
        end,
        capture_stdout = true,
        is_async = true
    }
}

--- Execute an FFmpeg task based on a profile
-- @param profile_name string - Key from the ffmpeg_profiles table
-- @param params table - Table of parameters for the argument builder
-- @param callback function|nil - Callback for async tasks (success, res, err)
-- @return table|number|nil - Result table (sync/yielded) or command token (async)
-- @note If is_async is true and no callback is provided while in a coroutine, it will yield and wait for results.
function M.run_task(profile_name, params, callback)
    local p = ffmpeg_profiles[profile_name]
    if not p then
        mp.msg.error("FFmpeg profile not found: " .. tostring(profile_name))
        return nil
    end

    local cmd = {
        name = "subprocess",
        args = p.build_args(params),
        capture_stdout = p.capture_stdout or false,
        capture_stderr = p.capture_stderr or false,
        playback_only = false,
    }

    if p.is_async then
        if callback then
            return p.fn(cmd, callback)
        end

        local co = coroutine.running()
        if co then
            local token = p.fn(cmd, function(success, result, err)
                coroutine.resume(co, success, result, err)
            end)

            if type(token) == "number" then
                state.current_scan_token = token
            end

            local success, result, err = coroutine.yield()
            state.current_scan_token = nil

            if not success then
                return { status = -1, error = err or "Async command failed" }
            end
            return result
        else
            -- No callback and not in coroutine, just fire and forget
            return p.fn(cmd, function() end)
        end
    else
        return p.fn(cmd)
    end
end

return M
