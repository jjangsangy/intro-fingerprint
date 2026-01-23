local mp = require 'mp'
local mp_utils = require 'mp.utils'
local config = require 'modules.config'
local utils = require 'modules.utils'
local sys = require 'modules.sys'

local M = {}

--- Get the full path for the video fingerprint file
-- @return string - Full path to the video fingerprint file
function M.get_video_fingerprint_path()
    local dir = sys.get_fingerprint_dir()
    return mp_utils.join_path(dir, config.options.video_temp_filename)
end

--- Get the full path for the audio fingerprint file
-- @return string - Full path to the audio fingerprint file
function M.get_audio_fingerprint_path()
    local dir = sys.get_fingerprint_dir()
    return mp_utils.join_path(dir, config.options.audio_temp_filename)
end

--- Write video fingerprint to file
-- @param time_pos number - The timestamp of the frame
-- @param data string - The raw image data
-- @return boolean - True if successful, false otherwise
function M.write_video(time_pos, data)
    local path = M.get_video_fingerprint_path()
    utils.log_info("Saving video fingerprint to: " .. path)

    local file = io.open(path, "wb")
    if file then
        file:write(tostring(time_pos) .. "\n")
        file:write(data)
        file:close()
        return true
    end
    return false
end

--- Read video fingerprint from file
-- @return number|nil, string|nil - saved_time, target_bytes (or nil, nil on error)
function M.read_video()
    local path = M.get_video_fingerprint_path()
    local file = io.open(path, "rb")
    if not file then return nil, nil end

    local saved_time_str = file:read("*line")
    local saved_time = tonumber(saved_time_str)

    if not saved_time then
        file:close()
        return nil, nil
    end

    local target_bytes = file:read("*all")
    file:close()

    return saved_time, target_bytes
end

--- Write audio fingerprint to file
-- @param duration number - Duration of the capture
-- @param hashes table|cdata - List of hashes
-- @param count number - Number of hashes
-- @return boolean - True if successful
function M.write_audio(duration, hashes, count)
    local path = M.get_audio_fingerprint_path()
    utils.log_info("Saving audio fingerprint to: " .. path)

    local file = io.open(path, "wb")
    if file then
        file:write("# INTRO_FINGERPRINT_V1\n")
        file:write(string.format("%.4f\n", duration))

        local factor = config.options.audio_hop_size / config.options.audio_sample_rate

        -- Handle both FFI arrays and Lua tables
        if utils.ffi_status and type(hashes) == "cdata" then
            if hashes then
                for i = 0, count - 1 do
                    local h = hashes[i]
                    if h then
                        file:write(string.format("%d %.4f\n", h.h, h.t * factor))
                    end
                end
            end
        else
            if hashes then
                for _, h in ipairs(hashes) do
                    file:write(string.format("%d %.4f\n", h.h, h.t * factor))
                end
            end
        end
        file:close()
        return true
    end
    return false
end

--- Read audio fingerprint from file
-- @return number|nil, table|nil, number - capture_duration, saved_hashes (inverted index), total_hashes
-- @return nil, nil, 0 on failure
function M.read_audio()
    local path = M.get_audio_fingerprint_path()
    local file = io.open(path, "r")
    if not file then return nil, nil, 0 end

    local line = file:read("*line")
    if line == "# INTRO_FINGERPRINT_V1" then
        line = file:read("*line")
    end

    local capture_duration = tonumber(line)
    if not capture_duration then
        file:close()
        return nil, nil, 0
    end

    -- Load saved hashes (Inverted Index)
    local saved_hashes = {} -- hash -> list of times
    local count = 0
    for l in file:lines() do
        local h, t = string.match(l, "([%-]?%d+) ([%d%.]+)")
        h = tonumber(h)
        t = tonumber(t)
        if h and t then
            if not saved_hashes[h] then saved_hashes[h] = {} end
            table.insert(saved_hashes[h], t)
            count = count + 1
        end
    end
    file:close()

    return capture_duration, saved_hashes, count
end

return M
