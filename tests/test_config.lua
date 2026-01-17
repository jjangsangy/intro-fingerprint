local lu = require('tests.luaunit')
local config = require('modules.config')

TestConfig = {}

function TestConfig:test_defaults()
    lu.assertEquals(config.options.debug, "no")
    lu.assertEquals(config.options.audio_sample_rate, 11025)
    lu.assertEquals(config.options.audio_fft_size, 2048)
end

function TestConfig:test_video_phash_size()
    lu.assertEquals(config.options.video_phash_size, 32)
    -- Verify derived constant
    lu.assertEquals(config.VIDEO_FRAME_SIZE, 32 * 32)
end
