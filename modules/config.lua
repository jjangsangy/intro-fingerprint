local M = {}

--- @table options Configuration options for the intro skipper
-- These can be overridden in intro-fingerprint.conf or via --script-opts=intro-fingerprint-<key>=<value>
M.options = {
    -- Toggle console debug printing (Performance stats, scan info)
    debug = "no",

    -- Audio: Configuration
    audio_sample_rate = 11025,
    audio_fft_size = 2048,
    audio_hop_size = 1024,
    audio_target_t_min = 10,         -- min delay in frames for pairs
    audio_target_t_max = 100,        -- max delay in frames for pairs
    audio_threshold = 10,            -- minimum magnitude for peaks
    audio_scan_limit = 900,          -- max seconds to scan (15 mins)
    audio_fingerprint_duration = 10, -- duration of the audio fingerprint in seconds
    audio_segment_duration = 15,     -- duration of each scan segment in seconds
    audio_concurrency = 4,           -- number of concurrent ffmpeg workers
    audio_min_match_ratio = 0.30,    -- minimum percentage of hashes that must match (0.0 - 1.0)

    -- Video: Configuration
    video_phash_size = 64,         -- pHash size (64x64 input -> 16x16 DCT -> 256 bit hash)
    video_interval = 0.20,         -- time interval to check in seconds (0.20 = 200ms)
    video_threshold = 50,          -- tolerance for Hamming Distance (0-256).
    video_search_window = 10,      -- seconds before/after saved timestamp to search
    video_max_search_window = 300, -- stop expanding after this offset
    video_window_step = 30,        -- step size

    -- Name of the temp files
    video_temp_filename = "mpv_intro_skipper_video.dat",
    audio_temp_filename = "mpv_intro_skipper_audio.dat",

    -- Key Bindings
    key_save_intro = "Ctrl+i",
    key_skip_video = "Ctrl+Shift+s",
    key_skip_audio = "Ctrl+s",
}

--- Load configuration from file
-- @note Uses mp.options.read_options()
require('mp.options').read_options(M.options, 'intro-fingerprint')

--- @var VIDEO_FRAME_SIZE number - Expected size of a grayscale video frame in bytes
M.VIDEO_FRAME_SIZE = M.options.video_phash_size * M.options.video_phash_size

return M
