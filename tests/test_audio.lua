local lu = require('tests.luaunit')
local audio = require('modules.audio')
local utils = require('modules.utils')
local helpers = require('tests.helpers')

TestAudio = {}

function TestAudio:test_process_audio_sine_1000hz()
    local freq = 1000
    local duration = 2.0 -- 2.0 seconds to ensure enough frames for target window
    local pcm = helpers.generate_sine_pcm(freq, duration)

    local hashes, count = audio.process_audio_data(pcm)

    -- We expect some hashes.
    lu.assertTrue(count > 0)

    -- Check if the peak is consistent with 1000Hz.
    -- We can't easily reverse hash to freq without re-implementing logic,
    -- but we can check if it returns hashes at all.
    -- The hash contains (f1, f2, dt).
    -- Since it's a pure sine wave, f1 and f2 should be roughly the same frequency bin.

    if utils.ffi_status then
       -- hashes is cdata array
       local h1 = hashes[0].h
       -- Extract f1 (top 9 bits shifted)
       -- h = bor(lshift(f1, 23), lshift(f2, 14), dt)
       -- f1 = rshift(h, 23) & 0x1FF
       local f1 = utils.bit.band(utils.bit.rshift(h1, 23), 0x1FF)

       -- Expected bin: freq / (sample_rate / fft_size)
       -- 1000 / (11025 / 2048) = 1000 / 5.38 = ~185
       lu.assertAlmostEquals(f1, 185, 2) -- Allow +/- 2 bins
    else
       -- Lua path (table of hashes)
       -- hashes is a table of {h=..., t=...}
       local h1 = hashes[1].h
       -- Need to decode hash manually as in audio.lua fallback
       -- h = (f1 % MASK_9) * SHIFT_23 + (f2 % MASK_9) * SHIFT_14 + (dt % MASK_14)
       -- MASK_9 = 512, SHIFT_23 = 8388608

       local SHIFT_23 = 8388608
       local f1 = math.floor(h1 / SHIFT_23)

       lu.assertAlmostEquals(f1, 185, 2)
    end
end

function TestAudio:test_validate_audio()
    -- Silence
    local pcm_silence = string.rep(string.char(0,0), 1000)
    local valid, reason = audio.validate_audio(pcm_silence)
    lu.assertFalse(valid)
    lu.assertStrContains(reason, "Silence")

    -- Sparse
    local t = {}
    for i=1, 1000 do
        if i % 20 == 0 then table.insert(t, string.char(255, 100))
        else table.insert(t, string.char(0,0)) end
    end
    local pcm_sparse = table.concat(t)
    valid, reason = audio.validate_audio(pcm_sparse)
    lu.assertFalse(valid)
    lu.assertStrContains(reason, "Sparse")

    -- Good Signal (White Noise)
    math.randomseed(42)
    t = {}
    for i=1, 5000 do
        local val = math.random(-20000, 20000)
        if val < 0 then val = val + 65536 end
        local b1 = val % 256
        local b2 = math.floor(val / 256)
        table.insert(t, string.char(b1, b2))
    end
    local pcm_noise = table.concat(t)
    valid, reason = audio.validate_audio(pcm_noise)
    lu.assertTrue(valid)
end
