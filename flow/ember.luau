--!strict
-- Port of the fire scene of Flow (`Ember` in hooks/styles.ts): the automaton
-- of fire.ts for its shape and flicker, colored half its 256-color ramp, half
-- the truecolor black-body, with sparks breaking off and cooling into smoke;
-- banked to glowing coals while the agent waits on you.

local cellsM = require("./cells")
local pixels = require("./pixels")
local waiting = require("./waiting")
local fireM = require("./fire")
local js = require("./js")

local Cells, Rng = cellsM.Cells, cellsM.Rng
local mix, hash1, lowerBlock, BRAILLE = pixels.mix, pixels.hash1, pixels.lowerBlock, pixels.BRAILLE
local f32, round = js.f32, js.round
local colorFor, glyphFor, heatColor, smokeColor = fireM.colorFor, fireM.glyphFor, fireM.heatColor, fireM.smokeColor
local breath, easeWait, waitTone = waiting.breath, waiting.easeWait, waiting.waitTone

local SMOKE_AT = 0.38
local FAINTEST = 0.1
local COALS = { 0x3a0a04, 0x781806, 0xb8320c, 0xe85a18, 0xff8c2a, 0xffbe58 }

type Spark = { x: number, y: number, vy: number, heat: number, cool: number, phase: number }

local Ember = {}
Ember.__index = Ember

local M = {}

function M.make(seed: number?): any
	local sd = seed or (os.time() * 1000)
	return setmetatable({
		strength = 8,
		coverageBoost = 0,
		tint = "normal",
		night = false,
		waiting = false,
		kWait = 0,
		core = fireM.new(seed),
		rng = Rng.new(js.bxor(sd, 0x27d4eb2f)),
		soft = {},
		sparks = {} :: { Spark },
		out = Cells.new(0, 0),
		bits = {},
		spark = {},
		smoke = {},
		columns = 0,
		rows = 0,
		t = 0,
	}, Ember)
end

function Ember.ensure(self: any, columns: number, rows: number)
	self.core:ensure(columns, rows)
	if columns == self.columns and rows == self.rows then
		return
	end
	self.columns = columns
	self.rows = rows
	local n = columns * rows
	self.soft = table.create(n, 0)
	self.out = Cells.new(columns, rows)
	self.bits = table.create(n, 0)
	self.spark = table.create(n, 0)
	self.smoke = table.create(n, 0)
	self.sparks = {}
end

function Ember.step(self: any)
	local w, h = self.columns, self.rows
	if w == 0 or h == 0 then
		return
	end
	local core = self.core
	core.strength = self.strength
	core.coverageBoost = self.coverageBoost
	core:step()
	self.t += 1
	self.kWait = easeWait(self.kWait, self.waiting)
	local cells = core.cells
	local peak = math.max(1, core.peak)
	local soft = self.soft
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local sum, wt = 0, 0
			for dx = -2, 2 do
				local nx = x + dx
				if nx >= 0 and nx < w then
					local k = if dx == 0 then 3 elseif math.abs(dx) == 1 then 2 else 1
					sum += math.min(1, cells[y * w + nx + 1] / peak) * k
					wt += k
				end
			end
			local i = y * w + x + 1
			soft[i] = f32(soft[i] * 0.45 + (sum / wt) * 0.55)
		end
	end
	local s = self.strength
	local sparks: { Spark } = self.sparks
	if s == 0 then
		table.clear(sparks)
	end
	local rng = self.rng
	if s > 0 then
		local chance = if s == 1 then 0.0008 else 0.0022 * s
		for x = 0, w - 1 do
			local tip = -1
			for y = 0, h - 1 do
				if cells[y * w + x + 1] / peak > 0.3 then
					tip = y
					break
				end
			end
			if not (tip < 0 or rng:f() >= chance) then
				local heat = if s == 1 then SMOKE_AT else 0.72 + 0.25 * rng:f()
				local px = x * 2 + rng:f() * 2
				local vy = 0.2 + 0.18 * rng:f()
				local cool = 0.016 + 0.012 * rng:f()
				local phase = rng:f() * 6.283
				table.insert(sparks, { x = px, y = tip * 4, vy = vy, heat = heat, cool = cool, phase = phase })
			end
		end
	end
	local live = 0
	for _, p in sparks do
		local isSmoke = p.heat < SMOKE_AT
		if isSmoke then
			p.vy = math.max(0.05, p.vy * 0.985)
		end
		p.y -= p.vy
		p.x += math.sin(p.y * 0.5 + self.t * 0.15 + p.phase) * (if isSmoke then 0.3 else 0.14)
		p.heat -= if isSmoke then p.cool * 0.6 else p.cool
		if p.heat > 0.04 and p.y >= 0 and p.x >= 0 and p.x < w * 2 then
			live += 1
			sparks[live] = p
		end
	end
	for i = #sparks, live + 1, -1 do
		sparks[i] = nil
	end
end

local function drawCoals(self: any, out: cellsM.Cells)
	local w, h = self.columns, self.rows
	local b = breath(self.t)
	local core = self.core
	local peak = math.max(1, core.peak)
	local tall = h > 8
	for x = 0, w - 1 do
		if hash1(x * 31 + 7) < self.kWait then
			local i = (h - 1) * w + x
			if core.cells[i + 1] / peak < 0.6 then
				local own = 0.45 + 0.4 * hash1(x * 131 + 3) + 0.15 * hash1(x * 977 + self.t // 8)
				local heat = own * (0.4 + 0.6 * b)
				local v = round(math.min(1, heat) * 20) / 20 * (#COALS - 1.001)
				local lo = math.floor(v)
				local fg = mix(COALS[lo + 1], COALS[lo + 2], v - lo)
				out:set(i, if tall then 0x2588 else lowerBlock(4 + math.floor(hash1(x * 17 + 1) * 5)), fg)
				local j = i - w
				if tall and hash1(x * 53 + 11) < 0.7 and core.cells[j + 1] / peak < 0.45 then
					out:set(j, lowerBlock(1 + math.floor(hash1(x * 59 + 5) * 4)), mix(COALS[1], fg, 0.75))
				end
			end
		end
	end
end

function Ember.grid(self: any): cellsM.Cells
	local w, h = self.columns, self.rows
	local out = self.out
	local core = self.core
	local cells = core.cells
	local peak = math.max(1, core.peak)
	local s = self.strength
	local tint = self.tint
	local ramp = if self.kWait > 0.5 then math.max(s, 5) else s
	local bits, spark, smoke = self.bits, self.spark, self.smoke
	local n = w * h
	for i = 1, n do
		bits[i] = 0
		spark[i] = 0
		smoke[i] = 0
	end
	for _, p in self.sparks :: { Spark } do
		local px = math.floor(p.x)
		local py = math.floor(p.y)
		local c = (py // 4) * w + (px // 2)
		if not (c < 0 or c >= n) then
			bits[c + 1] = bit32.bor(bits[c + 1], BRAILLE[px % 2 + 1][py % 4 + 1])
			if p.heat >= SMOKE_AT then
				spark[c + 1] = f32(math.max(spark[c + 1], p.heat))
			else
				smoke[c + 1] = f32(math.max(smoke[c + 1], p.heat / SMOKE_AT))
			end
		end
	end
	for i = 0, n - 1 do
		local r = cells[i + 1] / peak
		if r >= FAINTEST then
			local smooth = math.min(1, (r + self.soft[i + 1]) * 0.55)
			local fg = mix(colorFor(ramp, r, tint), heatColor(s, smooth, tint), 0.5)
			out:set(i, glyphFor(r), fg)
		elseif bits[i + 1] ~= 0 then
			local fg = if spark[i + 1] > 0
				then (if tint == "smoke" then smokeColor(1) else heatColor(s, spark[i + 1], tint))
				else smokeColor(smoke[i + 1])
			out:set(i, 0x2800 + bits[i + 1], fg)
		else
			out:blank(i)
		end
	end
	if self.kWait > 0 and s > 0 then
		drawCoals(self, out)
	end
	waitTone(out, self.kWait, self.t, 0)
	return out
end

return M
