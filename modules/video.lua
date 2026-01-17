local mp = require 'mp'
local config = require 'modules.config'
local utils = require 'modules.utils'
local fft = require 'modules.fft'
local ffmpeg = require 'modules.ffmpeg'

local M = {}

--- @table POPCOUNT_TABLE lookup table for bit population count (0-255)
local POPCOUNT_TABLE = {}
for i = 0, 255 do
    local c = 0
    local n = i
    while n > 0 do
        if n % 2 == 1 then c = c + 1 end
        n = math.floor(n / 2)
    end
    POPCOUNT_TABLE[i] = c
end

--- Perform 1D DCT-II using Makhoul's reordering and FFT
-- @param input_ptr cdata - Input data array
-- @param n number - Size of the DCT
-- @param output_ptr cdata - Output data array (modified in-place)
-- @param method string - FFT method to use ("lua" or "stockham")
-- @param ctx table - Context containing temporary buffers
-- @note Used as the basis for the pHash calculation
local function dct_1d_makhoul_ffi(input_ptr, n, output_ptr, method, ctx)
    local real = ctx.real
    local imag = ctx.imag

    -- 1. Construct v[n] (Makhoul's reordering)
    local half_n = math.floor(n / 2)
    for i = 0, half_n - 1 do
        real[i] = input_ptr[2 * i]
    end
    for i = 0, half_n - 1 do
        real[half_n + i] = input_ptr[n - 1 - 2 * i]
    end
    for i = 0, n - 1 do imag[i] = 0.0 end

    -- 2. Compute FFT
    if method == "lua" then
        local l_re, l_im = ctx.l_re, ctx.l_im
        local rev = fft.get_lua_fft_cache(n).rev
        for i = 0, n - 1 do
            l_re[rev[i + 1]], l_im[rev[i + 1]] = tonumber(real[i]), tonumber(imag[i])
        end
        fft.fft_lua_optimized(l_re, l_im, n)
        for i = 0, n - 1 do
            real[i], imag[i] = l_re[i + 1], l_im[i + 1]
        end
    else -- stockham
        fft.fft_stockham(real, imag, ctx.wr, ctx.wi, n)
    end

    -- 3. Phase correction & Orthogonal Scaling
    local pi_over_2n = math.pi / (2 * n)
    local scale_ac = math.sqrt(2.0 / n)
    local scale_dc = math.sqrt(1.0 / n)

    for k = 0, n - 1 do
        local angle = k * pi_over_2n
        local val = 2.0 * (real[k] * math.cos(angle) + imag[k] * math.sin(angle))
        if k == 0 then
            output_ptr[k] = val * scale_dc
        else
            output_ptr[k] = val * scale_ac
        end
    end
end

--- @table phash_ctx_cache_ffi Cache for FFI-based pHash context
local phash_ctx_cache_ffi = {}

--- @table phash_lua_context Context and buffers for pure Lua pHash implementation
local phash_lua_context = {
    dct_matrix = nil,
    row_temp = {},
    data = {},
    values_flat = {}
}

--- Initialize the DCT matrix for pure Lua pHash
-- @note Uses matrix multiplication for Partial Direct DCT to improve performance in non-FFI environments
local function init_phash_lua_dct_matrix()
    if phash_lua_context.dct_matrix then return end
    local matrix = {}
    local N = 32
    local scale_dc = math.sqrt(1.0 / N)
    local scale_ac = math.sqrt(2.0 / N)
    for k = 0, 7 do
        matrix[k + 1] = {}
        local scale = (k == 0) and scale_dc or scale_ac
        for n = 0, N - 1 do
            local angle = (math.pi / N) * (n + 0.5) * k
            matrix[k + 1][n + 1] = scale * math.cos(angle)
        end
    end
    phash_lua_context.dct_matrix = matrix
    for x = 1, 8 do
        phash_lua_context.row_temp[x] = {}
        for y = 1, 32 do phash_lua_context.row_temp[x][y] = 0 end
    end
    for i = 1, 1024 do phash_lua_context.data[i] = 0 end
    for i = 1, 64 do phash_lua_context.values_flat[i] = 0 end
end

--- Compute a 32x32 pHash using FFI
-- @param bytes_ptr cdata - Pointer to raw grayscale image data
-- @param start_index number - Offset in the buffer to start reading
-- @return table - 8-byte hash as an array of numbers
-- @note Performs 2D DCT and extracts low-frequency coefficients to generate a 64-bit hash
function M.compute_phash_32_ffi(bytes_ptr, start_index)
    local n = 32
    local data = utils.ffi.new("double[1024]")
    local sum = 0
    for i = 0, 1023 do
        local val = bytes_ptr[start_index + i]
        data[i] = val
        sum = sum + val
    end
    local mean = sum / 1024
    for i = 0, 1023 do data[i] = data[i] - mean end

    if not phash_ctx_cache_ffi[n] then
        phash_ctx_cache_ffi[n] = {
            real = utils.ffi.new("double[?]", n),
            imag = utils.ffi.new("double[?]", n),
            wr = utils.ffi.new("double[?]", n),
            wi = utils.ffi.new("double[?]", n),
            l_re = {},
            l_im = {}
        }
    end
    local ctx = phash_ctx_cache_ffi[n]

    local method = "stockham"
    local tmp_in, tmp_out = utils.ffi.new("double[32]"), utils.ffi.new("double[32]")
    -- Rows
    for y = 0, 31 do
        local offset = y * 32
        for x = 0, 31 do tmp_in[x] = data[offset + x] end
        dct_1d_makhoul_ffi(tmp_in, 32, tmp_out, method, ctx)
        for x = 0, 31 do data[offset + x] = tmp_out[x] end
    end
    -- Cols
    for x = 0, 31 do
        for y = 0, 31 do tmp_in[y] = data[y * 32 + x] end
        dct_1d_makhoul_ffi(tmp_in, 32, tmp_out, method, ctx)
        for y = 0, 31 do data[y * 32 + x] = tmp_out[y] end
    end

    local values = {}
    local total_sum = 0
    for y = 0, 7 do
        for x = 0, 7 do
            local val = data[y * 32 + x]
            table.insert(values, val)
            total_sum = total_sum + val
        end
    end
    local mean_threshold = total_sum / 64

    local hash = { 0, 0, 0, 0, 0, 0, 0, 0 }
    for i = 0, 63 do
        if values[i + 1] > mean_threshold then
            local byte_idx = math.floor(i / 8) + 1
            local bit_idx = i % 8
            if utils.bit_status then
                hash[byte_idx] = utils.bit.bor(hash[byte_idx], utils.bit.lshift(1, 7 - bit_idx))
            else
                hash[byte_idx] = hash[byte_idx] + (2 ^ (7 - bit_idx))
            end
        end
    end
    return hash
end

--- Compute a 32x32 pHash using pure Lua
-- @param bytes string - Raw grayscale image data
-- @param start_index number - Offset in the string to start reading
-- @return table - 8-byte hash as an array of numbers
-- @note Uses Partial Direct DCT for performance without LuaJIT FFI
function M.compute_phash_32_lua(bytes, start_index)
    init_phash_lua_dct_matrix()
    local ctx = phash_lua_context
    local dct_mat = ctx.dct_matrix
    if not dct_mat then return { 0, 0, 0, 0, 0, 0, 0, 0 } end

    local values_flat = ctx.values_flat

    local sum = 0
    for i = 0, 1023 do
        local val = string.byte(bytes, start_index + i + 1)
        ctx.data[i + 1] = val
        sum = sum + val
    end
    local mean = sum / 1024

    for y = 0, 31 do
        local offset = y * 32
        for k = 1, 8 do
            local row_sum = 0
            local mat_row = dct_mat[k]
            for n = 1, 32 do
                row_sum = row_sum + (ctx.data[offset + n] - mean) * mat_row[n]
            end
            ctx.row_temp[k][y + 1] = row_sum
        end
    end

    local total_sum = 0
    local values_idx = 1
    for k = 1, 8 do
        local mat_row = dct_mat[k]
        for x = 1, 8 do
            local col_data = ctx.row_temp[x]
            local col_sum = 0
            for n = 1, 32 do
                col_sum = col_sum + col_data[n] * mat_row[n]
            end
            values_flat[values_idx] = col_sum
            total_sum = total_sum + col_sum
            values_idx = values_idx + 1
        end
    end

    local mean_threshold = total_sum / 64
    local hash = { 0, 0, 0, 0, 0, 0, 0, 0 }
    for i = 0, 63 do
        if values_flat[i + 1] > mean_threshold then
            local byte_idx = math.floor(i / 8) + 1
            local bit_idx = i % 8
            if utils.bit_status then
                hash[byte_idx] = utils.bit.bor(hash[byte_idx], utils.bit.lshift(1, 7 - bit_idx))
            else
                hash[byte_idx] = hash[byte_idx] + (2 ^ (7 - bit_idx))
            end
        end
    end
    return hash
end

--- Calculate Hamming distance between two 64-bit hashes
-- @param hash1 table - First hash (array of 8 bytes)
-- @param hash2 table - Second hash (array of 8 bytes)
-- @return number - Hamming distance (0-64)
-- @note Lower distance indicates higher similarity
function M.video_hamming_distance(hash1, hash2)
    local dist = 0
    for i = 1, 8 do
        local val1 = hash1[i]
        local val2 = hash2[i]
        local xor_val

        if utils.bit_status then
            xor_val = utils.bit.bxor(val1, val2)
        else
            local a, b = val1, val2
            local res = 0
            for bit_i = 0, 7 do
                local p = 2 ^ bit_i
                local a_bit = (a % (p * 2) >= p)
                local b_bit = (b % (p * 2) >= p)
                if a_bit ~= b_bit then res = res + p end
            end
            xor_val = res
        end

        dist = dist + POPCOUNT_TABLE[xor_val]
    end
    return dist
end

--- Scan a segment of video for a matching pHash
-- @param start_time number - Start timestamp in the video
-- @param duration number - Duration of the segment to scan
-- @param video_path string - Path to the video file
-- @param target_raw_bytes string|cdata - The reference pHash frame data
-- @param stats table|nil - Table to collect performance statistics
-- @return number|nil, number|nil - Best Hamming distance and its timestamp
-- @note Spawns ffmpeg to extract raw frames and computes pHash for each
-- @note Implementation uses early exit based on threshold and miss count
function M.scan_video_segment(start_time, duration, video_path, target_raw_bytes, stats)
    if duration <= 0 then return nil, nil end

    local ffmpeg_start = mp.get_time()
    local res = ffmpeg.run_task('scan_video', { start = start_time, duration = duration, path = video_path })
    local ffmpeg_end = mp.get_time()

    if not res or res.status ~= 0 or not res.stdout or #res.stdout == 0 then
        -- Silent fail is better for scan loops, but log if debug
        if config.options.debug == "yes" then mp.msg.error("FFmpeg failed during scan.") end
        return nil, nil
    end

    local stream = res.stdout
    local num_frames = math.floor(#stream / config.VIDEO_FRAME_SIZE)

    local target_hash
    if utils.ffi_status then
        local t_ptr = utils.ffi.cast("uint8_t*", target_raw_bytes)
        target_hash = M.compute_phash_32_ffi(t_ptr, 0)
    else
        target_hash = M.compute_phash_32_lua(target_raw_bytes, 0)
    end

    local stream_ptr
    if utils.ffi_status then
        stream_ptr = utils.ffi.cast("uint8_t*", stream)
    end

    local min_dist = 65
    local best_index_of_min = -1

    local last_valid_index = -1
    local last_valid_dist = 65
    local consecutive_misses = 0
    local max_miss_frames = math.ceil(1.0 / config.options.video_interval)

    for i = 0, num_frames - 1 do
        local offset = i * config.VIDEO_FRAME_SIZE
        local current_hash

        if utils.ffi_status then
            current_hash = M.compute_phash_32_ffi(stream_ptr, offset)
        else
            current_hash = M.compute_phash_32_lua(stream, offset)
        end

        local dist = (target_hash and current_hash) and M.video_hamming_distance(target_hash, current_hash) or 65

        if dist < min_dist then
            min_dist = dist
            best_index_of_min = i
        end

        if dist <= config.options.video_threshold then
            last_valid_index = i
            last_valid_dist = dist
            consecutive_misses = 0
        elseif last_valid_index >= 0 then
            consecutive_misses = consecutive_misses + 1
            if consecutive_misses > max_miss_frames then
                break
            end
        end
    end

    if stats then
        stats.ffmpeg = stats.ffmpeg + (ffmpeg_end - ffmpeg_start)
        stats.frames = stats.frames + num_frames
    end

    local final_dist = min_dist
    local match_timestamp = nil

    if last_valid_index >= 0 then
        final_dist = last_valid_dist
        match_timestamp = start_time + (last_valid_index * config.options.video_interval)
    elseif best_index_of_min >= 0 then
        match_timestamp = start_time + (best_index_of_min * config.options.video_interval)
    end

    return final_dist, match_timestamp
end

return M
