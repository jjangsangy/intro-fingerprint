--- Intro Fingerprint: Video & Audio Intro Skipper for mpv
-- This script provides functionality to capture and skip intros by fingerprinting
-- video frames (pHash) and audio segments (Constellation Hashing).
-- It supports both standard Lua and LuaJIT (FFI) for performance.

local mp = require 'mp'
local config = require 'modules.config'
local actions = require 'modules.actions'
local utils = require 'modules.utils'

--- Event observer for 'end-file' to ensure cleanup on file change
-- Ensures that scans are aborted if the user switches files while a scan is running.
mp.register_event("end-file", utils.abort_scan)

--- Register Key Bindings for script functionality
-- @note Uses mp.add_key_binding()
-- @note Commands: save-intro, skip-intro-video, skip-intro-audio
mp.add_key_binding(config.options.key_save_intro, "save-intro", actions.save_intro)
mp.add_key_binding(config.options.key_skip_video, "skip-intro-video", actions.skip_intro_video)
mp.add_key_binding(config.options.key_skip_audio, "skip-intro-audio", actions.skip_intro_audio)
