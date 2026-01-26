local lu = require('tests.luaunit')
local video = require('modules.video')
local utils = require('modules.utils')
local helpers = require('tests.helpers')

TestPDQHash = {}

function TestPDQHash:test_consistency_ffi_vs_lua()
    -- Only run if FFI is available
    if not utils.ffi_status then return end

    local img_str = helpers.generate_image_diagonal_gradient()
    local img_ffi = helpers.string_to_ffi(img_str)

    local hash_lua = video.compute_pdq_hash_lua(img_str, 0)
    local hash_ffi = video.compute_pdq_hash_ffi(img_ffi, 0)

    -- Both should return a table of 32 bytes
    lu.assertEquals(#hash_lua, 32)
    lu.assertEquals(#hash_ffi, 32)

    -- Verify hashes are perceptually identical (allow small FP differences)
    -- Floating point summation order differs between Lua (unrolled chunks) and FFI (linear loop)
    -- This can cause median-boundary values to flip bits.
    local dist = video.video_hamming_distance(hash_lua, hash_ffi)

    -- Allow up to 2 bits difference (out of 256) for floating point noise
    if dist > 2 then
        print(string.format("FFI vs Lua Hash Distance: %d", dist))
    end
    lu.assertTrue(dist <= 2, "Hashes should be nearly identical (dist <= 2)")
end

function TestPDQHash:test_pure_lua_fallback_no_bitop()
    -- Simulate environment without 'bit' library
    local original_bit_status = utils.bit_status
    local original_bit = utils.bit

    utils.bit_status = false
    utils.bit = nil

    local img_str = helpers.generate_image_diagonal_gradient()

    -- Run compute (this will trigger the arithmetic bit shifting fallback)
    -- We can compare it against the known "good" result (from previous test or itself with bitop)
    -- But since we mocked it globally, video module will use the fallback.

    local hash = video.compute_pdq_hash_lua(img_str, 0)
    lu.assertEquals(#hash, 32)

    -- Restore environment
    utils.bit_status = original_bit_status
    utils.bit = original_bit

    -- If we have bit library, verify the fallback result matches the optimized result
    if utils.bit_status then
        local hash_opt = video.compute_pdq_hash_lua(img_str, 0)
        for i = 1, 32 do
            lu.assertEquals(hash[i], hash_opt[i], "Fallback hash mismatch with optimized hash")
        end
    end
end

function TestPDQHash:test_hamming_distance_fallback()
    -- Test pure Lua XOR and popcount logic
    local original_bit_status = utils.bit_status
    utils.bit_status = false -- Force fallback

    local h1 = {}
    local h2 = {}
    for i = 1, 32 do
        h1[i] = 0xAA -- 10101010
        h2[i] = 0x55 -- 01010101
    end
    -- XOR(0xAA, 0x55) = 0xFF (11111111) -> 8 bits set
    -- Total distance = 32 bytes * 8 bits = 256

    local dist = video.video_hamming_distance(h1, h2)
    lu.assertEquals(dist, 256)

    -- Test identical
    dist = video.video_hamming_distance(h1, h1)
    lu.assertEquals(dist, 0)

    -- Test single bit difference
    local h3 = {}
    for i = 1, 32 do h3[i] = 0xAA end
    h3[1] = 0xAB -- 10101011 (last bit flipped from 0xAA)
    -- Distance should be 1
    dist = video.video_hamming_distance(h1, h3)
    lu.assertEquals(dist, 1)

    -- Restore
    utils.bit_status = original_bit_status
end

function TestPDQHash:test_quality_metrics_gradient()
    -- PDQ relies on Gradient Sum.
    -- Create an image with high contrast but NO gradient (e.g. checkerboard of 2x2 blocks?)
    -- Or just vertical lines.

    -- 1. Perfectly Flat Image -> Quality 0
    local img_flat = helpers.generate_image_flat(128)
    local valid, reason = video.validate_frame(img_flat, false)
    lu.assertFalse(valid)
    lu.assertStrContains(reason, "Low Contrast") -- Flat fails contrast first usually

    -- 2. Image with Contrast but Low Gradient?
    -- A checkerboard of large squares (e.g. 32x32) has few edges.
    -- A checkerboard of 1x1 pixels has MAXIMUM gradient.

    -- Let's make a "Horizontal Gradient" image (0..120).
    -- Rows are identical 0..120 gradient.
    -- This creates a smooth gradient where adjacent pixels differ by < 2.
    -- New Metric: floor(diff * 100 / 255) -> floor(1.9 * 0.39) = 0.
    -- So Quality = 0.
    -- But StdDev is still high (~35), so it passes Contrast check.
    t = {}
    for y=0, 63 do
        for x=0, 63 do
            local val = math.floor(x * 120 / 63)
            table.insert(t, string.char(val))
        end
    end
    local img_gradient = table.concat(t)

    -- Check stats for gradient image:
    -- Mean: ~60 (OK, > 15)
    -- StdDev: ~35 (OK, > 10)
    -- Entropy: High (OK)
    -- Gradient Sum:
    -- Horizontal diff is ~1.9. Quantized d = 0.
    -- Quality = 0.
    -- Default min quality is 1.0. So this SHOULD FAIL.

    valid, reason = video.validate_frame(img_gradient, false)
    lu.assertFalse(valid)
    lu.assertStrContains(reason, "Low Quality")

    -- 3. High Gradient Image (Noise)
    -- Random noise has high gradient everywhere.
    local img_noise = helpers.generate_image_random(42)

    valid, reason = video.validate_frame(img_noise, false)
    lu.assertTrue(valid)
end
