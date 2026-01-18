local lu = require('tests.luaunit')
local ffmpeg = require('modules.ffmpeg')
local mp = require('mp') -- This is the mock

TestFFmpeg = {}

function TestFFmpeg:setUp()
    mp._commands = {}
end

function TestFFmpeg:tearDown()
    mp._commands = {}
end

function TestFFmpeg:test_extract_video_args()
    local params = { time = 10.5, path = "/path/to/video.mkv" }

    -- Mock subprocess via the mp module logic in ffmpeg.lua
    -- ffmpeg.run_task uses mp.utils.subprocess for 'extract_video'

    local res = ffmpeg.run_task('extract_video', params)

    lu.assertEquals(#mp._commands, 1)
    local cmd = mp._commands[1]
    lu.assertEquals(cmd.name, "subprocess")

    -- Check args contain ffmpeg, input, time, etc.
    local args = cmd.args
    lu.assertIsTable(args)
    lu.assertEquals(args[1], "ffmpeg")

    -- Verify -ss time matches
    local ss_idx = -1
    for i, v in ipairs(args) do
        if v == "-ss" then ss_idx = i break end
    end
    lu.assertTrue(ss_idx > 0)
    lu.assertEquals(args[ss_idx+1], "10.5")

    -- Verify input
    local i_idx = -1
    for i, v in ipairs(args) do
        if v == "-i" then i_idx = i break end
    end
    lu.assertTrue(i_idx > 0)
    lu.assertEquals(args[i_idx+1], "/path/to/video.mkv")
end

function TestFFmpeg:test_scan_audio_async()
    local params = { start = 0, duration = 10, path = "video.mkv" }
    local called = false

    ffmpeg.run_task('scan_audio', params, function(success, res, err)
        called = true
        lu.assertTrue(success)
    end)

    mp._process_async_callbacks()

    lu.assertTrue(called)
    lu.assertEquals(#mp._commands, 1)

    -- scan_audio uses mp.command_native_async
    local cmd = mp._commands[1]
    lu.assertIsTable(cmd)
    lu.assertEquals(cmd.name, "subprocess") -- internally it constructs a 'subprocess' command for command_native
    lu.assertTrue(cmd.capture_stdout)
end

function TestFFmpeg:test_invalid_profile()
    -- Capture error log
    local res = ffmpeg.run_task('non_existent', {})
    lu.assertNil(res)

    -- Check if error was logged
    local found_error = false
    for _, log in ipairs(mp._log) do
        if log[1] == "error" and string.find(log[2], "not found") then
            found_error = true
            break
        end
    end
    lu.assertTrue(found_error)
end
