local M = {}

-- Global scanning state to prevent race conditions
--- @var scanning boolean - Whether a scan is currently in progress
M.scanning = false

--- @var current_scan_token number|nil - The token for the active async command
M.current_scan_token = nil

return M
