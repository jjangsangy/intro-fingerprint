local lu = require('tests.luaunit')
local utils = require('modules.utils')
local config = require('modules.config')
local mp = require('mp')
local state = require('modules.state')

TestUtils = {}

function TestUtils:setUp()
    mp._log = {}
    mp._commands = {}
    state.scanning = false
    state.current_scan_token = nil
end

function TestUtils:test_get_temp_dir()
    local temp = utils.get_temp_dir()
    lu.assertStrContains(temp, "") -- Just assert it returns a string
    -- On Windows it should likely be defined
    lu.assertTrue(#temp > 0)
end

function TestUtils:test_paths()
    -- These rely on the mocked mp.utils.join_path
    local vid_path = utils.get_video_fingerprint_path()
    local aud_path = utils.get_audio_fingerprint_path()
    
    lu.assertStrContains(vid_path, config.options.video_temp_filename)
    lu.assertStrContains(aud_path, config.options.audio_temp_filename)
end

function TestUtils:test_ffi_status()
    -- Depending on the runner (lua vs luajit), this will be true or false
    -- We just verify it is a boolean
    lu.assertTrue(type(utils.ffi_status) == "boolean")
end

function TestUtils:test_log_info()
    -- Should log when debug is yes
    config.options.debug = "yes"
    utils.log_info("Hello")
    lu.assertEquals(#mp._log, 1)
    lu.assertEquals(mp._log[1][1], "info")
    lu.assertEquals(mp._log[1][2], "Hello")

    -- Should not log when debug is no
    mp._log = {}
    config.options.debug = "no"
    utils.log_info("Hello")
    lu.assertEquals(#mp._log, 0)
end

function TestUtils:test_abort_scan()
    -- Setup active state
    state.scanning = true
    state.current_scan_token = 123
    
    -- Mock abort_async_command (already in mocks.lua but we want to verify calls)
    -- We'll just check if state is reset, as the mock implementation is empty
    -- To check if mp.abort_async_command was called, we'd need to spy on it.
    -- Let's improve the mock spy in mocks.lua or hook it here.
    
    local aborted_token = nil
    local orig_abort = mp.abort_async_command
    mp.abort_async_command = function(t) aborted_token = t end
    
    utils.abort_scan()
    
    lu.assertFalse(state.scanning)
    lu.assertNil(state.current_scan_token)
    lu.assertEquals(aborted_token, 123)
    
    -- Check logging
    -- utils.log_info calls msg.info if debug is on
    config.options.debug = "yes"
    utils.abort_scan()
    -- Should verify "Scan aborted." is logged
    local found = false
    for _, l in ipairs(mp._log) do
        if l[2] == "Scan aborted." then found = true end
    end
    lu.assertTrue(found)
    
    -- Restore
    mp.abort_async_command = orig_abort
end

function TestUtils:test_run_async()
    local called = false
    local function my_task()
        called = true
    end
    
    utils.run_async(my_task)
    lu.assertTrue(called)
    
    -- Test error handling
    local function error_task()
        error("Boom")
    end
    
    -- Should not crash test runner
    -- Should log error
    state.scanning = true
    utils.run_async(error_task)
    
    lu.assertFalse(state.scanning) -- Should reset scanning on error
    
    local found_err = false
    for _, l in ipairs(mp._log) do
        if l[1] == "error" and string.find(l[2], "Boom") then found_err = true end
    end
    lu.assertTrue(found_err)
end
