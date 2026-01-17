local lu = require('tests.luaunit')
local video = require('modules.video')
local utils = require('modules.utils')

TestVideo = {}

function TestVideo:test_hamming_distance()
    -- Hash is array of 8 bytes (0-255)
    local h1 = {0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00}
    local h2 = {0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00}
    
    -- Same hash -> distance 0
    lu.assertEquals(video.video_hamming_distance(h1, h2), 0)
    
    -- Invert one byte (0x00 -> 0xFF). Distance +8
    local h3 = {0xFF, 0xFF, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00}
    lu.assertEquals(video.video_hamming_distance(h1, h3), 8)
    
    -- Invert all bytes. Distance 8 * 8 = 64
    local h4 = {0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF}
    lu.assertEquals(video.video_hamming_distance(h1, h4), 64)
end

function TestVideo:test_compute_phash_lua()
    -- Create a 32x32 image (string)
    -- Vertical gradient: 0 at top, 255 at bottom
    local t = {}
    for y = 0, 31 do
        for x = 0, 31 do
            local val = math.floor(y * 255 / 31)
            table.insert(t, string.char(val))
        end
    end
    local data = table.concat(t)
    
    local hash = video.compute_phash_32_lua(data, 0)
    lu.assertEquals(#hash, 8)
    
    -- Should be consistent (deterministic)
    local hash2 = video.compute_phash_32_lua(data, 0)
    lu.assertEquals(hash, hash2)
end

function TestVideo:test_compute_phash_ffi()
    if not utils.ffi_status then return end
    local ffi = utils.ffi
    
    -- Create a 32x32 image
    local data = ffi.new("uint8_t[1024]")
    for y = 0, 31 do
        for x = 0, 31 do
            local val = math.floor(y * 255 / 31)
            data[y*32 + x] = val
        end
    end
    
    local hash = video.compute_phash_32_ffi(data, 0)
    lu.assertEquals(#hash, 8)
    
    -- Compare with Lua version (should be identical ideally, or very close)
    -- Construct string for Lua version
    local t = {}
    for i=0, 1023 do table.insert(t, string.char(data[i])) end
    local s = table.concat(t)
    local hash_lua = video.compute_phash_32_lua(s, 0)
    
    -- The algorithms might have slight float diffs but let's check exact match first
    lu.assertEquals(hash, hash_lua)
end

function TestVideo:test_validate_frame()
    -- Case 1: Flat image (low variance)
    local t = {}
    for i=1, 1024 do table.insert(t, string.char(100)) end
    local data_flat = table.concat(t)
    
    local valid, reason = video.validate_frame(data_flat, false)
    lu.assertFalse(valid)
    lu.assertStrContains(reason, "Low Variance")
    
    -- Case 2: Random Noise (high variance, low edge density?)
    -- Random noise usually has high edges too.
    math.randomseed(12345)
    t = {}
    for i=1, 1024 do table.insert(t, string.char(math.random(0, 255))) end
    local data_noise = table.concat(t)
    
    -- Check if it passes or fails on some other metric
    -- Random noise might fail "Dominant Color" if random isn't uniform enough? No.
    -- Edge density should be high.
    -- AC Energy should be high.
    -- pHash region variance should be high.
    
    local valid, reason = video.validate_frame(data_noise, false)
    -- It should pass unless random generated a flat image (unlikely)
    -- Or if "Low Edge Density" logic is specific.
    -- Actually random noise has VERY high edge density.
    
    -- Wait, edge check: if (gx + gy) > edge_threshold then count++
    -- In random noise, diff > 20 is very likely.
    
    if not valid then
       print("Random noise validation failed: " .. reason)
    end
    lu.assertTrue(valid)
end
