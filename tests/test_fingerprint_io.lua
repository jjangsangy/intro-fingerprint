local lu = require('tests.luaunit')
local fingerprint_io = require('modules.fingerprint_io')
local config = require('modules.config')
local mp = require('mp')
local utils = require('modules.utils')

TestFingerprintIO = {}

function TestFingerprintIO:setUp()
    mp._log = {}

    -- Store original filenames
    self.orig_video_filename = config.options.video_temp_filename
    self.orig_audio_filename = config.options.audio_temp_filename

    -- Set test filenames
    config.options.video_temp_filename = "test_mpv_intro_skipper_video.dat"
    config.options.audio_temp_filename = "test_mpv_intro_skipper_audio.dat"

    -- Cleanup any files
    os.remove(fingerprint_io.get_video_fingerprint_path())
    os.remove(fingerprint_io.get_audio_fingerprint_path())
end

function TestFingerprintIO:tearDown()
    os.remove(fingerprint_io.get_video_fingerprint_path())
    os.remove(fingerprint_io.get_audio_fingerprint_path())

    -- Restore original filenames
    config.options.video_temp_filename = self.orig_video_filename
    config.options.audio_temp_filename = self.orig_audio_filename
end

function TestFingerprintIO:test_paths()
    local vid_path = fingerprint_io.get_video_fingerprint_path()
    local aud_path = fingerprint_io.get_audio_fingerprint_path()

    lu.assertStrContains(vid_path, config.options.video_temp_filename)
    lu.assertStrContains(aud_path, config.options.audio_temp_filename)
end

function TestFingerprintIO:test_video_io()
    local timestamp = 123.456
    local data = "FRAME_DATA_123"

    -- Test Write
    local success = fingerprint_io.write_video(timestamp, data)
    lu.assertTrue(success)

    -- Test Read
    local read_time, read_data = fingerprint_io.read_video()
    lu.assertEquals(read_time, timestamp)
    lu.assertEquals(read_data, data)
end

function TestFingerprintIO:test_audio_io()
    local duration = 10.5
    local hashes = {
        {h = 100, t = 1.0},
        {h = 200, t = 2.0},
        {h = 300, t = 3.0}
    }
    
    local factor = config.options.audio_hop_size / config.options.audio_sample_rate
    
    local success = fingerprint_io.write_audio(duration, hashes, #hashes)
    lu.assertTrue(success)
    
    local read_dur, read_hashes, count = fingerprint_io.read_audio()
    assert(read_hashes)
    
    -- read_dur should be formatted to 4 decimals in write
    lu.assertAlmostEquals(read_dur, duration, 0.0001)
    lu.assertEquals(count, #hashes)
    
    -- Check content (inverted index)
    -- Hash 100 should be at time 1.0 * factor
    local time_100 = read_hashes[100][1]
    lu.assertAlmostEquals(time_100, 1.0 * factor, 0.001)
end

function TestFingerprintIO:test_read_nonexistent()
    local t, d = fingerprint_io.read_video()
    lu.assertNil(t)
    lu.assertNil(d)
    
    local dur, h, c = fingerprint_io.read_audio()
    lu.assertNil(dur)
    lu.assertNil(h)
    lu.assertEquals(c, 0)
end
