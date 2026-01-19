local mp = require 'mp'
local config = require 'modules.config'
local state = require 'modules.state'
local utils = require 'modules.utils'
local ui = require 'modules.ui'
local video = require 'modules.video'
local audio = require 'modules.audio'
local ffmpeg = require 'modules.ffmpeg'
local fingerprint_io = require 'modules.fingerprint_io'

local M = {}

-- =================================================================================================
-- Helper Functions: save_intro
-- =================================================================================================

--- Capture and validate video fingerprint
-- @param path string - Video file path
-- @param time_pos number - Timestamp to capture
-- @return boolean - Success status
function M.capture_video(path, time_pos)
    local res_v = ffmpeg.run_task('extract_video', { time = time_pos, path = path })

    if res_v and res_v.status == 0 and res_v.stdout and #res_v.stdout > 0 then
        local valid, reason = video.validate_frame(res_v.stdout, false)
        if not valid then
            utils.log_info("Frame Rejected: " .. reason)
            ui.show_message("Frame Rejected: " .. reason, 4)
            return false
        end

        fingerprint_io.write_video(time_pos, res_v.stdout)
        return true
    else
        ui.show_message("Error capturing video frame", 3)
        return false
    end
end

--- Capture and validate audio fingerprint
-- @param path string - Video file path
-- @param time_pos number - Timestamp to capture
-- @return boolean - Success status
function M.capture_audio(path, time_pos)
    local start_a = math.max(0, time_pos - config.options.audio_fingerprint_duration)
    local dur_a = time_pos - start_a

    if dur_a <= 1 then
        return true -- Consider short duration as "done" but maybe not successful capture, consistent with original logic which returned
    end

    local res_a = ffmpeg.run_task('extract_audio', { start = start_a, duration = dur_a, path = path })

    if not res_a or res_a.status ~= 0 or not res_a.stdout or #res_a.stdout == 0 then
        utils.log_info("Error capturing audio: " .. ((res_a and res_a.stderr) or "unknown"))
        return true -- Original logic returned "Intro Captured!" even on error here, likely assuming video was enough? Or just a bug/feature.
                    -- Actually original logic: ui.show_message("Intro Captured! (Video + Audio)", 2); return
                    -- So it treated it as completion.
    end

    local valid, reason = audio.validate_audio(res_a.stdout)
    if not valid then
        utils.log_info("Audio Rejected: " .. reason)
        ui.show_message("Audio Rejected: " .. reason, 4)
        return false
    end

    local hashes, count = audio.process_audio_data(res_a.stdout)
    if count < 50 then
        utils.log_info("Audio Rejected: Low Complexity (" .. count .. " hashes)")
        ui.show_message("Audio Rejected: Low Complexity", 4)
        return false
    end

    utils.log_info("Generated " .. count .. " audio hashes")
    fingerprint_io.write_audio(dur_a, hashes, count)
    return true
end

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
    if not M.capture_video(path, time_pos) then
        return
    end

    -- --- AUDIO SAVE ---
    if M.capture_audio(path, time_pos) then
        ui.show_message("Intro Captured! (Video + Audio)", 2)
    end
end

-- =================================================================================================
-- Helper Functions: skip_intro_video
-- =================================================================================================

--- Cleanup state and display results after a video scan
-- @param message string|nil - Optional message to display via OSD
-- @param scan_start_time number - Time when scan started
-- @param perf_stats table - Performance statistics
function M.finish_video_scan(message, scan_start_time, perf_stats)
    state.scanning = false

    local total_dur = mp.get_time() - scan_start_time
    perf_stats.lua = total_dur - perf_stats.ffmpeg

    if config.options.debug == "yes" then
        mp.msg.info(string.format("TOTAL PERF (Video): FFmpeg: %.4fs | Lua: %.4fs | Total: %.4fs | Frames: %d",
            perf_stats.ffmpeg, perf_stats.lua, total_dur, perf_stats.frames))
    end

    if message then ui.show_message(message, 2) end
end

--- Execute the video scan loop with expanding window
-- @param saved_time number - The timestamp of the saved fingerprint
-- @param target_bytes string - The raw fingerprint data
-- @param total_duration number - Total duration of the video
-- @param current_video string - Path to current video
-- @param perf_stats table - Performance statistics
-- @param scan_start_time number - Start time for perf calculation
function M.scan_video_loop(saved_time, target_bytes, total_duration, current_video, perf_stats, scan_start_time)
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
        M.finish_video_scan(string.format("Skipped! (Dist: %d)", dist), scan_start_time, perf_stats)
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
                M.finish_video_scan(string.format("Skipped! (Dist: %d)", d), scan_start_time, perf_stats)
                return
            end
        end

        if not state.scanning then break end

        if scanned_end > old_end then
            local d, t = video.scan_video_segment(old_end, scanned_end - old_end, current_video, target_bytes,
                perf_stats)
            if d and d <= config.options.video_threshold then
                mp.set_property("time-pos", t)
                M.finish_video_scan(string.format("Skipped! (Dist: %d)", d), scan_start_time, perf_stats)
                return
            end
        end
    end

    if state.scanning then
        M.finish_video_scan("No match found.", scan_start_time, perf_stats)
    end
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
        local saved_time, target_bytes = fingerprint_io.read_video()

        if not saved_time then
            ui.show_message("No intro captured yet.", 2)
            return
        end

        if not target_bytes or #target_bytes < config.VIDEO_FRAME_SIZE then
            ui.show_message("Invalid fingerprint data.", 2)
            return
        end

        state.scanning = true

        local perf_stats = { ffmpeg = 0, lua = 0, frames = 0 }
        local scan_start_time = mp.get_time()
        local current_video = mp.get_property("path")
        local total_duration = mp.get_property_number("duration") or math.huge

        M.scan_video_loop(saved_time, target_bytes, total_duration, current_video, perf_stats, scan_start_time)
    end)
end

-- =================================================================================================
-- Helper Functions: skip_intro_audio
-- =================================================================================================

--- Process a single hash match and update histograms
-- @param ctx table - Scan context
-- @param h number - The hash value
-- @param t number - Time index of the hash in the current segment
-- @param target_time number - Start timestamp of the current segment
-- @param local_histogram table - Histogram for the current segment
function M.process_hash_match(ctx, h, t, target_time, local_histogram)
    local rel_time = t * ctx.factor
    -- Filter: Ignore hashes that belong to the next segment's padding overlap
    if rel_time >= ctx.segment_dur then return end
    if not ctx.saved_hashes then return end
    local saved = ctx.saved_hashes[h]
    if not saved then return end

    local track_time = target_time + rel_time
    for _, fp_time in ipairs(saved) do
        local offset = track_time - fp_time
        local bin = math.floor(offset / ctx.time_bin_width + 0.5)
        ctx.global_offset_histogram[bin] = (ctx.global_offset_histogram[bin] or 0) + 1
        local_histogram[bin] = (local_histogram[bin] or 0) + 1
    end
end

--- Spawn an asynchronous worker to process a segment of audio
-- @param ctx table - Scan context
-- @param scan_time number - Start timestamp for the segment
function M.spawn_audio_worker(ctx, scan_time)
    ctx.active_workers = ctx.active_workers + 1
    local ffmpeg_start = mp.get_time()

    ffmpeg.run_task('scan_audio', { start = scan_time, duration = ctx.segment_dur + ctx.padding, path = ctx.path },
        function(success, res, err)
            ctx.active_workers = ctx.active_workers - 1
            ctx.perf_stats.ffmpeg = ctx.perf_stats.ffmpeg + (mp.get_time() - ffmpeg_start)

            if not (success and res.status == 0 and res.stdout and not ctx.stop_flag) then
                ctx.results_buffer[scan_time] = { hashes = {}, count = 0 }
                if ctx.co then coroutine.resume(ctx.co) end
                return
            end

            local chunk_hashes, ch_count = audio.process_audio_data(res.stdout)
            ctx.results_buffer[scan_time] = { hashes = chunk_hashes, count = ch_count }

            if ctx.co then coroutine.resume(ctx.co) end
        end)
end

--- Check for gradient drop to stop scan early
-- @param ctx table - Scan context
-- @param local_max number - Max score in local histogram
-- @param target_time number - Current processing time
-- @param local_ratio number - Match ratio
function M.check_early_stop(ctx, local_max, target_time, local_ratio)
    local confidence_threshold = config.options.audio_threshold * 2.5
    local meets_ratio = local_ratio >= config.options.audio_min_match_ratio

    if meets_ratio and local_max > ctx.previous_local_max then
        ctx.previous_local_max = local_max
    end

    if ctx.previous_local_max > confidence_threshold and local_max < (ctx.previous_local_max * 0.5) then
        utils.log_info(string.format("Gradient drop detected (%d -> %d) at %.1f. Stopping.",
            ctx.previous_local_max,
            local_max, target_time))
        ctx.stop_flag = true
    end
end

--- Cleanup state and display results after an audio scan
-- @param ctx table - Scan context
-- @param message string|nil - Optional message to display via OSD
function M.finish_audio_scan(ctx, message)
    state.scanning = false
    local total_dur = mp.get_time() - ctx.scan_start_time

    if config.options.debug == "yes" then
        -- Note: FFmpeg CPU time can exceed total wall clock time due to concurrency
        mp.msg.info(string.format("TOTAL PERF (Audio): Wall Time: %.4fs | FFmpeg CPU Time: %.4fs",
            total_dur, ctx.perf_stats.ffmpeg))
    end
    if message then ui.show_message(message, 2) end
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
        local capture_duration, saved_hashes, total_intro_hashes = fingerprint_io.read_audio()

        if not capture_duration then
            ui.show_message("No audio intro captured.", 2)
            return
        end

        if total_intro_hashes == 0 then
            ui.show_message("Empty audio fingerprint.", 2)
            return
        end
        utils.log_info("Loaded " .. total_intro_hashes .. " audio hashes. Duration adj: " .. capture_duration)

        state.scanning = true
        ui.show_message("Scanning Audio...", 120)

        -- Context initialization
        local ctx = {
            saved_hashes = saved_hashes,
            capture_duration = capture_duration,
            path = mp.get_property("path"),
            duration = mp.get_property_number("duration") or 0,

            global_offset_histogram = {},
            time_bin_width = 0.1,
            factor = config.options.audio_hop_size / config.options.audio_sample_rate,

            segment_dur = config.options.audio_segment_duration,
            padding = math.ceil(config.options.audio_target_t_max * config.options.audio_hop_size / config.options.audio_sample_rate) + 1.0,

            active_workers = 0,
            max_workers = config.options.audio_concurrency,
            results_buffer = {},
            stop_flag = false,
            previous_local_max = 0,
            header_printed = false,

            perf_stats = { ffmpeg = 0, lua = 0 },
            scan_start_time = mp.get_time(),
            co = coroutine.running()
        }

        local max_scan_time = math.min(ctx.duration, config.options.audio_scan_limit)
        local next_scan_time = 0
        local last_processed_time = -ctx.segment_dur
        local processed_count = 0

        -- Main Scheduler / Consumer Loop
        while (next_scan_time < max_scan_time or ctx.active_workers > 0) and not ctx.stop_flag do
            -- Spawn workers up to max_workers
            while ctx.active_workers < ctx.max_workers and next_scan_time < max_scan_time and not ctx.stop_flag do
                M.spawn_audio_worker(ctx, next_scan_time)
                next_scan_time = next_scan_time + ctx.segment_dur
            end

            -- Process completed results in order
            local target_time = last_processed_time + ctx.segment_dur
            while ctx.results_buffer[target_time] do
                local res = ctx.results_buffer[target_time]
                ctx.results_buffer[target_time] = nil -- Clear memory
                local chunk_hashes = res.hashes
                local ch_count = res.count

                local local_max = 0
                local local_histogram = {}

                -- Update Global & Local Histograms
                if utils.ffi_status and type(chunk_hashes) == "cdata" then
                    for i = 0, ch_count - 1 do
                        local ch = chunk_hashes[i]
                        M.process_hash_match(ctx, ch.h, ch.t, target_time, local_histogram)
                    end
                else
                    for _, ch in ipairs(chunk_hashes) do
                        M.process_hash_match(ctx, ch.h, ch.t, target_time, local_histogram)
                    end
                end

                for bin, cnt in pairs(local_histogram) do
                    local score = cnt + (local_histogram[bin - 1] or 0) + (local_histogram[bin + 1] or 0)
                    if score > local_max then local_max = score end
                end

                local local_ratio = local_max / total_intro_hashes

                if not ctx.header_printed then
                    utils.log_info(string.format("| %-11s | %-5s | %-5s |", "Segment (s)", "Score", "Ratio"))
                    utils.log_info("|-------------|-------|-------|")
                    ctx.header_printed = true
                end

                utils.log_info(string.format("| %11.1f | %5d | %5.2f |", target_time, local_max, local_ratio))

                M.check_early_stop(ctx, local_max, target_time, local_ratio)
                if ctx.stop_flag then break end

                last_processed_time = target_time
                target_time = last_processed_time + ctx.segment_dur
                processed_count = processed_count + 1
                ui.show_message(string.format("Scanning Audio %d%%...", math.floor(target_time / max_scan_time * 100)),
                    120)
            end

            if not ctx.stop_flag and (next_scan_time < max_scan_time or ctx.active_workers > 0) then
                coroutine.yield()
            end
        end

        if state.scanning then
            -- Find Peak in Global Histogram
            local best_bin = nil
            local max_val = 0
            for bin, cnt in pairs(ctx.global_offset_histogram) do
                local score = cnt + (ctx.global_offset_histogram[bin - 1] or 0) + (ctx.global_offset_histogram[bin + 1] or 0)
                if score > max_val then
                    max_val = score
                    best_bin = bin
                end
            end

            local best_ratio = max_val / total_intro_hashes
            if best_bin and max_val > config.options.audio_threshold and best_ratio >= config.options.audio_min_match_ratio then
                local peak_offset = best_bin * ctx.time_bin_width
                local target_pos = peak_offset + capture_duration
                mp.set_property("time-pos", target_pos)
                M.finish_audio_scan(ctx, string.format("Skipped! (Score: %d, Ratio: %.2f)", max_val, best_ratio))
            else
                M.finish_audio_scan(ctx, string.format("No match (Best Ratio: %.2f)", best_ratio))
            end
        end
    end)
end

return M
