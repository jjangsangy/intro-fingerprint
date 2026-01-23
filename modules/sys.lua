local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

local M = {}

--- Create a directory if it doesn't exist
-- @param path string - The directory path to create
function M.make_directory(path)
    local platform = mp.get_property("platform")
    local cmd

    if platform == "windows" then
        -- Windows requires backslashes for cmd.exe mkdir
        path = path:gsub("/", "\\")
        cmd = {"cmd.exe", "/c", "mkdir", path}
    else
        -- Linux/macOS uses 'mkdir -p' (the -p creates parent folders if missing)
        cmd = {"mkdir", "-p", path}
    end

    local res = mp.command_native({
        name = "subprocess",
        args = cmd,
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true
    })

    if res.status ~= 0 then
        -- Ignore error if directory already exists (status 1 on Windows often)
        -- But good to log if it's something else
        if res.status ~= 1 and res.stderr ~= "" then
             msg.warn("Failed to create directory: " .. path .. " Error: " .. (res.stderr or ""))
        end
    end
end

--- Get the directory where fingerprints should be stored
-- @return string - Full path to the fingerprints directory
function M.get_fingerprint_dir()
    local path = utils.join_path(mp.get_script_directory(), "fingerprints")
    M.make_directory(path)
    return path
end

return M
