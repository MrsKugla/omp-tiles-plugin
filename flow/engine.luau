--!strict
-- Port of Flow's hooks/engine.ts (MIT, Rob Macrae).

local cells = require("./cells")
local pixels = require("./pixels")
local sound = require("./sound")
local waiting = require("./waiting")
local js = require("./js")
local Cells, Rng, DEFAULT_COLOR, isTall = cells.Cells, cells.Rng, cells.DEFAULT_COLOR, cells.isTall
local BRAILLE, clamp01, dist, mix, QUAD = pixels.BRAILLE, pixels.clamp01, pixels.dist, pixels.mix, pixels.QUAD
local hear = sound.hear
local breath, easeWait, waitTone = waiting.breath, waiting.easeWait, waiting.waitTone

local function fill(a: {number}, value: number)
	for i = 1, #a do a[i] = value end
end

local SPEED = { 0, 0, 0.035, 0.07, 0.11, 0.15, 0.2, 0.27, 0.36, 0.47, 0.6 }

local MAX_SPEED = SPEED[10 + 1]

local SPOKES = 6

local SHAFT_RATIO = 1.6

local PITCH = 0.36

local C = { brass = 0xc8a24a, brassHi = 0xe8c66a, brassDk = 0x8f7230, copper = 0xb8733a, copperDk = 0x8a5228, iron = 0x5a5f66, ironLt = 0x8a9199, ironDk = 0x3a3e44, steel = 0xc6ced6, cavity = 0x1d1f23, face = 0xe6dcc0, needle = 0x2b211a, needleHot = 0xc0301c, lampOn = 0xffb43a, lampLow = 0x6a4818, lampBlue = 0x8cc4ff, blue = 0x3c8cff, blueOff = 0x2a3440, spark = 0xffb040, leather = 0x9a6236, leatherHi = 0xc48a52, wood = 0x8c6236, brick = 0x8a3a28, brickDk = 0x6a2c20, stone = 0xa89878, stoneDk = 0x6e6450, wallBrick = 0x3c2520, wallMortar = 0x221714 }

local FIRE = { 0x2a0805, 0x4a0d08, 0x7a160c, 0xb02a12, 0xd8501a, 0xf08a24, 0xffc246, 0xffe9a8 }

local BLUE_FIRE = { 0x0c1640, 0x13286a, 0x1c3c9a, 0x2a58c8, 0x3c7cf0, 0x6aa6ff, 0xa8d0ff, 0xeef6ff }

local BRAILLE_BASE = 0x2800

local BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }

local MAX_PUFFS = 200

local MAX_SPARKS = 64

local TAU = (math.pi * 2)

local TRAIN = 0

local HAMMER = 1

local STACK = 2

local BEAM = 3

local PANEL = 4

local GRIND = 5

local PIPE = 6

local BELL = 7

local WIDTH = { 0, 34, 12, 44, 26, 28, 0, 0 }

local frac = function(n) return (n - math.floor(n)) end

local function fireColor(h: any, ramp: any)
	if ramp == nil then ramp = FIRE end
	local x = (clamp01(h) * ((#ramp - 1)))
	local i = math.min((#ramp - 2), math.floor(x))
	return mix(ramp[i + 1], ramp[(i + 1) + 1], (x - i))
end

local SOLID = 0x1000000

local Engine = {}
Engine.__index = Engine

local M = {}

function M.make(seed: number?): any
	local self: any = setmetatable({}, Engine)
	self.strength = 8
	self.coverageBoost = 0
	self.sounds = {  }
	self.tint = "normal"
	self.waiting = false
	self.kWait = 0
	self.columns = 0
	self.rows = 0
	self.out = Cells.new(0, 0)
	self.t = 0
	self.quad = table.create(0, 0)
	self.bits = table.create(0, 0)
	self.bcol = table.create(0, 0)
	self.bpri = table.create(0, 0)
	self.steam = table.create(0, 0)
	self.spark = table.create(0, 0)
	self.qs = table.create(4, 0)
	self.qcols = table.create(4, 0)
	self.qcounts = table.create(4, 0)
	self.angle = 0
	self.omega = 0
	self.heat = 0.05
	self.pressure = 0
	self.lastHalf = 0
	self.sputter = 0
	self.nPuffs = 0
	self.px = table.create(MAX_PUFFS, 0)
	self.py = table.create(MAX_PUFFS, 0)
	self.pvx = table.create(MAX_PUFFS, 0)
	self.pvy = table.create(MAX_PUFFS, 0)
	self.pr = table.create(MAX_PUFFS, 0)
	self.pgrow = table.create(MAX_PUFFS, 0)
	self.pamp = table.create(MAX_PUFFS, 0)
	self.page = table.create(MAX_PUFFS, 0)
	self.plife = table.create(MAX_PUFFS, 0)
	self.nSparks = 0
	self.sx = table.create(MAX_SPARKS, 0)
	self.sy = table.create(MAX_SPARKS, 0)
	self.svx = table.create(MAX_SPARKS, 0)
	self.svy = table.create(MAX_SPARKS, 0)
	self.slife = table.create(MAX_SPARKS, 0)
	self.gears = {  }
	self.pulleys = {  }
	self.belts = {  }
	self.modules = {  }
	self.gauges = {  }
	self.emitters = {  }
	self.hangers = {  }
	self.shafts = {  }
	self.shaftY = 0
	self.wall = table.create(0, 0)
	self.riserX = (-1)
	self.riserY0 = 0
	self.riserY1 = 0
	self.shaft2Y = (-1)
	self.vertical = false
	self.ey = 0
	self.cx = 0
	self.cy = 0
	self.ux = 1
	self.uy = 0
	self.vx = 0
	self.vy = (-1)
	self.radius = 9.6
	self.crank = 5.2
	self.rodLen = 21
	self.cyl0 = 0
	self.cyl1 = 0
	self.pistonOffset = 0
	self.halfT = 4
	self.chimX = 0
	self.chimY = 0
	self.valveX = 0
	self.valveY = 0
	self.govX = 0
	self.govY = 0
	self.govArm = 5.5
	self.govBase = 0
	self.boilerTop = 0
	self.boilerBottom = 0
	self.night = false
	self.seed = js.shr(((if seed == nil then (os.time() * 1000) else seed)), 0)
	self.rng = Rng.new(seed)
	return self
end

function Engine.ensure(self: any, columns: any, rows: any)
	if ((columns == self.columns) and (rows == self.rows)) then
		return
	end
	self.columns = columns
	self.rows = rows
	self.out = Cells.new(columns, rows)
	self.quad = table.create((((columns * 2) * rows) * 2), 0)
	self.bits = table.create((columns * rows), 0)
	self.bcol = table.create((columns * rows), 0)
	self.bpri = table.create((columns * rows), 0)
	self.spark = table.create((columns * rows), 0)
	self.steam = table.create((((columns * 2) * rows) * 4), 0)
	self.nPuffs = 0
	self.nSparks = 0
	self:layout()
end

function Engine.addPulley(self: any, x: any, y: any, r: any, s: any, color: any, spokes: any)
	if spokes == nil then spokes = 3 end
	table.insert(self.pulleys, { x = x, y = y, r = r, phase = 0, s = s, color = color, spokes = spokes })
end

function Engine.addBelt(self: any, x1: any, y1: any, r1: any, s1: any, x2: any, y2: any, r2: any, crossed: any)
	if crossed == nil then crossed = false end
	table.insert(self.belts, { x1 = x1, y1 = y1, r1 = r1, x2 = x2, y2 = y2, r2 = r2, v = (s1 * r1), crossed = crossed })
	return ((((((if crossed then (-1) else 1)) * s1) * r1)) / r2)
end

function Engine.addGear(self: any, x: any, y: any, n: any, s: any, phase: any, color: any)
	local g = { x = x, y = y, n = n, r = (n * PITCH), phase = phase, s = s, color = color }
	table.insert(self.gears, g)
	return g
end

function Engine.meshGear(self: any, a: any, n: any, y: any, side: any, color: any)
	local r = (n * PITCH)
	local dist = ((a.r + r) + 0.5)
	local dy = math.max(((-dist) * 0.85), math.min((dist * 0.85), (y - a.y)))
	local dx = (side * math.sqrt(((dist * dist) - (dy * dy))))
	return self:meshAt(a, n, dx, dy, color)
end

function Engine.meshAt(self: any, a: any, n: any, dx: any, dy: any, color: any)
	local beta = math.atan2(dy, dx)
	local phase = ((beta + math.pi) - (((math.pi - (a.n * ((beta - a.phase))))) / n))
	return self:addGear((a.x + dx), (a.y + dy), n, ((((-a.s) * a.n)) / n), phase, color)
end

function Engine.layout(self: any)
	local wd = (self.columns * 2)
	local hd = (self.rows * 4)
	self.vertical = isTall(self.columns, self.rows)
	self.gears = {  }
	self.pulleys = {  }
	self.belts = {  }
	self.modules = {  }
	self.gauges = {  }
	self.emitters = {  }
	self.hangers = {  }
	self.shafts = {  }
	self.wall = table.create((self.columns * self.rows), 0)
	self.riserX = (-1)
	self.shaft2Y = (-1)
	if (not self.vertical) then
		local ex = (if (wd >= 100) then 2 else 0)
		local ey = (hd - 20)
		self.ey = ey
		self.radius = 9.6
		self.cx = (ex + 20)
		self.cy = (ey + 10)
		self.ux = 1
		self.uy = 0
		self.vx = 0
		self.vy = (-1)
		self.crank = 5.2
		self.rodLen = 20.5
		self.halfT = 4
		self.chimX = (ex + 80)
		self.chimY = (ey + 2)
		self.valveX = (ex + 73.5)
		self.valveY = (ey + 4)
		self.govX = (ex + 41)
		self.govY = (ey + 0.5)
		self.govArm = 5.2
		self.govBase = (self.cy - 2.5)
	else
		local mid = math.floor((wd / 2))
		self.ey = 0
		self.radius = math.max(8, math.min(12, (mid - 4)))
		self.cx = mid
		self.cy = ((hd - 3) - self.radius)
		self.ux = 0
		self.uy = (-1)
		self.vx = 1
		self.vy = 0
		self.crank = (self.radius * 0.52)
		self.rodLen = (self.crank * 2.9)
		self.halfT = 4.5
	end
	local near = (self.rodLen - self.crank)
	self.cyl0 = ((self.rodLen + self.crank) + ((if self.vertical then 5 else 4.5)))
	self.pistonOffset = ((self.cyl0 + 3) - near)
	self.cyl1 = (((self.cyl0 + 3) + (self.crank * 2)) + 3)
	table.insert(self.emitters, { x = 0, y = 0, kind = 0 })
	if self.vertical then
		self:layoutSpine(wd)
	else
		self:layoutBand(wd)
	end
	self.emitters[0 + 1].x = self.chimX
	self.emitters[0 + 1].y = self.chimY
end

function Engine.layoutSpine(self: any, wd: any)
	local hd = (self.rows * 4)
	local cylTop = (self.cy - self.cyl1)
	self.boilerBottom = math.floor((((cylTop - 7)) / 2))
	self.boilerTop = (self.boilerBottom - 7)
	self.chimX = (self.cx + 3)
	self.chimY = (((self.boilerTop - 3)) * 2)
	self.valveX = (self.cx - 5.5)
	self.valveY = ((self.boilerTop * 2) - 1)
	local avail = ((self.cx - self.halfT) - 1.5)
	self.govX = math.max(2, (avail / 2))
	self.govArm = math.max(2.5, math.min(5.2, ((avail / 2) - 0.3)))
	self.govY = (cylTop + 2.5)
	self.govBase = ((self.govY + self.govArm) + 2)
	local wallRow = math.max(0, math.floor((((self.boilerTop * 2)) / 4)))
	for i = (wallRow * self.columns), (#self.wall) - 1 do
		self.wall[i + 1] = js.u8(1)
	end
	self.shaftY = 2
	table.insert(self.shafts, { y = 2, x0 = 0, x1 = wd, s = SHAFT_RATIO })
	table.insert(self.hangers, math.floor((wd * 0.3)))
	table.insert(self.hangers, math.floor((wd * 0.7)))
	local s2y = ((self.boilerBottom * 2) + 3)
	self.shaft2Y = s2y
	local rX = (wd - 3.5)
	self:addPulley(rX, 2.5, 2, SHAFT_RATIO, C.ironLt)
	local s2 = self:addBelt(rX, 2.5, 2, SHAFT_RATIO, rX, (s2y + 0.5), 2.6)
	self:addPulley(rX, (s2y + 0.5), 2.6, s2, C.brass)
	table.insert(self.shafts, { y = s2y, x0 = 0, x1 = wd, s = s2 })
	local camX = math.max(3.5, math.min(6, (self.cx * 0.4)))
	local camY = ((self.boilerTop * 2) - 6)
	if ((camY - 15) > 4) then
		self:addPulley((camX + 3.5), 2.5, 2, SHAFT_RATIO, C.ironLt)
		local sc = self:addBelt((camX + 3.5), 2.5, 2, SHAFT_RATIO, camX, camY, 1.1)
		table.insert(self.modules, { kind = BELL, x = camX, y = camY, w = 0, s = sc, phase = 0, prev = 0 })
	end
	local gc = (self.columns - 5)
	local gr = (math.floor((((self.boilerTop * 2)) / 4)) - 2)
	if (((gc * 2) >= (self.chimX + 3)) and (gr >= 2)) then
		local two = ((gr - 2) >= 1)
		self:gaugeAt(gc, gr, 0.1)
		if two then
			self:gaugeAt(gc, (gr - 2), (-0.15))
		end
		self.riserX = ((gc * 2) + 1)
		self.riserY0 = ((((if two then (gr - 2) else gr)) * 4) + 2)
		self.riserY1 = (self.boilerTop * 2)
	end
	self:gaugeAt((math.floor((self.cx / 2)) - 2), math.floor(((((self.boilerTop * 2) + 5)) / 4)), 0)
	local fits = function(x, y, r, parent) return self:gearFits(x, y, r, parent, wd, hd) end
	local left = self:startGear(self.govX, self.govBase, (s2 * 1.25), 0.4, C.brass, fits, false)
	if left then
		self.govBase = left.y
		self:packChain(left, fits, 0)
	end
	local right = self:startGear((wd - 4), (s2y + 5), 0, 1.3, C.copper, fits, true)
	if right then
		right.s = self:addBelt(rX, (s2y + 0.5), 1.5, s2, right.x, right.y, 1.4)
		self:addPulley(rX, (s2y + 0.5), 1.5, s2, C.brassHi, 0)
		self:addPulley(right.x, right.y, 1.4, right.s, C.brassHi, 0)
		self:packChain(right, fits, 1)
	end
	local wn = math.ceil((((self.radius + 0.4)) / PITCH))
	local wheel = self:addGear(self.cx, self.cy, wn, 1, (math.pi / 2), C.ironLt)
	wheel.rim = true
	local angles = { (-0.6), (-2.54), (-0.25), (-2.89), 0.15, (-3.29), 0.5, (-3.64) }
	for k = 0, (#angles) - 1 do
		for n = 10, 6, -1 do
			local r = (n * PITCH)
			local dist = ((wheel.r + r) + 0.5)
			local dx = (math.cos(angles[k + 1]) * dist)
			local dy = (math.sin(angles[k + 1]) * dist)
			if (not self:gearFits((self.cx + dx), (self.cy + dy), r, wheel, wd, hd, true)) then
				continue
			end
			local p = self:meshAt(wheel, n, dx, dy, (if (js.band(k, 1) ~= 0) then C.brass else C.copper))
			self:packChain(p, fits, (2 + k))
			break
		end
	end
	local colors = { C.brass, C.copper, C.ironLt, C.brassHi }
	for pass = 0, (4) - 1 do
		local count = #self.gears
		local added = 0
		for i = 0, (count) - 1 do
			local o = self.gears[i + 1]
			for k = 0, (16) - 1 do
				local ang = ((((k / 16)) * TAU) + (pass * 0.2))
				for n = 10, 6, -1 do
					local r = (n * PITCH)
					local dist = ((o.r + r) + 0.5)
					local dx = (math.cos(ang) * dist)
					local dy = (math.sin(ang) * dist)
					if (not self:gearFits((o.x + dx), (o.y + dy), r, o, wd, hd, (o == wheel))) then
						continue
					end
					self:meshAt(o, n, dx, dy, colors[js.band(((i + k)), 3) + 1])
					added = added + 1
					break
				end
			end
		end
		if (not (added ~= 0)) then
			break
		end
	end
end

function Engine.gearFits(self: any, x: any, y: any, r: any, parent: any, wd: any, hd: any, onWheel: any)
	if onWheel == nil then onWheel = false end
	local tip = (r + 1)
	if ((((x - tip) < 0) or ((x + tip) > wd)) or ((y + tip) > (hd - 2.5))) then
		return false
	end
	if ((y - tip) < (self.shaft2Y + 2)) then
		return false
	end
	local wx = (x - self.cx)
	local wy = (y - self.cy)
	if ((not onWheel) and (math.sqrt(((wx * wx) + (wy * wy))) < ((self.radius + tip) + 2.2))) then
		return false
	end
	local cylTop = (self.cy - self.cyl1)
	local cylBottom = (self.cy - self.cyl0)
	if (((y + tip) > (cylTop - 1)) and ((y - tip) < ((self.cy - self.radius) + 3))) then
		local core = (if ((y - tip) < (cylBottom + 1)) then ((if (x > self.cx) then (self.halfT + 3.6) else (self.halfT + 1.4))) else 6.2)
		if (math.abs(wx) < (core + tip)) then
			return false
		end
	end
	if (((x < self.cx) and ((x - tip) < ((self.govX + self.govArm) + 1))) and ((y - tip) < ((self.govY + self.govArm) + 1.5))) then
		return false
	end
	for i = 0, (#self.gears) - 1 do
		local o = self.gears[i + 1]
		if (o == parent) then
			continue
		end
		local dx = (o.x - x)
		local dy = (o.y - y)
		if (math.sqrt(((dx * dx) + (dy * dy))) < ((o.r + r) + 2.4)) then
			return false
		end
	end
	return true
end

function Engine.startGear(self: any, x: any, y: any, s: any, phase: any, color: any, fits: any, hugRight: any)
	local wd = (self.columns * 2)
	for n = 12, 6, -1 do
		local r = (n * PITCH)
		local gx = (if hugRight then ((wd - r) - 1.2) else math.max((r + 1.1), x))
		for gy = (y + r), ((self.rows * 4)) - 1 do
			if fits(gx, gy, r, nil) then
				return self:addGear(gx, gy, n, s, phase, color)
			end
		end
	end
	return nil
end

function Engine.packChain(self: any, g: any, fits: any, seed: any)
	local sizes = { 9, 12, 7, 10, 6, 11, 8, 13 }
	local steeps = { 0.75, 0.95, 0.5, 0.3, 0.1, (-0.2) }
	local colors = { C.copper, C.brass, C.ironLt, C.brassHi }
	local side = (if (seed ~= 0) then (-1) else 1)
	for guard = 0, (24) - 1 do
		local placed = nil
		for k = 0, (#sizes) - 1 do
			if not (not placed) then break end
			local n = sizes[js.mod(((((seed * 3) + guard) + k)), #sizes) + 1]
			local r = (n * PITCH)
			local dist = ((g.r + r) + 0.5)
			for a = 0, (#steeps) - 1 do
				if not (not placed) then break end
				for sd = 0, (2) - 1 do
					if not (not placed) then break end
					local sgn = (if (sd == 0) then side else (-side))
					local dy = (steeps[a + 1] * dist)
					local dx = (sgn * math.sqrt(((dist * dist) - (dy * dy))))
					if fits((g.x + dx), (g.y + dy), r, g) then
						placed = self:meshAt(g, n, dx, dy, colors[js.mod(((guard + seed)), #colors) + 1])
						side = (-sgn)
					end
				end
			end
		end
		if (not placed) then
			return
		end
		g = placed
	end
end

function Engine.gaugeAt(self: any, col: any, row: any, bias: any)
	table.insert(self.gauges, { col = col, row = row, wc = 2, bias = bias })
end

function Engine.layoutBand(self: any, wd: any)
	local ey = self.ey
	local ex = (self.cx - 20)
	local lay = Rng.new(js.bxor(self.seed, ((self.columns * 7919))))
	self.shaftY = (ey + 2)
	self.boilerTop = (math.floor((ey / 2)) + 3)
	self:gaugeAt((math.floor((self.chimX / 2)) - 4), (math.floor((ey / 4)) + 2), 0)
	local x = (ex + 88)
	table.insert(self.shafts, { y = self.shaftY, x0 = (x - 2), x1 = wd, s = SHAFT_RATIO })
	local pool = { HAMMER, STACK, BEAM, PANEL, GRIND }
	local pi = #pool
	local i = 0
	while (x < wd) do
		local left = (wd - x)
		local kind = nil
		if (js.mod(i, 2) == 0) then
			kind = TRAIN
		else
			if (pi >= #pool) then
				for k = (#pool - 1), (0) + 1, -1 do
					local j = math.floor((lay:f() * ((k + 1))))
					local tmp = pool[k + 1]
					pool[k + 1] = pool[j + 1]
					pool[j + 1] = tmp
				end
				pi = 0
			end
			local old0 = pi
			pi = pi + 1
			kind = pool[old0 + 1]
		end
		i = i + 1
		local w = (if (kind == TRAIN) then math.min(left, (26 + math.floor((lay:f() * 30)))) else WIDTH[kind + 1])
		if ((w > left) or ((left - w) < 10)) then
			kind = (if (left >= 20) then TRAIN else PIPE)
			w = left
		end
		if (kind == TRAIN) then
			w = self:layoutTrain(x, w, lay)
		else
			self:layoutModule(kind, x, w)
		end
		table.insert(self.hangers, math.floor((x + 1)))
		x = (x + w)
	end
end

function Engine.layoutTrain(self: any, x: any, w: any, lay: any)
	local ey = self.ey
	local colors = { C.brass, C.copper, C.ironLt, C.brassHi }
	local ci = math.floor((lay:f() * 4))
	local n0 = (12 + math.floor((lay:f() * 4)))
	local r0 = (n0 * PITCH)
	local gx = ((x + r0) + 1.6)
	local gy = (ey + 11.5)
	self:addPulley(gx, (self.shaftY + 0.5), 2, SHAFT_RATIO, C.ironLt)
	local s = self:addBelt(gx, (self.shaftY + 0.5), 2, SHAFT_RATIO, gx, gy, 2.2, (lay:f() < 0.3))
	local old1 = ci
	ci = ci + 1
	local g = self:addGear(gx, gy, n0, s, (lay:f() * TAU), colors[js.mod(old1, 4) + 1])
	self:addPulley(gx, gy, 2.2, s, C.brassHi, 0)
	local sizes = { 8, 17, 9, 13, 7, 15, 10, 11, 16, 8 }
	local si = math.floor((lay:f() * #sizes))
	local right = ((gx + r0) + 1.2)
	for guard = 0, (20) - 1 do
		local old2 = si
		si = si + 1
		local n = sizes[js.mod(old2, #sizes) + 1]
		local r = (n * PITCH)
		local lo = (((ey + 4.6) + r) + 1.1)
		local hi = (((ey + 18.4) - r) - 1.1)
		local y = (if (lo >= hi) then (ey + 11.5) else (lo + (lay:f() * ((hi - lo)))))
		local dist = ((g.r + r) + 0.5)
		local dy = math.max(((-dist) * 0.85), math.min((dist * 0.85), (y - g.y)))
		local nx = (g.x + math.sqrt(((dist * dist) - (dy * dy))))
		if (((nx + r) + 1.2) > (x + w)) then
			break
		end
		local old3 = ci
		ci = ci + 1
		g = self:meshGear(g, n, y, 1, colors[js.mod(old3, 4) + 1])
		right = ((g.x + g.r) + 1.2)
	end
	return math.min(w, math.max(14, math.ceil(((right - x) + 2))))
end

function Engine.layoutModule(self: any, kind: any, x: any, w: any)
	local ey = self.ey
	local sy = (self.shaftY + 0.5)
	local m = { kind = kind, x = x, y = 0, w = w, s = 0, phase = 0, prev = 0 }
	if (kind == HAMMER) then
		self:addPulley((x + 16), sy, 2, SHAFT_RATIO, C.ironLt)
		m.s = self:addBelt((x + 16), sy, 2, SHAFT_RATIO, (x + 16), (ey + 13.1), 1.1)
	else
		if (kind == BEAM) then
			self:addPulley((x + 6), sy, 2, SHAFT_RATIO, C.ironLt)
			m.s = self:addBelt((x + 6), sy, 2, SHAFT_RATIO, (x + 6), (ey + 13), 1.2)
			self:addPulley((x + 6), (ey + 13), 3.6, m.s, C.ironLt, 4)
			self:addPulley((x + 6), (ey + 13), 1.2, m.s, C.brass, 0)
		else
			if (kind == GRIND) then
				self:addPulley((x + 4), sy, 2, SHAFT_RATIO, C.ironLt)
				m.s = self:addBelt((x + 4), sy, 2, SHAFT_RATIO, (x + 13), (ey + 11), 2, true)
			else
				if (kind == STACK) then
					table.insert(self.emitters, { x = (x + 6), y = (ey + 1.5), kind = 1 })
				else
					if (kind == PANEL) then
						self:gaugeAt(math.floor((((x + 5)) / 2)), (math.floor((ey / 4)) + 1), (-0.12))
						if (w >= 20) then
							self:gaugeAt(math.floor((((x + 15)) / 2)), (math.floor((ey / 4)) + 2), 0.08)
						end
						table.insert(self.emitters, { x = (x + 21), y = (ey + 9), kind = 2 })
					end
				end
			end
		end
	end
	table.insert(self.modules, m)
end

function Engine.step(self: any)
	self.t = self.t + 1
	local level = math.max(0, math.min(10, js.round(self.strength)))
	local smoke = (self.tint == "smoke")
	local was = breath((self.t - 1))
	self.kWait = easeWait(self.kWait, self.waiting)
	if (smoke and (self.rng:f() < 0.04)) then
		self.sputter = (6 + (self.rng:f() * 10))
	end
	if (self.sputter > 0) then
		self.sputter = self.sputter - 1
	end
	local target = ((SPEED[level + 1] * ((if (self.sputter > 0) then 0.45 else 1))) * ((1 - self.kWait)))
	self.omega = (self.omega + (((target - self.omega)) * 0.045))
	if (math.abs((target - self.omega)) < 0.0005) then
		self.omega = target
	end
	self.angle = (self.angle + self.omega)
	if (self.angle > (TAU * 1000)) then
		self.angle = (self.angle - (TAU * 1000))
	end
	local heatTarget = (if (level <= 0) then 0 else (0.1 + (((level - 1)) * 0.1)))
	self.heat = (self.heat + ((((heatTarget * ((if smoke then 0.75 else 1))) - self.heat)) * 0.03))
	local pTarget = (if (level <= 0) then 0 else math.min(0.97, ((0.06 + (((level - 1)) * 0.1)) + (self.coverageBoost * 0.001))))
	self.pressure = (self.pressure + (((pTarget - self.pressure)) * 0.025))
	local half = math.floor((self.angle / math.pi))
	if (half ~= self.lastHalf) then
		self.lastHalf = half
		if (((self.omega > 0.012) and (level > 0)) and (not ((smoke and (self.rng:f() < 0.35))))) then
			self:chuff(level)
		end
	end
	local extra = (((math.max(0, (level - 5)) ^ 1.4) * 0.1) + (self.coverageBoost * 0.004))
	if ((level >= 2) and (self.rng:f() < extra)) then
		self:puff(self.chimX, self.chimY, (0.35 + (self.rng:f() * 0.25)), 1.2, level)
	end
	if ((smoke and (level > 0)) and (self.rng:f() < 0.3)) then
		self:puff(self.chimX, self.chimY, (0.75 + (self.rng:f() * 0.3)), (1.5 + (level * 0.08)), math.max(2, level))
	end
	if (((level > 0) and (level <= 3)) and (self.rng:f() < ((if (level == 1) then 0.06 else 0.03)))) then
		self:wisp(self.valveX, self.valveY)
	end
	if ((((level > 0) and (self.kWait > 0.5)) and (was < 0.6)) and (breath(self.t) >= 0.6)) then
		for k = 0, (3) - 1 do
			self:wisp(self.valveX, self.valveY)
		end
	end
	if (((level >= 7) and (self.rng:f() < (((level - 6)) * 0.15))) and (not smoke)) then
		self:chimneySpark(level)
	end
	for i = 1, (#self.emitters) - 1 do
		local e = self.emitters[i + 1]
		if (((e.kind == 1) and (level >= 2)) and (self.rng:f() < ((0.05 + (level * 0.035)) + (self.coverageBoost * 0.002)))) then
			self:puff(e.x, e.y, (0.35 + (level * 0.04)), (1 + (level * 0.1)), level)
		else
			if (((e.kind == 2) and (level >= 6)) and (self.rng:f() < (((level - 5)) * 0.02))) then
				self:wisp(e.x, e.y)
			end
		end
	end
	self:machineEvents(level, smoke)
	self:movePuffs()
	self:moveSparks()
end

function Engine.machineEvents(self: any, level: any, smoke: any)
	for i = 0, (#self.modules) - 1 do
		local m = self.modules[i + 1]
		if (m.kind == HAMMER) then
			local lift = self:camLift(m)
			if (lift < (m.prev - 0.9)) then
				hear(self.sounds, { kind = "clank", v = (level / 10) })
			end
			if ((lift < (m.prev - 0.9)) and (level >= 4)) then
				local n = (if smoke then 1 else (1 + math.floor((level / 3))))
				for k = 0, (n) - 1 do
					self:emitSpark((m.x + 28), (self.ey + 15.5), (((self.rng:f() - 0.5)) * 1.6), (-((0.3 + (self.rng:f() * 0.6)))), (4 + (self.rng:f() * 5)))
				end
			end
			m.prev = lift
		else
			if (((m.kind == GRIND) and (level >= 4)) and (not smoke)) then
				if (self.rng:f() < (((level - 3)) * 0.12)) then
					self:emitSpark((m.x + 18.5), (self.ey + 10.5), (0.5 + (self.rng:f() * 1.1)), ((-0.2) + (self.rng:f() * 0.6)), (3 + (self.rng:f() * 5)))
				end
			end
		end
	end
end

function Engine.camLift(self: any, m: any)
	local a = (m.phase + (m.s * self.angle))
	return (1.8 * ((1 - frac((((2 * ((((-math.pi) / 2) - a)))) / TAU)))))
end

function Engine.chuff(self: any, level: any)
	hear(self.sounds, { kind = "chuff", v = (level / 10) })
	local amp = math.min(1.25, ((0.55 + (level * 0.05)) + (self.coverageBoost * 0.004)))
	self:puff(self.chimX, self.chimY, amp, (1.6 + (level * 0.16)), level)
end

function Engine.puff(self: any, x: any, y: any, amp: any, r: any, level: any)
	if (self.nPuffs >= MAX_PUFFS) then
		return (-1)
	end
	local old4 = self.nPuffs
	self.nPuffs = self.nPuffs + 1
	local i = old4
	local rng = self.rng
	self.px[i + 1] = js.f32((x + ((rng:f() - 0.5))))
	self.py[i + 1] = js.f32(y)
	if (not self.vertical) then
		self.pvx[i + 1] = js.f32(((0.35 + (level * 0.07)) + (rng:f() * 0.15)))
		self.pvy[i + 1] = js.f32(((-0.05) - (rng:f() * 0.08)))
	else
		self.pvx[i + 1] = js.f32((((rng:f() - 0.5)) * 0.45))
		self.pvy[i + 1] = js.f32((-(((0.3 + (level * 0.05)) + (rng:f() * 0.15)))))
	end
	self.pr[i + 1] = js.f32(r)
	self.pgrow[i + 1] = js.f32(((((0.06 + (rng:f() * 0.05)) + (level * 0.01))) * ((if self.vertical then 1.4 else 1))))
	self.pamp[i + 1] = js.f32(amp)
	self.page[i + 1] = js.f32(0)
	self.plife[i + 1] = js.f32((((if self.vertical then 40 else 50)) + (rng:f() * 24)))
	return i
end

function Engine.wisp(self: any, x: any, y: any)
	local i = self:puff(x, (y - 1), 0.45, 0.7, 1)
	if (i < 0) then
		return
	end
	self.pvx[i + 1] = js.f32((if self.vertical then (((self.rng:f() - 0.5)) * 0.2) else (0.12 + (self.rng:f() * 0.1))))
	self.pvy[i + 1] = js.f32(((-0.12) - (self.rng:f() * 0.08)))
	self.pgrow[i + 1] = js.f32(0.03)
	self.plife[i + 1] = js.f32((22 + (self.rng:f() * 10)))
end

function Engine.movePuffs(self: any)
	local wd = (self.columns * 2)
	local hd = (self.rows * 4)
	local sway = (math.sin((self.t * 0.045)) * 0.1)
	do
		local i = 0
		while (i < self.nPuffs) do
			self.page[i + 1] = js.f32((self.page[i + 1] + 1))
			self.px[i + 1] = js.f32((self.px[i + 1] + (self.pvx[i + 1] + ((if self.vertical then sway else 0)))))
			self.py[i + 1] = js.f32((self.py[i + 1] + self.pvy[i + 1]))
			self.pr[i + 1] = js.f32((self.pr[i + 1] + self.pgrow[i + 1]))
			if self.vertical then
				self.pvy[i + 1] = js.f32((self.pvy[i + 1] * 0.985))
			else
				self.pvy[i + 1] = js.f32((self.pvy[i + 1] + 0.008))
				if (self.pvy[i + 1] > 0.15) then
					self.pvy[i + 1] = js.f32(0.15)
				end
				if (self.py[i + 1] < (self.ey + 1.5)) then
					self.py[i + 1] = js.f32((self.ey + 1.5))
				end
			end
			local r = self.pr[i + 1]
			local gone = (((((self.page[i + 1] >= self.plife[i + 1]) or ((self.px[i + 1] - r) > wd)) or ((self.px[i + 1] + r) < 0)) or ((self.py[i + 1] + r) < 0)) or ((self.py[i + 1] - r) > hd))
			if gone then
				self.nPuffs = self.nPuffs - 1
				local j = self.nPuffs
				self.px[i + 1] = js.f32(self.px[j + 1])
				self.py[i + 1] = js.f32(self.py[j + 1])
				self.pvx[i + 1] = js.f32(self.pvx[j + 1])
				self.pvy[i + 1] = js.f32(self.pvy[j + 1])
				self.pr[i + 1] = js.f32(self.pr[j + 1])
				self.pgrow[i + 1] = js.f32(self.pgrow[j + 1])
				self.pamp[i + 1] = js.f32(self.pamp[j + 1])
				self.page[i + 1] = js.f32(self.page[j + 1])
				self.plife[i + 1] = js.f32(self.plife[j + 1])
			else
				i = i + 1
			end
		end
	end
end

function Engine.emitSpark(self: any, x: any, y: any, vx: any, vy: any, life: any)
	if (self.nSparks >= MAX_SPARKS) then
		return
	end
	local old6 = self.nSparks
	self.nSparks = self.nSparks + 1
	local i = old6
	self.sx[i + 1] = js.f32(x)
	self.sy[i + 1] = js.f32(y)
	self.svx[i + 1] = js.f32(vx)
	self.svy[i + 1] = js.f32(vy)
	self.slife[i + 1] = js.f32(life)
end

function Engine.chimneySpark(self: any, level: any)
	local rng = self.rng
	if self.vertical then
		self:emitSpark((self.chimX + (((rng:f() - 0.5)) * 2)), self.chimY, (((rng:f() - 0.5)) * 0.9), (-((0.9 + (rng:f() * 0.8)))), (6 + (rng:f() * 10)))
	else
		self:emitSpark(self.chimX, self.chimY, ((0.5 + (rng:f() * 0.9)) + (level * 0.04)), (-((0.2 + (rng:f() * 0.5)))), (6 + (rng:f() * 10)))
	end
end

function Engine.moveSparks(self: any)
	do
		local i = 0
		while (i < self.nSparks) do
			self.sx[i + 1] = js.f32((self.sx[i + 1] + self.svx[i + 1]))
			self.sy[i + 1] = js.f32((self.sy[i + 1] + self.svy[i + 1]))
			self.svy[i + 1] = js.f32((self.svy[i + 1] + (if self.vertical then 0.04 else 0.06)))
			self.slife[i + 1] = js.f32((self.slife[i + 1] - 1))
			if (self.slife[i + 1] <= 0) then
				self.nSparks = self.nSparks - 1
				local j = self.nSparks
				self.sx[i + 1] = js.f32(self.sx[j + 1])
				self.sy[i + 1] = js.f32(self.sy[j + 1])
				self.svx[i + 1] = js.f32(self.svx[j + 1])
				self.svy[i + 1] = js.f32(self.svy[j + 1])
				self.slife[i + 1] = js.f32(self.slife[j + 1])
			else
				i = i + 1
			end
		end
	end
end

function Engine.q(self: any, qx: any, qy: any, color: any)
	local x = math.floor(qx)
	local y = math.floor(qy)
	if ((((x < 0) or (y < 0)) or (x >= (self.columns * 2))) or (y >= (self.rows * 2))) then
		return
	end
	self.quad[(((y * self.columns) * 2) + x) + 1] = js.u32(((js.band(color, 0xffffff)) + SOLID))
end

function Engine.qrect(self: any, x0: any, y0: any, x1: any, y1: any, color: any)
	for y = math.floor(y0), y1 do
		for x = math.floor(x0), x1 do
			self:q(x, y, color)
		end
	end
end

function Engine.dot(self: any, x: any, y: any, color: any, pri: any)
	local dx = math.floor(x)
	local dy = math.floor(y)
	if ((((dx < 0) or (dy < 0)) or (dx >= (self.columns * 2))) or (dy >= (self.rows * 4))) then
		return
	end
	local c = (((js.sar(dy, 2)) * self.columns) + (js.sar(dx, 1)))
	self.bits[c + 1] = js.u8(js.bor(self.bits[c + 1], BRAILLE[js.band(dx, 1) + 1][js.band(dy, 3) + 1]))
	if (pri >= self.bpri[c + 1]) then
		self.bpri[c + 1] = js.u8(pri)
		self.bcol[c + 1] = js.u32(color)
	end
end

function Engine.line(self: any, x0: any, y0: any, x1: any, y1: any, color: any, pri: any)
	local n = (math.ceil((math.max(math.abs((x1 - x0)), math.abs((y1 - y0))) * 1.5)) + 1)
	for k = 0, n do
		local f = (k / n)
		self:dot((x0 + (((x1 - x0)) * f)), (y0 + (((y1 - y0)) * f)), color, pri)
	end
end

function Engine.dither(self: any, x: any, y: any, p: any)
	return (p > (((BAYER[js.bor((js.shl((js.band(y, 3)), 2)), (js.band(x, 3))) + 1] + 0.5)) / 16))
end

function Engine.fx(self: any, s: any, t: any)
	return ((self.cx + (s * self.ux)) + (t * self.vx))
end

function Engine.fy(self: any, s: any, t: any)
	return ((self.cy + (s * self.uy)) + (t * self.vy))
end

function Engine.grid(self: any)
	local out = self.out
	local n = (self.columns * self.rows)
	local level = math.max(0, math.min(10, js.round(self.strength)))
	if ((level <= 0) or (n == 0)) then
		for i = 0, (n) - 1 do
			out:blank(i)
		end
		return out
	end
	fill(self.quad, 0)
	fill(self.bits, 0)
	fill(self.bpri, 0)
	fill(self.spark, 0)
	fill(self.steam, 0)
	self:drawSteam()
	self:drawShaft()
	for i = 0, (#self.gears) - 1 do
		self:drawGear(self.gears[i + 1])
	end
	for i = 0, (#self.pulleys) - 1 do
		self:drawPulley(self.pulleys[i + 1])
	end
	for i = 0, (#self.modules) - 1 do
		self:drawModule(self.modules[i + 1])
	end
	for i = 0, (#self.belts) - 1 do
		self:drawBelt(self.belts[i + 1])
	end
	self:drawWheel()
	self:drawLinkage()
	self:drawGovernor()
	if self.vertical then
		self:drawBoilerSpine()
	else
		self:drawBoilerBand()
	end
	self:drawBed()
	self:drawSparks()
	self:compose()
	for i = 0, (#self.gauges) - 1 do
		self:drawGauge(self.gauges[i + 1])
	end
	waitTone(out, self.kWait, self.t)
	return out
end

-- Methods from line 923 on live in engine_draw.luau; scenes.luau loads it as a separate step.
local DRAW_ENV = { Engine = Engine, BAYER = BAYER, BEAM = BEAM, BELL = BELL, BLUE_FIRE = BLUE_FIRE, BRAILLE = BRAILLE, BRAILLE_BASE = BRAILLE_BASE, C = C, DEFAULT_COLOR = DEFAULT_COLOR, GRIND = GRIND, HAMMER = HAMMER, MAX_SPEED = MAX_SPEED, PANEL = PANEL, PIPE = PIPE, QUAD = QUAD, SOLID = SOLID, SPOKES = SPOKES, STACK = STACK, TAU = TAU, clamp01 = clamp01, dist = dist, fireColor = fireColor, frac = frac, js = js, mix = mix }

M.__drawEnv = DRAW_ENV
return M
