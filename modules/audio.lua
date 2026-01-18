local mp = require 'mp'
local config = require 'modules.config'
local utils = require 'modules.utils'
local fft = require 'modules.fft'

local M = {}

-- Constants for fallback bitwise operations
local MASK_9 = 512
local MASK_14 = 16384
local SHIFT_14 = 16384
local SHIFT_23 = 8388608

--- Extract peaks from magnitude spectrum (Squared Magnitudes)
-- @param magnitudes table - Array of squared magnitudes for each frequency bin
-- @param freq_bin_count number - Number of frequency bins
-- @param threshold_sq number - Squared magnitude threshold
-- @return table - List of indices for the top frequency peaks
-- @note Limits peaks to 5 per frame to maintain fingerprint density and performance
local function get_peaks(magnitudes, freq_bin_count, threshold_sq)
    local peaks = {}
    local p_count = 0

    for i = 2, freq_bin_count - 1 do
        local m = magnitudes[i]
        if m > threshold_sq and m > magnitudes[i - 1] and m > magnitudes[i + 1] then
            -- Store peak: frequency index
            p_count = p_count + 1
            peaks[p_count] = i
        end
    end

    if p_count <= 5 then return peaks end

    -- Keep top 5
    local sorted = {}
    for i = 1, p_count do
        local p = peaks[i]
        sorted[i] = { idx = p, mag = magnitudes[p] }
    end
    table.sort(sorted, function(a, b) return a.mag > b.mag end)
    
    local top_peaks = {}
    for i = 1, 5 do
        top_peaks[i] = sorted[i].idx
    end
    return top_peaks
end

--- Generate hashes from spectrogram peaks
-- @param spectrogram table - Array of frames, each containing a list of peak frequency indices
-- @return table - List of generated hashes with their relative time offsets
-- @note Combines pairs of peaks within a target time window into a single 32-bit hash
local function generate_hashes(spectrogram)
    local hashes = {} -- list of {hash, time_offset}

    for t1, peaks1 in ipairs(spectrogram) do
        for _, f1 in ipairs(peaks1) do
            -- Target zone
            for t2 = t1 + config.options.audio_target_t_min, math.min(#spectrogram, t1 + config.options.audio_target_t_max) do
                local peaks2 = spectrogram[t2]
                for _, f2 in ipairs(peaks2) do
                    local dt = t2 - t1
                    -- Hash: [f1:9][f2:9][dt:14]
                    local h
                    if utils.bit_status then
                        h = utils.bit.bor(
                            utils.bit.lshift(utils.bit.band(f1, 0x1FF), 23),
                            utils.bit.lshift(utils.bit.band(f2, 0x1FF), 14),
                            utils.bit.band(dt, 0x3FFF)
                        )
                    else
                        h = (f1 % MASK_9) * SHIFT_23 +
                            (f2 % MASK_9) * SHIFT_14 +
                            (dt % MASK_14)
                    end
                    table.insert(hashes, { h = h, t = t1 - 1 })
                end
            end
        end
    end
    return hashes
end


--- FFI version of get_peaks
-- @param mags cdata - Pointer to magnitude array
-- @param row_ptr cdata - Pointer to the destination row in the flattened peaks array
-- @param freq_bin_count number - Number of frequency bins
-- @param threshold number - Magnitude threshold for peak detection
-- @return number - Number of peaks found (up to 5)
-- @note Uses insertion sort to find the top 5 peaks efficiently in C-land
local function get_peaks_ffi(mags, row_ptr, freq_bin_count, threshold)
    local count = 0

    -- 0-based indexing for mags (FFI array)
    for i = 1, freq_bin_count - 2 do
        local m = mags[i]
        if m > threshold and m > mags[i - 1] and m > mags[i + 1] then
            -- Found a peak.
            -- Insertion sort into top 5
            local idx = i
            local pos = count
            while pos > 0 do
                -- Compare with magnitude of peak at row_ptr[pos-1]
                if mags[row_ptr[pos - 1]] < m then
                    pos = pos - 1
                else
                    break
                end
            end

            if pos < 5 then
                local end_k = count
                if end_k >= 5 then end_k = 4 end
                for k = end_k, pos + 1, -1 do
                    row_ptr[k] = row_ptr[k - 1]
                end

                row_ptr[pos] = idx
                if count < 5 then count = count + 1 end
            end
        end
    end
    return count
end

--- Generate hashes from peaks using FFI
-- @param peaks cdata - Flattened int16_t array of peaks
-- @param counts cdata - Array of peak counts per frame
-- @param num_frames number - Total number of frames in the segment
-- @return cdata, number - Array of hash_entry structures and the total count
-- @note High-performance hash generation avoiding Lua object allocation
local function generate_hashes_ffi(peaks, counts, num_frames)
    -- Estimate max hashes: 5 peaks * 90 window * 5 peaks * num_frames
    local max_hashes = num_frames * 2250
    local hashes = utils.ffi.new("hash_entry[?]", max_hashes)
    local count = 0

    local t_min = config.options.audio_target_t_min
    local t_max = config.options.audio_target_t_max

    for t1 = 0, num_frames - 1 do
        local c1 = counts[t1]
        if c1 > 0 then
            -- peaks is flattened int16_t array. row size 5.
            local p1_base = t1 * 5

            local limit_t2 = math.min(num_frames, t1 + t_max + 1)
            for t2 = t1 + t_min, limit_t2 - 1 do
                local c2 = counts[t2]
                if c2 > 0 then
                    local p2_base = t2 * 5
                    local dt = t2 - t1

                    for k1 = 0, c1 - 1 do
                        local f1 = peaks[p1_base + k1]
                        for k2 = 0, c2 - 1 do
                            local f2 = peaks[p2_base + k2]

                            local h = utils.bit.bor(
                                utils.bit.lshift(utils.bit.band(f1, 0x1FF), 23),
                                utils.bit.lshift(utils.bit.band(f2, 0x1FF), 14),
                                utils.bit.band(dt, 0x3FFF)
                            )

                            hashes[count].h = h
                            hashes[count].t = t1
                            count = count + 1
                        end
                    end
                end
            end
        end
    end

    return hashes, count
end

--- Validate audio quality (RMS and signal presence)
-- @param pcm_str string - Raw audio data (s16le)
-- @return boolean, string - Validity status and rejection reason (if any)
function M.validate_audio(pcm_str)
    local rms_threshold = 0.005
    local sparsity_threshold = 0.10
    local sum_sq = 0
    local non_zero_count = 0
    local num_samples = 0

    if utils.ffi_status then
        -- FFI Path
        num_samples = math.floor(#pcm_str / 2)
        local ptr = utils.ffi.cast("int16_t*", pcm_str)
        
        for i = 0, num_samples - 1 do
            local val = ptr[i] / 32768.0
            sum_sq = sum_sq + (val * val)
            if val ~= 0 then
                non_zero_count = non_zero_count + 1
            end
        end
    else
        -- Lua Path
        num_samples = math.floor(#pcm_str / 2)
        for i = 1, #pcm_str, 2 do
            local b1 = string.byte(pcm_str, i)
            local b2 = string.byte(pcm_str, i + 1)
            local val = b1 + b2 * 256
            if val > 32767 then val = val - 65536 end
            val = val / 32768.0
            
            sum_sq = sum_sq + (val * val)
            if val ~= 0 then
                non_zero_count = non_zero_count + 1
            end
        end
    end

    if num_samples == 0 then
        return false, "No Audio Data"
    end

    local rms = math.sqrt(sum_sq / num_samples)
    local signal_ratio = non_zero_count / num_samples

    if rms < rms_threshold then
        return false, "Silence Detected"
    end

    if signal_ratio < sparsity_threshold then
        return false, "Signal Too Sparse"
    end

    return true, nil
end

--- Process raw PCM audio data into constellation hashes
-- @param pcm_str string|cdata - Raw audio data (s16le)
-- @return table|cdata, number - List of hashes and their count
-- @note Automatically chooses between pure Lua and FFI implementations based on availability
-- @note Applies Hann windowing and performs FFT-based spectrogram analysis
function M.process_audio_data(pcm_str)
    local fft_size = config.options.audio_fft_size
    local hop_size = config.options.audio_hop_size

    -- --- LUA TABLE PATH (Fallback) ---
    if not utils.ffi_status then
        local spectrogram = {}
        local samples = {}
        local num_samples_raw = math.floor(#pcm_str / 2)
        
        -- Convert s16le string to samples (Direct Indexing)
        for i = 0, num_samples_raw - 1 do
            local base = i * 2 + 1
            local b1 = string.byte(pcm_str, base)
            local b2 = string.byte(pcm_str, base + 1)
            local val = b1 + b2 * 256
            if val > 32767 then val = val - 65536 end
            samples[i + 1] = val / 32768.0
        end

        local num_samples = num_samples_raw
        local cache = fft.get_lua_fft_cache(fft_size)
        if not cache then
            mp.msg.error("FFT cache not initialized")
            return {}, 0
        end
        local rev = cache.rev
        local hann = cache.hann
        local real_buf = {}
        local imag_buf = {}
        
        local threshold_sq = config.options.audio_threshold * config.options.audio_threshold
        local spec_count = 0

        for i = 1, num_samples - fft_size + 1, hop_size do
            -- Scramble into buffer while applying Hann window
            for j = 0, fft_size - 1 do
                local target = rev[j + 1]
                real_buf[target] = samples[i + j] * hann[j + 1]
                imag_buf[target] = 0
            end

            fft.fft_lua_optimized(real_buf, imag_buf, fft_size)

            local mags = {}
            for k = 1, fft_size / 2 do
                -- Use squared magnitude to avoid math.sqrt calls
                mags[k] = real_buf[k] ^ 2 + imag_buf[k] ^ 2
            end

            local peaks = get_peaks(mags, fft_size / 2, threshold_sq)
            spec_count = spec_count + 1
            spectrogram[spec_count] = peaks
        end

        local hashes = generate_hashes(spectrogram)
        return hashes, #hashes
    end

    -- --- FFI PATH ---
    local num_samples = math.floor(#pcm_str / 2)
    local ptr = utils.ffi.cast("int16_t*", pcm_str)

    local samples = utils.ffi.new("double[?]", num_samples)
    for i = 0, num_samples - 1 do
        samples[i] = ptr[i] / 32768.0
    end

    -- Pre-calculate Hann Window
    local hann = utils.ffi.new("double[?]", fft_size)
    for i = 0, fft_size - 1 do
        hann[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (fft_size - 1)))
    end

    -- Buffers for FFT
    local real_buf = utils.ffi.new("double[?]", fft_size)
    local imag_buf = utils.ffi.new("double[?]", fft_size)
    local work_re = utils.ffi.new("double[?]", fft_size)
    local work_im = utils.ffi.new("double[?]", fft_size)
    local mag_buf = utils.ffi.new("double[?]", fft_size / 2)
    local threshold_sq = config.options.audio_threshold * config.options.audio_threshold

    local num_frames = math.floor((num_samples - fft_size) / hop_size) + 1
    if num_frames < 0 then num_frames = 0 end

    -- Spectrogram storage: 5 peaks per frame
    local peaks_flat = utils.ffi.new("int16_t[?]", num_frames * 5)
    local counts = utils.ffi.new("int8_t[?]", num_frames)

    for i = 0, num_frames - 1 do
        local sample_idx = i * hop_size
        for j = 0, fft_size - 1 do
            real_buf[j] = samples[sample_idx + j] * hann[j]
            imag_buf[j] = 0.0
        end

        fft.fft_stockham(real_buf, imag_buf, work_re, work_im, fft_size)

        for k = 0, fft_size / 2 - 1 do
            -- Using squared magnitude to avoid sqrt
            local r = real_buf[k]
            local i_part = imag_buf[k]
            mag_buf[k] = r * r + i_part * i_part
        end

        -- Writes directly to flat array
        counts[i] = get_peaks_ffi(mag_buf, peaks_flat + i * 5, fft_size / 2, threshold_sq)
    end

    return generate_hashes_ffi(peaks_flat, counts, num_frames)
end

return M
