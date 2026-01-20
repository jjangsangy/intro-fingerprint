local lu = require('tests.luaunit')
local config = require('modules.config')

TestConfig = {}

function TestConfig:test_defaults()
    lu.assertEquals(config.options.debug, "no")
    lu.assertEquals(config.options.audio_sample_rate, 11025)
    lu.assertEquals(config.options.audio_fft_size, 2048)
end

function TestConfig:test_video_hash_size()
    lu.assertEquals(config.options.video_hash_size, 64)
    -- Verify derived constant
    lu.assertEquals(config.VIDEO_FRAME_SIZE, 64 * 64)
end
