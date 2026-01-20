local lu = require('tests.luaunit')
local video = require('modules.video')
local utils = require('modules.utils')

TestVideo = {}

function TestVideo:test_hamming_distance()
    -- Hash is array of 32 bytes (0-255)
    local h1 = {}
    for i=1, 32 do h1[i] = 0xFF end
    local h2 = {}
    for i=1, 32 do h2[i] = 0xFF end

    -- Same hash -> distance 0
    lu.assertEquals(video.video_hamming_distance(h1, h2), 0)

    -- Invert one byte (0xFF -> 0x00). Distance +8
    local h3 = {}
    for i=1, 32 do h3[i] = 0xFF end
    h3[1] = 0x00
    lu.assertEquals(video.video_hamming_distance(h1, h3), 8)

    -- Invert all bytes. Distance 32 * 8 = 256
    local h4 = {}
    for i=1, 32 do h4[i] = 0x00 end
    lu.assertEquals(video.video_hamming_distance(h1, h4), 256)
end

function TestVideo:test_compute_pdq_hash_lua()
    -- Create a 64x64 image (string)
    -- Vertical gradient: 0 at top, 255 at bottom
    local t = {}
    for y = 0, 63 do
        for x = 0, 63 do
            local val = math.floor(y * 255 / 63)
            table.insert(t, string.char(val))
        end
    end
    local data = table.concat(t)

    local hash = video.compute_pdq_hash_lua(data, 0)
    lu.assertEquals(#hash, 32)

    -- Should be consistent (deterministic)
    local hash2 = video.compute_pdq_hash_lua(data, 0)
    lu.assertEquals(hash, hash2)
end

function TestVideo:test_compute_pdq_hash_ffi()
    if not utils.ffi_status then return end
    local ffi = utils.ffi

    -- Create a 64x64 image
    local data = ffi.new("uint8_t[4096]")
    for y = 0, 63 do
        for x = 0, 63 do
            local val = math.floor(y * 255 / 63)
            data[y*64 + x] = val
        end
    end

    local hash = video.compute_pdq_hash_ffi(data, 0)
    lu.assertEquals(#hash, 32)

    -- Compare with Lua version
    local t = {}
    for i=0, 4095 do table.insert(t, string.char(data[i])) end
    local s = table.concat(t)
    local hash_lua = video.compute_pdq_hash_lua(s, 0)

    -- Floating point operations might cause minor differences in LSBs
    -- but usually they should match for clean gradients.
    -- Let's check similarity (distance 0)
    local dist = video.video_hamming_distance(hash, hash_lua)
    lu.assertEquals(dist, 0)
end

function TestVideo:test_validate_frame()
    -- Case 1: Flat image (low gradient sum)
    local t = {}
    for i=1, 4096 do table.insert(t, string.char(100)) end
    local data_flat = table.concat(t)

    local valid, reason = video.validate_frame(data_flat, false)
    lu.assertFalse(valid)
    lu.assertStrContains(reason, "Low Quality")

    -- Case 2: Random Noise (high gradient sum)
    math.randomseed(12345)
    t = {}
    for i=1, 4096 do table.insert(t, string.char(math.random(0, 255))) end
    local data_noise = table.concat(t)

    local valid, reason = video.validate_frame(data_noise, false)
    if not valid then
       print("Random noise validation failed: " .. reason)
    end
    lu.assertTrue(valid)
end
