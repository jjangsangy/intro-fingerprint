local lu = require('tests.luaunit')
local audio = require('modules.audio')
local utils = require('modules.utils')
local config = require('modules.config')

TestReproIssue = {}

-- Helper to generate sine wave
local function generate_sine_pcm(freq, duration_sec)
    local sample_rate = config.options.audio_sample_rate
    local num_samples = math.floor(sample_rate * duration_sec)
    local t_table = {}
    for i = 0, num_samples - 1 do
        local t = i / sample_rate
        local val = math.sin(2 * math.pi * freq * t)
        local val_int = math.floor(val * 32767)
        if val_int > 32767 then val_int = 32767 end
        if val_int < -32768 then val_int = -32768 end
        if val_int < 0 then val_int = val_int + 65536 end
        local b1 = val_int % 256
        local b2 = math.floor(val_int / 256)
        table.insert(t_table, string.char(b1, b2))
    end
    return table.concat(t_table)
end

function TestReproIssue:setUp()
    self.original_bit_status = utils.bit_status
    self.original_bit = utils.bit

    -- Ensure bit library is available for this test (polyfill if not)
    if not utils.bit_status then
        utils.bit_status = true
        utils.bit = {}

        -- Polyfill using arithmetic (matches audio.lua pure lua fallback)
        utils.bit.lshift = function(a, b) return a * (2^b) end
        utils.bit.rshift = function(a, b) return math.floor(a / (2^b)) end
        -- NOTE: This simple band only works for masks that are 2^n - 1 (like 0x1FF, 0x3FFF)
        utils.bit.band = function(a, b) return a % (b + 1) end
        -- NOTE: This simple bor only works for non-overlapping bits
        utils.bit.bor = function(...)
             local res = 0
             for _, v in ipairs({...}) do res = res + v end
             return res
        end
    end

    self.real_bor = utils.bit.bor

    -- Mock bor to simulate the bug: ignores 3rd argument
    utils.bit.bor = function(...)
        local args = {...}
        if #args == 0 then return 0 end
        local res = args[1]
        if #args >= 2 then
            res = self.real_bor(res, args[2])
        end
        -- Ignore args[3] and beyond
        return res
    end
end

function TestReproIssue:tearDown()
    -- Restore original state
    if utils.bit then
        utils.bit.bor = self.real_bor
    end
    utils.bit = self.original_bit
    utils.bit_status = self.original_bit_status
end

function TestReproIssue:test_fix_verification()
    local pcm = generate_sine_pcm(1000, 5.0)
    local hashes, count = audio.process_audio_data(pcm)

    -- Even with the mocked "buggy" bor (ignores 3rd arg),
    -- our nested call structure bor(bor(a,b), c) should preserve dt.

    local found_hashes = false

    if utils.ffi_status then
        for i = 0, count - 1 do
            found_hashes = true
            local h = hashes[i].h
            local dt = utils.bit.band(h, 0x3FFF)
            lu.assertTrue(dt >= 10, "dt should be >= 10 (t_min), got " .. dt)
        end
    else
        for _, entry in ipairs(hashes) do
            found_hashes = true
            local h = entry.h
            local dt = utils.bit.band(h, 0x3FFF)
            lu.assertTrue(dt >= 10, "dt should be >= 10 (t_min), got " .. dt)
        end
    end

    lu.assertTrue(found_hashes, "Should have generated some hashes")
end
