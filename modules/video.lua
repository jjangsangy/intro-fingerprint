local mp = require 'mp'
local config = require 'modules.config'
local utils = require 'modules.utils'
local ffmpeg = require 'modules.ffmpeg'
local pdq_matrix = require 'modules.pdq_matrix'

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

local BUFFER_W_H = 64
local DCT_OUTPUT_W_H = 16
local DCT_OUTPUT_MATRIX_SIZE = DCT_OUTPUT_W_H * DCT_OUTPUT_W_H -- 256
local HASH_LENGTH = 32 -- 256 bits = 32 bytes

local DCT_MATRIX = pdq_matrix.DCT_MATRIX

-- Cache DCT rows for pure Lua performance
local DCT_ROWS = {}
for i = 1, DCT_OUTPUT_W_H do
    DCT_ROWS[i] = DCT_MATRIX[i]
end

-- Cache FFI C types/variables if available
local ffi_dct_matrix
local ffi_float_arr
local ffi_byte_arr
local ffi_double_arr

if utils.ffi_status then
    local ffi = utils.ffi
    -- Create flat DCT matrix for FFI
    ffi_dct_matrix = ffi.new("float[?]", DCT_OUTPUT_W_H * BUFFER_W_H)
    for i = 0, DCT_OUTPUT_W_H - 1 do
        for j = 0, BUFFER_W_H - 1 do
            ffi_dct_matrix[i * BUFFER_W_H + j] = DCT_MATRIX[i + 1][j + 1]
        end
    end
end

--- Calculate Median of a table
-- @param t table - Array of numbers
-- @return number - Median value
local function calculate_median(t)
    table.sort(t)
    local len = #t
    if len % 2 == 0 then
        return (t[len / 2] + t[len / 2 + 1]) / 2
    else
        return t[math.ceil(len / 2)]
    end
end

--- Compute PDQ Hash using FFI
-- @param bytes_ptr cdata - Pointer to raw grayscale image data (64x64)
-- @param start_index number - Offset
-- @return table - 32-byte hash as an array of numbers (0-255)
local function compute_pdq_hash_ffi(bytes_ptr, start_index)
    local ffi = utils.ffi

    -- 1. Convert Input to Float (64x64)
    -- We process column-wise for the first multiplication if we want to match Rust loops:
    -- Rust: intermediate[i][j] = sum(DCT[i][k] * input[k][j])
    -- Input is typically row-major [y][x]. input[k][j] means row k, col j.

    -- Intermediate buffer: 16x64 (1024 floats)
    local intermediate = ffi.new("float[1024]")

    -- Step 1: Intermediate = DCT * Input
    -- DCT is 16x64. Input is 64x64.
    -- intermediate[i][j] (16x64)

    for i = 0, DCT_OUTPUT_W_H - 1 do -- 0..15
        local dct_row_offset = i * BUFFER_W_H
        for j = 0, BUFFER_W_H - 1 do -- 0..63
            local sum = 0.0
            for k = 0, BUFFER_W_H - 1 do -- 0..63
                -- DCT[i][k] * Input[k][j]
                -- Input is row-major: index = k * 64 + j
                local val = bytes_ptr[start_index + k * BUFFER_W_H + j]
                sum = sum + ffi_dct_matrix[dct_row_offset + k] * val
            end
            intermediate[i * BUFFER_W_H + j] = sum
        end
    end

    -- Step 2: Output = Intermediate * DCT^T
    -- Output is 16x16 (256 floats)
    -- output[i][j] = sum(intermediate[i][k] * DCT[j][k])

    local output_vals = {}

    for i = 0, DCT_OUTPUT_W_H - 1 do -- 0..15
        local inter_row_offset = i * BUFFER_W_H
        for j = 0, DCT_OUTPUT_W_H - 1 do -- 0..15
            local dct_row_offset = j * BUFFER_W_H -- This is actually row j of DCT
            local sum = 0.0
            for k = 0, BUFFER_W_H - 1 do -- 0..63
                sum = sum + intermediate[inter_row_offset + k] * ffi_dct_matrix[dct_row_offset + k]
            end
            table.insert(output_vals, sum)
        end
    end

    -- Step 3: Compute Median
    local sorted_vals = {}
    for i = 1, #output_vals do sorted_vals[i] = output_vals[i] end
    local median = calculate_median(sorted_vals)

    -- Step 4: Generate Hash (1 if > median, else 0)
    local hash = {}
    for i = 1, HASH_LENGTH do hash[i] = 0 end

    for i = 0, DCT_OUTPUT_MATRIX_SIZE - 1 do
        if output_vals[i + 1] > median then
            local byte_idx = math.floor(i / 8) + 1
            local bit_idx = i % 8
            -- PDQ Rust implementation: bit 0 is LSB or MSB?
            -- Rust: byte |= 1 << j; where j is 0..7 loop.
            -- hash[HASH_LENGTH - i - 1] = byte; (Wait, looking at rust code)
            -- for i in 0..HASH_LENGTH { ... for j in 0..8 { ... 1<<j } ... }
            -- It constructs bytes.
            -- Let's stick to a consistent order: MSB first (bit 7 down to 0) or LSB first.
            -- Existing pHash implementation used MSB first (1 << (7-bit_idx)).
            -- Rust code: `byte |= 1 << j`. j goes 0..7. So input[i*8 + 0] is LSB.
            -- To match Rust exactly might be tricky without strict ordering check.
            -- As long as we are consistent (Reference vs Query), it works.
            -- I'll use MSB first (1 << (7-bit_idx)) which is standard 'big-endian' bit order.

            if utils.bit_status then
                hash[byte_idx] = utils.bit.bor(hash[byte_idx], utils.bit.lshift(1, 7 - bit_idx))
            else
                hash[byte_idx] = hash[byte_idx] + (2 ^ (7 - bit_idx))
            end
        end
    end

    return hash
end

--- Compute PDQ Hash using Pure Lua
-- @param bytes string - Raw grayscale image data
-- @param start_index number - Offset
-- @return table - 32-byte hash as an array of numbers
local function compute_pdq_hash_lua(bytes, start_index)
    -- Optimized Pure Lua implementation: A * (B * A^T)
    -- 1. Temp = Input * DCT^T
    -- 2. Output = DCT * Temp

    -- Temp flattened: 16x64 = 1024.
    -- Stored column-major relative to Temp (row-major relative to Temp_T).
    -- temp[ (d-1)*64 + r + 1 ] stores Temp_T[d][r+1]
    local temp = {}
    -- Pre-allocate 1024 slots
    for i = 1, 1024 do temp[i] = 0.0 end

    -- Step 1: Compute Temp_T (Input * DCT^T)
    for r = 0, BUFFER_W_H - 1 do
        local row_offset = start_index + r * BUFFER_W_H
        -- Read full row into table (one allocation per row)
        local pixel_row = { string.byte(bytes, row_offset + 1, row_offset + BUFFER_W_H) }

        -- Accumulators for 16 DCT rows
        local s1, s2, s3, s4, s5, s6, s7, s8 = 0, 0, 0, 0, 0, 0, 0, 0
        local s9, s10, s11, s12, s13, s14, s15, s16 = 0, 0, 0, 0, 0, 0, 0, 0

        -- Process in chunks of 8
        for k = 0, 56, 8 do
            local p1, p2, p3, p4, p5, p6, p7, p8 = unpack(pixel_row, k + 1, k + 8)

            -- DCT Row 1
            local d = DCT_ROWS[1]
            s1 = s1 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                      p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 2
            d = DCT_ROWS[2]
            s2 = s2 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                      p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 3
            d = DCT_ROWS[3]
            s3 = s3 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                      p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 4
            d = DCT_ROWS[4]
            s4 = s4 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                      p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 5
            d = DCT_ROWS[5]
            s5 = s5 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                      p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 6
            d = DCT_ROWS[6]
            s6 = s6 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                      p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 7
            d = DCT_ROWS[7]
            s7 = s7 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                      p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 8
            d = DCT_ROWS[8]
            s8 = s8 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                      p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 9
            d = DCT_ROWS[9]
            s9 = s9 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                      p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 10
            d = DCT_ROWS[10]
            s10 = s10 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                        p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 11
            d = DCT_ROWS[11]
            s11 = s11 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                        p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 12
            d = DCT_ROWS[12]
            s12 = s12 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                        p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 13
            d = DCT_ROWS[13]
            s13 = s13 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                        p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 14
            d = DCT_ROWS[14]
            s14 = s14 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                        p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 15
            d = DCT_ROWS[15]
            s15 = s15 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                        p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
            -- DCT Row 16
            d = DCT_ROWS[16]
            s16 = s16 + p1 * d[k + 1] + p2 * d[k + 2] + p3 * d[k + 3] + p4 * d[k + 4] +
                        p5 * d[k + 5] + p6 * d[k + 6] + p7 * d[k + 7] + p8 * d[k + 8]
        end

        -- Write to temp
        local r_idx = r + 1
        temp[r_idx] = s1
        temp[64 + r_idx] = s2
        temp[128 + r_idx] = s3
        temp[192 + r_idx] = s4
        temp[256 + r_idx] = s5
        temp[320 + r_idx] = s6
        temp[384 + r_idx] = s7
        temp[448 + r_idx] = s8
        temp[512 + r_idx] = s9
        temp[576 + r_idx] = s10
        temp[640 + r_idx] = s11
        temp[704 + r_idx] = s12
        temp[768 + r_idx] = s13
        temp[832 + r_idx] = s14
        temp[896 + r_idx] = s15
        temp[960 + r_idx] = s16
    end

    -- Step 2: Compute Output (DCT * Temp)
    -- Initialize output_vals
    local output_vals = {}
    for i = 1, 256 do output_vals[i] = 0.0 end

    -- Optimization: Iterate j (cols of Temp) then k (chunks) then i (rows of DCT).
    -- This allows unpacking Temp values once and reusing them for all DCT rows.
    for j = 1, DCT_OUTPUT_W_H do
        local temp_base = (j - 1) * 64

        for k_chunk = 0, 56, 8 do
            local t1, t2, t3, t4, t5, t6, t7, t8 = unpack(temp, temp_base + k_chunk + 1, temp_base + k_chunk + 8)

            for i = 1, DCT_OUTPUT_W_H do
                local d = DCT_ROWS[i]
                local out_idx = (i - 1) * DCT_OUTPUT_W_H + j

                output_vals[out_idx] = output_vals[out_idx] +
                    t1 * d[k_chunk + 1] +
                    t2 * d[k_chunk + 2] +
                    t3 * d[k_chunk + 3] +
                    t4 * d[k_chunk + 4] +
                    t5 * d[k_chunk + 5] +
                    t6 * d[k_chunk + 6] +
                    t7 * d[k_chunk + 7] +
                    t8 * d[k_chunk + 8]
            end
        end
    end

    -- Median and Hash
    local sorted_vals = {}
    for i = 1, 256 do sorted_vals[i] = output_vals[i] end
    local median = calculate_median(sorted_vals)

    local hash = {}
    for i = 1, HASH_LENGTH do hash[i] = 0 end

    for i = 0, DCT_OUTPUT_MATRIX_SIZE - 1 do
        if output_vals[i + 1] > median then
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

--- Calculate Hamming distance between two 256-bit (32-byte) hashes
-- @param hash1 table - First hash (array of 32 bytes)
-- @param hash2 table - Second hash (array of 32 bytes)
-- @return number - Hamming distance (0-256)
function M.video_hamming_distance(hash1, hash2)
    local dist = 0
    for i = 1, HASH_LENGTH do
        local val1 = hash1[i]
        local val2 = hash2[i]
        local xor_val

        if utils.bit_status then
            xor_val = utils.bit.bxor(val1, val2)
        else
            -- Pure lua XOR
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

--- PDQ Image Domain Quality Metric (Validation)
-- @param frame_data cdata|string - Raw 64x64 frame
-- @param is_ffi boolean
-- @return boolean, string - Valid status and reason
function M.validate_frame(frame_data, is_ffi)
    local get_pixel
    if is_ffi then
        get_pixel = function(idx) return frame_data[idx] end
    else
        get_pixel = function(idx) return string.byte(frame_data, idx + 1) end
    end

    local len = BUFFER_W_H * BUFFER_W_H
    local sum = 0
    local counts = {} -- Histogram for entropy
    for i = 0, 255 do counts[i] = 0 end

    -- 1. Pass: Calculate Sum and Histogram
    for i = 0, len - 1 do
        local val = get_pixel(i)
        sum = sum + val
        counts[val] = counts[val] + 1
    end

    -- 2. Calculate Mean
    local mean = sum / len

    -- 3. Check Brightness (Too dark or Too bright/white)
    -- Low brightness often means black screen/fade.
    -- High brightness could be white flash or solid white.
    if mean < 5 then
        return false, string.format("Too Dark (Mean: %.1f)", mean)
    end
    if mean > 250 then
        return false, string.format("Too Bright (Mean: %.1f)", mean)
    end

    -- 4. Calculate Standard Deviation and Entropy
    local variance_sum = 0
    local entropy = 0

    for i = 0, len - 1 do
        local val = get_pixel(i)
        local diff = val - mean
        variance_sum = variance_sum + (diff * diff)
    end

    for i = 0, 255 do
        if counts[i] > 0 then
            local p = counts[i] / len
            entropy = entropy - (p * math.log(p) / math.log(2))
        end
    end

    local std_dev = math.sqrt(variance_sum / len)

    -- 5. Check Contrast (Standard Deviation)
    -- A solid color (even if not black/white) will have near 0 std dev.
    -- Normal scenes usually have std_dev > 20.
    if std_dev < 10.0 then
        return false, string.format("Low Contrast (StdDev: %.1f)", std_dev)
    end

    -- 6. Check Information Content (Entropy)
    -- Max entropy for 8-bit is 8.0. Random noise is high.
    -- Solid color is 0.
    -- Typical complex scenes > 6.0.
    -- Simple animations/logos might be 4.0-5.0.
    if entropy < 4.0 then
        return false, string.format("Low Information (Entropy: %.1f)", entropy)
    end

    -- 7. PDQ Gradient Sum Quality
    -- Quality = Gradient Sum / 90
    -- Gradient Sum = sum(|u - v|/255) for all adjacent pixels (Horiz and Vert)
    local gradient_sum = 0.0

    -- Vertical diffs
    for y = 0, BUFFER_W_H - 2 do
        for x = 0, BUFFER_W_H - 1 do
            local idx1 = y * BUFFER_W_H + x
            local idx2 = (y + 1) * BUFFER_W_H + x
            local u = get_pixel(idx1)
            local v = get_pixel(idx2)
            gradient_sum = gradient_sum + math.abs(u - v)
        end
    end

    -- Horizontal diffs
    for y = 0, BUFFER_W_H - 1 do
        for x = 0, BUFFER_W_H - 2 do
            local idx1 = y * BUFFER_W_H + x
            local idx2 = y * BUFFER_W_H + x + 1
            local u = get_pixel(idx1)
            local v = get_pixel(idx2)
            gradient_sum = gradient_sum + math.abs(u - v)
        end
    end

    gradient_sum = gradient_sum / 255.0
    local quality = gradient_sum / 90.0

    -- PDQ recommendation is check for gradients.
    -- If we passed entropy/std_dev, we likely have variation,
    -- but this ensures the variation has spatial structure (edges).
    if quality < 0.01 then
        return false, string.format("Low Quality (Gradient: %.3f)", quality)
    end

    return true, "Passed"
end

--- Scan a segment of video for a matching PDQ hash
-- @param start_time number - Start timestamp in the video
-- @param duration number - Duration of the segment to scan
-- @param video_path string - Path to the video file
-- @param target_raw_bytes string|cdata - The reference pHash frame data
-- @param stats table|nil - Table to collect performance statistics
-- @return number|nil, number|nil - Best Hamming distance and its timestamp
function M.scan_video_segment(start_time, duration, video_path, target_raw_bytes, stats)
    if duration <= 0 then return nil, nil end

    local ffmpeg_start = mp.get_time()
    -- Ensure ffmpeg extracts 64x64 frames by using config.VIDEO_FRAME_SIZE (4096)
    local res = ffmpeg.run_task('scan_video', { start = start_time, duration = duration, path = video_path })
    local ffmpeg_end = mp.get_time()

    if not res or res.status ~= 0 or not res.stdout or #res.stdout == 0 then
        if config.options.debug == "yes" then mp.msg.error("FFmpeg failed during scan.") end
        return nil, nil
    end

    local stream = res.stdout
    local num_frames = math.floor(#stream / config.VIDEO_FRAME_SIZE)
    if num_frames == 0 then return nil, nil end

    -- Compute Target Hash
    local target_hash
    if utils.ffi_status then
        local t_ptr = utils.ffi.cast("uint8_t*", target_raw_bytes)
        target_hash = compute_pdq_hash_ffi(t_ptr, 0)
    else
        target_hash = compute_pdq_hash_lua(target_raw_bytes, 0)
    end

    local stream_ptr
    if utils.ffi_status then
        stream_ptr = utils.ffi.cast("uint8_t*", stream)
    end

    local min_dist = 257 -- Max dist is 256
    local best_index_of_min = -1

    local last_valid_index = -1
    local last_valid_dist = 257
    local consecutive_misses = 0
    local max_miss_frames = math.ceil(1.0 / config.options.video_interval)

    for i = 0, num_frames - 1 do
        local offset = i * config.VIDEO_FRAME_SIZE
        local current_hash

        if utils.ffi_status then
            current_hash = compute_pdq_hash_ffi(stream_ptr, offset)
        else
            current_hash = compute_pdq_hash_lua(stream, offset)
        end

        local dist = (target_hash and current_hash) and M.video_hamming_distance(target_hash, current_hash) or 257

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

-- Export compute functions for testing if needed
M.compute_pdq_hash_ffi = compute_pdq_hash_ffi
M.compute_pdq_hash_lua = compute_pdq_hash_lua

return M
