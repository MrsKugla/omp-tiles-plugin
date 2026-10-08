--!strict
-- Port of Flow's hooks/night.ts: one night for every scene that has one.

local M = {}

M.NIGHT_HORIZON = 0x070b16
M.NIGHT_ZENITH = 0x020308
M.STAR = 0xeef0f4
M.STAR_DIM = 0x7d8696
M.MOON = 0xf4f0da
M.MOON_ACROSS = 0.82
M.MOON_ROW = 1

-- The moon's center on a quadrant pixel layer: returns x, y.
function M.moonPixel(columns: number, rows: number): (number, number)
	return columns * 2 * M.MOON_ACROSS, 2 * math.min(M.MOON_ROW, math.max(0, rows - 3)) + 1
end

function M.moonRadius(tall: boolean): number
	return if tall then 2.6 else 1.6
end

function M.moonCover(x: number, y: number, mx: number, my: number, r: number): number
	local dx, dy = x - mx, (y - my) * 2
	local d = math.sqrt(dx * dx + dy * dy)
	return if d >= r + 0.5 then 0 elseif d <= r - 0.5 then 1 else r + 0.5 - d
end

return M
