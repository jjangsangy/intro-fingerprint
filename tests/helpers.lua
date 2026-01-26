local config = require('modules.config')

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

return M
