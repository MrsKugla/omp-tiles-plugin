--!strict
-- Port of Flow's hooks/waiting.ts: the sepia breath while the agent waits on you.

local cellsM = require("./cells")
local pixels = require("./pixels")
local js = require("./js")
local clamp, mix = pixels.clamp, pixels.mix
local DEFAULT_COLOR = cellsM.DEFAULT_COLOR
local extract = bit32.extract
local round = js.round

local M = {}

M.WAIT_EASE = 0.06
M.BREATH_FRAMES = 56
local DEPTH = 0.11
local GLOW = { 0x17, 0x0e, 0x04 }
M.SEPIA_AMOUNT = 0.82
local SEPIA = { 0x000000, 0x2c1b0c, 0x6a4420, 0xb07a36, 0xe2b46a, 0xfff1d4 }

function M.easeWait(k: number, waiting: boolean?): number
	return clamp(k + clamp((if waiting then 1 else 0) - k, -M.WAIT_EASE, M.WAIT_EASE))
end

local E = math.exp(1)
local function breath(t: number): number
	local bf = M.BREATH_FRAMES
	local x = math.fmod(math.fmod(t, bf) + bf, bf) / bf
	return (math.exp(math.sin(x * 2 * math.pi - math.pi / 2)) - 1 / E) / (E - 1 / E)
end
M.breath = breath

local function waitLift(k: number, t: number): number
	return 1 - DEPTH * clamp(k) * (1 - breath(t))
end
M.waitLift = waitLift

local function lum(c: number): number
	return (extract(c, 16, 8) * 0.3 + extract(c, 8, 8) * 0.59 + extract(c, 0, 8) * 0.11) / 255
end

local function sepia(v: number): number
	local x = clamp(v) * (#SEPIA - 1)
	local i = math.min(#SEPIA - 2, math.floor(x))
	return mix(SEPIA[i + 1], SEPIA[i + 2], x - i)
end

local function waitGlow(k: number, t: number): number
	return clamp(k) * breath(t)
end
M.waitGlow = waitGlow

local function waitColor(c: number, k: number, lift: number, amount: number?, glow: number?): number
	local am = amount or M.SEPIA_AMOUNT
	local gl = glow or 0
	if c == DEFAULT_COLOR or k <= 0 then
		return c
	end
	local s = if am > 0 then mix(c, sepia(lum(c)), k * am) else c
	local r = math.min(255, round(extract(s, 16, 8) * lift + GLOW[1] * gl))
	local g = math.min(255, round(extract(s, 8, 8) * lift + GLOW[2] * gl))
	local b = math.min(255, round(extract(s, 0, 8) * lift + GLOW[3] * gl))
	return r * 65536 + g * 256 + b
end
M.waitColor = waitColor

-- lamps: per cell (1-based table of color or -1), may be nil.
function M.waitTone(out: cellsM.Cells, k: number, t: number, amount: number?, lamps: { number }?)
	if k <= 0 then
		return
	end
	local am = if amount == nil then M.SEPIA_AMOUNT else amount
	local lift = waitLift(k, t)
	local glow = waitGlow(k, t)
	local n = out.columns * out.rows
	for i = 0, n - 1 do
		local fg = out:foreground(i)
		local bg = out:background(i)
		if not (fg == DEFAULT_COLOR and bg == DEFAULT_COLOR) then
			local lamp = if lamps then lamps[i + 1] else -1
			local function tone(c: number): number
				return if c == lamp then waitColor(c, k, lift, 0) else waitColor(c, k, lift, am, glow)
			end
			out:set(i, out:codePoint(i), tone(fg), tone(bg))
		end
	end
end

return M
