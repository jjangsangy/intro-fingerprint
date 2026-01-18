local lu = require('tests.luaunit')
local actions = require('modules.actions')
local mp = require('mp')
local utils = require('modules.utils')
local config = require('modules.config')

TestActions = {}

function TestActions:setUp()
    mp._commands = {}
    mp._messages = {}
    mp._properties = {}
    mp._command_returns = {}

    -- Setup valid state
    mp.set_property("path", "video.mkv")
    mp.set_property("time-pos", 100)
    mp.set_property("duration", 200)

    -- Create dummy fingerprint files if needed
    self.v_path = utils.get_video_fingerprint_path()
    self.a_path = utils.get_audio_fingerprint_path()

    os.remove(self.v_path)
    os.remove(self.a_path)
end

function TestActions:tearDown()
    os.remove(self.v_path)
    os.remove(self.a_path)
    mp._command_returns = {}
end

function TestActions:test_save_intro_no_video()
    mp.set_property("path", nil)
    actions.save_intro()
    lu.assertStrContains(mp._messages[1], "No video")
end

function TestActions:test_save_intro_success()
    -- Mock video extraction result
    -- Random noise to ensure variance check passes
    local t = {}
    for i=1, 1024 do table.insert(t, string.char(math.random(0, 255))) end
    local dummy_frame = table.concat(t)

    -- Mock audio extraction result
    local dummy_pcm = {}
    -- Generate 2 seconds of audio with multiple frequencies to ensure peaks
    local sample_rate = 11025
    local duration = 2
    local f1, f2, f3 = 440, 880, 1200
    for i=0, (sample_rate * duration) - 1 do
        local t = i / sample_rate
        local val = (math.sin(2 * math.pi * f1 * t) +
                     math.sin(2 * math.pi * f2 * t) +
                     math.sin(2 * math.pi * f3 * t)) / 3.0
        local val_int = math.floor(val * 32767)
        if val_int < 0 then val_int = val_int + 65536 end
        local b1 = val_int % 256
        local b2 = math.floor(val_int / 256)
        table.insert(dummy_pcm, string.char(b1, b2))
    end
    local dummy_pcm_str = table.concat(dummy_pcm)

    -- Setup dynamic return
    mp._command_returns["subprocess"] = function(t)
        -- Check if args indicate video or audio
        local is_video = false
        local is_audio = false
        for _, v in ipairs(t.args) do
            if v == "rawvideo" then is_video = true end
            if v == "s16le" then is_audio = true end
        end

        if is_video then
            return {status=0, stdout=dummy_frame}
        elseif is_audio then
            return {status=0, stdout=dummy_pcm_str}
        end

        return {status=0, stdout=""}
    end

    actions.save_intro()

    -- Check messages
    local found_success = false
    for _, msg in ipairs(mp._messages) do
        if string.find(msg, "Intro Captured") then found_success = true end
    end
    lu.assertTrue(found_success)

    -- Check files exist
    local fv = io.open(self.v_path, "rb")
    lu.assertTrue(fv ~= nil)
    if fv then fv:close() end

    local fa = io.open(self.a_path, "rb")
    lu.assertTrue(fa ~= nil)
    if fa then fa:close() end
end

function TestActions:test_skip_intro_video_match()
    -- Create random frame for perfect match
    local t = {}
    for i=1, 1024 do table.insert(t, string.char(math.random(0, 255))) end
    local dummy_frame = table.concat(t)

    -- Create a fingerprint file
    local f = io.open(self.v_path, "wb")
    assert(f, "File doesn't exist "..self.v_path)
    f:write("50.0\n")
    f:write(dummy_frame)
    f:close()

    -- Mock scan result

    mp._command_returns["subprocess"] = {
        status = 0,
        stdout = dummy_frame -- Perfect match
    }

    actions.skip_intro_video()

    -- Process the async scan callback to resume coroutine
    mp._process_async_callbacks()

    -- Check if success message
    local found_skipped = false
    for _, msg in ipairs(mp._messages) do
        if string.find(msg, "Skipped!") then found_skipped = true end
    end
    lu.assertTrue(found_skipped)
end
