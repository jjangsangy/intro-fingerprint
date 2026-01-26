local config = require('modules.config')
local utils = require('modules.utils')

local M = {}

--- Generate Sine Wave PCM data
-- @param freq number Frequency in Hz
-- @param duration_sec number Duration in seconds
-- @return string PCM data (s16le)
function M.generate_sine_pcm(freq, duration_sec)
    local sample_rate = config.options.audio_sample_rate
    local num_samples = math.floor(sample_rate * duration_sec)
    local t_table = {}

    for i = 0, num_samples - 1 do
        local t = i / sample_rate
        local val = math.sin(2 * math.pi * freq * t)
        -- Scale to int16 range
        local val_int = math.floor(val * 32767)
        if val_int > 32767 then val_int = 32767 end
        if val_int < -32768 then val_int = -32768 end

        -- Pack as s16le (little endian)
        if val_int < 0 then val_int = val_int + 65536 end
        local b1 = val_int % 256
        local b2 = math.floor(val_int / 256)
        table.insert(t_table, string.char(b1, b2))
    end
    return table.concat(t_table)
end

--- Convert Lua string to FFI byte array
-- @param str string Input string
-- @return cdata|nil FFI array or nil if FFI not available
function M.string_to_ffi(str)
    if not utils.ffi_status then return nil end
    local len = #str
    local buf = utils.ffi.new("uint8_t[?]", len)
    for i = 0, len - 1 do
        buf[i] = string.byte(str, i + 1)
    end
    return buf
end

--- Generate a 64x64 diagonal gradient image
-- @return string Image data (4096 bytes)
function M.generate_image_diagonal_gradient()
    local t = {}
    for y = 0, 63 do
        for x = 0, 63 do
            local val = math.floor((x + y) * 255 / 126)
            table.insert(t, string.char(val))
        end
    end
    return table.concat(t)
end

--- Generate a flat color image
-- @param val number Pixel value (0-255)
-- @param size number Total size in bytes (default 4096)
-- @return string Image data
function M.generate_image_flat(val, size)
    size = size or 4096
    local t = {}
    for i = 1, size do
        table.insert(t, string.char(val))
    end
    return table.concat(t)
end

--- Generate a random noise image
-- @param seed number Random seed
-- @param size number Total size in bytes (default 4096)
-- @return string Image data
function M.generate_image_random(seed, size)
    size = size or 4096
    math.randomseed(seed)
    local t = {}
    for i = 1, size do
        table.insert(t, string.char(math.random(0, 255)))
    end
    return table.concat(t)
end

return M
