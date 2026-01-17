local utils = require 'modules.utils'
local M = {}

-- FFT Helpers for both Video & Audio
--- @table lua_fft_caches Cache for FFT twiddle factors, bit-reversal tables, and window functions
local lua_fft_caches = {}

--- Initialize FFT cache for a given size
-- @param n number - FFT size (must be power of 2)
-- @note Pre-calculates trig tables and bit-reversal indices to avoid GC overhead
function M.init_lua_fft_cache(n)
    if lua_fft_caches[n] then return end

    local m = math.log(n) / math.log(2)
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

    local twiddles_re = {}
    local twiddles_im = {}
    local k = 1
    while k < n do
        twiddles_re[k] = {}
        twiddles_im[k] = {}
        for i = 0, k - 1 do
            local angle = -math.pi * i / k
            twiddles_re[k][i] = math.cos(angle)
            twiddles_im[k][i] = math.sin(angle)
        end
        k = k * 2
    end

    local hann = {}
    for i = 0, n - 1 do
        hann[i + 1] = 0.5 * (1 - math.cos(2 * math.pi * i / (n - 1)))
    end

    lua_fft_caches[n] = {
        rev = rev,
        twiddles_re = twiddles_re,
        twiddles_im = twiddles_im,
        hann = hann,
        n = n
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

--- Perform optimized Cooley-Tukey FFT in pure Lua
-- @param real table - Real part of the input/output array (modified in-place)
-- @param imag table - Imaginary part of the input/output array (modified in-place)
-- @param n number - FFT size
-- @note Implementation uses pre-allocated caches and avoids trigonometric calls in the loop
function M.fft_lua_optimized(real, imag, n)
    local cache = M.get_lua_fft_cache(n)
    local tw_re = cache.twiddles_re
    local tw_im = cache.twiddles_im

    local k = 1
    while k < n do
        local step = k * 2
        local tre = tw_re[k]
        local tim = tw_im[k]
        for i = 0, k - 1 do
            local w_real = tre[i]
            local w_imag = tim[i]

            for j = i, n - 1, step do
                local idx1 = j + 1
                local idx2 = j + k + 1

                local r2 = real[idx2]
                local i2 = imag[idx2]
                local t_real = w_real * r2 - w_imag * i2
                local t_imag = w_real * i2 + w_imag * r2

                local r1 = real[idx1]
                local i1 = imag[idx1]
                real[idx2] = r1 - t_real
                imag[idx2] = i1 - t_imag
                real[idx1] = r1 + t_real
                imag[idx1] = i1 + t_imag
            end
        end
        k = step
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
        for i = 0, n - 1 do
            re[i] = x_re[i]
            im[i] = x_im[i]
        end
    end
end

return M
