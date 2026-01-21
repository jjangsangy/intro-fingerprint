local M = {}

--- @table DCT_MATRIX - 16x64 DCT Matrix (Rows 1-16 of standard DCT-II)
-- Generated at runtime to avoid hardcoding large tables.
-- Formula: D[u][x] = sqrt(2/64) * cos( (pi/64) * (x + 0.5) * u )
-- Where u is frequency index (1..16) and x is spatial index (0..63)
M.DCT_MATRIX = {}

local sqrt2_64 = math.sqrt(2 / 64)
local pi_64 = math.pi / 64

for u = 1, 16 do
    local row = {}
    for x = 0, 63 do
        -- u is 1-based here, matching frequency 1..16 (DC is 0)
        local val = sqrt2_64 * math.cos(pi_64 * (x + 0.5) * u)
        table.insert(row, val)
    end
    table.insert(M.DCT_MATRIX, row)
end

return M
