--!strict
-- Port of Flow's hooks/fire.ts (the automaton, glyphs, 256-color ramps) and
-- hooks/fire-palette.ts (the truecolor ramps). Arrays here are 0-based by
-- index arithmetic (t[i + 1]) to match the original line for line.

local cellsM = require("./cells")
local js = require("./js")
local f32, u8, u16, round = js.f32, js.u8, js.u16, js.round

local M = {}

local GLYPHS = { 0x2591, 0x2592, 0x2593, 0x2588 }
local BODY_ROWS = 4
local HEADROOM_COOL = 14
local HEADROOM_COOL_MIN = 4
M.SMOKE_TIPS = 0.5
local SMOKE_TIPS = M.SMOKE_TIPS

local PEAKS = { 0, 2, 4, 7, 11, 14, 17, 20, 24, 29, 35 }
local SEEDS = { 0, 10, 24, 42, 60, 74, 86, 94, 100, 100, 100 }

-- Map strength to (peak heat, base coverage %). Strength is used as an index
-- in the original (`peaks[s]!`): a fractional strength reads undefined there,
-- which callers never pass.
function M.params(strength: number): (number, number)
	if strength <= 0 then
		return 0, 0
	end
	local s = math.min(10, strength)
	return PEAKS[s + 1], SEEDS[s + 1]
end

local LIFE_MIN = 20
local LIFE_SPAN = 95
local LEVEL_OUT = 0.08

local function xterm(idx: number): number
	if idx >= 232 then
		local g = 8 + (idx - 232) * 10
		return g * 65536 + g * 256 + g
	end
	if idx >= 16 then
		local lv = { 0, 95, 135, 175, 215, 255 }
		local i = idx - 16
		return lv[i // 36 + 1] * 65536 + lv[(i // 6) % 6 + 1] * 256 + lv[i % 6 + 1]
	end
	return 0xffffff
end

local BLUE_PILOT = { 19, 27, 33 }
local ORANGE = { 130, 166, 172, 208, 214, 220 }
local MIX5 = { 124, 160, 166, 208, 214, 220 }
local RED67 = { 88, 124, 160, 196, 202, 208 }
local RED8 = { 52, 88, 124, 160, 196, 202, 208, 214 }
local RED9 = { 88, 124, 160, 196, 202, 208, 214, 220 }
local RED10 = { 124, 160, 196, 202, 208, 214, 220, 226 }
local SMOKE = { 236, 238, 240, 242, 244, 246, 248, 250 }
local BLUE_CORE = { 33, 39, 45, 51, 87, 159 }

local function pick(r: { number }, x: number): number
	local n = #r
	return r[math.min(n - 1, math.floor(math.min(1, math.max(0, x)) * n)) + 1]
end

function M.colorFor(strength: number, r: number, tint: string?): number
	local tn = tint or "normal"
	local idx
	if tn == "smoke" and r < SMOKE_TIPS then
		idx = pick(SMOKE, r / SMOKE_TIPS)
	elseif tn == "blue" and r >= 0.6 then
		idx = pick(BLUE_CORE, (r - 0.6) / 0.4)
	elseif strength == 1 then
		idx = pick(BLUE_PILOT, r)
	elseif strength <= 4 then
		local warmth = if strength == 2 then 0.75 elseif strength == 3 then 0.92 else 1
		idx = if r < warmth then pick(ORANGE, r) else pick(BLUE_PILOT, r)
	elseif strength == 5 then
		idx = pick(MIX5, r)
	elseif strength <= 7 then
		idx = pick(RED67, r)
	elseif strength == 8 then
		idx = pick(RED8, r)
	elseif strength == 9 then
		idx = pick(RED9, r)
	else
		idx = pick(RED10, r)
	end
	return xterm(idx)
end

function M.glyphFor(r: number): number
	return if r < 0.18 then GLYPHS[1] elseif r < 0.52 then GLYPHS[2] elseif r < 0.86 then GLYPHS[3] else GLYPHS[4]
end

-- fire-palette.ts ------------------------------------------------------------

type Stop = { number }
local BLACKBODY: { Stop } = {
	{ 0, 48, 6, 3 },
	{ 0.18, 118, 16, 5 },
	{ 0.38, 204, 48, 8 },
	{ 0.58, 246, 124, 20 },
	{ 0.78, 255, 204, 72 },
	{ 1, 255, 249, 218 },
}
local PILOT: { Stop } = { { 0, 10, 18, 74 }, { 0.5, 34, 88, 226 }, { 1, 172, 216, 255 } }
local BLUE_HOT: { Stop } = {
	{ 0, 48, 6, 3 },
	{ 0.3, 150, 26, 8 },
	{ 0.55, 238, 112, 22 },
	{ 0.75, 124, 172, 255 },
	{ 1, 228, 242, 255 },
}
local GREY: { Stop } = { { 0, 44, 44, 46 }, { 1, 196, 196, 200 } }
local WISP: { Stop } = { { 0, 46, 44, 46 }, { 1, 128, 122, 120 } }
local STEPS = 48

local function ramp(stops: { Stop }, t: number): number
	local x = math.min(1, math.max(0, t))
	local i = 2
	while i < #stops and stops[i][1] < x do
		i += 1
	end
	local a, b = stops[i - 1], stops[i]
	local k = if b[1] == a[1] then 0 else (x - a[1]) / (b[1] - a[1])
	local function ch(j: number): number
		return round(a[j + 2] + (b[j + 2] - a[j + 2]) * k)
	end
	return ch(0) * 65536 + ch(1) * 256 + ch(2)
end

local luts: { [any]: { number } } = {}
local function lut(stops: { Stop }): { number }
	local l = luts[stops]
	if not l then
		l = table.create(STEPS + 1)
		for i = 0, STEPS do
			l[i + 1] = ramp(stops, i / STEPS)
		end
		luts[stops] = l
	end
	return l
end

function M.smokeColor(t: number): number
	return lut(WISP)[round(math.min(1, math.max(0, t)) * STEPS) + 1]
end

function M.heatColor(strength: number, t: number, tint: string?): number
	local tn = tint or "normal"
	if tn == "smoke" and t < SMOKE_TIPS then
		return lut(GREY)[round((t / SMOKE_TIPS) * STEPS) + 1]
	end
	local stops = if tn == "blue" then BLUE_HOT elseif strength == 1 then PILOT else BLACKBODY
	local reach = if strength == 1 then 1 else 0.52 + 0.048 * math.min(10, strength)
	return lut(stops)[round(math.min(1, math.max(0, t)) * reach * STEPS) + 1]
end

-- The automaton ---------------------------------------------------------------

export type AsciiFire = {
	w: number,
	h: number,
	cells: { number },
	strength: number,
	coverageBoost: number,
	peak: number,
	t: number,
	rank: { number },
	target: { number },
	level: { number },
	rate: { number },
	life: { number },
	rng: cellsM.Rng,
	ensure: (self: AsciiFire, w: number, h: number) -> (),
	step: (self: AsciiFire) -> (),
}

local Fire = {}
Fire.__index = Fire

function M.new(seed: number?): AsciiFire
	return (setmetatable({
		w = 0,
		h = 0,
		cells = {},
		strength = 8,
		coverageBoost = 0,
		peak = 1,
		t = 0,
		rank = {},
		target = {},
		level = {},
		rate = {},
		life = {},
		rng = cellsM.Rng.new(seed),
	}, Fire) :: any) :: AsciiFire
end

local function reroll(self: AsciiFire, x: number)
	local rng = self.rng
	self.rank[x + 1] = f32(rng:f())
	self.target[x + 1] = f32(0.6 + 0.4 * rng:f())
	self.rate[x + 1] = f32(0.03 + 0.07 * rng:f())
	self.life[x + 1] = u16(LIFE_MIN + math.floor(rng:f() * LIFE_SPAN))
end

function Fire.ensure(self: AsciiFire, w: number, h: number)
	if w ~= self.w or h ~= self.h then
		self.w = w
		self.h = h
		self.cells = table.create(w * h, 0)
		self.rank = table.create(w, 0)
		self.target = table.create(w, 0)
		self.level = table.create(w, 0)
		self.rate = table.create(w, 0)
		self.life = table.create(w, 0)
		for x = 0, w - 1 do
			reroll(self, x)
			self.life[x + 1] = u16(math.floor(self.rng:f() * (LIFE_MIN + LIFE_SPAN)))
		end
	end
end

local function baseDip(self: AsciiFire, x: number, span: number): number
	local a = math.sin(x * 0.3 + self.t * 0.22)
	local b = math.sin(x * 0.11 - self.t * 0.15)
	return math.floor((((a + b) * 0.5 + 1) * 0.5) * span)
end

function Fire.step(self: AsciiFire)
	local w, h = self.w, self.h
	if w == 0 or h < 2 then
		return
	end
	local peak, baseSeed = M.params(self.strength)
	local seedPct = if peak == 0 then 0 else math.min(100, baseSeed + self.coverageBoost)
	local cells = self.cells
	if peak > 0 and peak < self.peak then
		local k = peak / self.peak
		for i = 1, #cells do
			cells[i] = u8(round(cells[i] * k))
		end
	end
	self.peak = math.max(1, peak)
	if peak == 0 then
		for i = 1, #cells do
			cells[i] = 0
		end
		return
	end
	local bottom = (h - 1) * w
	local span = peak * 0.18
	local rng = self.rng
	for x = 0, w - 1 do
		if self.life[x + 1] == 0 then
			reroll(self, x)
		else
			self.life[x + 1] -= 1
		end
		local isLit = self.rank[x + 1] * 100 < seedPct
		local goal = if isLit then self.target[x + 1] else 0
		local lv = self.level[x + 1]
		local st = self.rate[x + 1]
		self.level[x + 1] = f32(if lv < goal then math.min(goal, lv + st) else math.max(goal, lv - st))
		if self.level[x + 1] < LEVEL_OUT then
			cells[bottom + x + 1] = 0
		else
			local v = math.max(peak - baseDip(self, x, span) - (rng:int() % 3), math.floor(peak / 2))
			cells[bottom + x + 1] = u8(math.max(1, round(v * self.level[x + 1])))
		end
	end
	local isTall = h > BODY_ROWS + 1
	local headroom = if isTall then 1 else math.max(0, h - BODY_ROWS)
	local stretch = if isTall then math.min(1, (BODY_ROWS / (h - 1)) * 1.8) else 1
	for x = 0, w - 1 do
		for y = 1, h - 1 do
			local src = y * w + x
			local p = cells[src + 1]
			if p == 0 then
				cells[src - w + 1] = 0
			else
				local extra = if y - 1 < headroom then HEADROOM_COOL_MIN + (rng:int() % HEADROOM_COOL) else 0
				local roll = rng:int() % 11
				local cool = (if isTall then round(roll * stretch) else roll) + extra
				local nx = x + (1 - (rng:int() % 3))
				if nx >= 0 and nx < w then
					cells[(y - 1) * w + nx + 1] = u8(math.max(0, p - cool))
				end
			end
		end
	end
	self.t += 1
end

return M
