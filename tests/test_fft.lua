local lu = require('tests.luaunit')
local fft = require('modules.fft')
local utils = require('modules.utils')

TestFFT = {}

function TestFFT:test_lua_fft_basic()
    -- Test with DC signal [1, 1, 1, 1]
    -- Expected FFT: [4, 0, 0, 0]
    local n = 4
    local real = {1, 1, 1, 1}
    local imag = {0, 0, 0, 0}

    fft.fft_lua_optimized(real, imag, n)

    -- Check result with some tolerance
    lu.assertAlmostEquals(real[1], 4, 0.0001)
    lu.assertAlmostEquals(imag[1], 0, 0.0001)

    lu.assertAlmostEquals(real[2], 0, 0.0001)
    lu.assertAlmostEquals(real[3], 0, 0.0001)
    lu.assertAlmostEquals(real[4], 0, 0.0001)
end

function TestFFT:test_lua_fft_sine()
    -- Test with Sine wave
    local n = 16
    local input_real = {}
    -- Frequency k=2 (2 full cycles in N samples)
    for i = 0, n-1 do
        input_real[i+1] = math.cos(2 * math.pi * 2 * i / n)
    end

    -- Bit-reverse inputs as required by fft_lua_optimized
    local cache = fft.get_lua_fft_cache(n)
    local rev = cache.rev
    local real = {}
    local imag = {}

    for i = 0, n-1 do
        real[rev[i+1]] = input_real[i+1]
        imag[rev[i+1]] = 0
    end

    fft.fft_lua_optimized(real, imag, n)

    -- Peak should be at index 3 (k=2, 0-based index 2 -> 1-based index 3) and index 15 (k=N-2 -> index 15)
    -- Magnitude should be N/2 for real part? Or N?
    -- For real cosine: 0.5 * (e^ix + e^-ix). FFT(e^ix) is delta at k.
    -- So peaks at k=2 and k=14 with magnitude N/2 = 8.

    lu.assertAlmostEquals(real[3], 8, 0.0001)
    lu.assertAlmostEquals(real[15], 8, 0.0001)
    lu.assertAlmostEquals(imag[3], 0, 0.0001)

    -- DC should be near 0
    lu.assertAlmostEquals(real[1], 0, 0.0001)
end

function TestFFT:test_stockham_fft()
    if not utils.ffi_status then
        print("Skipping FFI tests (FFI not enabled)")
        return
    end

    local ffi = utils.ffi
    local n = 4
    local real = ffi.new("double[?]", n)
    local imag = ffi.new("double[?]", n)
    local y_re = ffi.new("double[?]", n)
    local y_im = ffi.new("double[?]", n)

    -- Set DC signal
    for i = 0, n-1 do
        real[i] = 1
        imag[i] = 0
    end

    fft.fft_stockham(real, imag, y_re, y_im, n)

    -- Verify
    lu.assertAlmostEquals(real[0], 4, 0.0001)
    lu.assertAlmostEquals(real[1], 0, 0.0001)
    lu.assertAlmostEquals(real[2], 0, 0.0001)
    lu.assertAlmostEquals(real[3], 0, 0.0001)
end

function TestFFT:test_stockham_fft_sine()
    if not utils.ffi_status then
        print("Skipping FFI tests (FFI not enabled)")
        return
    end

    local ffi = utils.ffi
    local n = 16
    local real = ffi.new("double[?]", n)
    local imag = ffi.new("double[?]", n)
    local y_re = ffi.new("double[?]", n)
    local y_im = ffi.new("double[?]", n)

    -- Frequency k=2 (2 full cycles in N samples)
    for i = 0, n-1 do
        real[i] = math.cos(2 * math.pi * 2 * i / n)
        imag[i] = 0
    end

    fft.fft_stockham(real, imag, y_re, y_im, n)

    -- For k=2, peak should be at index 2 (if 0-based) or 3 (if 1-based, but C array is 0-based).
    -- Also at N-k = 14.

    -- Let's check index 2 and 14.
    lu.assertAlmostEquals(real[2], 8, 0.0001)
    lu.assertAlmostEquals(real[14], 8, 0.0001)
    lu.assertAlmostEquals(imag[2], 0, 0.0001)

    -- DC should be near 0
    lu.assertAlmostEquals(real[0], 0, 0.0001)
end
