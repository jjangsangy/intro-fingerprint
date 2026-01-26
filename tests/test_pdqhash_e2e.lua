local lu = require('tests.luaunit')
local video = require('modules.video')
local utils = require('modules.utils')
local mp_utils = require('mp.utils')
local config = require('modules.config')
local helpers = require('tests.helpers')

TestPDQHashE2E = {}

function TestPDQHashE2E:setUp()
    -- Read reference hashes
    self.references = {}
    local f = io.open("tests/images/reference_hashes.txt", "r")
    if f then
        for line in f:lines() do
            local filename, hash, quality = line:match("([^:]+):(%x+):?(%d*)")
            if filename and hash then
                self.references[filename] = { hash = hash, quality = tonumber(quality) }
            end
        end
        f:close()
    else
        print("Warning: tests/images/reference_hashes.txt not found")
    end
end

function TestPDQHashE2E:test_e2e_hashing()
    if not next(self.references) then
        lu.skip("No reference hashes found")
    end

    local temp_dir = utils.get_temp_dir()

    for filename, ref_data in pairs(self.references) do
        local ref_hex = ref_data.hash
        local ref_quality = ref_data.quality

        -- 1. Load Image using FFmpeg via temp file (cross-platform safe)
        local temp_filename = string.format("test_pdq_%s_%d.raw", filename, os.time())
        local temp_path = mp_utils.join_path(temp_dir, temp_filename)

        -- Construct complex filter chain matching ffmpeg.lua
        local size = config.options.video_hash_size
        local vf_str = string.format([[
            scale=512:512:flags=bilinear,
            format=rgb24,
            colorchannelmixer=rr=0.299:rg=0.587:rb=0.114:gr=0.299:gg=0.587:gb=0.114:br=0.299:bg=0.587:bb=0.114,
            format=gray,
            avgblur=sizeX=4:sizeY=4,
            avgblur=sizeX=4:sizeY=4,
            scale=%d:%d:flags=neighbor
        ]], size, size):gsub("%s+", "")

        local cmd = string.format('ffmpeg -v quiet -y -i "tests/images/%s" -f rawvideo -vf "%s" "%s"', filename, vf_str, temp_path)

        local ret = os.execute(cmd)
        if ret ~= 0 and ret ~= true then
            lu.fail("FFmpeg command failed: " .. cmd)
        end

        local f = io.open(temp_path, "rb")
        if not f then
            lu.fail("Failed to open temp file: " .. temp_path)
            return
        end

        local pixels = f:read("*a")
        f:close()
        os.remove(temp_path)

        -- Verify we got 4096 bytes (64x64)
        if #pixels ~= 4096 then
            -- Fallback/Fail message
            lu.fail(string.format("Image %s decode failed. Expected 4096 bytes, got %d. Check if ffmpeg is in PATH.", filename, #pixels))
        end

        -- 2. Convert Reference Hex to Bytes
        local ref_bytes = {}
        for i = 1, #ref_hex, 2 do
            table.insert(ref_bytes, tonumber(ref_hex:sub(i, i+1), 16))
        end

        -- 3. Test Quality Metric (if reference available)
        if ref_quality then
            local valid, reason, quality_score = video.validate_frame(pixels, false)
            -- Allow slight deviation (±5) due to floating point/rounding differences in processing chain
            lu.assertTrue(math.abs(quality_score - ref_quality) <= 5, string.format("Quality mismatch for %s: Got %d, Expected %d", filename, quality_score, ref_quality))
        end

        -- 4. Test Pure Lua
        local hash_lua = video.compute_pdq_hash_lua(pixels, 0)
        local dist_lua = video.video_hamming_distance(hash_lua, ref_bytes)

        -- 5. Test FFI (if available)
        if utils.ffi_status then
             local buf = helpers.string_to_ffi(pixels)

             -- Test FFI Quality Metric
             if ref_quality then
                local valid, reason, quality_score = video.validate_frame(buf, true)
                lu.assertTrue(math.abs(quality_score - ref_quality) <= 5, string.format("FFI Quality mismatch for %s: Got %d, Expected %d", filename, quality_score, ref_quality))
             end

             local hash_ffi = video.compute_pdq_hash_ffi(buf, 0)
             local dist_ffi = video.video_hamming_distance(hash_ffi, ref_bytes)

             -- print(string.format("Image: %s, Dist (Lua): %d, Dist (FFI): %d", filename, dist_lua, dist_ffi))

             -- Assert difference < 10% (26 bits)
             lu.assertTrue(dist_ffi <= 26, string.format("FFI distance too high for %s: %d (Expected <= 26)", filename, dist_ffi))

             -- Consistency check
             local dist_cross = video.video_hamming_distance(hash_lua, hash_ffi)
             lu.assertEquals(dist_cross, 0, string.format("Lua vs FFI mismatch for %s: %d", filename, dist_cross))
        else
             -- print(string.format("Image: %s, Dist (Lua): %d (FFI not available)", filename, dist_lua))
        end

        -- Assert difference < 10% (26 bits) for Lua
        lu.assertTrue(dist_lua <= 26, string.format("Lua distance too high for %s: %d (Expected <= 26)", filename, dist_lua))
    end
end
