-- tests/run_tests.lua

-- 1. Setup paths
-- Add project root to package.path so we can require 'modules.xxx'
-- Assuming this script is run from project root: lua tests/run_tests.lua
package.path = package.path .. ";./?.lua;./?/init.lua"

-- 2. Setup Testing Framework and Dependencies (Before loading tests)
local function download_file(path, url)
    local f = io.open(path, "r")
    if f ~= nil then
        io.close(f)
        return
    end

    print("File " .. path .. " not found. Downloading...")

    local success = false
    local ret

    -- 1. Try curl
    if not success then
        local cmd = "curl -L -o " .. path .. " " .. url
        ret = os.execute(cmd)
        if ret == 0 or ret == true then success = true end
    end

    -- 2. Try wget
    if not success then
         local cmd = "wget -O " .. path .. " " .. url
         ret = os.execute(cmd)
         if ret == 0 or ret == true then success = true end
    end

    -- 3. Try BITSAdmin (Windows cmd fallback)
    if not success then
        -- bitsadmin requires absolute paths and backslashes
        local win_path = path:gsub("/", "\\")
        local job_name = "Download_" .. os.time()
        -- %CD% is expanded by cmd.exe to the current directory
        local cmd = 'bitsadmin /transfer "' .. job_name .. '" /priority foreground "' .. url .. '" "%CD%\\' .. win_path .. '"'
        ret = os.execute(cmd)
        if ret == 0 or ret == true then success = true end
    end

    if not success then
         print("Error: Failed to download " .. path .. ". Please download it manually from:")
         print(url)
         print("and place it in " .. path)
         os.exit(1)
    end
end

local function setup_dependencies()
    -- Ensure luaunit
    download_file("tests/luaunit.lua", "https://raw.githubusercontent.com/bluebird75/luaunit/master/luaunit.lua")

    -- Ensure zfft (reference implementation for perf tests)
    download_file("tests/zfft.lua", "https://raw.githubusercontent.com/zorggn/zorg-fft/refs/heads/master/src/lua/zfft.lua")
end

setup_dependencies()

-- 3. Setup Mocks
local mocks = require('tests.mocks')
local mp_mock = mocks.create_mp()

-- Preload 'mp' and its sub-modules
mocks.init_preload(mp_mock)

-- 4. Load Test Files
require('tests.test_config')
require('tests.test_utils')
require('tests.test_fft')
require('tests.test_video')
require('tests.test_audio')
require('tests.test_ffmpeg')
require('tests.test_ui')
require('tests.test_state')
require('tests.test_actions')
require('tests.test_fingerprint_io')
require('tests.test_fft_perf')
require('tests.test_pdqhash')

-- 5. Run Tests
local lu = require('tests.luaunit')
os.exit(lu.LuaUnit.run())
