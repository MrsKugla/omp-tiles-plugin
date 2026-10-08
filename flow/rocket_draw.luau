--!strict
-- Second half of rocket.luau (split so each half compiles within Tern's per-call budget).
-- Port of Flow (MIT, Rob Macrae). `install(env)` adds these methods to the class.
return function(env: any)
local LaunchSite = env.LaunchSite
local DEFAULT_COLOR = env.DEFAULT_COLOR
local LAYER = env.LAYER
local LIGHT = env.LIGHT
local LIMB = env.LIMB
local OCEAN = env.OCEAN
local PMAX = env.PMAX
local QUAD = env.QUAD
local RAMPS = env.RAMPS
local TILE = env.TILE
local breath = env.breath
local finite = env.finite
local fitQuad = env.fitQuad
local g = env.g
local hash = env.hash
local js = env.js
local lowerBlock = env.lowerBlock
local mix = env.mix
local rampColor = env.rampColor
local truncate = env.truncate
local truth = env.truth
function LaunchSite:openTwin()

self.splitTall = self.tall
local w = (if truth(self.splitTall) then self.columns else math.floor((self.columns / 2)))
local h = (if truth(self.splitTall) then math.floor((self.rows / 2)) else self.rows)
local t = self:twin()
t.boosterOnly = true
t.night = self.night
t.tint = self.tint
t.strength = 1
t:ensure(w, h)
t:geo()
t.fresh = false
t.part = "booster"
t.returning = true
t.state = "fly"
t.flyTime = 120
t.staged = 7
t.sinceStage = 0
t.layer = LAYER[(7) + 1]
t.alt = (t.layer + TILE)
t.v = (-0.6)
t.service = 0
self.twinSite = t
self.twinW = w
self.twinH = h
self.twinDone = 0
end
function LaunchSite:stepTwin()

if (truth(self.twinDue) and not (truth(self.ghost))) then
self.twinDue = false
self:openTwin()
end
local t = self.twinSite
if not (truth(t)) then
return
end
t.night = self.night
t.tint = self.tint
t.strength = 1
t:step()
for _, e in ipairs(t.sounds) do
if (#self.sounds < 16) then
table.insert(self.sounds, e)
end
end
truncate(t.sounds, 0)
if ((t.state == "rest") or (t.state == "landed")) then
self.twinDone = self.twinDone + 1
end
local open = (self.twinDone < 20)
local full = (if truth(self.splitTall) then self.twinH else self.twinW)
self.splitW = (self.splitW + math.max((-0.6), math.min(0.6, ((if truth(open) then full else 0) - self.splitW))))
if (not (truth(open)) and (self.splitW <= 0)) then
self.splitW = 0
self.twinSite = nil
self.boosterHome = true
end
end
function LaunchSite:go(state)

self.state = state
self.timer = 0
end
function LaunchSite:boosterSprite()

local s = self.spec
local st = self.state
if ((((truth(self.braking) or (st == "landed")) or (st == "catch")) or (st == "lower")) or (st == "release")) then
return s.land
end
return s.fins
end
function LaunchSite:ramp()

if (self.tint == "smoke") then
return RAMPS.smoke
end
if (self.tint == "blue") then
return RAMPS.blue
end
return self.look.ramp
end
function LaunchSite:nozzle()

local s = self.spec
local bottom = self:partRows(self.part)[(1) + 1]
return {(self:apx() + (if truth(bottom) then (s.fly.h - bottom) else 0)), (((self.bodyPx + self.pos) + (s.bodyW / 2)) - 0.5), (if truth((self.part == "upper")) then 0.6 else 1)}
end
function LaunchSite:plumeLen()

local p = self.part
if ((((self.thr <= 0) or (p == "dragon")) or (p == "capsule")) or (self.flop > 0.3)) then
return 0
end
local len = (((self.spec.plume * self.thr) * (0.85 + (0.3 * self.rng:f()))) * (if truth((self.part == "upper")) then 0.7 else 1))
if ((self.tint == "smoke") and (hash(js.sar(self.t, 1), 3, 43) < 0.35)) then
len = (len * 0.25)
end
return len
end
function LaunchSite:spawn(x, y, vx, vy, life, r0, r1, color, a0)

local i = self.nextP
self.nextP = js.mod((i + 1), PMAX)
self.px[(i) + 1] = js.f32(x)
self.py[(i) + 1] = js.f32(y)
self.vx[(i) + 1] = js.f32(vx)
self.vy[(i) + 1] = js.f32(vy)
self.life[(i) + 1] = js.f32(life)
self.maxLife[(i) + 1] = js.f32(life)
self.r0[(i) + 1] = js.f32(r0)
self.r1[(i) + 1] = js.f32(r1)
self.pcol[(i) + 1] = js.u32(color)
self.a0[(i) + 1] = js.f32(a0)
end
function LaunchSite:stepParticles()

for i = 0, PMAX, 1 do
if not ((i < PMAX)) then break end
if (self.life[(i) + 1] <= 0) then
continue
end
self.life[(i) + 1] = js.f32((self.life[(i) + 1] - 1))
self.px[(i) + 1] = js.f32((self.px[(i) + 1] + self.vx[(i) + 1]))
self.py[(i) + 1] = js.f32((self.py[(i) + 1] + self.vy[(i) + 1]))
self.vx[(i) + 1] = js.f32((self.vx[(i) + 1] * 0.96))
end
local s = self.spec
local r = self.rng
local A, cx = unpack(self:nozzle())
local scale = (if truth(self.tall) then 1 else 0.6)
local smoky = (self.tint == "smoke")
local len = (if truth((self.thr > 0)) then (s.plume * self.thr) else 0)
if ((len > 0) and ((A - len) < 2)) then
local n = ((if truth(self.tall) then 6 else 2) + (if truth((self.state == "ignite")) then 2 else 0))
for k = 0, n, 1 do
if not ((k < n)) then break end
local side = (if truth((r:f() < 0.5)) then (-1) else 1)
local out = ((s.bodyW / 2) + ((r:f() * ((len - A) + 2)) * 1.2))
local shade = (if truth(smoky) then mix(10132122, 4868682, r:f()) else mix(16777215, 11844290, (r:f() * 0.7)))
self:spawn((cx + (side * out)), ((r:f() * 2) - 0.5), ((side * (0.35 + (r:f() * 1.3))) * scale), (0.03 + (r:f() * 0.12)), (40 + (r:f() * 50)), s.puff[(0) + 1], (s.puff[(1) + 1] * (0.7 + (r:f() * 0.5))), shade, 0.85)
end
end
if (((((self.state == "fly") and (len > 0)) and ((A - len) > 1)) and (self.orbit < 0.3)) and (self.layer < 80)) then
local thick = (if truth((self.layer < 40)) then 1 else 0.6)
self:spawn((cx + ((r:f() - 0.5) * s.bodyW)), ((A - len) - 1), ((r:f() - 0.5) * 0.1), 0, (30 + (r:f() * 30)), s.puff[(0) + 1], ((s.puff[(1) + 1] * 0.6) * thick), (if truth(smoky) then 5921370 else 14278373), (if truth(smoky) then 0.6 else (0.55 * thick)))
end
local venting = ((((self.state == "rest") or (self.state == "ignite")) or ((self.state == "landed") and (self.timer > 30))) or ((self.state == "release") and (self.alt <= (s.mount / 2))))
if truth(venting) then
local p = (((0.16 + (math.min(60, self.coverageBoost) * 0.01)) + (if truth(smoky) then 0.25 else 0)) * (if truth(self.tall) then 1 else 0.6))
local sp = s.fly
local from, to = unpack(self:partRows(self.part))
for _, tuple in ipairs(s.vents) do
local col, row, dir = unpack(tuple)
if (((row < from) or (row >= to)) or (r:f() >= p)) then
continue
end
self:spawn((((self.ox + self.pos) + col) + (dir * 0.5)), (self:apx() + ((sp.h - 1) - row)), ((dir * (0.12 + (r:f() * 0.3))) * (if truth(self.tall) then 1 else 0.7)), (-(0.02 + (r:f() * 0.05))), (22 + (r:f() * 26)), 0.5, ((if truth(self.tall) then 2.2 else 1.1) * (0.7 + (r:f() * 0.6))), (if truth(smoky) then 9079438 else (if truth((self.tint == "blue")) then 12376319 else 15922939)), 0.7)
end
end
if (self.boom > 0) then
if (self.boom < 5) then
for k = 0, (if truth(self.tall) then 10 else 4), 1 do
if not ((k < (if truth(self.tall) then 10 else 4))) then break end
local hot = r:f()
self:spawn((cx + ((r:f() - 0.5) * s.stage)), (1 + (r:f() * 2)), (((r:f() - 0.5) * 1.2) * scale), (0.2 + (r:f() * 0.8)), (14 + (r:f() * 16)), s.puff[(0) + 1], (s.puff[(1) + 1] * 1.4), (if truth((hot < 0.3)) then 16773824 else (if truth((hot < 0.7)) then 16751146 else 14172202)), 1)
end
end
self.boom = (if truth((self.boom > 30)) then 0 else (self.boom + 1))
end
if ((((truth(self.look.catches) and (self.part == "upper")) and (self.burn > 6)) and (self.burn < 84)) and (self.flop > 0.5)) then
local len = s.stage
local mid = ((self:apx() + (s.fly.h - s.stage)) + (s.stage / 2))
for k = 0, (if truth(self.tall) then 4 else 2), 1 do
if not ((k < (if truth(self.tall) then 4 else 2))) then break end
local hot = r:f()
self:spawn((cx + (((r:f() - 0.5) * len) * 2)), (((mid - (s.bodyW / 2)) - 1) - r:f()), ((r:f() - 0.5) * 0.4), (0.5 + (r:f() * 1.1)), (6 + (r:f() * 8)), 0.5, 1.2, (if truth((hot < 0.4)) then 16734880 else (if truth((hot < 0.75)) then 16742954 else 16761962)), 0.85)
end
end
if (((self.part == "capsule") and (self.burn > 28)) and (self.burn < 88)) then
local n = (if truth(((self.burn > 40) and (self.burn < 75))) then 4 else 2)
for k = 0, n, 1 do
if not ((k < n)) then break end
local hot = r:f()
self:spawn((cx + (((r:f() - 0.5) * s.bodyW) * 1.5)), (A + (r:f() * 3)), ((r:f() - 0.5) * 0.6), (0.6 + (r:f() * 1.2)), (8 + (r:f() * 10)), 0.5, 1.2, (if truth((hot < 0.35)) then 16734880 else (if truth((hot < 0.7)) then 16742954 else 16761962)), 0.9)
end
end
if (self.splash > 0) then
local n = (if truth((self.splash < 3)) then (if truth(self.tall) then 18 else 8) else (if truth(((self.splash < 40) and (r:f() < 0.3))) then 1 else 0))
for k = 0, n, 1 do
if not ((k < n)) then break end
local side = (if truth((r:f() < 0.5)) then (-1) else 1)
self:spawn((cx + (side * ((s.bodyW / 2) + (r:f() * 2)))), 0, ((side * (0.2 + (r:f() * 0.6))) * scale), (0.3 + (r:f() * (if truth(self.tall) then 0.9 else 0.4))), (10 + (r:f() * 14)), 0.6, (s.puff[(1) + 1] * 0.6), 15660799, 0.9)
end
self.splash = (if truth((self.state == "landed")) then (self.splash + 1) else 0)
end
if (((truth(smoky) and (self.state == "fly")) and (self.orbit <= 0.3)) and (r:f() < 0.4)) then
self:spawn(cx, (A - 1), ((r:f() - 0.5) * 0.4), (-0.1), (25 + (r:f() * 20)), s.puff[(0) + 1], s.puff[(1) + 1], 5592410, 0.75)
end
if (((self.state == "fly") and (self:target() > 0)) and (self.tint ~= "normal")) then
self.base = ((2 * ((self:scroll() + self.rows) - 2)) + 1)
local px, py, th, sc = unpack(self:pose(s.fly))
local sn = math.sin(th)
local cs = math.cos(th)
local reach = (s.fly.h * sc)
local ride = (math.max(0, self.v) * 2)
if (truth(smoky) and (r:f() < 0.7)) then
local yh = (self.base - (py + ((reach * cs) / 2)))
local drift = (((if truth((r:f() < 0.5)) then (-1) else 1) * cs) * (0.2 + (r:f() * 0.5)))
self:spawn(((px - (reach * sn)) + ((r:f() - 0.5) * 2)), yh, (drift - (sn * (0.3 + (r:f() * 0.5)))), (ride - (cs * 0.05)), (18 + (r:f() * 14)), s.puff[(0) + 1], (s.puff[(1) + 1] * 1.3), 6052962, 0.85)
else
if (not (truth(smoky)) and (r:f() < 0.6)) then
local side = (if truth((r:f() < 0.5)) then (-1) else 1)
local at = (0.55 + (r:f() * 0.35))
local yh = (self.base - (py - (((reach * at) * cs) / 2)))
self:spawn(((px + ((reach * at) * sn)) + ((side * cs) * 1.5)), yh, ((side * cs) * (0.5 + (r:f() * 0.4))), (ride - ((side * sn) * 0.3)), (9 + (r:f() * 6)), 0.8, s.puff[(1) + 1], 15003903, 1)
end
end
end
end
function LaunchSite:paint(x, yh, color, a)

self:paintP(x, (self.base - yh), color, a)
end
function LaunchSite:paintP(x, py, color, a)

x = (math.floor(x) - self:viewX())
if (((((x < 0) or (x >= self.pw)) or (py < 0)) or (py >= self.ph)) or (a <= 0.03)) then
return
end
local k = ((py * self.pw) + x)
local old = self.pa[(k) + 1]
if (a >= 1) then
self.pc[(k) + 1] = js.u32(color)
self.pa[(k) + 1] = js.f32(1)
else
if (old == 0) then
self.pc[(k) + 1] = js.u32(color)
self.pa[(k) + 1] = js.f32(a)
else
self.pc[(k) + 1] = js.u32(mix(self.pc[(k) + 1], color, a))
self.pa[(k) + 1] = js.f32((old + (a * (1 - old))))
end
end
local cell = ((js.sar(py, 1) * self.columns) + js.sar(x, 1))
if not (truth(self.touched[(cell) + 1])) then
self.touched[(cell) + 1] = js.u8(1)
self.list[(self.nTouched) + 1] = js.i32(cell)
self.nTouched = self.nTouched + 1
end
end
function LaunchSite:siteHidden()

return (truth(self.boosterOnly) and not (truth(self.look.catches)))
end
function LaunchSite:drawVehicle(out, _top)

self:geo()
self.base = ((2 * ((self:scroll() + self.rows) - 2)) + 1)
if not (truth(self:siteHidden())) then
self:drawTower()
self:drawMount()
end
self:drawEarth(out)
self:drawParticles()
if (self.orbit > 0.02) then
self:drawTiltedPlume()
else
self:drawPlume()
end
self:drawRocket()
if truth(self.look.catches) then
self:drawArms()
end
if not (truth(self:siteHidden())) then
self:drawLights()
end
self:composite(out)
end
function LaunchSite:drawTower()

local s = self.spec
local tw = s.towerW
local col = self.look.tower
local mz = self.look.mechazilla
local top = math.min((s.towerH - 1), self.base)
for y = math.max(0, ((self.base - self.ph) + 1)), top, 1 do
if not ((y <= top)) then break end
local x0 = self.tx
self:paint(x0, y, col, 1)
self:paint(((x0 + tw) - 1), y, col, 1)
if (truth(mz) and (tw >= 6)) then
local t = js.mod(y, (tw - 2))
self:paint(((x0 + 1) + t), y, col, 1)
self:paint((((x0 + tw) - 2) - t), y, col, 1)
else
if (not (truth(mz)) and (js.mod(y, 4) == 0)) then
for x = 1, (tw - 1), 1 do
if not ((x < (tw - 1))) then break end
self:paint((x0 + x), y, col, 1)
end
else
self:paint(((x0 + 1) + js.mod(y, (tw - 2))), y, col, 0.85)
end
end
end
if truth(self.tall) then
local rx = (self.tx + (if truth(mz) then js.sar(tw, 1) else (tw - 1)))
for y = s.towerH, (s.towerH + (if truth(mz) then 4 else 2)), 1 do
if not ((y < (s.towerH + (if truth(mz) then 4 else 2)))) then break end
self:paint(rx, y, 9080985, 1)
end
if truth(mz) then
local ay = js.round(self.armY)
for y = (ay - 1), (ay + s.armThick), 1 do
if not ((y <= (ay + s.armThick))) then break end
for x = 0, tw, 1 do
if not ((x < tw)) then break end
self:paint((self.tx + x), y, self.look.carriage, 1)
end
end
end
if (s.service ~= nil) then
local y = (s.mount + ((s.fly.h - 1) - s.service))
local full = (self.tx - (self.bodyPx + s.bodyW))
local len = math.max(1, js.round((full * self.service)))
for x = 1, len, 1 do
if not ((x <= len)) then break end
self:paint((self.tx - x), y, self.look.tower, 1)
end
self:paint((self.tx - 1), (y - 1), self.look.tower, 0.8)
end
end
end
function LaunchSite:drawMount()

local m = self.spec.mount
if (m <= 0) then
return
end
local l = (self.bodyPx - 2)
local r = ((self.bodyPx + self.spec.bodyW) + 1)
local col = 8423055
for x = l, r, 1 do
if not ((x <= r)) then break end
self:paint(x, (m - 1), col, 1)
end
for y = 0, (m - 1), 1 do
if not ((y < (m - 1))) then break end
self:paint(l, y, col, 1)
self:paint(r, y, col, 1)
end
end
function LaunchSite:drawParticles()

for i = 0, PMAX, 1 do
if not ((i < PMAX)) then break end
local life = self.life[(i) + 1]
if (life <= 0) then
continue
end
local f = (1 - (life / self.maxLife[(i) + 1]))
local rad = (self.r0[(i) + 1] + ((self.r1[(i) + 1] - self.r0[(i) + 1]) * math.sqrt(f)))
local a = (self.a0[(i) + 1] * (1 - f))
local cx = js.round(self.px[(i) + 1])
local cy = js.round(self.py[(i) + 1])
local color = self.pcol[(i) + 1]
if (rad < 0.8) then
self:paint(cx, cy, color, a)
continue
end
local rx = math.floor(rad)
local ry = math.floor((rad / 2))
local inv = (1 / (rad * rad))
local under = mix(color, 9344414, 0.3)
for dy = (-ry), ry, 1 do
if not ((dy <= ry)) then break end
for dx = (-rx), rx, 1 do
if not ((dx <= rx)) then break end
local d2 = (((dx * dx) + ((4 * dy) * dy)) * inv)
if (d2 > 1) then
continue
end
self:paint((cx + dx), (cy + dy), (if truth((dy < 0)) then under else color), (a * (1 - (0.6 * d2))))
end
end
end
end
function LaunchSite:drawPlume()

local len = self:plumeLen()
if (len < 0.5) then
return
end
local s = self.spec
local ramp = self:ramp()
local A, cx, wk = unpack(self:nozzle())
local spread = (0.08 + math.min(0.45, (self.alt / 180)))
local t = self.t
for d = 0, len, 1 do
if not ((d < len)) then break end
local y = ((A - 1) - d)
local half = (((s.bodyW / 2) * wk) + (d * spread))
if (y < 0) then
self:deflect(cx, half, (len - d), ramp)
break
end
local k = (d / len)
local diamond = (if truth(((truth(self.tall) and (js.mod(d, 5) == 2)) and (k < 0.6))) then 0.15 else 0)
local xa = math.ceil((cx - half))
local xb = math.floor((cx + half))
for x = xa, xb, 1 do
if not ((x <= xb)) then break end
local edge = (math.abs((x - cx)) / (half + 0.5))
local n = (hash(x, (d + (t * 7)), 47) - 0.5)
local heat = ((((1 - (0.85 * k)) - ((0.45 * edge) * edge)) + diamond) + (n * 0.15))
local a = math.min(1, ((((1 - k) * 2.4) - (edge * 0.35)) + (n * 0.4)))
self:paint(x, y, rampColor(ramp, heat), a)
end
end
end
function LaunchSite:deflect(cx, half, rest, ramp)

local reach = ((rest * 1.4) + 2)
local t = self.t
for side = (-1), 1, 2 do
if not ((side <= 1)) then break end
for s = 0, reach, 1 do
if not ((s <= reach)) then break end
local x = js.round((cx + (side * (half + s))))
local k = (s / reach)
local n = (hash(x, t, 53) - 0.5)
local heat = ((0.85 - (0.75 * k)) + (n * 0.2))
local a = ((1 - (k * 0.85)) + (n * 0.3))
self:paint(x, 0, rampColor(ramp, heat), a)
if (k > 0.3) then
self:paint(x, 1, rampColor(ramp, (heat - 0.25)), (a * 0.6))
end
end
end
end
function LaunchSite:pose(sp, posX, turned)
if posX == nil then posX = self.pos end
if turned == nil then turned = true end
local o = self.orbit
local cx = ((self.ox + posX) + (sp.w / 2))
local cy = ((((self.base - self:apx()) - sp.h) + 1) + (sp.h / 2))
if (((o <= 0) and truth(turned)) and ((self.flop > 0) or (self.lean ~= 0))) then
local th = (((-(math.pi / 2)) * self.flop) + self.lean)
local r0, r1 = unpack(self:partRows(self.part))
local off = ((sp.h / 2) - ((r0 + r1) / 2))
local sn = math.sin(th)
local cs = math.cos(th)
return {(cx - ((2 * off) * sn)), ((cy - off) + (off * cs)), th, 1}
end
if (o <= 0) then
return {cx, cy, 0, 1}
end
local k = ((o * o) * (3 - (2 * o)))
local ocx = ((self.pw / 2) + (if truth(self.tall) then 0 else (-2)))
local ocy = ((self.ph - (if truth(self.splitTall) then (2 * self.splitW) else 0)) * (if truth(self.tall) then 0.42 else 0.36))
local room = (self.pw - (if truth(self.splitTall) then 0 else (2 * self.splitW)))
local sc = (if truth(self.tall) then (1 - (k * (1 - math.min(0.85, ((room - 7) / ((2 * sp.h) * math.max(0.3, math.sin(self.tilt)))))))) else 1)
local r0, r1 = unpack(self:partRows(self.part))
local off = ((sp.h / 2) - ((r0 + r1) / 2))
local sn = math.sin(self.tilt)
local cs = math.cos(self.tilt)
return {(cx + (((ocx - (((2 * off) * sn) * sc)) - cx) * k)), (cy + (((ocy + ((off * cs) * sc)) - cy) * k)), self.tilt, sc}
end
function LaunchSite:partRows(part)

local s = self.spec
local dr = (if s.dragon == nil then 0 else s.dragon)
local cap = (if s.capsule == nil then 0 else s.capsule)
repeat
if part == "upper" then
return {0, s.stage}
elseif part == "booster" then
return {s.stage, s.fly.h}
elseif part == "dragon" then
return {0, dr}
elseif part == "capsule" then
return {0, cap}
elseif part == "trunk" then
return {cap, dr}
elseif part == "stage2" then
return {dr, s.stage}
else
return {0, s.fly.h}
end
until true
end
function LaunchSite:drawRocket()

local s = self.spec
local sp = (if truth((self.part == "booster")) then self:boosterSprite() else s.fly)
self:drawBody(sp, self.part, 0, (if truth((self.part == "booster")) then self.fadeIn else 1))
local g = self.ghost
if truth(g) then
self:drawBody(s.fly, g.part, g.d, (g.life / g.max))
end
local catches = self.look.catches
if (self.state == "pan") then
self:drawBody(s.fly, "full", (s.mount - self:apx()), 1, 0, true)
else
if (((truth(catches) and (self.part == "upper")) and truth(self.boosterHome)) and (self.orbit < 0.01)) then
self:drawBody(s.fly, "booster", (s.mount - self:apx()), 1, 0, true)
else
if ((truth(catches) and (self.part == "booster")) and (self.state == "stack")) then
self:drawBody(s.fly, "upper", self.stackOff, 1, self.shipX, true)
end
end
end
self:drawCarrier()
self:drawChutes()
end
function LaunchSite:drawChutes()

if (not (truth(self.chute)) or (self.chuteOpen <= 0)) then
return
end
local s = self.spec
local k = self.chuteOpen
local top = ((self:apx() + s.fly.h) - 1)
local cx = ((((self.ox + self.pos) + s.bodyL) + (s.bodyW / 2)) - 0.5)
local mains = (self.chute == 2)
local tall = self.tall
local rise = js.round(((if truth(mains) then (if truth(tall) then 9 else 3) else (if truth(tall) then 5 else 2)) * (0.5 + (0.5 * k))))
local spread = (if truth(mains) then (if truth(tall) then {(-6), (-2), 2, 6} else {(-1.5), 1.5}) else (if truth(tall) then {(-2), 2} else {0}))
local half = math.max(1, js.round(((if truth(mains) then (if truth(tall) then 2 else 1.5) else 1) * k)))
local riser = 12765135
for _, off in ipairs(spread) do
local x = js.round((cx + (off * k)))
local y = (top + rise)
if truth(tall) then
for i = 1, rise, 1 do
if not ((i < rise)) then break end
local f = (i / rise)
self:paint(js.round((cx + ((x - cx) * f))), (top + i), riser, 0.7)
end
end
for dx = (-half), half, 1 do
if not ((dx <= half)) then break end
local c = (if truth((truth(mains) and truth(js.mod((x + dx), 2)))) then 15229994 else 15922165)
self:paint((x + dx), y, c, 1)
if ((math.abs(dx) < half) or (half == 1)) then
self:paint((x + dx), (y + 1), c, 1)
end
end
end
end
function LaunchSite:drawCarrier()

local cx = self.carrierX
if not (truth(finite(cx))) then
return
end
local s = self.spec
local x0 = js.round((((self.ox + cx) + s.bodyL) - 3))
local x1 = ((x0 + s.bodyW) + 5)
local sea = (math.floor(((x0 + x1) / 4)) < self:shore())
for x = x0, x1, 1 do
if not ((x <= x1)) then break end
self:paint(x, 1, (if truth(sea) then 6975352 else 8028040), 1)
if truth(sea) then
self:paint(x, 0, 2895926, 1)
else
if (js.band((x - x0), 1) == 0) then
self:paint(x, 0, 1711136, 1)
end
end
end
if truth(sea) then
self:paint(x1, 2, 9080985, 1)
self:paint(x1, 3, 9080985, 1)
self:paint((x1 - 1), 2, 9080985, 1)
end
end
function LaunchSite:drawBody(sp, part, d, alpha, posX, upright)
if posX == nil then posX = self.pos end
if upright == nil then upright = false end
if (alpha <= 0.03) then
return
end
local s = self.spec
local r0, r1 = unpack(self:partRows(part))
local frost = (truth(self.look.mechazilla) and ((self.state == "rest") or (self.state == "ignite")))
local cx0, cy0, th, sc = unpack(self:pose(sp, posX, not truth(upright)))
local cs = math.cos(th)
local sn = math.sin(th)
local cx = (cx0 + (((2 * d) * sn) * sc))
local cy = (cy0 - ((d * cs) * sc))
local rx = (math.ceil(((((math.abs(cs) * sp.w) / 2) + (math.abs(sn) * sp.h)) * sc)) + 1)
local ry = (math.ceil(((((math.abs(sn) * sp.w) / 4) + ((math.abs(cs) * sp.h) / 2)) * sc)) + 1)
local inv = (1 / sc)
local burning = (((d == 0) and (part == self.part)) and (self.thr > 0))
local heat = (if truth(((((part == "capsule") or (part == "dragon")) and (self.burn > 20)) and (self.burn < 95))) then math.sin(((math.pi * (self.burn - 20)) / 75)) else 0)
local baseHeat = (if truth((((((part == "booster") and truth(self.boosterOnly)) and not (truth(self.look.catches))) and (self.state == "fly")) and (self.staged == 5))) then 0.5 else 0)
local shipHeat = (if truth(((((part == "upper") and truth(self.look.catches)) and (self.burn > 0)) and (self.burn < 90))) then math.sin(((math.pi * self.burn) / 90)) else 0)
local tilesTo = (s.bodyL + math.floor((s.bodyW / 2)))
for py = math.floor((cy - ry)), math.ceil((cy + ry)), 1 do
if not ((py <= math.ceil((cy + ry)))) then break end
if ((py < 0) or (py >= self.ph)) then
continue
end
local uy = (((py + 0.5) - cy) * 2)
for px = math.floor((cx - rx)), math.ceil((cx + rx)), 1 do
if not ((px <= math.ceil((cx + rx)))) then break end
local ux = ((px + 0.5) - cx)
local col = math.floor(((((ux * cs) + (uy * sn)) * inv) + (sp.w / 2)))
local row = math.floor(((((((-ux) * sn) + (uy * cs)) * inv) / 2) + (sp.h / 2)))
if ((((col < 0) or (col >= sp.w)) or (row < r0)) or (row >= r1)) then
continue
end
local c = sp.c[(((row * sp.w) + col)) + 1]
if (c < 0) then
continue
end
if (heat > 0) then
c = mix(c, 16742954, math.min(0.9, (heat * (0.4 + ((0.6 * (row - r0)) / math.max(1, (r1 - r0)))))))
end
if (shipHeat > 0) then
c = mix(c, (if truth((col < tilesTo)) then 16738858 else 16756848), (shipHeat * (if truth((col < tilesTo)) then 0.85 else 0.35)))
end
if ((baseHeat > 0) and (row >= (r1 - 3))) then
c = mix(c, 14172202, (baseHeat * (1 - (((r1 - 1) - row) / 3))))
end
if (((truth(burning) and (row == (r1 - 1))) and (col >= s.bodyL)) and (col < (s.bodyL + s.bodyW))) then
c = mix(c, (if truth((self.tint == "blue")) then 9224447 else 16761962), math.min(0.95, (self.thr * 1.4)))
end
if (((truth(frost) and (row > (sp.h * 0.6))) and (row < (sp.h - 2))) and (hash(col, row, 61) < 0.55)) then
c = mix(c, 16054524, 0.6)
end
self:paintP(px, py, c, alpha)
end
end
end
function LaunchSite:drawTiltedPlume()

local len = self:plumeLen()
if (len < 0.5) then
return
end
local s = self.spec
local sp = s.fly
local cx, cy, th, sc = unpack(self:pose(sp))
local cs = math.cos(th)
local sn = math.sin(th)
local ramp = self:ramp()
local aft = ((2 * self:partRows(self.part)[(1) + 1]) - sp.h)
local tx = (cx - ((aft * sn) * sc))
local ty = ((cy * 2) + ((aft * cs) * sc))
local L = ((len * 2) * sc)
local wk = self:nozzle()[(2) + 1]
for d = 0.5, L, 1 do
if not ((d < L)) then break end
local k = (d / L)
local half = ((((s.bodyW / 2) * wk) * sc) + (d * 0.12))
for e = (-half), half, 0.75 do
if not ((e <= half)) then break end
local x = math.floor(((tx - (sn * d)) + (cs * e)))
local y = math.floor((((ty + (cs * d)) + (sn * e)) / 2))
local edge = (math.abs(e) / (half + 0.5))
local n = (hash(x, (y + (self.t * 7)), 47) - 0.5)
local heat = (((1 - (0.85 * k)) - ((0.45 * edge) * edge)) + (n * 0.15))
self:paintP(x, y, rampColor(ramp, heat), (math.min(1, ((((1 - k) * 1.6) - (edge * 0.4)) + (n * 0.3))) * (if truth((self.tint == "normal")) then 0.55 else 0.85)))
end
end
end
function LaunchSite:drawEarth(out)

local o = self.orbit
if (o <= 0.01) then
return
end
local w = self.columns
local h = self.rows
local ph = self.ph
local h0 = (if truth(self.tall) then 6 else 2)
local h1 = (if truth(self.tall) then 2.5 else 0.4)
local ex = math.floor(self.earthX)
for c = 0, w, 1 do
if not ((c < w)) then break end
local rel = (((c + 0.5) - (w / 2)) / (w / 2))
local top = ((ph - (h0 - (((h0 - h1) * rel) * rel))) / 2)
local rc = math.min((h - 1), math.floor(top))
local eighths = math.max(0, math.min(8, math.floor(((((rc + 1) - top) * 8) + hash(c, 0, 73)))))
local i = ((rc * w) + c)
local behind = out:background(i)
local limb = mix(LIMB, OCEAN, (math.max(0, ((eighths - 2) / 6)) * 0.65))
out:set(i, lowerBlock(eighths), mix(behind, limb, o), behind)
for y = (2 * (rc + 1)), ph, 1 do
if not ((y < ph)) then break end
for x = (2 * c), ((2 * c) + 2), 1 do
if not ((x < ((2 * c) + 2))) then break end
local n = hash(js.sar((x + ex), 1), y, 71)
local m = hash(js.sar(((x + ex) + 1), 2), js.sar(y, 1), 72)
self:paintP(x, y, (if truth(((n < 0.16) or (m < 0.12))) then 14542576 else (if truth((m > 0.86)) then 5012293 else OCEAN)), o)
end
end
end
end
function LaunchSite:drawArms()

local s = self.spec
local ay = js.round(self.armY)
local start = (self.tx - 1)
local tip = (((self.bodyPx + self.armX) - 1) - (if truth((truth(self.look.mechazilla) and truth(self.tall))) then 2 else 0))
local full = ((start - tip) + 1)
local len = (s.armStub + js.round((self.reach * (full - s.armStub))))
local col = self.look.arm
for t = 0, s.armThick, 1 do
if not ((t < s.armThick)) then break end
for x = 0, len, 1 do
if not ((x < len)) then break end
self:paint((start - x), (ay + t), col, 1)
end
end
if ((self.reach >= 1) and truth(self.tall)) then
self:paint(tip, (ay - 1), col, 1)
self:paint(tip, (ay + s.armThick), col, 1)
end
end
function LaunchSite:drawLights()

local s = self.spec
local blue = (self.tint == "blue")
local top = (if truth(self.tall) then (s.towerH + (if truth(self.look.mechazilla) then 4 else 2)) else (s.towerH - 1))
local tx = (if truth(self.tall) then (self.tx + (if truth(self.look.mechazilla) then js.sar(s.towerW, 1) else (s.towerW - 1))) else ((self.tx + s.towerW) - 1))
local t = self.t
local dim = (if truth((self.tint == "smoke")) then 0.45 else 1)
if (js.mod(t, 24) < 6) then
self:paint(tx, top, (if truth(blue) then LIGHT.blue else LIGHT.red), dim)
end
if truth(blue) then
do
local y = 2
local k = 0
local first = true
while true do
if not first then
y = (y + (if truth(self.tall) then 6 else 3))
k = k + 1
end
first = false
if not truth((y < (top - 1))) then break end
if (js.mod((t + (k * 5)), 24) < 14) then
self:paint((self.tx + (if truth(js.band(k, 1)) then 0 else (s.towerW - 1))), y, LIGHT.blue, 1)
end
end
end
end
if (self.kWait > 0) then
do
local y = 2
local k = 0
local first = true
while true do
if not first then
y = (y + (if truth(self.tall) then 6 else 3))
k = k + 1
end
first = false
if not truth((y < (top - 1))) then break end
self:paint((self.tx + (if truth(js.band(k, 1)) then 0 else (s.towerW - 1))), y, LIGHT.amber, (self.kWait * (0.25 + (0.75 * breath(t)))))
end
end
end
local extra = (if truth((self.coverageBoost <= 0)) then 0 else (if truth((self.coverageBoost < 30)) then 1 else 2))
for k = 1, extra, 1 do
if not ((k <= extra)) then break end
if (js.mod((t + (k * 8)), 24) >= 6) then
continue
end
local y = js.round(((s.towerH * (3 - k)) / 4))
self:paint((self.tx + (if truth(js.band(k, 1)) then 0 else (s.towerW - 1))), y, (if truth(blue) then LIGHT.blue else (if truth((k == 1)) then LIGHT.amber else LIGHT.green)), dim)
end
end
function LaunchSite:composite(out)

local w = self.columns
local pw = self.pw
local q = self.quad
for n = 0, self.nTouched, 1 do
if not ((n < self.nTouched)) then break end
local cell = self.list[(n) + 1]
self.touched[(cell) + 1] = js.u8(0)
local r = js.bor((cell / w), 0)
local c = (cell - (r * w))
local behind = out:behind(cell)
local k0 = (((2 * r) * pw) + (2 * c))
for p = 0, 4, 1 do
if not ((p < 4)) then break end
local k = ((k0 + (if truth(js.band(p, 2)) then pw else 0)) + js.band(p, 1))
local a = self.pa[(k) + 1]
q[(p) + 1] = (if truth((a == 0)) then behind else (if truth((a >= 1)) then self.pc[(k) + 1] else mix(behind, self.pc[(k) + 1], a)))
self.pa[(k) + 1] = js.f32(0)
end
local f = self.fit
fitQuad(q, f, math.huge)
if (f.spread == 0) then
out:set(cell, 32, DEFAULT_COLOR, q[(0) + 1])
else
out:set(cell, QUAD[(f.mask) + 1], f.fg, f.bg)
end
end
self.nTouched = 0
end
end
