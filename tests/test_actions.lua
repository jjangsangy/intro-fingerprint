local lu = require('tests.luaunit')
local actions = require('modules.actions')
local mp = require('mp')
local utils = require('modules.utils')
local config = require('modules.config')
local fingerprint_io = require('modules.fingerprint_io')
local audio = require('modules.audio')
local video = require('modules.video')

TestActions = {}

function TestActions:mock(module, name, fn)
    self.mocks = self.mocks or {}
    self.mocks[module] = self.mocks[module] or {}
    
    -- Only save original once
    if not self.mocks[module][name] then
        self.mocks[module][name] = module[name]
    end
    
    module[name] = fn
end

function TestActions:restore_mocks()
    if not self.mocks then return end
    for module, funcs in pairs(self.mocks) do
        for name, orig in pairs(funcs) do
            module[name] = orig
        end
    end
    self.mocks = nil
end

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
    self.v_path = fingerprint_io.get_video_fingerprint_path()
    self.a_path = fingerprint_io.get_audio_fingerprint_path()

    os.remove(self.v_path)
    os.remove(self.a_path)
end

function TestActions:tearDown()
    self:restore_mocks()
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
    fingerprint_io.write_video(50.0, dummy_frame)

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

function TestActions:test_capture_video_success()
    -- Generate dummy video data (grayscale)
    local t = {}
    for i=1, 1024 do table.insert(t, string.char(math.random(0, 255))) end
    local dummy_frame = table.concat(t)
    
    mp._command_returns["subprocess"] = { status=0, stdout=dummy_frame }

    local res = actions.capture_video("test.mkv", 100)
    lu.assertTrue(res)
    
    -- Check file created
    local f = io.open(self.v_path, "rb")
    lu.assertTrue(f ~= nil)
    if f then f:close() end
end

function TestActions:test_capture_video_failure()
    mp._command_returns["subprocess"] = { status=1, stdout="" }
    local res = actions.capture_video("test.mkv", 100)
    lu.assertFalse(res)
end

function TestActions:test_capture_audio_success()
    -- Create non-silent audio
    local t = {}
    for i=1, 44100 do -- 1 sec
        local val = math.floor(math.sin(i/100) * 10000)
        local val_u = val
        if val_u < 0 then val_u = val_u + 65536 end
        local b1 = val_u % 256
        local b2 = math.floor(val_u / 256)
        table.insert(t, string.char(b1, b2))
    end
    local valid_pcm = table.concat(t)
    
    mp._command_returns["subprocess"] = { status=0, stdout=valid_pcm }
    
    local res = actions.capture_audio("test.mkv", 100)
    lu.assertTrue(res)
    
    -- Check file created
    local f = io.open(self.a_path, "rb")
    lu.assertTrue(f ~= nil)
    if f then f:close() end
end

function TestActions:test_process_hash_match()
    local ctx = {
        saved_hashes = { [123] = {10.0, 20.0} },
        factor = 1.0,
        segment_dur = 5.0,
        time_bin_width = 0.1,
        global_offset_histogram = {}
    }
    local local_histogram = {}
    
    actions.process_hash_match(ctx, 123, 1.0, 100.0, local_histogram)
    
    local bin = math.floor(91.0 / 0.1 + 0.5)
    lu.assertEquals(ctx.global_offset_histogram[bin], 1)
    lu.assertEquals(local_histogram[bin], 1)
end

function TestActions:test_check_early_stop()
    local ctx = {
        previous_local_max = 100,
        stop_flag = false
    }
    config.options.audio_threshold = 10
    config.options.audio_min_match_ratio = 0.1
    
    actions.check_early_stop(ctx, 40, 200.0, 0.5)
    
    lu.assertTrue(ctx.stop_flag)
end

function TestActions:test_check_early_stop_no_drop()
    local ctx = {
        previous_local_max = 100,
        stop_flag = false
    }
    config.options.audio_threshold = 10
    
    actions.check_early_stop(ctx, 80, 200.0, 0.5)
    
    lu.assertFalse(ctx.stop_flag)
end

function TestActions:test_capture_audio_low_complexity()
    -- Mock audio.process_audio_data to return few hashes
    self:mock(audio, 'process_audio_data', function(data)
        return {}, 10 -- Less than 50
    end)

    -- Return valid (non-silent) audio data so validate_audio passes
    -- but logic will fail on hash count
    local t = {}
    for i=1, 2048 do -- 1024 samples
        table.insert(t, string.char(math.random(0, 255)))
    end
    local valid_pcm = table.concat(t)

    mp._command_returns["subprocess"] = { status=0, stdout=valid_pcm }
    
    local res = actions.capture_audio("test.mkv", 100)
    
    lu.assertFalse(res)
    lu.assertStrContains(mp._messages[1], "Low Complexity")
end

function TestActions:test_capture_audio_short_duration()
    config.options.audio_fingerprint_duration = 20
    -- time_pos 15 means start=0, dur=15. If we set time_pos=0.5...
    -- capture_audio checks dur_a <= 1
    
    local res = actions.capture_audio("test.mkv", 0.5)
    lu.assertTrue(res) -- Returns true but does nothing
    -- Should not have called subprocess
    local called = false
    for _, cmd in ipairs(mp._commands) do
        if cmd.name == "subprocess" then called = true end
    end
    lu.assertFalse(called)
end

function TestActions:test_skip_intro_video_no_file()
    -- Ensure no fingerprint file
    if os.remove then os.remove(self.v_path) end
    
    actions.skip_intro_video()
    
    -- Async runs immediately in test environment usually but here it's utils.run_async
    mp._process_async_callbacks()
    
    lu.assertStrContains(mp._messages[1], "No intro captured")
end

function TestActions:test_skip_intro_video_no_match()
    -- Create random frame
    local t = {}
    for i=1, 1024 do table.insert(t, string.char(math.random(0, 255))) end
    local dummy_frame = table.concat(t)
    fingerprint_io.write_video(50.0, dummy_frame)
    
    -- Mock scan result with mismatch (different frame)
    local t2 = {}
    for i=1, 1024 do table.insert(t2, string.char(math.random(0, 255))) end
    local mismatch_frame = table.concat(t2)
    
    mp._command_returns["subprocess"] = {
        status = 0,
        stdout = mismatch_frame
    }
    
    -- Limit loop for test
    local orig_max = config.options.video_max_search_window
    config.options.video_max_search_window = config.options.video_search_window + 10
    
    actions.skip_intro_video()
    
    local max_iters = 20
    local i = 0
    while #mp._async_callbacks > 0 and i < max_iters do
        mp._process_async_callbacks()
        i = i + 1
    end
    
    config.options.video_max_search_window = orig_max
    
    local found_no_match = false
    for _, msg in ipairs(mp._messages) do
        if string.find(msg, "No match found") then found_no_match = true end
    end
    lu.assertTrue(found_no_match)
end

function TestActions:test_skip_intro_audio_match()
    -- Mock fingerprint_io.read_audio
    self:mock(fingerprint_io, 'read_audio', function()
        return 2.0, {[12345] = {0.5}}, 100 -- 100 total hashes
    end)

    -- Mock audio.process_audio_data
    self:mock(audio, 'process_audio_data', function(data)
        if data == "MATCH" then
            -- Create 60 matches (ratio 0.6 > 0.4)
            local t = {}
            for k=1, 60 do
                table.insert(t, {h=12345, t=0.5}) -- all align perfectly
            end
            return t, 60
        else
            return {}, 0
        end
    end)

    mp._command_returns["subprocess"] = function(cmd)
        local ss = nil
        for i, v in ipairs(cmd.args) do
            if v == "-ss" then ss = tonumber(cmd.args[i+1]) break end
        end
        if ss and ss == 0 then return {status=0, stdout="MATCH"} end
        return {status=0, stdout="NOPE"}
    end

    config.options.audio_threshold = 10
    config.options.audio_min_match_ratio = 0.4
    
    actions.skip_intro_audio()
    
    local i = 0
    while #mp._async_callbacks > 0 and i < 50 do
        mp._process_async_callbacks()
        i = i + 1
    end
    
    local skipped = false
    for _, msg in ipairs(mp._messages) do
        if string.find(msg, "Skipped!") then skipped = true end
    end
    lu.assertTrue(skipped)
end

function TestActions:test_skip_intro_audio_no_match()
    self:mock(fingerprint_io, 'read_audio', function()
        return 2.0, {[12345] = {0.5}}, 100
    end)

    self:mock(audio, 'process_audio_data', function(data)
        return {}, 0
    end)

    mp._command_returns["subprocess"] = {status=0, stdout="NOPE"}

    config.options.audio_scan_limit = 60 -- limit scan to 60s
    
    actions.skip_intro_audio()
    
    local i = 0
    while #mp._async_callbacks > 0 and i < 100 do
        mp._process_async_callbacks()
        i = i + 1
    end
    
    local no_match = false
    for _, msg in ipairs(mp._messages) do
        if string.find(msg, "No match") then no_match = true end
    end
    lu.assertTrue(no_match)
end
