local mp = require 'mp'
local M = {}

--- Display a message via OSD
-- @param message string - The message to display
-- @param timeout number|nil - Optional timeout in seconds
function M.show_message(message, timeout)
    mp.osd_message(message, timeout or 2)
end

return M
