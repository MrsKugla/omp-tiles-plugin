--!strict
-- Second half of engine.luau (split so each half compiles within Tern's per-call budget).
-- Port of Flow (MIT, Rob Macrae). `install(env)` adds these methods to the class.
return function(env: any)
local Engine = env.Engine
local BAYER = env.BAYER
local BEAM = env.BEAM
local BELL = env.BELL
local BLUE_FIRE = env.BLUE_FIRE
local BRAILLE = env.BRAILLE
local BRAILLE_BASE = env.BRAILLE_BASE
local C = env.C
local DEFAULT_COLOR = env.DEFAULT_COLOR
local GRIND = env.GRIND
local HAMMER = env.HAMMER
local MAX_SPEED = env.MAX_SPEED
local PANEL = env.PANEL
local PIPE = env.PIPE
local QUAD = env.QUAD
local SOLID = env.SOLID
local SPOKES = env.SPOKES
local STACK = env.STACK
local TAU = env.TAU
local clamp01 = env.clamp01
local dist = env.dist
local fireColor = env.fireColor
local frac = env.frac
local js = env.js
local mix = env.mix
function Engine.drawShaft(self: any)
	for i = 0, (#self.shafts) - 1 do
		local sh = self.shafts[i + 1]
		local sy = math.floor(sh.y)
		local v = math.abs(((sh.s * self.omega) * 1.2))
		local off = math.floor(((sh.s * self.angle) * 1.2))
		local blur = (v > 1.3)
		for x = math.floor(sh.x0), (sh.x1) - 1 do
			if blur then
				self:dot(x, sy, C.steel, 1)
				self:dot(x, (sy + 1), C.ironLt, 1)
			else
				self:dot(x, (if ((js.band(((x + off)), 3)) < 2) then sy else (sy + 1)), C.steel, 1)
			end
		end
	end
	local y = math.floor(self.shaftY)
	for i = 0, (#self.hangers) - 1 do
		local hx = self.hangers[i + 1]
		self:line(hx, (y - 2), hx, (y - 0.5), C.iron, 1)
		self:dot((hx - 1), (y - 2), C.iron, 1)
		self:dot((hx + 1), (y - 2), C.iron, 1)
	end
end

function Engine.drawGear(self: any, g: any)
	local a = (g.phase + (g.s * self.angle))
	local w = math.abs((g.s * self.omega))
	local blurT = clamp01(((((((w * g.n)) / TAU) - 0.4)) / 0.5))
	local blurS = clamp01((((w - 0.3)) / 0.4))
	local tip = (g.r + 0.95)
	local spokes = (if (g.r >= 4) then 3 else 0)
	local spacing = (TAU / math.max(1, spokes))
	local dark = mix(g.color, 0x202020, 0.35)
	local x0 = math.floor((g.x - tip))
	local x1 = math.ceil((g.x + tip))
	local y0 = math.floor((g.y - tip))
	local y1 = math.ceil((g.y + tip))
	for y = y0, y1 do
		local dy = ((y + 0.5) - g.y)
		for x = x0, x1 do
			local dx = ((x + 0.5) - g.x)
			local d = math.sqrt(((dx * dx) + (dy * dy)))
			if ((d > tip) or ((g.rim and (d <= g.r)))) then
				continue
			end
			if (d <= 0.9) then
				self:dot(x, y, C.brassHi, 3)
				continue
			end
			if (d > g.r) then
				local m = frac(((((g.n * ((math.atan2(dy, dx) - a)))) / TAU) + 0.2))
				local p = ((((if (m < 0.4) then 1 else 0)) * ((1 - blurT))) + (0.4 * blurT))
				if self:dither(x, y, p) then
					self:dot(x, y, g.color, 2)
				end
				continue
			end
			if (d > (g.r - 1)) then
				self:dot(x, y, g.color, 2)
				continue
			end
			if (spokes == 0) then
				continue
			end
			local m = js.mod(((math.atan2(dy, dx) - a)), spacing)
			if (m < 0) then
				m = (m + spacing)
			end
			local near = (math.min(m, (spacing - m)) * d)
			local p = ((((if (near < 0.5) then 1 else 0)) * ((1 - blurS))) + (0.3 * blurS))
			if self:dither(x, y, p) then
				self:dot(x, y, dark, 1)
			end
		end
	end
end

function Engine.drawPulley(self: any, p: any)
	local a = (p.phase + (p.s * self.angle))
	local w = math.abs((p.s * self.omega))
	local blur = clamp01((((w - 0.3)) / 0.4))
	local spacing = (TAU / math.max(1, p.spokes))
	local x0 = math.floor((p.x - p.r))
	local x1 = math.ceil((p.x + p.r))
	local y0 = math.floor((p.y - p.r))
	local y1 = math.ceil((p.y + p.r))
	for y = y0, y1 do
		local dy = ((y + 0.5) - p.y)
		for x = x0, x1 do
			local dx = ((x + 0.5) - p.x)
			local d = math.sqrt(((dx * dx) + (dy * dy)))
			if (d > p.r) then
				continue
			end
			if ((d > (p.r - 0.95)) or (d <= 0.75)) then
				self:dot(x, y, p.color, 3)
				continue
			end
			if (p.spokes == 0) then
				continue
			end
			local m = js.mod(((math.atan2(dy, dx) - a)), spacing)
			if (m < 0) then
				m = (m + spacing)
			end
			local near = (math.min(m, (spacing - m)) * d)
			local pr = ((((if (near < 0.6) then 1 else 0)) * ((1 - blur))) + (0.35 * blur))
			if self:dither(x, y, pr) then
				self:dot(x, y, C.iron, 2)
			end
		end
	end
	if (((p.spokes == 0) and (p.r >= 1.4)) and (w < 0.5)) then
		self:dot((p.x + (math.cos(a) * ((p.r - 0.5)))), (p.y + (math.sin(a) * ((p.r - 0.5)))), C.steel, 4)
	end
end

function Engine.drawBelt(self: any, b: any)
	local ddx = (b.x2 - b.x1)
	local ddy = (b.y2 - b.y1)
	local len = math.sqrt(((ddx * ddx) + (ddy * ddy)))
	if (len < 1) then
		return
	end
	local dx = (ddx / len)
	local dy = (ddy / len)
	local nx = (-dy)
	local ny = dx
	local travel = (b.v * self.angle)
	local speed = math.abs((b.v * self.omega))
	local blur = (speed > 1.5)
	for side = (-1), 1, 2 do
		local ax = (b.x1 + ((nx * b.r1) * side))
		local ay = (b.y1 + ((ny * b.r1) * side))
		local s2 = (if b.crossed then (-side) else side)
		local bx = (b.x2 + ((nx * b.r2) * s2))
		local by = (b.y2 + ((ny * b.r2) * s2))
		local lx = (bx - ax)
		local ly = (by - ay)
		local l = math.sqrt(((lx * lx) + (ly * ly)))
		local steps = math.ceil(l)
		local off = (if (side > 0) then travel else (-travel))
		for k = 0, steps do
			local f = (k / math.max(1, steps))
			local ph = js.mod((((js.mod(((k + off)), 5)) + 5)), 5)
			local x = (ax + (lx * f))
			local y = (ay + (ly * f))
			if blur then
				self:dot(x, y, (if ((js.band(k, 1)) == 0) then C.leatherHi else C.leather), 3)
			else
				if (ph < 3.4) then
					self:dot(x, y, (if (ph < 1) then C.leatherHi else C.leather), 3)
				end
			end
		end
	end
end

function Engine.drawModule(self: any, m: any)
	local x = m.x
	local ey = self.ey
	local qy0 = math.floor((ey / 2))
	if (m.kind == BELL) then
		local a = (m.phase + (m.s * self.angle))
		for yy = math.floor((m.y - 3)), (m.y + 3) do
			for xx = math.floor((m.x - 3)), (m.x + 3) do
				local dx = ((xx + 0.5) - m.x)
				local dy = ((yy + 0.5) - m.y)
				local d = math.sqrt(((dx * dx) + (dy * dy)))
				if (d > 2.9) then
					continue
				end
				local rr = (1.5 + (1.3 * ((1 - frac((((2 * ((math.atan2(dy, dx) - a)))) / TAU))))))
				if (d <= rr) then
					self:dot(xx, yy, (if (d < 1) then C.brassHi else C.iron), (if (d < 1) then 4 else 2))
				end
			end
		end
		local lift = (self:camLift(m) * ((1.3 / 1.8)))
		local top = (((m.y - 1.5) - lift) - 9)
		self:line(m.x, ((m.y - 2) - lift), m.x, top, C.steel, 4)
		self:dot((m.x - 1), top, C.iron, 4)
		self:dot((m.x + 1), top, C.iron, 4)
		self:line(1, (m.y - 6), (m.x - 1), (m.y - 6), C.iron, 1)
		local ring = ((lift > 1.05) and (self.omega > 0.02))
		local bq = math.floor(((((((m.y - 1.5) - 1.3) - 9) - 3)) / 2))
		local bx = math.floor(m.x)
		self:qrect((bx - 1), (bq - 1), bx, (bq - 1), (if ring then C.brassHi else C.brass))
		self:qrect((bx - 2), bq, (bx + 1), bq, (if ring then C.brassHi else C.brassDk))
		self:line((bx - 0.5), ((bq * 2) - 2), 1, ((bq * 2) - 5), C.iron, 1)
		if ring then
			self:dot((bx - 4), ((bq * 2) + 1), C.brassHi, 3)
			self:dot((bx + 3), ((bq * 2) + 1), C.brassHi, 3)
			self:dot((bx - 5), (bq * 2), C.brassDk, 3)
			self:dot((bx + 4), (bq * 2), C.brassDk, 3)
		end
	else
		if (m.kind == HAMMER) then
			local a = (m.phase + (m.s * self.angle))
			local ccx = (x + 16)
			local ccy = (ey + 13.1)
			for yy = math.floor((ccy - 4)), (ccy + 4) do
				for xx = math.floor((ccx - 4)), (ccx + 4) do
					local dx = ((xx + 0.5) - ccx)
					local dy = ((yy + 0.5) - ccy)
					local d = math.sqrt(((dx * dx) + (dy * dy)))
					if (d > 3.9) then
						continue
					end
					local rr = (2 + (1.8 * ((1 - frac((((2 * ((math.atan2(dy, dx) - a)))) / TAU))))))
					if (d <= rr) then
						self:dot(xx, yy, (if (d < 1.1) then C.brassHi else C.iron), (if (d < 1.1) then 4 else 2))
					end
				end
			end
			local lift = self:camLift(m)
			local pxv = (x + 6)
			local pyv = (ey + 9)
			local contactY = (((ccy - 2) - lift) - 0.5)
			local k = (((contactY - pyv)) / 10)
			local hx = (x + 28)
			local hy = (pyv + (k * 22))
			self:line(pxv, pyv, hx, hy, C.wood, 3)
			self:line(pxv, (pyv + 1), hx, (hy + 1), C.wood, 3)
			self:qrect((x + 5), (qy0 + 5), (x + 6), (qy0 + 8), C.ironDk)
			self:q((x + 5), (qy0 + 4), C.brass)
			local hq = math.floor((((hy + 1)) / 2))
			self:qrect((hx - 2), hq, (hx + 1), (hq + 1), C.iron)
			self:qrect((x + 25), (qy0 + 8), (x + 31), (qy0 + 8), C.ironDk)
		else
			if (m.kind == STACK) then
				for qy = (qy0 + 1), (qy0 + 8) do
					for qx = (x + 3), (x + 8) do
						local brick = (if ((js.band(((qx + ((js.band(qy, 1)) * 2))), 3)) == 0) then C.brickDk else C.brick)
						self:q(qx, qy, (if (qy == (qy0 + 1)) then C.brass else brick))
					end
				end
				self:qrect((x + 5), (qy0 + 7), (x + 6), (qy0 + 8), self:fireAt((x + 5), 7))
			else
				if (m.kind == BEAM) then
					local a = (m.phase + (m.s * self.angle))
					local pinX = ((x + 6) + (math.cos(a) * 2.4))
					local pinY = ((ey + 13) + (math.sin(a) * 2.4))
					local pivX = (x + 22)
					local pivY = (ey + 5)
					local h = 15
					local endX = (pivX - h)
					local rod = 7
					local ddx = (pinX - endX)
					local yL = (pinY - math.sqrt(math.max(0, ((rod * rod) - (ddx * ddx)))))
					local sn = math.max((-0.6), math.min(0.6, (((yL - pivY)) / h)))
					local cs = math.sqrt((1 - (sn * sn)))
					local lx = (pivX - (h * cs))
					local ly = (pivY + (h * sn))
					local rx = (pivX + (h * cs))
					local ry = (pivY - (h * sn))
					self:line(lx, ly, rx, ry, C.iron, 3)
					self:line(lx, (ly + 1), rx, (ry + 1), C.ironLt, 3)
					self:line(pinX, pinY, lx, (ly + 1), C.steel, 4)
					self:dot(pinX, pinY, C.brassHi, 5)
					self:line(rx, (ry + 1), rx, (ey + 12), C.steel, 4)
					self:qrect((x + 21), (qy0 + 3), (x + 22), (qy0 + 8), C.iron)
					self:q((x + 21), (qy0 + 2), C.brass)
					self:q((x + 22), (qy0 + 2), C.brass)
					local pc = math.floor(rx)
					self:qrect((pc - 2), (qy0 + 6), (pc + 2), (qy0 + 8), C.copper)
					self:qrect((pc - 3), (qy0 + 6), (pc + 3), (qy0 + 6), C.brassDk)
					self:qrect((pc + 3), (qy0 + 7), ((x + m.w) - 1), (qy0 + 7), C.copperDk)
				else
					if (m.kind == GRIND) then
						local a = (m.phase + (m.s * self.angle))
						local gx = (x + 13)
						local gy = (ey + 11)
						local blur = clamp01((((math.abs((m.s * self.omega)) - 0.25)) / 0.4))
						for yy = math.floor((gy - 6)), (gy + 6) do
							for xx = math.floor((gx - 6)), (gx + 6) do
								local dx = ((xx + 0.5) - gx)
								local dy = ((yy + 0.5) - gy)
								local d = math.sqrt(((dx * dx) + (dy * dy)))
								if ((d > 5.8) or (d < 2.4)) then
									continue
								end
								local grain = ((js.band(((math.floor((d * 0.9)) + math.floor(((((((math.atan2(dy, dx) - a)) / TAU)) * 14) + 14)))), 1)) == 0)
								local p = (if (d > 5) then 1 else ((((if grain then 0.9 else 0.15)) * ((1 - blur))) + (0.5 * blur)))
								if self:dither(xx, yy, p) then
									self:dot(xx, yy, (if (d > 5) then C.stone else C.stoneDk), 2)
								end
							end
						end
						self:drawPulleyAt(gx, gy, 2, m.s)
						self:qrect((x + 7), (qy0 + 8), (x + 19), (qy0 + 8), C.wood)
						self:qrect((x + 19), (qy0 + 5), (x + 20), (qy0 + 5), C.ironLt)
						self:qrect((x + 20), (qy0 + 6), (x + 20), (qy0 + 8), C.ironDk)
					else
						if ((m.kind == PANEL) or (m.kind == PIPE)) then
							local x1 = ((x + m.w) - 1)
							self:qrect(x, (qy0 + 6), x1, (qy0 + 6), C.copper)
							if (m.kind == PANEL) then
								self:qrect((x + 2), (qy0 + 2), (x + 3), (qy0 + 5), C.copperDk)
								self:qrect(((x + m.w) - 5), (qy0 + 3), ((x + m.w) - 4), (qy0 + 5), C.copperDk)
								self:qrect((x + 1), (qy0 + 2), (x + 4), (qy0 + 2), C.brassDk)
								self:drawHandwheel((x + 11), (ey + 9.5))
								self:qrect((x + 10), (qy0 + 6), (x + 12), (qy0 + 6), C.brass)
							else
								if (m.w >= 6) then
									self:drawHandwheel((x + math.floor((m.w / 2))), (ey + 9.5))
									self:qrect(((x + math.floor((m.w / 2))) - 1), (qy0 + 6), ((x + math.floor((m.w / 2))) + 1), (qy0 + 6), C.brass)
								end
							end
						end
					end
				end
			end
		end
	end
end

function Engine.drawPulleyAt(self: any, x: any, y: any, r: any, s: any)
	local a = (s * self.angle)
	for k = 0, (10) - 1 do
		local t = (((k / 10)) * TAU)
		self:dot((x + (math.cos(t) * ((r - 0.4)))), (y + (math.sin(t) * ((r - 0.4)))), C.brass, 3)
	end
	self:dot(x, y, C.brassHi, 4)
	self:dot((x + (math.cos(a) * 1.2)), (y + (math.sin(a) * 1.2)), C.steel, 4)
end

function Engine.drawHandwheel(self: any, x: any, y: any)
	local a = (math.sin(((self.t * 0.01) + x)) * 0.6)
	for k = 0, (12) - 1 do
		local t = (((k / 12)) * TAU)
		self:dot((x + (math.cos(t) * 2.4)), (y + (math.sin(t) * 2.4)), C.brass, 3)
	end
	for k = 0, (5) - 1 do
		local t = (a + (((k / 5)) * TAU))
		self:line(x, y, (x + (math.cos(t) * 1.8)), (y + (math.sin(t) * 1.8)), C.brassDk, 2)
	end
	self:dot(x, y, C.brassHi, 4)
end

function Engine.drawWheel(self: any)
	local R = self.radius
	local rim = (R - 1.7)
	local hub = 1.9
	local spacing = (TAU / SPOKES)
	local blur = clamp01((((self.omega - 0.17)) / 0.24))
	local smear = ((blur * spacing) * 0.95)
	local x0 = math.floor((self.cx - R))
	local x1 = math.ceil((self.cx + R))
	local y0 = math.floor((self.cy - R))
	local y1 = math.ceil((self.cy + R))
	local spinPhase = js.band(((self.t * 5)), 15)
	local rimColor = mix(C.ironLt, C.brassDk, 0.15)
	for y = y0, y1 do
		for x = x0, x1 do
			local ddx = ((x + 0.5) - self.cx)
			local ddy = ((y + 0.5) - self.cy)
			local d = math.sqrt(((ddx * ddx) + (ddy * ddy)))
			if (d > R) then
				continue
			end
			if (d >= rim) then
				self:dot(x, y, rimColor, 2)
				continue
			end
			if (d <= hub) then
				self:dot(x, y, C.brass, 4)
				continue
			end
			local s = ((ddx * self.ux) + (ddy * self.uy))
			local t = ((ddx * self.vx) + (ddy * self.vy))
			local a = math.atan2(t, s)
			local m = js.mod(((a - self.angle)), spacing)
			if (m < 0) then
				m = (m + spacing)
			end
			local behind = (spacing - m)
			local near = (math.min(m, behind) * d)
			if (near < 0.75) then
				self:dot(x, y, (if (blur > 0.5) then C.ironLt else C.iron), 1)
				continue
			end
			if ((smear > 0) and (behind < smear)) then
				local k = (1 - (behind / smear))
				if self:dither((x + spinPhase), y, (k * ((0.35 + (0.5 * blur))))) then
					self:dot(x, y, C.ironDk, 0)
				end
			end
		end
	end
end

function Engine.drawLinkage(self: any)
	local th = self.angle
	local rc = self.crank
	local L = self.rodLen
	local sinT = math.sin(th)
	local cosT = math.cos(th)
	local pinS = (rc * cosT)
	local pinT = (rc * sinT)
	local sH = ((rc * cosT) + math.sqrt(((L * L) - (((rc * rc) * sinT) * sinT))))
	local pinX = self:fx(pinS, pinT)
	local pinY = self:fy(pinS, pinT)
	local hx = self:fx(sH, 0)
	local hy = self:fy(sH, 0)
	local ht = self.halfT
	local near = (L - rc)
	local gt = (if self.vertical then 3.5 else 2.5)
	self:line(self:fx((near - 3), gt), self:fy((near - 3), gt), self:fx(self.cyl0, gt), self:fy(self.cyl0, gt), C.iron, 1)
	self:line(self:fx((near - 3), (-gt)), self:fy((near - 3), (-gt)), self:fx(self.cyl0, (-gt)), self:fy(self.cyl0, (-gt)), C.iron, 1)
	self:line(hx, hy, self:fx((self.cyl0 + 1), 0), self:fy((self.cyl0 + 1), 0), C.steel, 3)
	local eS = (1.6 * math.cos((th + (math.pi / 2))))
	local eT = (1.6 * math.sin((th + (math.pi / 2))))
	local vS = ((self.cyl0 + 2) + (eS * 0.6))
	self:line(self:fx(eS, eT), self:fy(eS, eT), self:fx(vS, (ht + 1.6)), self:fy(vS, (ht + 1.6)), C.brassDk, 2)
	self:line(self.cx, self.cy, pinX, pinY, C.brassDk, 3)
	self:line(pinX, pinY, hx, hy, C.steel, 4)
	for oy = (-1), 0 do
		for ox = (-1), 0 do
			self:dot(((pinX + ox) + 0.5), ((pinY + oy) + 0.5), C.brassHi, 5)
		end
	end
	local sP = (sH + self.pistonOffset)
	local s0 = math.min((near - 4), self.cyl0)
	local s1 = (self.cyl1 + 0.5)
	local tMax = (ht + 4)
	local qw = (self.columns * 2)
	local qh = (self.rows * 2)
	local xa = self:fx(s0, (-tMax))
	local xb = self:fx(s1, tMax)
	local ya = self:fy(s0, (-tMax))
	local yb = self:fy(s1, tMax)
	local qx0 = math.max(0, math.floor(math.min(xa, xb)))
	local qx1 = math.min((qw - 1), math.ceil(math.max(xa, xb)))
	local qy0 = math.max(0, math.floor((math.min(ya, yb) / 2)))
	local qy1 = math.min((qh - 1), math.ceil((math.max(ya, yb) / 2)))
	local chest0 = (self.cyl0 + 3.5)
	local chest1 = (self.cyl1 - 3.5)
	local steamInside = mix(C.cavity, 0x3a4048, clamp01((self.heat * 1.2)))
	for qy = qy0, qy1 do
		for qx = qx0, qx1 do
			local px = ((qx + 0.5) - self.cx)
			local py = (((qy * 2) + 1) - self.cy)
			local s = ((px * self.ux) + (py * self.uy))
			local t = ((px * self.vx) + (py * self.vy))
			local at = math.abs(t)
			if ((math.abs((s - sH)) <= 1.5) and (at <= 2)) then
				self:q(qx, qy, C.brass)
				continue
			end
			if ((s >= self.cyl0) and (s <= self.cyl1)) then
				local capped = ((s < (self.cyl0 + 2)) or (s > (self.cyl1 - 2)))
				if (capped and (at <= (ht + 1.2))) then
					self:q(qx, qy, C.iron)
					continue
				end
				if (at <= (ht - 1.4)) then
					self:q(qx, qy, (if (math.abs((s - sP)) <= 1.1) then C.brassHi else (if (s < sP) then C.cavity else steamInside)))
					continue
				end
				if (at <= ht) then
					self:q(qx, qy, C.copper)
					continue
				end
				if ((((t > ht) and (t <= (ht + 3))) and (s >= chest0)) and (s <= chest1)) then
					self:q(qx, qy, (if ((t > (ht + 1.5)) and (((s < (chest0 + 1)) or (s > (chest1 - 1))))) then C.brassDk else C.ironLt))
					continue
				end
			end
		end
	end
end

function Engine.drawGovernor(self: any)
	local spin = clamp01((self.omega / MAX_SPEED))
	local phi = (0.22 + (1.05 * math.sqrt(spin)))
	local L = self.govArm
	local x = self.govX
	local y = self.govY
	self:line(x, (if (self.shaft2Y >= 0) then (self.shaft2Y + 1) else (y - 0.5)), x, self.govBase, C.iron, 1)
	local wob = (if (spin > 0.05) then ((0.12 * math.sin((self.angle * 1.7))) * spin) else 0)
	local sinP = (math.sin(phi) * ((1 - math.abs(wob))))
	local cosP = math.cos(phi)
	local sleeveY = (y + ((L * cosP) * 1.05))
	for side = (-1), 1, 2 do
		local bx = (x + ((side * L) * sinP))
		local by = (y + (L * cosP))
		self:line(x, y, bx, by, C.brassDk, 2)
		self:line((x + (((side * L) * sinP) * 0.5)), (y + ((L * cosP) * 0.5)), x, sleeveY, C.brassDk, 2)
		for oy = (-1), 0 do
			for ox = (-1), 0 do
				self:dot(((bx + ox) + 0.5), ((by + oy) + 0.5), C.brassHi, 5)
			end
		end
	end
	self:dot(x, sleeveY, C.brass, 3)
	self:dot(x, (y - 1), C.brass, 3)
end

function Engine.fireAt(self: any, qx: any, qy: any)
	local flick = (((self.rng:f() * 0.18) - 0.06) + (math.sin(((self.t * 0.7) + (qx * 1.3))) * 0.04))
	local h = ((self.heat * ((if (js.band(qy, 1) ~= 0) then 1 else 0.88))) + (flick * ((0.4 + self.heat))))
	if (self.tint == "blue") then
		return fireColor((0.3 + (h * 0.75)), BLUE_FIRE)
	end
	return fireColor((if (self.sputter > 0) then (h * 0.7) else h))
end

function Engine.warningLamp(self: any, qx: any, qy: any)
	local on = ((self.tint == "blue") and (js.mod((js.sar(self.t, 3)), 3) ~= 0))
	local color = (if on then C.blue else (if (self.tint == "blue") then 0x24508c else C.blueOff))
	local x = js.band(math.floor(qx), js.bnot(1))
	self:q(x, qy, color)
	self:q((x + 1), qy, color)
end

function Engine.drawBoilerBand(self: any)
	local ex = (self.cx - 20)
	local qy0 = math.floor((((self.cy - 10)) / 2))
	local Y = function(k) return (qy0 + k) end
	local b0 = (ex + 70)
	local b1 = (ex + 83)
	for k = 3, 8 do
		local inset = (if (k == 3) then 1 else 0)
		self:qrect((b0 + inset), Y(k), (b1 - inset), Y(k), (if (k == 5) then C.brass else (if (k == 3) then C.copperDk else C.copper)))
	end
	for k = 7, 8 do
		for x = (b0 + 2), (b1 - 4) do
			local frame = ((x == (b0 + 2)) or (x == (b1 - 4)))
			self:q(x, Y(k), (if frame then C.brassDk else self:fireAt(x, k)))
		end
	end
	self:qrect((math.floor(self.chimX) - 2), Y(1), (math.floor(self.chimX) + 1), Y(1), C.brass)
	self:qrect((math.floor(self.chimX) - 1), Y(2), math.floor(self.chimX), Y(2), C.ironDk)
	self:q(math.floor(self.valveX), Y(2), C.brass)
	self:warningLamp((b0 + 6), Y(2))
	local chestEnd = math.floor(self:fx((self.cyl1 - 4), 0))
	self:qrect(chestEnd, Y(1), (b0 + 1), Y(1), C.copperDk)
	self:q(chestEnd, Y(2), C.copperDk)
	self:qrect((b0 + 1), Y(2), (b0 + 2), Y(2), C.copperDk)
	self:qrect(math.floor(self:fx(((self.rodLen - self.crank) - 2), 0)), Y(7), math.floor(self:fx(((self.rodLen - self.crank) - 1), 0)), Y(8), C.ironDk)
	self:qrect(math.floor(self:fx(self.cyl0, 0)), Y(7), math.floor(self:fx((self.cyl0 + 1), 0)), Y(8), C.ironDk)
	self:qrect(math.floor(self:fx((self.cyl1 - 1), 0)), Y(7), math.floor(self:fx(self.cyl1, 0)), Y(8), C.ironDk)
end

function Engine.drawBoilerSpine(self: any)
	local wd = (self.columns * 2)
	local mid = self.cx
	local half = math.min(15, (math.floor((wd / 2)) - 3))
	local bottom = self.boilerBottom
	local top = self.boilerTop
	local b0 = (mid - half)
	local b1 = ((mid + half) - 1)
	for k = top, bottom do
		local inset = (if (k == top) then 2 else (if (k == (top + 1)) then 1 else 0))
		local color = (if (k == top) then C.copperDk else (if (k == (top + 4)) then C.brass else C.copper))
		self:qrect((b0 + inset), k, (b1 - inset), k, color)
	end
	for k = (bottom - 2), (bottom - 1) do
		for x = (b0 + 3), (b1 - 3) do
			local frame = ((x == (b0 + 3)) or (x == (b1 - 3)))
			self:q(x, k, (if frame then C.brassDk else self:fireAt(x, k)))
		end
	end
	self:qrect((b0 - 1), bottom, (b1 + 1), bottom, C.ironDk)
	local cx = math.floor(self.chimX)
	local chimTop = math.floor((self.chimY / 2))
	self:qrect((cx - 2), chimTop, (cx + 1), chimTop, C.brass)
	self:qrect((cx - 1), (chimTop + 1), cx, (top - 1), C.ironDk)
	self:q(math.floor(self.valveX), (top - 1), C.brass)
	self:q(math.floor(self.valveX), top, C.brass)
	self:warningLamp((b1 - 3), (top + 1))
	local px = math.floor(self:fx(0, (self.halfT + 2)))
	local chestTop = math.floor((self:fy((self.cyl1 - 4), 0) / 2))
	for k = (bottom + 1), chestTop do
		self:q(px, k, C.copperDk)
	end
	local g0 = math.floor((self:fy(((self.rodLen - self.crank) - 3), 0) / 2))
	self:qrect(math.floor((self.cx - 6)), g0, math.floor((self.cx - 5)), g0, C.ironDk)
	self:qrect(math.floor((self.cx + 4)), g0, math.floor((self.cx + 5)), g0, C.ironDk)
	for x = (b0 + 1), (b1 - 1), 3 do
		self:q(x, (top + 4), C.brassHi)
	end
	for k = 2, (top) - 1 do
		local rivet = (js.mod(k, 4) == 0)
		self:q(0, k, (if rivet then C.brassDk else C.iron))
		self:q((wd - 1), k, (if rivet then C.brassDk else C.iron))
	end
	if (self.riserX >= 0) then
		local rq0 = math.floor((self.riserY0 / 2))
		local rq1 = math.floor((self.riserY1 / 2))
		self:qrect(self.riserX, rq0, (self.riserX + 1), rq1, C.copperDk)
		self:qrect((self.riserX - 1), (rq1 - 1), (self.riserX + 2), (rq1 - 1), C.brass)
	end
end

function Engine.drawBed(self: any)
	local wd = (self.columns * 2)
	local qy = ((self.rows * 2) - 1)
	local x0 = 0
	local x1 = (wd - 1)
	if (not self.vertical) then
		x0 = (math.ceil((self.cx + self.radius)) + 1)
	end
	self:qrect(x0, qy, x1, qy, C.ironDk)
	local lit = math.min((if self.vertical then 4 else 16), js.round((self.coverageBoost / ((if self.vertical then 12 else 4)))))
	if (lit <= 0) then
		return
	end
	local step = math.max(4, js.band(math.floor((((x1 - x0)) / ((lit + 1)))), js.bnot(1)))
	for k = 0, (lit) - 1 do
		local x = ((js.band(((x0 + (step * ((k + 1))))), js.bnot(1))) - ((if self.vertical then 0 else 0)))
		if ((x + 1) > x1) then
			break
		end
		local blink = (js.mod((((js.sar(self.t, 3)) + (k * 5))), 13) == 0)
		local on = (if (self.tint == "smoke") then C.lampLow else (if (self.tint == "blue") then C.lampBlue else C.lampOn))
		self:q(x, qy, (if blink then C.brassDk else on))
		self:q((x + 1), qy, (if blink then C.brassDk else on))
	end
end

function Engine.drawSteam(self: any)
	local wd = (self.columns * 2)
	local hd = (self.rows * 4)
	local st = self.steam
	for i = 0, (self.nPuffs) - 1 do
		local r = self.pr[i + 1]
		local life = (self.page[i + 1] / self.plife[i + 1])
		local amp = ((self.pamp[i + 1] * ((1 - life))) * ((1 - (life * 0.3))))
		local x = self.px[i + 1]
		local y = self.py[i + 1]
		local x0 = math.max(0, math.floor((x - r)))
		local x1 = math.min((wd - 1), math.ceil((x + r)))
		local y0 = math.max(0, math.floor((y - r)))
		local y1 = math.min((hd - 1), math.ceil((y + r)))
		local inv = (1 / ((r * r)))
		for yy = y0, y1 do
			local dy = ((yy + 0.5) - y)
			for xx = x0, x1 do
				local dx = ((xx + 0.5) - x)
				local f = (1 - ((((dx * dx) + (dy * dy))) * inv))
				if (f > 0) then
					st[((yy * wd) + xx) + 1] = js.f32((st[((yy * wd) + xx) + 1] + (amp * f)))
				end
			end
		end
	end
end

function Engine.drawSparks(self: any)
	for i = 0, (self.nSparks) - 1 do
		local x = math.floor(self.sx[i + 1])
		local y = math.floor(self.sy[i + 1])
		if ((((x < 0) or (y < 0)) or (x >= (self.columns * 2))) or (y >= (self.rows * 4))) then
			continue
		end
		local c = (((js.sar(y, 2)) * self.columns) + (js.sar(x, 1)))
		self.spark[c + 1] = js.u8(js.bor(self.spark[c + 1], BRAILLE[js.band(x, 1) + 1][js.band(y, 3) + 1]))
	end
end

function Engine.steamColor(self: any, d: any)
	if (self.tint == "smoke") then
		return mix(0x2a2826, 0x6e6a66, d)
	end
	if (self.tint == "blue") then
		return mix(0x34507e, 0xa8ccff, d)
	end
	return mix(0x5d666e, 0xe8ecef, d)
end

function Engine.compose(self: any)
	local out = self.out
	local w = self.columns
	local qw = (w * 2)
	local wd = (w * 2)
	local quad = self.quad
	local st = self.steam
	for row = 0, (self.rows) - 1 do
		for col = 0, (w) - 1 do
			local i = ((row * w) + col)
			local qa = (((row * 2) * qw) + (col * 2))
			local q0 = quad[qa + 1]
			local q1 = quad[(qa + 1) + 1]
			local q2 = quad[(qa + qw) + 1]
			local q3 = quad[((qa + qw) + 1) + 1]
			if (js.bor(js.bor(js.bor(q0, q1), q2), q3) ~= 0) then
				self:solidCell(i, q0, q1, q2, q3)
				continue
			end
			local sbits = 0
			local sum = 0
			local dx0 = (col * 2)
			local dy0 = (row * 4)
			for dy = 0, (4) - 1 do
				local base = ((((dy0 + dy)) * wd) + dx0)
				for dx = 0, (2) - 1 do
					local v = st[(base + dx) + 1]
					sum = (sum + (if (v > 1) then 1 else v))
					if (v > (((BAYER[js.bor((js.shl((js.band(((dy0 + dy)), 3)), 2)), (js.band(((dx0 + dx)), 3))) + 1] + 0.5)) / 16)) then
						sbits = js.bor(sbits, BRAILLE[dx + 1][dy + 1])
					end
				end
			end
			local avg = (sum / 8)
			local b = self.bits[i + 1]
			local sp = self.spark[i + 1]
			local wall = (self.wall[i + 1] == 1)
			local bg = (if wall then C.wallMortar else DEFAULT_COLOR)
			if (sp ~= 0) then
				out:set(i, js.bor(js.bor(BRAILLE_BASE, sp), b), C.spark, bg)
			else
				if (b ~= 0) then
					out:set(i, js.bor(js.bor(BRAILLE_BASE, b), ((if (avg > 0.3) then sbits else 0))), self.bcol[i + 1], bg)
				else
					if (sbits ~= 0) then
						out:set(i, js.bor(BRAILLE_BASE, sbits), self:steamColor((avg * 1.4)), bg)
					else
						if wall then
							out:set(i, (if ((js.band(((col + ((js.band(row, 1)) * 2))), 3)) == 0) then 0x2597 else 0x2584), C.wallBrick, C.wallMortar)
						else
							out:blank(i)
						end
					end
				end
			end
		end
	end
end

function Engine.solidCell(self: any, i: any, q0: any, q1: any, q2: any, q3: any)
	local cols = self.qcols
	local counts = self.qcounts
	local qs = self.qs
	qs[0 + 1] = js.u32(q0)
	qs[1 + 1] = js.u32(q1)
	qs[2 + 1] = js.u32(q2)
	qs[3 + 1] = js.u32(q3)
	local n = 0
	local empty = false
	for k = 0, (4) - 1 do
		local q = qs[k + 1]
		if (q == 0) then
			empty = true
			continue
		end
		local j = 0
		while ((j < n) and (cols[j + 1] ~= q)) do
			j = j + 1
		end
		if (j == n) then
			cols[n + 1] = js.u32(q)
			counts[n + 1] = js.u8(0)
			n = n + 1
		end
		counts[j + 1] = js.u8(counts[j + 1] + 1)
	end
	local a = 0
	for j = 1, (n) - 1 do
		if (counts[j + 1] > counts[a + 1]) then
			a = j
		end
	end
	local b = (-1)
	if (not empty) then
		for j = 0, (n) - 1 do
			if ((j ~= a) and (((b < 0) or (counts[j + 1] > counts[b + 1])))) then
				b = j
			end
		end
	end
	local fg = (cols[a + 1] - SOLID)
	local bg = (if (b >= 0) then (cols[b + 1] - SOLID) else (-1))
	local mask = 0
	for k = 0, (4) - 1 do
		local q = qs[k + 1]
		if (q == 0) then
			continue
		end
		local c = (q - SOLID)
		if (((bg < 0) or (c == fg)) or (((c ~= bg) and (dist(c, fg) <= dist(c, bg))))) then
			mask = js.bor(mask, js.shl(1, k))
		end
	end
	if ((bg >= 0) and (mask == 15)) then
		self.out:set(i, 0x2588, fg)
	else
		self.out:set(i, QUAD[mask + 1], fg, (if (bg >= 0) then bg else (if (self.wall[i + 1] == 1) then C.wallMortar else DEFAULT_COLOR)))
	end
end

function Engine.drawGauge(self: any, g: any)
	local col = g.col
	local row = g.row
	local wc = g.wc
	local hc = 1
	if ((((col < 0) or (row < 0)) or ((col + wc) > self.columns)) or ((row + hc) > self.rows)) then
		return
	end
	local gw = (wc * 2)
	local gh = (hc * 4)
	local base = clamp01((self.pressure + (g.bias * self.pressure)))
	local p = clamp01((base + ((if (base > 0.7) then (math.sin(((self.t * 1.9) + g.col)) * 0.025) else 0))))
	local a = ((((-0.75) + (1.5 * p))) * math.pi)
	local ox = (gw / 2)
	local oy = (gh * 0.7)
	local len = (math.min((gw / 2), oy) + 0.2)
	local dx = math.sin(a)
	local dy = (-math.cos(a))
	local b0 = 0
	local b1 = 0
	for k = 0, 8 do
		local f = (((k / 8)) * len)
		local x = math.floor((ox + (dx * f)))
		local y = math.floor((((oy - 0.5) + (dy * f)) + 0.5))
		if ((((x < 0) or (y < 0)) or (x >= gw)) or (y >= gh)) then
			continue
		end
		local bit = BRAILLE[js.band(x, 1) + 1][js.band(y, 3) + 1]
		if (js.sar(x, 1) == 0) then
			b0 = js.bor(b0, bit)
		else
			b1 = js.bor(b1, bit)
		end
	end
	local color = (if (p > 0.85) then C.needleHot else C.needle)
	local face = (if (self.tint == "blue") then mix(C.face, 0x8cbcff, 0.6) else (if (self.tint == "smoke") then mix(C.face, 0x5a5650, 0.45) else C.face))
	self.out:set(((row * self.columns) + col), js.bor(BRAILLE_BASE, b0), color, face)
	self.out:set((((row * self.columns) + col) + 1), js.bor(BRAILLE_BASE, b1), color, face)
end
end
