local lu = require('tests.luaunit')

-- Setup mocks if needed (for standalone execution)
if not package.preload['mp'] and not package.loaded['mp'] then
    local mocks = require('tests.mocks')
    local mp_mock = mocks.create_mp()
    package.preload['mp'] = function() return mp_mock end
    package.preload['mp.msg'] = function() return mp_mock.msg end
    package.preload['mp.utils'] = function() return mp_mock.utils end
    package.preload['mp.options'] = function() return mp_mock.options end
end

local fft = require('modules.fft')

-- Mock ffi for zfft if running on standard Lua
if not package.preload['ffi'] then
    package.preload['ffi'] = function() return {} end
end

local zfft = require('tests.zfft')

TestFFTPerf = {}

function TestFFTPerf:test_perf_comparison()
    -- Use a reasonably large N to amortize overhead
    local n = 2048
    local iterations = 50

    -- 1. Setup local FFT (cache warmup)
    fft.init_lua_fft_cache(n)
    local cache = fft.get_lua_fft_cache(n)
    local rev = cache.rev
    local real_buf = {}
    local imag_buf = {}
    -- Pre-allocate
    for i = 1, n do real_buf[i] = 0; imag_buf[i] = 0 end

    -- Generate random input
    local input = {}
    for i = 1, n do input[i] = math.random() end

    -- Measure Local FFT
    -- We include scrambling time because it's part of the usage pattern for this implementation
    local start_time = os.clock()
    for _ = 1, iterations do
        -- Scramble
        for i = 0, n - 1 do
            local val = input[i + 1]
            local target = rev[i + 1]
            real_buf[target] = val
            imag_buf[target] = 0
        end
        -- Compute
        fft.fft_lua_optimized(real_buf, imag_buf, n)
    end
    local local_duration = os.clock() - start_time

    -- Measure ZFFT
    local z_input_re = {}
    local z_input_im = {}
    -- Pre-allocate
    for i = 1, n do z_input_re[i] = 0; z_input_im[i] = 0 end

    local z_start_time = os.clock()
    for _ = 1, iterations do
        -- Fill input
        for i = 1, n do
            z_input_re[i] = input[i]
            z_input_im[i] = 0
        end
        -- Compute
        zfft.fft(z_input_re, z_input_im)
    end
    local z_duration = os.clock() - z_start_time

    local speedup = z_duration / local_duration

    print(string.format("\nPerformance Test (N=%d, Iter=%d):", n, iterations))
    print(string.format("Local FFT: %.4fs", local_duration))
    print(string.format("ZFFT:      %.4fs", z_duration))
    print(string.format("Speedup:   %.2fx", speedup))

    -- Threshold: Ensure local implementation is at least 2.7x faster than ZFFT
    -- (Local uses cached twiddles and optimized arithmetic, ZFFT computes twiddles every time)
    -- We set a conservative threshold to catch major regressions without flakiness.
    -- Based on expected performance difference due to caching.
    local threshold = 2.7

    lu.assertIsTrue(speedup > threshold,
        string.format("Performance regression: Speedup %.2fx is below threshold %.1fx", speedup, threshold))
end

-- If this is the main script, run the tests
if arg and arg[0] and arg[0]:match("test_fft_perf.lua") then
    os.exit(lu.LuaUnit.run())
end
