local mp = require 'mp'
local config = require 'modules.config'
local state = require 'modules.state'
local utils = require 'modules.utils'
local ui = require 'modules.ui'
local video = require 'modules.video'
local audio = require 'modules.audio'

local M = {}

--- Capture and save the current video frame and preceding audio as an intro fingerprint
-- @note Triggers OSD messages for user feedback
-- @note Spawns two sync subprocesses (ffmpeg) to extract video and audio data
-- @note Saves fingerprints to the system temp directory
function M.save_intro()
    local path = mp.get_property("path")
    local time_pos = mp.get_property_number("time-pos")

    if not path or not time_pos then
        ui.show_message("Cannot capture: No video playing", 2)
        return
    end

    ui.show_message("Generating fingerprints...")

    -- --- VIDEO SAVE ---
    local fp_path_v = utils.get_video_fingerprint_path()
    utils.log_info("Saving video fingerprint to: " .. fp_path_v)

    local vf_str = string.format("scale=%d:%d:flags=bilinear,format=gray", config.options.video_phash_size,
        config.options.video_phash_size)
    local args_v = {
        "ffmpeg", "-hide_banner", "-loglevel", "fatal", "-hwaccel", "auto",
        "-ss", tostring(time_pos), "-i", path, "-map", "v:0",
        "-vframes", "1", "-vf", vf_str, "-f", "rawvideo", "-y", "-"
    }

    local res_v = require('mp.utils').subprocess({ args = args_v, cancellable = false, capture_stderr = true })

    if res_v.status == 0 and res_v.stdout and #res_v.stdout > 0 then
        local file_v = io.open(fp_path_v, "wb")
        if file_v then
            file_v:write(tostring(time_pos) .. "\n")
            file_v:write(res_v.stdout)
            file_v:close()
        end
    else
        ui.show_message("Error capturing video frame", 3)
    end

    -- --- AUDIO SAVE ---
    local fp_path_a = utils.get_audio_fingerprint_path()
    utils.log_info("Saving audio fingerprint to: " .. fp_path_a)

    local start_a = math.max(0, time_pos - config.options.audio_fingerprint_duration)
    local dur_a = time_pos - start_a

    if dur_a <= 1 then
        ui.show_message("Intro Captured! (Video + Audio)", 2)
        return
    end

    local args_a = {
        "ffmpeg", "-hide_banner", "-loglevel", "fatal", "-vn", "-sn",
        "-ss", tostring(start_a), "-t", tostring(dur_a),
        "-i", path, "-map", "a:0",
        "-ac", "1", "-ar", tostring(config.options.audio_sample_rate),
        "-af", "dynaudnorm",
        "-f", "s16le", "-y", "-"
    }
    local res_a = require('mp.utils').subprocess({ args = args_a, cancellable = false, capture_stderr = true })

    if res_a.status ~= 0 or not res_a.stdout or #res_a.stdout == 0 then
        utils.log_info("Error capturing audio: " .. (res_a.stderr or "unknown"))
        ui.show_message("Intro Captured! (Video + Audio)", 2)
        return
    end

    local hashes, count = audio.process_audio_data(res_a.stdout)
    utils.log_info("Generated " .. count .. " audio hashes")

    local file_a = io.open(fp_path_a, "wb")
    if file_a then
        -- Format:
        -- Line 1: Header/Version
        -- Line 2: Duration of the capture (offset to skip to)
        -- Lines 3+: hash time
        file_a:write("# INTRO_FINGERPRINT_V1\n")
        file_a:write(string.format("%.4f\n", dur_a))

        local factor = config.options.audio_hop_size / config.options.audio_sample_rate
        if utils.ffi_status and type(hashes) == "cdata" then
            for i = 0, count - 1 do
                local h = hashes[i]
                file_a:write(string.format("%d %.4f\n", h.h, h.t * factor))
            end
        else
            for _, h in ipairs(hashes) do
                file_a:write(string.format("%d %.4f\n", h.h, h.t * factor))
            end
        end
        file_a:close()
    end
    ui.show_message("Intro Captured! (Video + Audio)", 2)
end

--- Scan the current video for a match using video pHash and skip if found
-- @note Runs asynchronously in a coroutine
-- @note Uses OSD messages to display progress and results
-- @note Expands the search window outwards from the saved timestamp until a match is found or limit reached
-- @note Modifies mpv property 'time-pos' on successful match
function M.skip_intro_video()
    if state.scanning then
        ui.show_message("Scan in progress...", 2)
        return
    end

    utils.run_async(function()
        local fp_path = utils.get_video_fingerprint_path()
        local file = io.open(fp_path, "rb")

        if not file then
            ui.show_message("No intro captured yet.", 2)
            return
        end

        local saved_time_str = file:read("*line")
        local saved_time = tonumber(saved_time_str)

        if not saved_time then
            ui.show_message("Corrupted fingerprint file.", 2)
            file:close()
            return
        end

        local target_bytes = file:read("*all")
        file:close()

        if not target_bytes or #target_bytes < config.VIDEO_FRAME_SIZE then
            ui.show_message("Invalid fingerprint data.", 2)
            return
        end

        state.scanning = true

        local perf_stats = { ffmpeg = 0, lua = 0, frames = 0 }
        local scan_start_time = mp.get_time()

        --- Cleanup state and display results after a video scan
        -- @param message string|nil - Optional message to display via OSD
        local function finish_scan(message)
            state.scanning = false

            local total_dur = mp.get_time() - scan_start_time
            perf_stats.lua = total_dur - perf_stats.ffmpeg

            if config.options.debug == "yes" then
                mp.msg.info(string.format("TOTAL PERF (Video): FFmpeg: %.4fs | Lua: %.4fs | Total: %.4fs | Frames: %d",
                    perf_stats.ffmpeg, perf_stats.lua, total_dur, perf_stats.frames))
            end

            if message then ui.show_message(message, 2) end
        end

        local current_video = mp.get_property("path")
        local total_duration = mp.get_property_number("duration") or math.huge

        ui.show_message(
            string.format(
                "Scanning Video %d%%...",
                math.floor(config.options.video_search_window / config.options.video_max_search_window * 100)
            ),
            120
        )

        local window_size = config.options.video_search_window
        local scanned_start = math.max(0, saved_time - window_size)
        local scanned_end = math.min(total_duration, saved_time + window_size)

        local dist, timestamp = video.scan_video_segment(scanned_start, scanned_end - scanned_start, current_video,
            target_bytes,
            perf_stats)

        if dist and dist <= config.options.video_threshold then
            mp.set_property("time-pos", timestamp)
            finish_scan(string.format("Skipped! (Dist: %d)", dist))
            return
        end

        while window_size <= config.options.video_max_search_window do
            if not state.scanning then break end

            local old_start = scanned_start
            local old_end = scanned_end

            window_size = window_size + config.options.video_window_step
            scanned_start = math.max(0, saved_time - window_size)
            scanned_end = math.min(total_duration, saved_time + window_size)

            if scanned_start == old_start and scanned_end == old_end then break end

            ui.show_message(
                string.format(
                    "Scanning Video %d%%...",
                    math.min(100, math.floor(window_size / config.options.video_max_search_window * 100))
                ),
                120
            )

            if scanned_start < old_start then
                local d, t = video.scan_video_segment(scanned_start, old_start - scanned_start, current_video,
                    target_bytes,
                    perf_stats)
                if d and d <= config.options.video_threshold then
                    mp.set_property("time-pos", t)
                    finish_scan(string.format("Skipped! (Dist: %d)", d))
                    return
                end
            end

            if not state.scanning then break end

            if scanned_end > old_end then
                local d, t = video.scan_video_segment(old_end, scanned_end - old_end, current_video, target_bytes,
                    perf_stats)
                if d and d <= config.options.video_threshold then
                    mp.set_property("time-pos", t)
                    finish_scan(string.format("Skipped! (Dist: %d)", d))
                    return
                end
            end
        end

        if state.scanning then
            finish_scan("No match found.")
        end
    end)
end

--- Scan the current audio for a match using Constellation Hashing and skip if found
-- @note Runs asynchronously in a coroutine with concurrent FFmpeg workers
-- @note Uses a Global Offset Histogram to identify the most likely match point
-- @note Implements gradient-based early stopping to terminate scans when match strength declines
-- @note Modifies mpv property 'time-pos' on successful match
-- @note Provides real-time OSD progress updates
function M.skip_intro_audio()
    if state.scanning then
        ui.show_message("Scan in progress...", 2)
        return
    end

    utils.run_async(function()
        local fp_path = utils.get_audio_fingerprint_path()
        local file = io.open(fp_path, "r")
        if not file then
            ui.show_message("No audio intro captured.", 2)
            return
        end

        local line = file:read("*line")
        if line == "# INTRO_FINGERPRINT_V1" then
            line = file:read("*line")
        end

        local capture_duration = tonumber(line)
        if not capture_duration then
            ui.show_message("Invalid audio fingerprint file.", 2)
            file:close()
            return
        end

        -- Load saved hashes (Inverted Index)
        local saved_hashes = {} -- hash -> list of times
        local total_intro_hashes = 0
        for l in file:lines() do
            local h, t = string.match(l, "([%-]?%d+) ([%d%.]+)")
            h = tonumber(h)
            t = tonumber(t)
            if h and t then
                if not saved_hashes[h] then saved_hashes[h] = {} end
                table.insert(saved_hashes[h], t)
                total_intro_hashes = total_intro_hashes + 1
            end
        end
        file:close()

        if total_intro_hashes == 0 then
            ui.show_message("Empty audio fingerprint.", 2)
            return
        end
        utils.log_info("Loaded " .. total_intro_hashes .. " audio hashes. Duration adj: " .. capture_duration)

        state.scanning = true
        ui.show_message("Scanning Audio...", 120)

        local perf_stats = { ffmpeg = 0, lua = 0 }
        local scan_start_time = mp.get_time()

        --- Cleanup state and display results after an audio scan
        -- @param message string|nil - Optional message to display via OSD
        local function finish_scan(message)
            state.scanning = false
            local total_dur = mp.get_time() - scan_start_time

            if config.options.debug == "yes" then
                -- Note: FFmpeg CPU time can exceed total wall clock time due to concurrency
                mp.msg.info(string.format("TOTAL PERF (Audio): Wall Time: %.4fs | FFmpeg CPU Time: %.4fs",
                    total_dur, perf_stats.ffmpeg))
            end
            if message then ui.show_message(message, 2) end
        end

        local path = mp.get_property("path")
        local duration = mp.get_property_number("duration") or 0
        local max_scan_time = math.min(duration, config.options.audio_scan_limit)

        -- Global Offset Histogram
        local global_offset_histogram = {}
        local time_bin_width = 0.1
        local factor = config.options.audio_hop_size / config.options.audio_sample_rate

        -- Linear Scan Parameters
        local segment_dur = config.options.audio_segment_duration
        -- Padding: enough to cover audio_target_t_max plus FFT window overhead.
        local padding = math.ceil(config.options.audio_target_t_max * config.options.audio_hop_size /
            config.options.audio_sample_rate) + 1.0

        --- Process a single hash match and update histograms
        -- @param h number - The hash value
        -- @param t number - Time index of the hash in the current segment
        -- @param target_time number - Start timestamp of the current segment
        -- @param local_histogram table - Histogram for the current segment
        local function process_hash_match(h, t, target_time, local_histogram)
            local rel_time = t * factor
            -- Filter: Ignore hashes that belong to the next segment's padding overlap
            if rel_time >= segment_dur then return end

            local saved = saved_hashes[h]
            if not saved then return end

            local track_time = target_time + rel_time
            for _, fp_time in ipairs(saved) do
                local offset = track_time - fp_time
                local bin = math.floor(offset / time_bin_width + 0.5)
                global_offset_histogram[bin] = (global_offset_histogram[bin] or 0) + 1
                local_histogram[bin] = (local_histogram[bin] or 0) + 1
            end
        end

        -- Concurrency State
        local active_workers = 0
        local processed_count = 0
        local max_workers = config.options.audio_concurrency
        local next_scan_time = 0
        local results_buffer = {} -- indexed by scan_time
        local stop_flag = false
        local previous_local_max = 0
        local last_processed_time = -segment_dur
        local header_printed = false

        local co = coroutine.running()

        --- Spawn an asynchronous worker to process a segment of audio
        -- @param scan_time number - Start timestamp for the segment
        -- @note Uses mp.command_native_async to run FFmpeg and processes results in a callback
        local function spawn_worker(scan_time)
            active_workers = active_workers + 1
            local args = {
                "ffmpeg", "-hide_banner", "-loglevel", "fatal", "-vn", "-sn",
                "-ss", tostring(scan_time), "-t", tostring(segment_dur + padding),
                "-i", path, "-map", "a:0",
                "-ac", "1", "-ar", tostring(config.options.audio_sample_rate),
                "-af", "dynaudnorm",
                "-f", "s16le", "-y", "-"
            }

            local ffmpeg_start = mp.get_time()
            mp.command_native_async({ name = "subprocess", args = args, capture_stdout = true },
                function(success, res, err)
                    active_workers = active_workers - 1
                    perf_stats.ffmpeg = perf_stats.ffmpeg + (mp.get_time() - ffmpeg_start)

                    if not (success and res.status == 0 and res.stdout and not stop_flag) then
                        results_buffer[scan_time] = { hashes = {}, count = 0 }
                        if co then coroutine.resume(co) end
                        return
                    end

                    local chunk_hashes, ch_count = audio.process_audio_data(res.stdout)
                    results_buffer[scan_time] = { hashes = chunk_hashes, count = ch_count }

                    if co then coroutine.resume(co) end
                end)
        end

        -- Main Scheduler / Consumer Loop
        while (next_scan_time < max_scan_time or active_workers > 0) and not stop_flag do
            -- Spawn workers up to max_workers
            while active_workers < max_workers and next_scan_time < max_scan_time and not stop_flag do
                spawn_worker(next_scan_time)
                next_scan_time = next_scan_time + segment_dur
            end

            -- Process completed results in order
            local target_time = last_processed_time + segment_dur
            while results_buffer[target_time] do
                local res = results_buffer[target_time]
                results_buffer[target_time] = nil -- Clear memory
                local chunk_hashes = res.hashes
                local ch_count = res.count

                local local_max = 0
                local local_histogram = {}

                -- Update Global & Local Histograms
                -- Linear Scan Rule: Only accept hashes anchored within the segment [target_time, target_time + segment_dur)
                if utils.ffi_status and type(chunk_hashes) == "cdata" then
                    for i = 0, ch_count - 1 do
                        local ch = chunk_hashes[i]
                        process_hash_match(ch.h, ch.t, target_time, local_histogram)
                    end
                else
                    for _, ch in ipairs(chunk_hashes) do
                        process_hash_match(ch.h, ch.t, target_time, local_histogram)
                    end
                end

                for bin, cnt in pairs(local_histogram) do
                    local score = cnt + (local_histogram[bin - 1] or 0) + (local_histogram[bin + 1] or 0)
                    if score > local_max then local_max = score end
                end

                local local_ratio = local_max / total_intro_hashes

                if not header_printed then
                    utils.log_info(string.format("| %-11s | %-5s | %-5s |", "Segment (s)", "Score", "Ratio"))
                    utils.log_info("|-------------|-------|-------|")
                    header_printed = true
                end

                utils.log_info(string.format("| %11.1f | %5d | %5.2f |", target_time, local_max, local_ratio))

                -- Gradient-based early stopping (Ordered check)
                -- Only consider matches that meet the minimum match ratio
                local confidence_threshold = config.options.audio_threshold * 2.5
                local meets_ratio = local_ratio >= config.options.audio_min_match_ratio

                if meets_ratio and local_max > previous_local_max then
                    previous_local_max = local_max
                end

                if previous_local_max > confidence_threshold and local_max < (previous_local_max * 0.5) then
                    utils.log_info(string.format("Gradient drop detected (%d -> %d) at %.1f. Stopping.",
                        previous_local_max,
                        local_max, target_time))
                    stop_flag = true
                    break
                end

                last_processed_time = target_time
                target_time = last_processed_time + segment_dur
                processed_count = processed_count + 1
                ui.show_message(string.format("Scanning Audio %d%%...", math.floor(target_time / max_scan_time * 100)),
                    120)
            end

            if not stop_flag and (next_scan_time < max_scan_time or active_workers > 0) then
                coroutine.yield()
            end
        end

        if state.scanning then
            -- Find Peak in Global Histogram
            local best_bin = nil
            local max_val = 0
            for bin, cnt in pairs(global_offset_histogram) do
                local score = cnt + (global_offset_histogram[bin - 1] or 0) + (global_offset_histogram[bin + 1] or 0)
                if score > max_val then
                    max_val = score
                    best_bin = bin
                end
            end

            local best_ratio = max_val / total_intro_hashes
            if best_bin and max_val > config.options.audio_threshold and best_ratio >= config.options.audio_min_match_ratio then
                local peak_offset = best_bin * time_bin_width
                local target_pos = peak_offset + capture_duration
                mp.set_property("time-pos", target_pos)
                finish_scan(string.format("Skipped! (Score: %d, Ratio: %.2f)", max_val, best_ratio))
            else
                finish_scan(string.format("No match (Best Ratio: %.2f)", best_ratio))
            end
        end
    end)
end

return M
