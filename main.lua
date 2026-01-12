-- Configuration
local options = {
    -- Toggle console debug printing (Performance stats, scan info)
    debug = "no",

    -- Audio: Configuration
    audio_sample_rate = 11025,
    audio_fft_size = 2048,
    audio_hop_size = 1024,
    audio_target_t_min = 10,         -- min delay in frames for pairs
    audio_target_t_max = 100,        -- max delay in frames for pairs
    audio_threshold = 10,            -- minimum magnitude for peaks
    audio_scan_limit = 900,          -- max seconds to scan (15 mins)
    audio_fingerprint_duration = 10, -- duration of the audio fingerprint in seconds
    audio_segment_duration = 15,     -- duration of each scan segment in seconds
    audio_concurrency = 4,           -- number of concurrent ffmpeg workers
    audio_min_match_ratio = 0.25,    -- minimum percentage of hashes that must match (0.0 - 1.0)
    audio_use_fftw = "no",           -- use libfftw for FFT processing

    -- Video: Configuration
    video_dhash_width = 9,         -- gradient hash requires specific dhash dimensions: 9x8
    video_dhash_height = 8,
    video_interval = 0.20,         -- time interval to check in seconds (0.20 = 200ms)
    video_threshold = 12,          -- tolerance for Hamming Distance (0-64).
    video_search_window = 10,      -- seconds before/after saved timestamp to search
    video_max_search_window = 300, -- stop expanding after this offset
    video_window_step = 30,        -- step size

    -- Name of the temp files
    video_temp_filename = "mpv_intro_skipper_video.dat",
    audio_temp_filename = "mpv_intro_skipper_audio.dat",

    -- Key Bindings
    key_save_intro = "Ctrl+i",
    key_skip_video = "Ctrl+Shift+s",
    key_skip_audio = "Ctrl+s",
}

local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

require('mp.options').read_options(options, 'intro-fingerprint')

-- Attempt to load FFI (LuaJIT only) and Bit library
local ffi_status, ffi = pcall(require, "ffi")
local bit_status, bit = pcall(require, "bit")

-- Global scanning state to prevent race conditions
local scanning = false
local current_scan_token = nil

-- Constants for fallback bitwise operations
local MASK_9 = 512       -- 2^9
local MASK_14 = 16384    -- 2^14
local SHIFT_14 = 16384   -- 2^14
local SHIFT_23 = 8388608 -- 2^23

-- Frame size in bytes (9 * 8 = 72 bytes)
local VIDEO_FRAME_SIZE = options.video_dhash_width * options.video_dhash_height

-- Helper for debug logging
local function log_info(str)
    if options.debug == "yes" then
        msg.info(str)
    end
end

local function abort_scan()
    if current_scan_token then
        mp.abort_async_command(current_scan_token)
        current_scan_token = nil
    end
    scanning = false
    log_info("Scan aborted.")
end

mp.register_event("end-file", abort_scan)

local function run_async(func)
    local co = coroutine.create(func)
    local function resume(...)
        local status, res = coroutine.resume(co, ...)
        if not status then
            msg.error("Coroutine error: " .. tostring(res))
            scanning = false
        end
    end
    resume()
end

local function async_subprocess(t)
    local co = coroutine.running()
    if not co then return utils.subprocess(t) end

    local cmd = {
        name = "subprocess",
        args = t.args,
        capture_stdout = true,
        capture_stderr = true
    }

    current_scan_token = mp.command_native_async(cmd, function(success, result, err)
        coroutine.resume(co, success, result, err)
    end)

    local success, result, err = coroutine.yield()
    current_scan_token = nil

    if not success then
        return { status = -1, error = err }
    end
    return result
end

-- Pre-calculate bit population count lookup table (0-255)
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

if ffi_status then
    ffi.cdef [[
        typedef unsigned char uint8_t;
        typedef struct { double r; double i; } complex_t;
        typedef int16_t int16;
        typedef struct { uint32_t h; uint32_t t; } hash_entry;

        typedef float fftwf_complex[2];
        typedef struct fftwf_plan_s *fftwf_plan;
        fftwf_plan fftwf_plan_dft_1d(int n, fftwf_complex *in, fftwf_complex *out, int sign, unsigned flags);
        void fftwf_execute(const fftwf_plan plan);
        void fftwf_destroy_plan(fftwf_plan plan);
        void *fftwf_malloc(size_t n);
        void fftwf_free(void *p);
    ]]
end

local fftw_lib = nil
local fftw_path_tried = false

local function get_script_dir()
    local dir = mp.get_script_directory()
    if dir then
        return utils.join_path(dir, "")
    end

    -- Fallback for older mpv versions or unusual environments
    local source = debug.getinfo(1).source
    if source and source:sub(1, 1) == "@" then
        return source:sub(2):match("(.*[/\\])") or ""
    end
    return ""
end

local function load_fftw_library()
    if fftw_lib then return fftw_lib end

    local libs = {}
    if ffi.os == "Windows" then
        libs = { "libfftw3f-3.dll", "libfftw3f-3" }
    elseif ffi.os == "Linux" then
        libs = { "libfftw3f.so.3", "libfftw3f.so", "fftw3f" }
    elseif ffi.os == "OSX" then
        if ffi.arch == "arm64" then
            libs = { "libfftw3f.3.dylib", "libfftw3f.dylib", "fftw3f" }
        end
    end

    local script_dir = get_script_dir()
    local search_paths = {}

    -- 1. Try Local 'libs' directory
    if script_dir ~= "" then
        local local_libs_dir = utils.join_path(script_dir, "libs")
        for _, lib in ipairs(libs) do
            if lib:match("%.") then -- Only check files with extensions locally
                table.insert(search_paths, utils.join_path(local_libs_dir, lib))
            end
        end
    end

    -- 2. Try System paths (ffi.load handles this with just the name)
    for _, lib in ipairs(libs) do
        table.insert(search_paths, lib)
    end

    for _, path in ipairs(search_paths) do
        log_info("Attempting to load FFTW from: " .. path)
        local status, lib = pcall(ffi.load, path)
        if status then
            msg.info("Successfully loaded FFTW from: " .. path)
            return lib
        end
    end

    return nil
end

local function get_temp_dir()
    return os.getenv("TEMP") or os.getenv("TMP") or os.getenv("TMPDIR") or "/tmp"
end

local function get_video_fingerprint_path()
    local temp_dir = get_temp_dir()
    return utils.join_path(temp_dir, options.video_temp_filename)
end

local function get_audio_fingerprint_path()
    local temp_dir = get_temp_dir()
    return utils.join_path(temp_dir, options.audio_temp_filename)
end

-- ==========================================
-- VIDEO ALGORITHM: GRADIENT HASH (dHash)
-- ==========================================

local function compute_video_hash_from_chunk(bytes, start_index, is_ffi)
    local hash = {}

    for y = 0, 7 do
        local row_byte = 0
        local row_offset = (y * 9)

        for x = 0, 7 do
            local idx = start_index + row_offset + x
            local p1, p2

            if is_ffi then
                p1 = bytes[idx]
                p2 = bytes[idx + 1]
            else
                p1 = string.byte(bytes, idx + 1)
                p2 = string.byte(bytes, idx + 2)
            end

            if p1 < p2 then
                if bit_status then
                    row_byte = bit.bor(row_byte, bit.lshift(1, x))
                else
                    row_byte = row_byte + (2 ^ x)
                end
            end
        end
        hash[y + 1] = row_byte
    end
    return hash
end

local function video_hamming_distance(hash1, hash2)
    local dist = 0
    for i = 1, 8 do
        local val1 = hash1[i]
        local val2 = hash2[i]
        local xor_val

        if bit_status then
            xor_val = bit.bxor(val1, val2)
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

local function scan_video_segment(start_time, duration, video_path, target_raw_bytes, stats)
    if duration <= 0 then return nil, nil end

    local args = {
        "ffmpeg",
        "-hide_banner", "-loglevel", "fatal",
        "-hwaccel", "auto",
    }

    local vf = string.format("fps=1/%s,scale=%d:%d:flags=bilinear,format=gray",
        options.video_interval, options.video_dhash_width, options.video_dhash_height)

    local rest_args = {
        "-ss", tostring(start_time),
        "-t", tostring(duration),
        "-skip_frame", "bidir",
        "-skip_loop_filter", "all",
        "-i", video_path,
        "-map", "v:0",
        "-vf", vf,
        "-f", "rawvideo",
        "-"
    }

    for _, v in ipairs(rest_args) do
        table.insert(args, v)
    end

    local ffmpeg_start = mp.get_time()
    local res = async_subprocess({ args = args })
    local ffmpeg_end = mp.get_time()

    if res.status ~= 0 or not res.stdout or #res.stdout == 0 then
        -- Silent fail is better for scan loops, but log if debug
        if options.debug == "yes" then msg.error("FFmpeg failed during scan.") end
        return nil, nil
    end

    local stream = res.stdout
    local num_frames = math.floor(#stream / VIDEO_FRAME_SIZE)

    local target_hash
    if ffi_status then
        local t_ptr = ffi.cast("uint8_t*", target_raw_bytes)
        target_hash = compute_video_hash_from_chunk(t_ptr, 0, true)
    else
        target_hash = compute_video_hash_from_chunk(target_raw_bytes, 0, false)
    end

    local stream_ptr
    if ffi_status then
        stream_ptr = ffi.cast("uint8_t*", stream)
    end

    local min_dist = 65
    local best_index_of_min = -1

    local last_valid_index = -1
    local last_valid_dist = 65
    local consecutive_misses = 0
    local max_miss_frames = math.ceil(1.0 / options.video_interval)

    for i = 0, num_frames - 1 do
        local offset = i * VIDEO_FRAME_SIZE
        local current_hash

        if ffi_status then
            current_hash = compute_video_hash_from_chunk(stream_ptr, offset, true)
        else
            current_hash = compute_video_hash_from_chunk(stream, offset, false)
        end

        local dist = video_hamming_distance(target_hash, current_hash)

        if dist < min_dist then
            min_dist = dist
            best_index_of_min = i
        end

        if dist <= options.video_threshold then
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
        match_timestamp = start_time + (last_valid_index * options.video_interval)
    elseif best_index_of_min >= 0 then
        match_timestamp = start_time + (best_index_of_min * options.video_interval)
    end

    return final_dist, match_timestamp
end

-- ==========================================
-- AUDIO ALGORITHM: CONSTELLATION HASHING
-- ==========================================

-- Simple Cooley-Tukey FFT (Iterative for performance, bit-reversal approach)
-- Input: real array. Output: real, imag arrays.
local function fft_simple(real_in, n)
    if n <= 1 then return real_in, {} end

    -- This is a very basic Lua FFT. For production, a specialized library is better.
    -- However, for 2048 points, this recursion might be too deep/slow in Lua.
    -- We'll use an iterative bit-reversal approach.

    local m = math.log(n) / math.log(2)
    local cos = math.cos
    local sin = math.sin
    local pi = math.pi

    local real = {}
    local imag = {}

    -- Bit reversal
    for i = 0, n - 1 do
        local j = 0
        local k = i
        for _ = 1, m do
            j = j * 2 + (k % 2)
            k = math.floor(k / 2)
        end
        real[j + 1] = real_in[i + 1] or 0
        imag[j + 1] = 0
    end

    local k = 1
    while k < n do
        local step = k * 2
        for i = 0, k - 1 do
            local angle = -pi * i / k
            local w_real = cos(angle)
            local w_imag = sin(angle)

            for j = i, n - 1, step do
                local idx1 = j + 1
                local idx2 = j + k + 1

                local t_real = w_real * real[idx2] - w_imag * imag[idx2]
                local t_imag = w_real * imag[idx2] + w_imag * real[idx2]

                real[idx2] = real[idx1] - t_real
                imag[idx2] = imag[idx1] - t_imag
                real[idx1] = real[idx1] + t_real
                imag[idx1] = imag[idx1] + t_imag
            end
        end
        k = step
    end

    return real, imag
end

-- Extract peaks from magnitude spectrum
local function get_peaks(magnitudes, freq_bin_count)
    -- Divide into bands to ensure spread (optional, but good for robustness)
    -- We'll just take local maxima above threshold
    local peaks = {}
    local threshold = options.audio_threshold

    for i = 2, freq_bin_count - 1 do
        local m = magnitudes[i]
        if m > threshold and m > magnitudes[i - 1] and m > magnitudes[i + 1] then
            -- Store peak: frequency index
            table.insert(peaks, i)
        end
    end
    -- Sort peaks by magnitude? Optional. We just take them.
    -- Limit number of peaks per frame to avoid noise
    if #peaks > 5 then
        -- Keep top 5
        local sorted = {}
        for _, p in ipairs(peaks) do
            table.insert(sorted, { idx = p, mag = magnitudes[p] })
        end
        table.sort(sorted, function(a, b) return a.mag > b.mag end)
        peaks = {}
        for i = 1, 5 do
            table.insert(peaks, sorted[i].idx)
        end
    end
    return peaks
end

-- Generate hashes from spectrogram peaks
-- spectrogram: array of frames, each frame is list of peak freq indices
local function generate_hashes(spectrogram)
    local hashes = {} -- list of {hash, time_offset}

    for t1, peaks1 in ipairs(spectrogram) do
        for _, f1 in ipairs(peaks1) do
            -- Target zone
            for t2 = t1 + options.audio_target_t_min, math.min(#spectrogram, t1 + options.audio_target_t_max) do
                local peaks2 = spectrogram[t2]
                for _, f2 in ipairs(peaks2) do
                    local dt = t2 - t1
                    -- Hash: [f1:9][f2:9][dt:14]
                    local h
                    if bit_status then
                        h = bit.bor(
                            bit.lshift(bit.band(f1, 0x1FF), 23),
                            bit.lshift(bit.band(f2, 0x1FF), 14),
                            bit.band(dt, 0x3FFF)
                        )
                    else
                        -- Arithmetic fallback: (f1 % 512) << 23 | (f2 % 512) << 14 | (dt % 16384)
                        -- Since fields do not overlap, OR is equivalent to ADD.
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

-- Precomputed twiddle tables for FFI FFT
local twiddles_re, twiddles_im = nil, nil
local twiddles_size = 0

local function ensure_twiddles(n)
    if twiddles_size == n then return end
    twiddles_re = ffi.new("double[?]", n)
    twiddles_im = ffi.new("double[?]", n)
    local pi = math.pi
    for i = 0, n - 1 do
        local angle = -2.0 * pi * i / n
        twiddles_re[i] = math.cos(angle)
        twiddles_im[i] = math.sin(angle)
    end
    twiddles_size = n
end

-- Stockham Radix-4 Autosort FFT (FFI Optimized)
-- Uses planar (split-complex) format.
-- n must be a power of 2.
local function fft_stockham(re, im, y_re, y_im, n)
    ensure_twiddles(n)

    local x_re, x_im = re, im
    local z_re, z_im = y_re, y_im

    local l = 1
    local t_re, t_im = twiddles_re, twiddles_im
    local n_quarter = n / 4
    local n_half = n / 2

    -- If n is not a power of 4 (e.g., 2048), we perform one Radix-2 pass first
    if (math.log(n) / math.log(2)) % 2 ~= 0 then
        for k = 0, n_half - 1 do
            local i0 = k
            local i1 = k + n_half

            local r0, im0 = x_re[i0], x_im[i0]
            local r1, im1 = x_re[i1], x_im[i1]

            z_re[2 * k] = r0 + r1
            z_im[2 * k] = im0 + im1
            z_re[2 * k + 1] = r0 - r1
            z_im[2 * k + 1] = im0 - im1
        end
        l = 2
        -- Swap pointers
        x_re, z_re = z_re, x_re
        x_im, z_im = z_im, x_im
    end

    -- Radix-4 passes
    while l <= n_quarter do
        local m = n / (4 * l)

        -- To improve JIT compilation and cache performance, we need unit-stride access in the inner loop.
        -- When l is small (l=1), j-outer/k-inner is efficient.
        -- When l is large, swapping to k-outer/j-inner ensures data access is unit-stride.
        if l == 1 then
            -- Trivial multiplications for l=1 (j is always 0, w=1)
            for k = 0, m - 1 do
                local i0 = k
                local i1 = i0 + n_quarter
                local i2 = i1 + n_quarter
                local i3 = i2 + n_quarter

                local r0, im0 = x_re[i0], x_im[i0]
                local r1, im1 = x_re[i1], x_im[i1]
                local r2, im2 = x_re[i2], x_im[i2]
                local r3, im3 = x_re[i3], x_im[i3]

                local a02r, a02i = r0 + r2, im0 + im2
                local a13r, a13i = r1 + r3, im1 + im3
                local s02r, s02i = r0 - r2, im0 - im2
                local s13r, s13i = r1 - r3, im1 - im3

                local dst = 4 * k
                z_re[dst] = a02r + a13r
                z_im[dst] = a02i + a13i
                z_re[dst + 1] = s02r + s13i
                z_im[dst + 1] = s02i - s13r
                z_re[dst + 2] = a02r - a13r
                z_im[dst + 2] = a02i - a13i
                z_re[dst + 3] = s02r - s13i
                z_im[dst + 3] = s02i + s13r
            end
        else
            -- Swapped loop for l > 1: j is now the inner loop (unit stride)
            for k = 0, m - 1 do
                local base_i = k * l
                local base_z = 4 * k * l

                -- Peel j=0 iteration to avoid complex multiplications (w=1)
                do
                    local i0 = base_i
                    local i1 = i0 + n_quarter
                    local i2 = i1 + n_quarter
                    local i3 = i2 + n_quarter

                    local r0, im0 = x_re[i0], x_im[i0]
                    local r1, im1 = x_re[i1], x_im[i1]
                    local r2, im2 = x_re[i2], x_im[i2]
                    local r3, im3 = x_re[i3], x_im[i3]

                    local a02r, a02i = r0 + r2, im0 + im2
                    local a13r, a13i = r1 + r3, im1 + im3
                    local s02r, s02i = r0 - r2, im0 - im2
                    local s13r, s13i = r1 - r3, im1 - im3

                    z_re[base_z] = a02r + a13r
                    z_im[base_z] = a02i + a13i
                    z_re[base_z + l] = s02r + s13i
                    z_im[base_z + l] = s02i - s13r
                    z_re[base_z + 2 * l] = a02r - a13r
                    z_im[base_z + 2 * l] = a02i - a13i
                    z_re[base_z + 3 * l] = s02r - s13i
                    z_im[base_z + 3 * l] = s02i + s13r
                end

                for j = 1, l - 1 do
                    local i0 = base_i + j
                    local i1 = i0 + n_quarter
                    local i2 = i1 + n_quarter
                    local i3 = i2 + n_quarter

                    local r0, im0 = x_re[i0], x_im[i0]
                    local r1, im1 = x_re[i1], x_im[i1]
                    local r2, im2 = x_re[i2], x_im[i2]
                    local r3, im3 = x_re[i3], x_im[i3]

                    local w1r, w1i = t_re[j * m], t_im[j * m]
                    local w2r, w2i = t_re[j * 2 * m], t_im[j * 2 * m]
                    local w3r, w3i = t_re[j * 3 * m], t_im[j * 3 * m]

                    local t1r = r1 * w1r - im1 * w1i
                    local t1i = r1 * w1i + im1 * w1r
                    local t2r = r2 * w2r - im2 * w2i
                    local t2i = r2 * w2i + im2 * w2r
                    local t3r = r3 * w3r - im3 * w3i
                    local t3i = r3 * w3i + im3 * w3r

                    local a02r, a02i = r0 + t2r, im0 + t2i
                    local a13r, a13i = t1r + t3r, t1i + t3i
                    local s02r, s02i = r0 - t2r, im0 - t2i
                    local s13r, s13i = t1r - t3r, t1i - t3i

                    local dst = base_z + j
                    z_re[dst] = a02r + a13r
                    z_im[dst] = a02i + a13i
                    z_re[dst + l] = s02r + s13i
                    z_im[dst + l] = s02i - s13r
                    z_re[dst + 2 * l] = a02r - a13r
                    z_im[dst + 2 * l] = a02i - a13i
                    z_re[dst + 3 * l] = s02r - s13i
                    z_im[dst + 3 * l] = s02i + s13r
                end
            end
        end
        l = l * 4
        x_re, z_re = z_re, x_re
        x_im, z_im = z_im, x_im
    end

    -- If final result is in scratch buffer, copy it back
    if x_re ~= re then
        for i = 0, n - 1 do
            re[i] = x_re[i]
            im[i] = x_im[i]
        end
    end
end

-- FFI version of get_peaks
-- Writes up to 5 peaks into row_ptr[0..4]
-- Returns number of peaks found
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

local function generate_hashes_ffi(peaks, counts, num_frames)
    -- Estimate max hashes: 5 peaks * 90 window * 5 peaks * num_frames
    local max_hashes = num_frames * 2250
    local hashes = ffi.new("hash_entry[?]", max_hashes)
    local count = 0

    local t_min = options.audio_target_t_min
    local t_max = options.audio_target_t_max

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

                            local h = bit.bor(
                                bit.lshift(bit.band(f1, 0x1FF), 23),
                                bit.lshift(bit.band(f2, 0x1FF), 14),
                                bit.band(dt, 0x3FFF)
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

-- Process PCM data to hashes
local function process_audio_data(pcm_str)
    local fft_size = options.audio_fft_size
    local hop_size = options.audio_hop_size
    local spectrogram = {}

    -- --- FFI PATH ---
    if ffi_status then
        local num_samples = math.floor(#pcm_str / 2)
        local ptr = ffi.cast("int16_t*", pcm_str)

        -- FFTW logic branch
        if options.audio_use_fftw == "yes" then
            if not fftw_lib and not fftw_path_tried then
                fftw_path_tried = true
                msg.info("FFTW enabled in config. Searching for library...")
                fftw_lib = load_fftw_library()
                if not fftw_lib then
                    msg.error("Could not find or load FFTW library. Falling back to internal FFT.")
                end
            end

            if fftw_lib then
                local samples = ffi.new("double[?]", num_samples)
                for i = 0, num_samples - 1 do
                    samples[i] = ptr[i] / 32768.0
                end

                local hann = ffi.new("double[?]", fft_size)
                for i = 0, fft_size - 1 do
                    hann[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (fft_size - 1)))
                end

                local fft_in = fftw_lib.fftwf_malloc(ffi.sizeof("fftwf_complex") * fft_size)
                local fft_out = fftw_lib.fftwf_malloc(ffi.sizeof("fftwf_complex") * fft_size)
                local fft_in_c = ffi.cast("fftwf_complex*", fft_in)
                local fft_out_c = ffi.cast("fftwf_complex*", fft_out)

                -- FFTW_FORWARD = -1, FFTW_ESTIMATE = 64
                local plan = fftw_lib.fftwf_plan_dft_1d(fft_size, fft_in_c, fft_out_c, -1, 64)

                local num_frames = math.floor((num_samples - fft_size) / hop_size) + 1
                if num_frames < 0 then num_frames = 0 end

                local peaks_flat = ffi.new("int16_t[?]", num_frames * 5)
                local counts = ffi.new("int8_t[?]", num_frames)
                local mag_buf = ffi.new("double[?]", fft_size / 2)
                local threshold_sq = options.audio_threshold * options.audio_threshold

                for i = 0, num_frames - 1 do
                    local sample_idx = i * hop_size
                    for j = 0, fft_size - 1 do
                        fft_in_c[j][0] = samples[sample_idx + j] * hann[j]
                        fft_in_c[j][1] = 0.0
                    end

                    fftw_lib.fftwf_execute(plan)
                    for k = 0, fft_size / 2 - 1 do

                        -- Using squared magnitude to avoid sqrt
                        local r = fft_out_c[k][0]
                        local i_part = fft_out_c[k][1]
                        mag_buf[k] = r * r + i_part * i_part
                    end
                    counts[i] = get_peaks_ffi(mag_buf, peaks_flat + i * 5, fft_size / 2, threshold_sq)
                end

                fftw_lib.fftwf_destroy_plan(plan)
                fftw_lib.fftwf_free(fft_in)
                fftw_lib.fftwf_free(fft_out)

                return generate_hashes_ffi(peaks_flat, counts, num_frames)
            end
        end

        -- Original FFI Path (Fallback)
        local samples = ffi.new("double[?]", num_samples)
        for i = 0, num_samples - 1 do
            samples[i] = ptr[i] / 32768.0
        end

        -- Pre-calculate Hann Window
        local hann = ffi.new("double[?]", fft_size)
        for i = 0, fft_size - 1 do
            hann[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (fft_size - 1)))
        end

        -- Buffers for FFT
        local real_buf = ffi.new("double[?]", fft_size)
        local imag_buf = ffi.new("double[?]", fft_size)
        local work_re = ffi.new("double[?]", fft_size)
        local work_im = ffi.new("double[?]", fft_size)
        local mag_buf = ffi.new("double[?]", fft_size / 2)
        local threshold_sq = options.audio_threshold * options.audio_threshold

        local num_frames = math.floor((num_samples - fft_size) / hop_size) + 1
        if num_frames < 0 then num_frames = 0 end

        -- Spectrogram storage: 5 peaks per frame
        local peaks_flat = ffi.new("int16_t[?]", num_frames * 5)
        local counts = ffi.new("int8_t[?]", num_frames)

        for i = 0, num_frames - 1 do
            local sample_idx = i * hop_size
            for j = 0, fft_size - 1 do
                real_buf[j] = samples[sample_idx + j] * hann[j]
                imag_buf[j] = 0.0
            end

            fft_stockham(real_buf, imag_buf, work_re, work_im, fft_size)

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

    -- --- LUA TABLE PATH (Fallback) ---
    local samples = {}
    -- Convert s16le string to samples
    for i = 1, #pcm_str, 2 do
        local b1 = string.byte(pcm_str, i)
        local b2 = string.byte(pcm_str, i + 1)
        local val = b1 + b2 * 256
        if val > 32767 then val = val - 65536 end
        table.insert(samples, val / 32768.0)
    end

    local num_samples = #samples
    local hann = {}
    for i = 0, fft_size - 1 do
        hann[i + 1] = 0.5 * (1 - math.cos(2 * math.pi * i / (fft_size - 1)))
    end

    for i = 1, num_samples - fft_size + 1, hop_size do
        local window = {}
        for j = 0, fft_size - 1 do
            window[j + 1] = samples[i + j] * hann[j + 1]
        end

        local real, imag = fft_simple(window, fft_size)
        local mags = {}
        for k = 1, fft_size / 2 do
            mags[k] = math.sqrt(real[k] ^ 2 + imag[k] ^ 2)
        end

        local peaks = get_peaks(mags, fft_size / 2)
        table.insert(spectrogram, peaks)
    end

    local hashes = generate_hashes(spectrogram)
    return hashes, #hashes
end

-- ==========================================
-- MAIN FUNCTIONS
-- ==========================================

-- 1. SAVE FINGERPRINT (VIDEO + AUDIO)
local function save_intro()
    local path = mp.get_property("path")
    local time_pos = mp.get_property_number("time-pos")

    if not path or not time_pos then
        mp.osd_message("Cannot capture: No video playing", 2)
        return
    end

    mp.osd_message("Generating fingerprints...", 120)

    -- --- VIDEO SAVE ---
    local fp_path_v = get_video_fingerprint_path()
    log_info("Saving video fingerprint to: " .. fp_path_v)

    local vf = string.format("scale=%d:%d:flags=bilinear,format=gray", options.video_dhash_width,
        options.video_dhash_height)
    local args_v = {
        "ffmpeg", "-hide_banner", "-loglevel", "fatal", "-hwaccel", "auto",
        "-ss", tostring(time_pos), "-i", path, "-map", "v:0",
        "-vframes", "1", "-vf", vf, "-f", "rawvideo", "-y", "-"
    }

    local res_v = utils.subprocess({ args = args_v, cancellable = false, capture_stderr = true })

    if res_v.status == 0 and res_v.stdout and #res_v.stdout > 0 then
        local file_v = io.open(fp_path_v, "wb")
        if file_v then
            file_v:write(tostring(time_pos) .. "\n")
            file_v:write(res_v.stdout)
            file_v:close()
        end
    else
        mp.osd_message("Error capturing video frame", 3)
    end

    -- --- AUDIO SAVE ---
    local fp_path_a = get_audio_fingerprint_path()
    log_info("Saving audio fingerprint to: " .. fp_path_a)

    local start_a = math.max(0, time_pos - options.audio_fingerprint_duration)
    local dur_a = time_pos - start_a

    if dur_a > 1 then
        local args_a = {
            "ffmpeg", "-hide_banner", "-loglevel", "fatal", "-vn", "-sn",
            "-ss", tostring(start_a), "-t", tostring(dur_a),
            "-i", path, "-map", "a:0",
            "-ac", "1", "-ar", tostring(options.audio_sample_rate),
            "-f", "s16le", "-y", "-"
        }
        local res_a = utils.subprocess({ args = args_a, cancellable = false, capture_stderr = true })

        if res_a.status == 0 and res_a.stdout and #res_a.stdout > 0 then
            local hashes, count = process_audio_data(res_a.stdout)
            log_info("Generated " .. count .. " audio hashes")

            local file_a = io.open(fp_path_a, "wb")
            if file_a then
                -- Format:
                -- Line 1: Header/Version
                -- Line 2: Duration of the capture (offset to skip to)
                -- Lines 3+: hash time
                file_a:write("# INTRO_FINGERPRINT_V1\n")
                file_a:write(string.format("%.4f\n", dur_a))

                local factor = options.audio_hop_size / options.audio_sample_rate
                if ffi_status and type(hashes) == "cdata" then
                    for i = 0, count - 1 do
                        local h = hashes[i]
                        file_a:write(string.format("%d %.4f\n", h.h, h.t * factor))
                    end
                else
                    for _, h in ipairs(hashes) do
                        file_a:write(string.format("%d %.4f\n", h.h, h.t * factor))
                    end
                end
                file_a:close()
            end
        else
            log_info("Error capturing audio: " .. (res_a.stderr or "unknown"))
        end
    end
    mp.osd_message("Intro Captured! (Video + Audio)", 2)
end

-- 2. SKIP INTRO (VIDEO)
local function skip_intro_video()
    if scanning then
        mp.osd_message("Scan in progress...", 2)
        return
    end

    run_async(function()
        local fp_path = get_video_fingerprint_path()
        local file = io.open(fp_path, "rb")

        if not file then
            mp.osd_message("No intro captured yet.", 2)
            return
        end

        local saved_time_str = file:read("*line")
        local saved_time = tonumber(saved_time_str)

        if not saved_time then
            mp.osd_message("Corrupted fingerprint file.", 2)
            file:close()
            return
        end

        local target_bytes = file:read("*all")
        file:close()

        if not target_bytes or #target_bytes < VIDEO_FRAME_SIZE then
            mp.osd_message("Invalid fingerprint data.", 2)
            return
        end

        scanning = true

        local perf_stats = { ffmpeg = 0, lua = 0, frames = 0 }
        local scan_start_time = mp.get_time()

        local function finish_scan(message)
            scanning = false

            local total_dur = mp.get_time() - scan_start_time
            perf_stats.lua = total_dur - perf_stats.ffmpeg

            if options.debug == "yes" then
                msg.info(string.format("TOTAL PERF (Video): FFmpeg: %.4fs | Lua: %.4fs | Total: %.4fs | Frames: %d",
                    perf_stats.ffmpeg, perf_stats.lua, total_dur, perf_stats.frames))
            end

            if message then mp.osd_message(message, 2) end
        end

        local current_video = mp.get_property("path")
        local total_duration = mp.get_property_number("duration") or math.huge

        mp.osd_message(
            string.format("Scanning Video %d%%...",
                math.floor(options.video_search_window / options.video_max_search_window * 100)),
            60)

        local window_size = options.video_search_window
        local scanned_start = math.max(0, saved_time - window_size)
        local scanned_end = math.min(total_duration, saved_time + window_size)

        local dist, timestamp = scan_video_segment(scanned_start, scanned_end - scanned_start, current_video,
            target_bytes,
            perf_stats)

        if dist and dist <= options.video_threshold then
            mp.set_property("time-pos", timestamp)
            finish_scan(string.format("Skipped! (Dist: %d)", dist))
            return
        end

        while window_size <= options.video_max_search_window do
            if not scanning then break end

            local old_start = scanned_start
            local old_end = scanned_end

            window_size = window_size + options.video_window_step
            scanned_start = math.max(0, saved_time - window_size)
            scanned_end = math.min(total_duration, saved_time + window_size)

            if scanned_start == old_start and scanned_end == old_end then break end

            mp.osd_message(
                string.format("Scanning Video %d%%...",
                    math.min(100, math.floor(window_size / options.video_max_search_window * 100))),
                60)

            if scanned_start < old_start then
                local d, t = scan_video_segment(scanned_start, old_start - scanned_start, current_video, target_bytes,
                    perf_stats)
                if d and d <= options.video_threshold then
                    mp.set_property("time-pos", t)
                    finish_scan(string.format("Skipped! (Dist: %d)", d))
                    return
                end
            end

            if not scanning then break end

            if scanned_end > old_end then
                local d, t = scan_video_segment(old_end, scanned_end - old_end, current_video, target_bytes, perf_stats)
                if d and d <= options.video_threshold then
                    mp.set_property("time-pos", t)
                    finish_scan(string.format("Skipped! (Dist: %d)", d))
                    return
                end
            end
        end

        if scanning then
            finish_scan("No match found.")
        end
    end)
end

-- 3. SKIP INTRO (AUDIO)
local function skip_intro_audio()
    if scanning then
        mp.osd_message("Scan in progress...", 2)
        return
    end

    run_async(function()
        local fp_path = get_audio_fingerprint_path()
        local file = io.open(fp_path, "r")
        if not file then
            mp.osd_message("No audio intro captured.", 2)
            return
        end

        local line = file:read("*line")
        if line == "# INTRO_FINGERPRINT_V1" then
            line = file:read("*line")
        end

        local capture_duration = tonumber(line)
        if not capture_duration then
            mp.osd_message("Invalid audio fingerprint file.", 2)
            file:close()
            return
        end

        -- Load saved hashes (Inverted Index)
        local saved_hashes = {} -- hash -> list of times
        local total_intro_hashes = 0
        for l in file:lines() do
            local h, t = string.match(l, "([%-]?%d+) ([%d%.]+)")
            if h and t then
                h = tonumber(h)
                t = tonumber(t)
                if not saved_hashes[h] then saved_hashes[h] = {} end
                table.insert(saved_hashes[h], t)
                total_intro_hashes = total_intro_hashes + 1
            end
        end
        file:close()

        if total_intro_hashes == 0 then
            mp.osd_message("Empty audio fingerprint.", 2)
            return
        end
        log_info("Loaded " .. total_intro_hashes .. " audio hashes. Duration adj: " .. capture_duration)

        scanning = true
        mp.osd_message("Scanning Audio...", 10)

        local perf_stats = { ffmpeg = 0, lua = 0 }
        local scan_start_time = mp.get_time()

        local function finish_scan(message)
            scanning = false
            local total_dur = mp.get_time() - scan_start_time

            if options.debug == "yes" then
                -- Note: FFmpeg CPU time can exceed total wall clock time due to concurrency
                msg.info(string.format("TOTAL PERF (Audio): Wall Time: %.4fs | FFmpeg CPU Time: %.4fs",
                    total_dur, perf_stats.ffmpeg))
            end
            if message then mp.osd_message(message, 2) end
        end

        local path = mp.get_property("path")
        local duration = mp.get_property_number("duration") or 0
        local max_scan_time = math.min(duration, options.audio_scan_limit)

        -- Global Offset Histogram
        local global_offset_histogram = {}
        local time_bin_width = 0.1
        local factor = options.audio_hop_size / options.audio_sample_rate

        -- Linear Scan Parameters
        local segment_dur = options.audio_segment_duration
        -- Padding: enough to cover audio_target_t_max plus FFT window overhead.
        local padding = math.ceil(options.audio_target_t_max * options.audio_hop_size / options.audio_sample_rate) + 1.0

        -- Concurrency State
        local active_workers = 0
        local processed_count = 0
        local max_workers = options.audio_concurrency
        local next_scan_time = 0
        local results_buffer = {} -- indexed by scan_time
        local stop_flag = false
        local previous_local_max = 0
        local last_processed_time = -segment_dur

        local co = coroutine.running()

        local function spawn_worker(scan_time)
            active_workers = active_workers + 1
            local args = {
                "ffmpeg", "-hide_banner", "-loglevel", "fatal", "-vn", "-sn",
                "-ss", tostring(scan_time), "-t", tostring(segment_dur + padding),
                "-i", path, "-map", "a:0",
                "-ac", "1", "-ar", tostring(options.audio_sample_rate),
                "-f", "s16le", "-y", "-"
            }

            local ffmpeg_start = mp.get_time()
            mp.command_native_async({ name = "subprocess", args = args, capture_stdout = true },
                function(success, res, err)
                    active_workers = active_workers - 1
                    perf_stats.ffmpeg = perf_stats.ffmpeg + (mp.get_time() - ffmpeg_start)

                    if success and res.status == 0 and res.stdout and not stop_flag then
                        local chunk_hashes, ch_count = process_audio_data(res.stdout)
                        results_buffer[scan_time] = { hashes = chunk_hashes, count = ch_count }
                    else
                        results_buffer[scan_time] = { hashes = {}, count = 0 }
                    end

                    if co then coroutine.resume(co) end
                end)
        end

        -- Main Scheduler / Consumer Loop
        while (next_scan_time < max_scan_time or active_workers > 0) and not stop_flag do
            -- Spawn workers up to max_workers
            while active_workers < max_workers and next_scan_time < max_scan_time and not stop_flag do
                spawn_worker(next_scan_time)
                next_scan_time = next_scan_time + segment_dur
            end

            -- Process completed results in order
            local target_time = last_processed_time + segment_dur
            while results_buffer[target_time] do
                local res = results_buffer[target_time]
                results_buffer[target_time] = nil -- Clear memory
                local chunk_hashes = res.hashes
                local ch_count = res.count

                local local_max = 0
                local local_histogram = {}

                -- Update Global & Local Histograms
                -- Linear Scan Rule: Only accept hashes anchored within the segment [target_time, target_time + segment_dur)
                if ffi_status and type(chunk_hashes) == "cdata" then
                    for i = 0, ch_count - 1 do
                        local ch = chunk_hashes[i]
                        local rel_time = ch.t * factor
                        -- Filter: Ignore hashes that belong to the next segment's padding overlap
                        if rel_time < segment_dur then
                            local track_time = target_time + rel_time
                            local saved = saved_hashes[ch.h]
                            if saved then
                                for _, fp_time in ipairs(saved) do
                                    local offset = track_time - fp_time
                                    local bin = math.floor(offset / time_bin_width + 0.5)
                                    global_offset_histogram[bin] = (global_offset_histogram[bin] or 0) + 1
                                    local_histogram[bin] = (local_histogram[bin] or 0) + 1
                                end
                            end
                        end
                    end
                else
                    for _, ch in ipairs(chunk_hashes) do
                        local rel_time = ch.t * factor
                        if rel_time < segment_dur then
                            local track_time = target_time + rel_time
                            local saved = saved_hashes[ch.h]
                            if saved then
                                for _, fp_time in ipairs(saved) do
                                    local offset = track_time - fp_time
                                    local bin = math.floor(offset / time_bin_width + 0.5)
                                    global_offset_histogram[bin] = (global_offset_histogram[bin] or 0) + 1
                                    local_histogram[bin] = (local_histogram[bin] or 0) + 1
                                end
                            end
                        end
                    end
                end

                for _, cnt in pairs(local_histogram) do
                    if cnt > local_max then local_max = cnt end
                end

                local local_ratio = local_max / total_intro_hashes
                log_info(string.format("Processed segment %.1f: Local max %d (Ratio: %.2f)", target_time, local_max,
                    local_ratio))

                -- Gradient-based early stopping (Ordered check)
                -- Only consider matches that meet the minimum match ratio
                local confidence_threshold = options.audio_threshold * 2.5
                local meets_ratio = local_ratio >= options.audio_min_match_ratio

                if meets_ratio and local_max > previous_local_max then
                    previous_local_max = local_max
                end

                if previous_local_max > confidence_threshold and local_max < (previous_local_max * 0.5) then
                    log_info(string.format("Gradient drop detected (%d -> %d) at %.1f. Stopping.", previous_local_max,
                        local_max, target_time))
                    stop_flag = true
                    break
                end

                last_processed_time = target_time
                target_time = last_processed_time + segment_dur
                processed_count = processed_count + 1
                mp.osd_message(string.format("Scanning Audio %d%%...", math.floor(target_time / max_scan_time * 100)), 1)
            end

            if not stop_flag and (next_scan_time < max_scan_time or active_workers > 0) then
                coroutine.yield()
            end
        end

        if scanning then
            -- Find Peak in Global Histogram
            local best_bin = nil
            local max_val = 0
            for bin, cnt in pairs(global_offset_histogram) do
                if cnt > max_val then
                    max_val = cnt
                    best_bin = bin
                end
            end

            local best_ratio = max_val / total_intro_hashes
            if best_bin and max_val > options.audio_threshold and best_ratio >= options.audio_min_match_ratio then
                local peak_offset = best_bin * time_bin_width
                local target_pos = peak_offset + capture_duration
                mp.set_property("time-pos", target_pos)
                finish_scan(string.format("Skipped! (Score: %d, Ratio: %.2f)", max_val, best_ratio))
            else
                finish_scan(string.format("No match (Best Ratio: %.2f)", best_ratio))
            end
        end
    end)
end

mp.add_key_binding(options.key_save_intro, "save-intro", save_intro)
mp.add_key_binding(options.key_skip_video, "skip-intro-video", skip_intro_video)
mp.add_key_binding(options.key_skip_audio, "skip-intro-audio", skip_intro_audio)
