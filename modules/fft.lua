local utils = require 'modules.utils'
local M = {}

-- FFT Helpers for both Video & Audio
--- @table lua_fft_caches Cache for FFT twiddle factors, bit-reversal tables, and window functions
local lua_fft_caches = {}

--- Initialize FFT cache for a given size
-- @param n number - FFT size (must be power of 2)
-- @note Pre-calculates trig tables and working buffers to avoid GC overhead
function M.init_lua_fft_cache(n)
    if lua_fft_caches[n] then return end

    local m = math.log(n) / math.log(2)
    -- Bit-reversal table (kept for compatibility, though not used by Stockham FFT)
    local rev = {}
    for i = 0, n - 1 do
        local j = 0
        local k = i
        for _ = 1, m do
            j = j * 2 + (k % 2)
            k = math.floor(k / 2)
        end
        rev[i + 1] = j + 1
    end

    -- Twiddle factors for Stockham (flat array)
    -- These correspond to exp(-2*pi*i*j/n) but we only need the table for the full circle
    local twiddles_re = {}
    local twiddles_im = {}
    local pi = math.pi
    for i = 0, n - 1 do
        local angle = -2.0 * pi * i / n
        twiddles_re[i] = math.cos(angle)
        twiddles_im[i] = math.sin(angle)
    end

    -- Hann window
    local hann = {}
    for i = 0, n - 1 do
        hann[i + 1] = 0.5 * (1 - math.cos(2 * math.pi * i / (n - 1)))
    end

    -- Work buffers for Stockham (ping-pong)
    local work_re = {}
    local work_im = {}
    for i = 1, n do
        work_re[i] = 0
        work_im[i] = 0
    end

    lua_fft_caches[n] = {
        rev = rev,
        twiddles_re = twiddles_re,
        twiddles_im = twiddles_im,
        hann = hann,
        work_re = work_re,
        work_im = work_im,
        n = n,
        log2_n = m
    }
end

--- Get a cached Lua FFT configuration
-- @param n number - FFT size
-- @return table|nil - The cached FFT configuration
function M.get_lua_fft_cache(n)
    if not lua_fft_caches[n] then
        M.init_lua_fft_cache(n)
    end
    return lua_fft_caches[n]
end

--- Perform optimized Stockham FFT in pure Lua (Radix-4)
-- @param re table - Real part of the input/output array (modified in-place)
-- @param im table - Imaginary part of the input/output array (modified in-place)
-- @param n number - FFT size
-- @note Implementation uses pre-allocated caches and avoids trigonometric calls in the loop
-- @note Expects NATURAL ORDER input (no bit-reversal needed)
function M.fft_lua_optimized(re, im, n)
    local cache = M.get_lua_fft_cache(n)
    local t_re = cache.twiddles_re
    local t_im = cache.twiddles_im
    local z_re = cache.work_re
    local z_im = cache.work_im
    
    -- Current input/output arrays
    -- We switch references between (re, im) and (z_re, z_im)
    local x_re, x_im = re, im
    local y_re, y_im = z_re, z_im

    local l = 1
    local n_quarter = n / 4
    local n_half = n / 2

    -- If log2(n) is odd, perform one Radix-2 iteration first
    -- Use cached log2_n to avoid math.log
    if cache.log2_n % 2 ~= 0 then
        -- 1-based indexing loop: k=1 to n_half
        for k = 1, n_half do
            local i0 = k
            local i1 = k + n_half

            local r0, im0 = x_re[i0], x_im[i0]
            local r1, im1 = x_re[i1], x_im[i1]

            local dst0 = 2 * k - 1
            local dst1 = 2 * k

            y_re[dst0] = r0 + r1
            y_im[dst0] = im0 + im1
            y_re[dst1] = r0 - r1
            y_im[dst1] = im0 - im1
        end
        l = 2
        -- Swap buffers
        x_re, y_re = y_re, x_re
        x_im, y_im = y_im, x_im
    end

    while l <= n_quarter do
        local m = n / (4 * l)
        
        if l == 1 then
            -- Optimized Radix-4 for l=1 (no twiddles, m iterations)
            local dst = 1
            for k = 1, m do
                -- 1-based input indices
                -- x inputs at k, k+m, k+2m, k+3m (where m=n_quarter)
                local i0 = k
                local i1 = i0 + n_quarter
                local i2 = i1 + n_quarter
                local i3 = i2 + n_quarter

                local r0, im0 = x_re[i0], x_im[i0]
                local r1, im1 = x_re[i1], x_im[i1]
                local r2, im2 = x_re[i2], x_im[i2]
                local r3, im3 = x_re[i3], x_im[i3]

                -- Butterfly operations
                local a02r, a02i = r0 + r2, im0 + im2
                local a13r, a13i = r1 + r3, im1 + im3
                local s02r, s02i = r0 - r2, im0 - im2
                local s13r, s13i = r1 - r3, im1 - im3

                -- Output
                y_re[dst]     = a02r + a13r
                y_im[dst]     = a02i + a13i
                y_re[dst + 1] = s02r + s13i
                y_im[dst + 1] = s02i - s13r
                y_re[dst + 2] = a02r - a13r
                y_im[dst + 2] = a02i - a13i
                y_re[dst + 3] = s02r - s13i
                y_im[dst + 3] = s02i + s13r
                
                dst = dst + 4
            end
        else
            -- General Radix-4 Step
            -- Outer loop runs 'm' times
            -- Inner loop runs 'l' times (j=1 to l-1) plus separate j=0
            
            -- Pointers for incremental updates
            -- base_i corresponds to k*l (0-based) -> k*l + 1 (1-based)
            -- base_z corresponds to 4*k*l (0-based) -> 4*k*l + 1 (1-based)
            local base_i_1 = 1
            local base_z_1 = 1
            
            local stride_i = l
            local stride_z = 4 * l

            -- Pre-calculate twiddle increments
            local tw_step1 = m
            local tw_step2 = 2 * m
            local tw_step3 = 3 * m

            for k = 1, m do
                -- j = 0 iteration (twiddle is 1)
                do
                    local i0 = base_i_1
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

                    local dst = base_z_1
                    y_re[dst]             = a02r + a13r
                    y_im[dst]             = a02i + a13i
                    y_re[dst + l]     = s02r + s13i
                    y_im[dst + l]     = s02i - s13r
                    y_re[dst + 2 * l] = a02r - a13r
                    y_im[dst + 2 * l] = a02i - a13i
                    y_re[dst + 3 * l] = s02r - s13i
                    y_im[dst + 3 * l] = s02i + s13r
                end

                -- j loop (1 to l-1)
                -- Avoid k*l multiplication inside
                -- Access twiddles incrementally
                local w_idx1 = tw_step1
                local w_idx2 = tw_step2
                local w_idx3 = tw_step3
                
                local src_ptr = base_i_1 + 1
                local dst_ptr = base_z_1 + 1
                
                for j = 1, l - 1 do
                    local i0 = src_ptr
                    local i1 = i0 + n_quarter
                    local i2 = i1 + n_quarter
                    local i3 = i2 + n_quarter

                    local r0, im0 = x_re[i0], x_im[i0]
                    local r1, im1 = x_re[i1], x_im[i1]
                    local r2, im2 = x_re[i2], x_im[i2]
                    local r3, im3 = x_re[i3], x_im[i3]

                    -- Twiddle access using incremental indices
                    -- Note: w_idx starts at m (>=1)
                    local w1r, w1i = t_re[w_idx1], t_im[w_idx1]
                    local w2r, w2i = t_re[w_idx2], t_im[w_idx2]
                    local w3r, w3i = t_re[w_idx3], t_im[w_idx3]

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

                    y_re[dst_ptr]             = a02r + a13r
                    y_im[dst_ptr]             = a02i + a13i
                    y_re[dst_ptr + l]     = s02r + s13i
                    y_im[dst_ptr + l]     = s02i - s13r
                    y_re[dst_ptr + 2 * l] = a02r - a13r
                    y_im[dst_ptr + 2 * l] = a02i - a13i
                    y_re[dst_ptr + 3 * l] = s02r - s13i
                    y_im[dst_ptr + 3 * l] = s02i + s13r

                    src_ptr = src_ptr + 1
                    dst_ptr = dst_ptr + 1
                    
                    w_idx1 = w_idx1 + tw_step1
                    w_idx2 = w_idx2 + tw_step2
                    w_idx3 = w_idx3 + tw_step3
                end
                
                -- Increment base pointers for next k
                base_i_1 = base_i_1 + stride_i
                base_z_1 = base_z_1 + stride_z
            end
        end
        l = l * 4
        x_re, y_re = y_re, x_re
        x_im, y_im = y_im, x_im
    end

    -- If the final result is in the work buffer (z_re), copy it back to re
    -- Note: x_re points to the buffer containing the CURRENT result.
    if x_re ~= re then
        for i = 1, n do
            re[i] = x_re[i]
            im[i] = x_im[i]
        end
    end
end

--- @table twiddles_cache Cache for FFI-based twiddle factors
local twiddles_cache = {}

--- Get or create FFI twiddle factors for FFT
-- @param n number - FFT size
-- @return cdata, cdata - Real and Imaginary twiddle factor arrays
function M.get_twiddles(n)
    if twiddles_cache[n] then
        return twiddles_cache[n].re, twiddles_cache[n].im
    end

    local re = utils.ffi.new("double[?]", n)
    local im = utils.ffi.new("double[?]", n)
    local pi = math.pi
    for i = 0, n - 1 do
        local angle = -2.0 * pi * i / n
        re[i] = math.cos(angle)
        im[i] = math.sin(angle)
    end
    twiddles_cache[n] = { re = re, im = im }
    return re, im
end

--- Perform Stockham auto-sort FFT (FFI-based)
-- @param re cdata - Real part array (modified in-place)
-- @param im cdata - Imaginary part array (modified in-place)
-- @param y_re cdata - Work array for real part
-- @param y_im cdata - Work array for imaginary part
-- @param n number - FFT size
-- @note High-performance FFT implementation using LuaJIT FFI and Stockham algorithm
function M.fft_stockham(re, im, y_re, y_im, n)
    local t_re, t_im = M.get_twiddles(n)

    local x_re, x_im = re, im
    local z_re, z_im = y_re, y_im

    local l = 1
    local n_quarter = n / 4
    local n_half = n / 2

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
        x_re, z_re = z_re, x_re
        x_im, z_im = z_im, x_im
    end

    while l <= n_quarter do
        local m = n / (4 * l)
        if l == 1 then
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
            for k = 0, m - 1 do
                local base_i = k * l
                local base_z = 4 * k * l
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

    if x_re ~= re then
        for i = 1, n do
            re[i] = x_re[i]
            im[i] = x_im[i]
        end
    end
end

return M
