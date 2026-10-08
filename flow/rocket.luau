--!strict
-- Port of Flow's hooks/rocket.ts (MIT, Rob Macrae).
local js = require('./js')
local cells = require('./cells')
local Rng, DEFAULT_COLOR = cells.Rng, cells.DEFAULT_COLOR
local clouds = require('./clouds_layered')
local layered, snap = clouds.layered, clouds.snap
local night = require('./night')
local STAR, STAR_DIM = night.STAR, night.STAR_DIM
local pixels = require('./pixels')
local fitQuad, g, hash, lowerBlock, mix, QUAD = pixels.fitQuad, pixels.g, pixels.hash, pixels.lowerBlock, pixels.mix, pixels.QUAD
local SkyWorld = require('./sky').SkyWorld
local hear = require('./sound').hear
local waiting = require('./waiting')
local breath, waitTone = waiting.breath, waiting.waitTone
local function truth(v) return v ~= nil and v ~= false and v ~= 0 and v ~= '' and v == v end
local function finite(v) return v == v and v ~= math.huge and v ~= -math.huge end
local function truncate(a, n) for i = #a, n + 1, -1 do a[i] = nil end end
local function fill(a, v) for i = 1, #a do a[i] = v end return a end
local function findIndex(a, f) for i, v in ipairs(a) do if truth(f(v)) then return i - 1 end end return -1 end
local function concat(...) local a = {} for _, part in ipairs({...}) do for _, v in ipairs(part) do table.insert(a, v) end end return a end








local ceilEven = function(n) return (n + js.band(n, 1)) end

local function sprite(rows, pal)
local h = #rows
local w = #rows[(0) + 1]
local c = table.create((w * h), (-1))
for y = 0, h, 1 do
if not ((y < h)) then break end
for x = 0, w, 1 do
if not ((x < w)) then break end
local p = pal[string.sub(rows[(y) + 1], (x) + 1, (x) + 1)]
if (p ~= nil) then
c[(((y * w) + x)) + 1] = p
end
end
end
return {w = w, h = h, c = c}
end
local function firstRow(rows, ch)
return findIndex(rows, function(r) return string.find(r, ch, 1, true) end)
end
local FALCON_PAL = {W = 16053751, w = 12830928, K = 1908773, G = 3817030, L = 2895669, E = 7370109, H = 2763825, P = 2306394}
local STARSHIP_PAL = {k = 3948358, S = 14278114, s = 10725809, F = 2303531, D = 4145994, d = 9278363, B = 13094098, b = 10002344, G = 3422271, E = 5198682}
local FALCON_BAND = {"..Ww..", "..Ww..", "..KK..", ".GWwG.", "..Ww..", "..Ww..", "..KK.."}
local FALCON_BAND_LAND = {"..Ww..", "..Ww..", "..KK..", ".GWwG.", "..Ww..", "..Ww..", "L.KK.L"}
local FALCON_TALL_TOP = {"....Ww....", "...WWWw...", "...WWWw...", "...HHHH...", "...WPPw...", "...WWWw...", "...WWWw...", "...WWWw...", "...KKKK...", "...KKKK..."}
local FALCON_TALL_MID = table.create(12, "...WWWw...")
local FALCON_TALL = concat(FALCON_TALL_TOP, {"..GWWWwG.."}, FALCON_TALL_MID, {"...KWwK..."}, {"...KWwK..."}, {"...KWwK..."}, {"...KWwK..."}, {"...KKKK..."}, {"....EE...."})
local FALCON_TALL_FINS = concat(FALCON_TALL_TOP, {".GGWWWwGG."}, FALCON_TALL_MID, {"...KWwK..."}, {"...KWwK..."}, {"...KWwK..."}, {"...KWwK..."}, {"...KKKK..."}, {"....EE...."})
local FALCON_TALL_LAND = concat(FALCON_TALL_TOP, {".GGWWWwGG."}, FALCON_TALL_MID, {"..LWWWwL.."}, {"..LWWWwL.."}, {".L.WWWw.L."}, {".L.WWWw.L."}, {"L..KKKK..L"}, {"L...EE...L"})
local STARSHIP_BAND = {"..kS..", "FkSSsF", ".kSSs.", "FkSSsF", "GBBBbG", ".BBBb.", ".bbbb."}
local STARSHIP_TALL = concat({"....kS...."}, {"...kkSS..."}, {"..kkkSSs.."}, {".FkkkSSsF."}, {".FkkkSSsF."}, table.create(7, "..kkkSSs.."), {".FkkkSSsF."}, {"FFkkkSSsFF"}, {"FFkkkSSsFF"}, {"..kkkSSs.."}, {"..DDDDDD.."}, {"..DdDdDd.."}, {"GGBBBBBbGG"}, table.create(17, "..BBBBBb.."), {"..bbbbbb.."}, {"..EEEEEE.."})

local FALCON_SPECS = {{fly = sprite(FALCON_BAND, FALCON_PAL), fins = sprite(FALCON_BAND, FALCON_PAL), land = sprite(FALCON_BAND_LAND, FALCON_PAL), stage = firstRow(FALCON_BAND, "K"), dragon = 1, capsule = 1, bodyL = 2, bodyW = 2, grip = 1, mount = 0, towerW = 4, towerH = 8, armCatch = 6, armThick = 1, armStub = 1, plume = 7, vents = {{1, 1, (-1)}, {4, 1, 1}, {4, 5, 1}}, puff = {0.6, 2.2}}, {fly = sprite(FALCON_TALL, FALCON_PAL), fins = sprite(FALCON_TALL_FINS, FALCON_PAL), land = sprite(FALCON_TALL_LAND, FALCON_PAL), stage = firstRow(FALCON_TALL, "K"), dragon = (firstRow(FALCON_TALL, "P") + 1), capsule = firstRow(FALCON_TALL, "P"), bodyL = 3, bodyW = 4, grip = 16, mount = 0, towerW = 4, towerH = 38, armCatch = 33, armThick = 1, armStub = 2, plume = 22, vents = {{2, 6, (-1)}, {7, 5, 1}, {2, 25, (-1)}, {7, 26, 1}}, service = 3, puff = {1.2, 4}}}
local STARSHIP_SPECS = {{fly = sprite(STARSHIP_BAND, STARSHIP_PAL), fins = sprite(STARSHIP_BAND, STARSHIP_PAL), land = sprite(STARSHIP_BAND, STARSHIP_PAL), stage = firstRow(STARSHIP_BAND, "G"), bodyL = 1, bodyW = 4, grip = 1, mount = 0, towerW = 4, towerH = 8, armCatch = 6, armThick = 1, armStub = 1, plume = 7, vents = {{0, 2, (-1)}, {5, 2, 1}, {5, 5, 1}}, puff = {0.7, 2.4}}, {fly = sprite(STARSHIP_TALL, STARSHIP_PAL), fins = sprite(STARSHIP_TALL, STARSHIP_PAL), land = sprite(STARSHIP_TALL, STARSHIP_PAL), stage = firstRow(STARSHIP_TALL, "D"), bodyL = 2, bodyW = 6, grip = 18, mount = 4, towerW = 6, towerH = 50, armCatch = 40, armThick = 2, armStub = 3, plume = 26, vents = {{1, 9, (-1)}, {8, 7, 1}, {1, 31, (-1)}, {8, 33, 1}}, service = 8, puff = {1.4, 4.5}}}

local RAMPS = {merlin = {5905936, 13780506, 16748319, 16765527, 16776168}, raptor = {4856366, 14174250, 16751162, 16768143, 15922431}, blue = {1709648, 4930262, 4161023, 10275071, 15923455}, smoke = {3026478, 5855577, 8289400, 11050120, 14207144}}
local function rampColor(r, heat)
local h = (if truth((heat <= 0)) then 0 else (if truth((heat >= 1)) then 4 else (heat * 4)))
local i = math.min(3, js.bor(h, 0))
return mix(r[(i) + 1], r[((i + 1)) + 1], (h - i))
end

local PAD = {glyph = g("▀"), fg = 10132899, bg = 7040628}
local TRENCH = {glyph = g("▀"), fg = 4869200, bg = 7040628}
local SEA = {glyph = g("▀"), fg = 3833024, bg = 1920654}
local LIGHT = {red = 16726832, amber = 16756768, green = 6094714, blue = 4892927}
local IGNITE = 20
local CLOSE = 12
local STAGE_FRAMES = 14
local DEC = 0.03
local VMAX = 2.2
local VMAX_DOWN = 1.6
local ACC_DOWN = 0.025



local SEP_LAYER = 80
local LANDED_FRAMES = 42
local LAYER = {0, 0, 22, 32, 44, 56, 70, 86, 140, 140, 140}
local SPEED = {0, 0, 0.3, 0.42, 0.55, 0.7, 0.85, 1, 1, 1, 1}
local TILE = 14
local FADE = 3
local TILE_X = 397
local PAINT = 2
local CLOUD_LO = 11
local CLOUD_HI = 90
local TILT_BAND = {0.9, 1.27, (math.pi / 2)}
local TILT_TALL = {0.52, 1.27, (math.pi / 2)}
local ORBIT_SPEED = {1.6, 2.6, 3.8}
local ORBIT_BURN = {0.3, 0.2, 0}
local TINT_BURN = 0.6
local HEADROOM = 0.28
local GLYPH = {dot = g("·"), star = g("*"), vert = g("│"), horiz = g("─"), diag = g("╱"), top = g("▀")}
local PMAX = 384
local LIMB = 7124210
local OCEAN = 1920654
local LaunchSite = {}
LaunchSite.__index = LaunchSite
setmetatable(LaunchSite, {__index = SkyWorld})
function LaunchSite.new(seed)
local self = setmetatable(SkyWorld.new(seed), LaunchSite)
self.sounds = {}
self.staged = (-1)
self.sinceStage = STAGE_FRAMES
self.descending = false
self.state = "rest"
self.timer = 0
self.flyTime = 0
self.v = 0
self.thr = 0
self.armY = (-1)
self.reach = 0
self.service = 1
self.part = "full"
self.ghost = nil
self.fadeIn = 1
self.pos = 0
self.view = 0
self.lz = 0
self.shipX = 0
self.stackOff = 0
self.phase = 0
self.armX = 0
self.returning = false
self.twinSite = nil
self.splitW = 0
self.twinW = 0
self.twinDone = 0
self.twinDue = false
self.boosterOnly = false
self.boosterHome = false
self.boomed = false
self.splash = 0
self.carrierX = js.NaN
self.burn = 0
self.flop = 0
self.lean = 0
self.boom = 0
self.chute = 0
self.chuteOpen = 0
self.splitTall = false
self.twinH = 0
self.braking = false
self.layer = (-1)
self.wraps = 0
self.orbit = 0
self.starX = 0
self.starY = 0
self.starVX = 0
self.starVY = 0
self.earthX = 0
self.tilt = 0
self.orbitSpeed = 0
self.camP = 0
self.fresh = true
self.cFg = 0
self.cBg = 0
self.pw = 0
self.ph = 0
self.pc = table.create(0, 0)
self.pa = table.create(0, 0)
self.touched = table.create(0, 0)
self.list = table.create(0, 0)
self.nTouched = 0
self.base = 0
self.quad = table.create(4, 0)
self.fit = {mask = 0, fg = 0, bg = 0, spread = 0}
self.px = table.create(PMAX, 0)
self.py = table.create(PMAX, 0)
self.vx = table.create(PMAX, 0)
self.vy = table.create(PMAX, 0)
self.life = table.create(PMAX, 0)
self.maxLife = table.create(PMAX, 0)
self.r0 = table.create(PMAX, 0)
self.r1 = table.create(PMAX, 0)
self.a0 = table.create(PMAX, 0)
self.pcol = table.create(PMAX, 0)
self.nextP = 0
self.geoKey = (-1)
self.tall = false
self.ox = 0
self.bodyPx = 0
self.tx = 0
self.padL = 0
self.padR = 0
self.room = 0
self.rng = Rng.new((if seed == nil then os.time() * 1000 else seed) * 2654435761)
return self
end
function LaunchSite:ambience()

local own = self:ownAmbience()
local t = self.twinSite
if not (truth(t)) then
return own
end
local b = t:ownAmbience()
local roar = math.max(((if own.roar == nil then 0 else own.roar) * (1 - (if own.space == nil then 0 else own.space))), (if b.roar == nil then 0 else b.roar))
return {roar = roar, vent = math.max((if own.vent == nil then 0 else own.vent), (if b.vent == nil then 0 else b.vent)), wind = math.max((if own.wind == nil then 0 else own.wind), (if b.wind == nil then 0 else b.wind)), space = 0, sea = math.max((if own.sea == nil then 0 else own.sea), (if b.sea == nil then 0 else b.sea))}
end
function LaunchSite:ownAmbience()

local st = self.state
local p = self.part
local flying = (st == "fly")
local engines = (if truth(((p == "dragon") or (p == "capsule"))) then 0 else self.thr)
return {roar = engines, vent = (if truth(((((st == "rest") or (st == "ignite")) or (st == "landed")) or (st == "stack"))) then 1 else 0), wind = (if truth((truth(flying) and (self.orbit < 0.5))) then (math.min(1, (math.abs(self.v) / 1.2)) * (if truth(self.chute) then 0.4 else 1)) else 0), space = self.orbit, sea = (if truth(((((st == "landed") and ((p == "capsule") or (truth(self.look.catches) and not (truth(self.boosterOnly))))) or (st == "pan")) or ((st == "carry") and truth(self.look.catches)))) then 1 else 0)}
end
function LaunchSite:step()

local asked = math.max(0, math.min(10, js.round(self.strength)))
self.sinceStage = self.sinceStage + 1
if ((asked == 0) or (self.staged < 0)) then
self.staged = asked
self.descending = false
else
if (self.sinceStage >= STAGE_FRAMES) then
if (truth(self.descending) or ((asked <= 1) and (self.staged > 1))) then
self.staged = self.staged - 1
self.sinceStage = 0
self.descending = (self.staged > 1)
else
if ((asked > self.staged) and not (truth(self.waiting))) then
self.staged = self.staged + 1
self.sinceStage = 0
end
end
end
end
self.strength = self.staged
SkyWorld.step(self)
end
function LaunchSite:grid()

if ((self.staged >= 0) and (self.strength > 0)) then
self.strength = self.staged
end
local out = self:drawFrame()
waitTone(out, self.kWait, self.t)
return out
end
function LaunchSite:ensure(columns, rows)

SkyWorld.ensure(self, columns, rows)
if ((self.pw == (columns * 2)) and (self.ph == (rows * 2))) then
return
end
if (truth(self.twinSite) or truth(self.twinDue)) then
self.twinSite = nil
self.twinDue = false
self.splitW = 0
self.boosterHome = true
end
self.pw = (columns * 2)
self.ph = (rows * 2)
self.pc = table.create((self.pw * self.ph), 0)
self.pa = table.create((self.pw * self.ph), 0)
self.touched = table.create((columns * rows), 0)
self.list = table.create((columns * rows), 0)
self.nTouched = 0
end
function LaunchSite:seed(altitude)

SkyWorld.seed(self, altitude)
if (self.alt > 3) then
self.state = "fly"
self.v = 0.2
self.thr = 0.6
self.reach = 0
end
end
function LaunchSite:geo()

local key = ((self.columns * 65536) + self.rows)
if (key == self.geoKey) then
return
end
self.geoKey = key
self.tall = (self.rows >= 16)
local s = self.specs[((if truth(self.tall) then 1 else 0)) + 1]
self.spec = s
local ox0 = (-s.bodyL)
local tx0 = ceilEven((ox0 + s.fly.w))
local pw = (self.columns * 2)
local body
if truth(self.tall) then
body = (2 * js.round((((pw / 2) - (((ox0 + tx0) + s.towerW) / 2)) / 2)))
else
body = (2 * math.floor((self.columns * 0.42)))
end
body = math.max(((-ox0) + 2), math.min(body, (((pw - tx0) - s.towerW) - 2)))
self.bodyPx = ceilEven(body)
self.ox = (self.bodyPx + ox0)
self.tx = (self.bodyPx + tx0)
self.padL = math.floor(((self.ox - 2) / 2))
self.padR = math.floor((((self.tx + s.towerW) + 1) / 2))
self.lz = (if truth((truth(self.boosterOnly) and truth(self.look.catches))) then 0 else ((-2) * math.ceil((((pw - self.ox) + 4) / 2))))
if (self.state == "rest") then
self.alt = (s.mount / 2)
end
end
function LaunchSite:viewX()

return (2 * js.round(((self.view - (if truth(self.splitTall) then 0 else self.splitW)) / 2)))
end
function LaunchSite:seaX()

return (if truth(self.look.catches) then self.lz else (2 * self.lz))
end
function LaunchSite:shore()

if (not (truth(self.lz)) or truth(self.boosterOnly)) then
return (-1000000000)
end
return math.floor(((self.ox + ((self:seaX() + (if truth(self.look.catches) then 0 else self.lz)) / 2)) / 2))
end
function LaunchSite:lzL()

return math.floor(((self.ox + self.lz) / 2))
end
function LaunchSite:vehicleHeight()

self:geo()
return math.ceil((self.spec.fly.h / 2))
end
function LaunchSite:apx()

return js.round((self.alt * 2))
end
function LaunchSite:scroll()

self:geo()
return math.max(0, math.ceil(self:scrollExact()))
end
function LaunchSite:scrollExact()

return ((((((self:apx() + self:topRow()) + 2) + self:chuteRoom()) + js.round(self.camP)) - (2 * self.rows)) / 2)
end
function LaunchSite:topRow()

return (self.spec.fly.h - self:partRows(self.part)[(0) + 1])
end
function LaunchSite:chuteRoom()

return js.round(self.room)
end
function LaunchSite:groundFeature(x)

self:geo()
if ((x >= (math.min(self.padL, self:lzL()) - 3)) and (x <= (self.padR + 3))) then
return nil
end
if (x < self:shore()) then
return nil
end
return SkyWorld.groundFeature(self, x)
end
function LaunchSite:scenery(x, y, sky)

if (y == (-1)) then
self:geo()
if (((x >= self.padL) and (x <= self.padR)) and not (truth(self:siteHidden()))) then
local mid = js.sar((self.bodyPx + (self.spec.bodyW / 2)), 1)
return (if truth(((x == mid) or ((self.spec.bodyW > 2) and (x == (mid - 1))))) then TRENCH else PAD)
end
if (x < self:shore()) then
return {glyph = SEA.glyph, fg = mix(SEA.fg, 1057852, self:dark()), bg = mix(SEA.bg, 661032, self:dark())}
end
if (((not (truth(self.look.catches)) and truth(self.lz)) and (x >= self:lzL())) and (x <= (self:lzL() + math.ceil((self.spec.land.w / 2))))) then
return PAD
end
end
return SkyWorld.scenery(self, x, y, sky)
end
function LaunchSite:drawFrame()

local out = self.out
local w = self.columns
local h = self.rows
if (self.strength <= 0) then
for i = 0, (w * h), 1 do
if not ((i < (w * h))) then break end
out:blank(i)
end
return out
end
self:geo()
local scroll = self:scroll()
local exact = math.max(0, (((((((self.alt * 2) + self:topRow()) + 2) + self:chuteRoom()) + js.round(self.camP)) - (2 * h)) / 2))
local phi = (exact - scroll)
local layer = math.max(0, self.layer)
local skyShift = math.max(0, (self.alt - layer))
local a = (layer - (TILE / 2))
local o = self.orbit
local drift = math.floor(js.mod((self.t * 0.1), 100000))
local svx = math.abs(self.starVX)
local svy = (math.abs(self.starVY) * 2)
local starGlyph = (if truth(((svx + svy) < 0.7)) then 0 else (if truth((svx < (svy * 0.5))) then GLYPH.vert else (if truth((svy < (svx * 0.4))) then GLYPH.horiz else GLYPH.diag)))
local sx = math.floor(self.starX)
local sy = math.floor(self.starY)
local panC = (self:viewX() / 2)
local rb = self.rowBg
truncate(rb, h)
for r = 0, h, 1 do
if not ((r < h)) then break end
local y = ((scroll - 1) + ((h - 1) - r))
local yf = (y + phi)
local real = ((yf - a) < TILE)
local skyY = (yf - skyShift)
if ((skyY < 0) and (y >= 0)) then
skyY = 0
else
if (((skyShift > 0) and (skyY < 0)) and not ((truth(real) and (y < 0)))) then
skyY = 0
end
end
local bg = (if truth((truth(real) and (y < 0))) then self:skyAt(y) else self:skyAt(skyY))
if (o > 0) then
bg = mix(bg, 0, o)
end
rb[(r) + 1] = bg
local stars = (math.max((o * 1.3), math.min(1, ((skyY - 70) / 40)), (if truth(not truth((truth(real) and (y <= 0)))) then (0.5 * self:dark()) else 0)) * 0.04)
for x = 0, w, 1 do
if not ((x < w)) then break end
local i = ((r * w) + x)
if (truth(real) and (y <= 0)) then
local s = self:scenery((x + panC), y, bg)
if truth(s) then
out:set(i, s.glyph, s.fg, (if s.bg == nil then bg else s.bg))
else
out:set(i, 32, DEFAULT_COLOR, bg)
end
continue
end
if ((o < 0.98) and truth(self:foldedCloud(((x + drift) + panC), yf, a, bg))) then
local fg = snap((if truth((o > 0)) then mix(self.cFg, bg, o) else self.cFg), bg)
local cb = snap((if truth((o > 0)) then mix(self.cBg, bg, o) else self.cBg), bg)
if ((fg ~= bg) or (cb ~= bg)) then
out:set(i, GLYPH.top, fg, cb)
continue
end
end
if (stars > 0) then
local hs = hash(((x + sx) + panC), (r - sy), 7)
if (hs < stars) then
local bright = (if truth((hash(((x + sx) + panC), (r - sy), 8) < 0.5)) then STAR else STAR_DIM)
local glyph = (if starGlyph ~= 0 then starGlyph else (if truth((hs < (stars * 0.2))) then GLYPH.star else GLYPH.dot))
out:set(i, glyph, bright, bg)
continue
end
end
out:set(i, 32, DEFAULT_COLOR, bg)
end
end
self:drawMoon(out)
self:drawVehicle(out, 0)
self:drawSplit(out)
return out
end
function LaunchSite:drawSplit(out)

local t = self.twinSite
local n = js.round(self.splitW)
if (not (truth(t)) or (n <= 0)) then
return
end
local src = t:grid()
local W = self.columns
local H = self.rows
local fc, fr = unpack(t:focus())
if truth(self.splitTall) then
local from = math.max(0, math.min((self.twinH - n), js.round((fr - (n / 2)))))
do
local r = 0
local first = true
while true do
if not first then
r = r + 1
end
first = false
if not truth(((r < n) and (r < H))) then break end
for x = 0, W, 1 do
if not ((x < W)) then break end
local j = (((from + r) * self.twinW) + x)
out:set(((((H - n) + r) * W) + x), src:codePoint(j), src:foreground(j), src:background(j))
end
end
end
if (n < H) then
for x = 0, W, 1 do
if not ((x < W)) then break end
out:set(((((H - n) - 1) * W) + x), GLYPH.horiz, 9080985, 1316378)
end
end
return
end
local from = math.max(0, math.min((self.twinW - n), js.round((fc - (n / 2)))))
for r = 0, H, 1 do
if not ((r < H)) then break end
do
local x = 0
local first = true
while true do
if not first then
x = x + 1
end
first = false
if not truth(((x < n) and (x < W))) then break end
local j = (((r * self.twinW) + from) + x)
out:set(((r * W) + x), src:codePoint(j), src:foreground(j), src:background(j))
end
end
if (n < W) then
out:set(((r * W) + n), GLYPH.vert, 9080985, 1316378)
end
end
end
function LaunchSite:foldedCloud(x, yf, a, sky)

local u = (yf - a)
local k = (if truth((u < 0)) then (-1) else math.floor((u / TILE)))
local kk = math.max(0, k)
local cy = (yf - (kk * TILE))
local xs = ((kk + self.wraps) * TILE_X)
local has = self:cloud((x + xs), cy, sky)
if (k < 0) then
return has
end
local f = (u - (k * TILE))
local cy2
local xs2
local wgt
if ((k >= 1) and (f < FADE)) then
cy2 = (cy + TILE)
xs2 = (xs - TILE_X)
wgt = (0.5 + ((0.5 * f) / FADE))
else
if (f > (TILE - FADE)) then
cy2 = (cy - TILE)
xs2 = (xs + TILE_X)
wgt = (0.5 + ((0.5 * (TILE - f)) / FADE))
else
return has
end
end
local fg1 = (if truth(has) then self.cFg else sky)
local bg1 = (if truth(has) then self.cBg else sky)
local has2 = self:cloud((x + xs2), cy2, sky)
if (not (truth(has)) and not (truth(has2))) then
return false
end
local fg2 = (if truth(has2) then self.cFg else sky)
local bg2 = (if truth(has2) then self.cBg else sky)
self.cFg = mix(fg2, fg1, wgt)
self.cBg = mix(bg2, bg1, wgt)
return true
end
function LaunchSite:cloud(x, y, sky)

if ((y < CLOUD_LO) or (y > CLOUD_HI)) then
return false
end
local c = layered.cell({x = (x / PAINT), y = (y / PAINT), sky = sky, t = self.t})
if not (truth(c)) then
return false
end
self.cFg = self:cloudLight(c.fg, sky)
self.cBg = self:cloudLight((if c.bg == nil then sky else c.bg), sky)
return true
end
function LaunchSite:advance()

self:geo()
local s = self.spec
local rest = (s.mount / 2)
local catchAlt = ((s.armCatch - s.grip) / 2)
local home = (self:target() <= 0)
local lv = math.max(0, math.min(10, js.round(self.strength)))
local want = LAYER[(lv) + 1]
if truth(self.fresh) then
self.fresh = false
if (not (truth(home)) and (lv >= 2)) then
self:settle(lv, want, catchAlt)
end
end
if (self.layer < 0) then
self.layer = (if truth(home) then LAYER[(2) + 1] else want)
end
local catches = self.look.catches
local shipHome = (truth(catches) and not (truth(self.boosterOnly)))
local sea = ((-(s.fly.h - s.stage)) / 2)
local capSea = ((-(s.fly.h - (if s.capsule == nil then 0 else s.capsule))) / 2)
local goal = (if truth(shipHome) then sea else (if truth(catches) then catchAlt else rest))
local homeward = (truth(home) or truth(self.returning))
self:stepTwin()
local hurry = (if truth(home) then 1 else 3)
local restArm = (s.mount + s.grip)
local thrGoal = 0
local armGoal = restArm
self.timer = self.timer + 1
self.braking = false
if (self.fadeIn < 1) then
self.fadeIn = math.min(1, (self.fadeIn + 0.06))
end
local roomGoal = (if truth((truth(self.chute) or ((self.part == "capsule") and (self.state == "fly")))) then (if truth(self.tall) then 14 else 4) else 0)
self.room = (self.room + math.max((-0.5), math.min(0.5, (roomGoal - self.room))))
repeat
if self.state == "rest" then
self.alt = rest
self.v = 0
if (self.part == "full") then
self.returning = false
end
if truth(finite(self.carrierX)) then
self.carrierX = (self.carrierX + 2)
if (((self.ox + self.carrierX) - self:viewX()) > (self.pw + 4)) then
self.carrierX = js.NaN
end
end
self.reach = math.max(0, (self.reach - (1 / CLOSE)))
self.service = math.min(1, (self.service + 0.05))
if not (truth(home)) then
self:go("ignite")
hear(self.sounds, {kind = "ignite", v = 1})
end
break
elseif self.state == "ignite" then
self.alt = rest
self.layer = want
self.service = math.max(0, (self.service - 0.1))
thrGoal = (if truth((self.timer < 4)) then 0.15 else math.min(1, (self.timer / IGNITE)))
if truth(home) then
self:go("rest")
else
if (self.timer >= IGNITE) then
self:go("fly")
self.flyTime = 0
end
end
break
elseif self.state == "fly" then
do
self.flyTime = self.flyTime + 1
self.service = math.max(0, (self.service - 0.1))
if (truth(self.boosterOnly) and not (truth(home))) then
self.v = math.max((self.v - 0.02), (-1))
self.alt = (self.alt + self.v)
self.layer = (self.layer + math.max((-0.6), math.min(0.6, (want - self.layer))))
self:unfold()
if truth((if truth(catches) then (self.flyTime < 136) else ((self.staged == 4) and (self.sinceStage < 14)))) then
thrGoal = 0.5
end
if ((self.staged <= 3) and not (truth(self.boomed))) then
self.boomed = true
hear(self.sounds, {kind = "sonic", v = 1})
end
break
end
if not (truth(homeward)) then
local vGoal = ((SPEED[(lv) + 1] * (1 - (0.8 * self.orbit))) + (math.max(0, (want - self.layer)) * 0.012))
if (self.v < vGoal) then
self.v = math.min(vGoal, ((self.v + 0.006) + (math.min(self.flyTime, 120) * 0.0004)))
else
self.v = math.max(vGoal, (self.v - 0.02))
end
self.alt = (self.alt + self.v)
local rate = math.max(0.05, (0.6 * math.max(0, self.v)))
self.layer = (self.layer + math.max((-rate), math.min(rate, (want - self.layer))))
thrGoal = (1 - (self.orbit * (1 - ORBIT_BURN[(math.max(0, (lv - 8))) + 1])))
if (self.tint ~= "normal") then
thrGoal = math.max(thrGoal, TINT_BURN)
end
if ((self.part == "full") and (self.layer >= SEP_LAYER)) then
self:separate()
end
if ((truth(s.dragon) and (self.part == "upper")) and (self.orbit > 0.95)) then
self.part = "dragon"
self.ghost = {part = "stage2", d = 0, v = (-0.02), acc = (-0.008), life = 70, max = 70}
end
break
end
self.returning = true
if ((truth(shipHome) and (self.part == "upper")) and (self.burn < 100)) then
self.burn = self.burn + 1
local flat = (if truth((self.burn < 85)) then 0.67 else 1)
self.flop = (self.flop + math.max((-0.04), math.min(0.04, (flat - self.flop))))
thrGoal = 0
self.v = math.max((self.v - 0.03), (-1.2))
self.alt = (self.alt + self.v)
self.layer = (self.layer + math.max((-1.5), math.min(1.5, ((if truth((self.burn < 80)) then LAYER[(4) + 1] else LAYER[(2) + 1]) - self.layer))))
self:unfold()
local step = math.max(0.4, (math.abs((self.lz - self.pos)) / 80))
self.pos = (self.pos + math.max((-step), math.min(step, (self.lz - self.pos))))
self.view = self.pos
break
end
if ((self.part == "full") and not (truth(self.boosterOnly))) then
self:separate()
end
if (truth(s.dragon) and (((self.part == "upper") or (self.part == "dragon")) or (self.part == "capsule"))) then
self.burn = self.burn + 1
thrGoal = 0
if (self.part == "upper") then
self.part = "dragon"
self.ghost = {part = "stage2", d = 0, v = (-0.03), acc = (-0.012), life = 60, max = 60}
end
if ((self.part == "dragon") and (self.burn > 20)) then
self.part = "capsule"
self.ghost = {part = "trunk", d = 0, v = (-0.03), acc = (-0.015), life = 40, max = 40}
end
local step = math.max(0.4, (math.abs((self:seaX() - self.pos)) / 60))
self.pos = (self.pos + math.max((-step), math.min(step, (self:seaX() - self.pos))))
self.view = self.pos
self.lean = (self.lean + math.max((-0.02), math.min(0.02, ((if truth(((self.burn > 20) and (self.burn < 95))) then (-0.3) else 0) - self.lean))))
if (self.burn < 95) then
self.v = math.max((self.v - 0.03), (-1.2))
self.alt = (self.alt + self.v)
self.layer = (self.layer + math.max((-0.6), math.min(0.6, (LAYER[(5) + 1] - self.layer))))
self:unfold()
break
end
local want = (if truth((self.burn < 115)) then 1 else 2)
if (want ~= self.chute) then
self.chute = want
hear(self.sounds, {kind = "chute", v = (want / 2)})
self.chuteOpen = 0
end
self.chuteOpen = math.min(1, (self.chuteOpen + 0.06))
self.v = (self.v + math.max((-0.05), math.min(0.05, ((if truth((self.chute == 1)) then (-0.9) else (-0.6)) - self.v))))
self.alt = (self.alt + self.v)
if (self.layer > (LAYER[(2) + 1] + 1)) then
self.layer = (self.layer + math.max((-1.2), math.min(1.2, (LAYER[(2) + 1] - self.layer))))
self:unfold()
else
if (self.alt <= capSea) then
self.alt = capSea
self.v = 0
self.view = self:seaX()
self.pos = self.view
self.splash = 1
hear(self.sounds, {kind = "splash", v = 0.6})
self:go("landed")
end
end
break
end
if truth(self.lz) then
local framesLeft = math.max(10, ((self.alt - goal) / 0.8))
local step = math.max(0.4, (math.abs((self.lz - self.pos)) / framesLeft))
self.pos = (self.pos + math.max((-step), math.min(step, (self.lz - self.pos))))
self.view = self.pos
end
local d = (goal - self.alt)
local brakeV = math.sqrt(((2 * DEC) * math.abs(d)))
if ((self.flop > 0) and (truth(self.braking) or (self.v <= ((-brakeV) * 0.9)))) then
self.flop = math.max(0, (self.flop - 0.05))
end
if (d > 0) then
self.v = (self.v + (0.006 + (math.min(self.flyTime, 120) * 0.0004)))
self.v = math.min(self.v, VMAX, brakeV)
thrGoal = (if truth(((self.v >= (brakeV - 0.01)) and (d < 4))) then 0.65 else 1)
else
if (d < 0) then
self.v = math.max((self.v - ACC_DOWN), (-VMAX_DOWN))
if (self.v <= (-brakeV)) then
self.v = (-brakeV)
self.braking = true
end
thrGoal = (if truth(self.braking) then 0.6 else 0)
else
thrGoal = 0.6
end
end
if ((math.abs(d) <= (math.abs(self.v) + 0.02)) and (math.abs(self.v) < 0.25)) then
self.alt = goal
self.v = 0
self.view = self.lz
self.pos = self.view
self:go((if truth(shipHome) then "landed" else (if truth(catches) then "catch" else "landed")))
if truth(shipHome) then
self.splash = 1
end
hear(self.sounds, {kind = (if truth(shipHome) then "splash" else (if truth(catches) then "clang" else "thud")), v = 1})
else
self.alt = (self.alt + self.v)
end
if (truth(catches) and not (truth(shipHome))) then
armGoal = s.armCatch
end
break
end
elseif self.state == "catch" then
self.alt = catchAlt
armGoal = s.armCatch
if (math.abs((self.armY - s.armCatch)) > 0.5) then
self.timer = 0
end
self.reach = math.min(1, (self.timer / CLOSE))
thrGoal = (if truth((self.reach < 1)) then 0.45 else 0)
if (self.timer >= (CLOSE + 8)) then
self:go("lower")
end
break
elseif self.state == "lower" then
do
armGoal = (-1)
local span = math.max(0.5, (catchAlt - rest))
local frac = ((self.alt - rest) / span)
self.alt = (self.alt - (math.max(0.012, (span * (0.004 + (0.022 * math.sin((math.pi * math.min(1, frac))))))) * (if truth(self.boosterOnly) then 2 else 1)))
if (self.alt <= rest) then
self.alt = rest
self:go("release")
end
break
end
elseif self.state == "release" then
armGoal = (-1)
self.reach = math.max(0, (self.reach - (1 / CLOSE)))
if (self.reach <= 0) then
self:go("rest")
end
break
elseif self.state == "landed" then
do
self.v = 0
if (not (truth(shipHome)) and (self.part ~= "capsule")) then
self.alt = rest
break
end
if (self.chuteOpen > 0) then
self.chuteOpen = math.max(0, (self.chuteOpen - 0.05))
else
self.chute = 0
end
if (self.part == "capsule") then
self.alt = capSea
if ((self.timer * hurry) >= 24) then
self.service = 1
self:go("pan")
end
break
end
local lie = (((s.stage / 2) - (s.bodyW / 4)) / 2)
if ((self.timer * hurry) < 30) then
self.flop = math.min(1, (self.flop + (0.05 * hurry)))
self.alt = (sea - (self.flop * lie))
if ((self.timer == 16) and (hurry == 1)) then
self.boom = 1
hear(self.sounds, {kind = "boom", v = 1})
end
break
end
if not (truth(finite(self.carrierX))) then
self.carrierX = ((self.pos + (self.pw / 2)) + (2 * s.fly.w))
end
if (self.carrierX > self.pos) then
self.alt = (sea - (self.flop * lie))
local speed = math.min((2 * hurry), math.max(0.3, (((self.carrierX - self.pos) * 0.05) * hurry)))
self.carrierX = math.max(self.pos, (self.carrierX - speed))
else
self.flop = math.max(0, (self.flop - (0.04 * hurry)))
self.alt = ((sea + (1 - self.flop)) - (self.flop * lie))
if (self.flop <= 0) then
self:go("carry")
end
end
break
end
elseif self.state == "pan" then
do
self.alt = capSea
local speed = math.min((4 * hurry), math.max(0.6, ((math.abs(self.view) * 0.05) * hurry)))
self.view = (self.view + math.max((-speed), math.min(speed, (-self.view))))
if (math.abs(self.view) < 0.5) then
self:resetToPad()
end
break
end
elseif self.state == "carry" then
do
local to = ((s.bodyL - 3) - s.fly.w)
self.alt = (sea + 1)
local speed = math.min((2.5 * hurry), math.max(0.3, ((math.abs((to - self.pos)) * 0.04) * hurry)))
self.pos = (self.pos + math.max((-speed), math.min(speed, (to - self.pos))))
self.view = self.pos
self.carrierX = self.pos
if (math.abs((to - self.pos)) < 0.01) then
self.shipX = to
self.pos = 0
self.alt = rest
self.part = "booster"
self.stackOff = (2 - (self:apx() + (s.fly.h - s.stage)))
self:go("stack")
self.phase = 1
end
break
end
elseif self.state == "stack" then
do
self.alt = rest
self.view = (self.view + math.max((-0.5), math.min(0.5, (-self.view))))
local park = ((s.bodyL - 3) - s.fly.w)
local grip = js.round((s.stage * 0.6))
local bottom = (self:apx() + (s.fly.h - s.stage))
armGoal = ((bottom + js.round(self.stackOff)) + grip)
local there = (math.abs((self.armY - armGoal)) < 1)
if ((self.phase >= 2) and truth(finite(self.carrierX))) then
self.carrierX = (self.carrierX - (1.5 * hurry))
if (((self.ox + self.carrierX) + s.fly.w) < self:viewX()) then
self.carrierX = js.NaN
end
end
repeat
if self.phase == 0 then
self.shipX = (self.shipX + math.min((1.5 * hurry), (park - self.shipX)))
if (self.shipX >= park) then
self.phase = 1
end
break
elseif self.phase == 1 then
self.armX = self.shipX
if truth(there) then
self.reach = math.min(1, (self.reach + (hurry / CLOSE)))
end
if (self.reach >= 1) then
self.phase = 2
end
break
elseif self.phase == 2 then
self.stackOff = math.min(3, (self.stackOff + (0.25 * hurry)))
if ((self.stackOff >= 3) and truth(there)) then
self.phase = 3
end
break
elseif self.phase == 3 then
self.shipX = (self.shipX + math.min((0.4 * hurry), (-self.shipX)))
self.armX = self.shipX
if (self.shipX >= 0) then
self.phase = 4
end
break
elseif self.phase == 4 then
self.stackOff = math.max(0, (self.stackOff - (0.2 * hurry)))
if (self.stackOff <= 0) then
self.part = "full"
self.phase = 5
end
break
else
self.reach = math.max(0, (self.reach - (hurry / CLOSE)))
if (self.reach <= 0) then
self.armX = 0
self.returning = false
self.boosterHome = false
self.burn = 0
self.flop = 0
self:go("rest")
end
end
until true
break
end
end
until true
if (armGoal < 0) then
self.armY = (self:apx() + s.grip)
else
if (self.armY < 0) then
self.armY = armGoal
else
self.armY = (self.armY + math.max((-0.6), math.min(0.6, (armGoal - self.armY))))
end
end
self.thr = (self.thr + ((thrGoal - self.thr) * 0.35))
if ((self.thr < 0.02) and (thrGoal == 0)) then
self.thr = 0
end
local flying = (self.state == "fly")
local orbitGoal = (if truth((((truth(flying) and not (truth(homeward))) and (lv >= 8)) and (self.layer > (LAYER[(8) + 1] - 30)))) then 1 else 0)
self.orbit = (self.orbit + math.max((-0.03), math.min(0.025, (orbitGoal - self.orbit))))
if (self.orbit < 0.001) then
self.orbit = 0
end
local oi = math.max(0, math.min(2, (lv - 8)))
local tiltGoal = (if truth(orbitGoal) then (if truth(self.tall) then TILT_TALL else TILT_BAND)[(oi) + 1] else 0)
self.tilt = (self.tilt + math.max((-0.055), math.min(0.025, (tiltGoal - self.tilt))))
self.orbitSpeed = (self.orbitSpeed + (((if truth(orbitGoal) then ORBIT_SPEED[(oi) + 1] else 0) - self.orbitSpeed) * 0.04))
local visible = (self.rows - (if truth(self.splitTall) then self.splitW else 0))
local headroom = math.min(js.round(((HEADROOM * visible) * 2)), math.max(0, (((2 * visible) - (s.fly.h - self:partRows(self.part)[(0) + 1])) - 6)))
local camGoal = (if truth(((truth(self.tall) and truth(flying)) and (not (truth(homeward)) or ((self.alt - goal) > 25)))) then headroom else 0)
self.camP = (self.camP + math.max((-0.6), math.min(0.6, (camGoal - self.camP))))
if (truth(flying) and not (truth(homeward))) then
local a = (self.layer - (TILE / 2))
while (((self:scroll() - 1) - a) >= ((2 * TILE) + 1)) do
self.alt = (self.alt - TILE)
self.wraps = self.wraps + 1
for i = 0, PMAX, 1 do
if not ((i < PMAX)) then break end
self.py[(i) + 1] = js.f32((self.py[(i) + 1] - (2 * TILE)))
end
end
end
local tilt = self.tilt
local os = (self.orbit * self.orbitSpeed)
self.starVX = (math.sin(tilt) * os)
self.starVY = ((if truth(flying) then (self.v * (1 - self.orbit)) else 0) + ((math.cos(tilt) * os) * 0.5))
self.starX = (self.starX + self.starVX)
self.starY = (self.starY + self.starVY)
self.earthX = (self.earthX + ((self.orbit * self.orbitSpeed) * 0.45))
local g = self.ghost
if truth(g) then
g.v = (g.v + g.acc)
g.d = (g.d + g.v)
g.life = g.life - 1
if g.life <= 0 then
self.ghost = nil
end
end
self:stepParticles()
end
function LaunchSite:settle(lv, layer, catchAlt)

self.state = "fly"
self.flyTime = 120
self.alt = (catchAlt + 200)
self.v = SPEED[(lv) + 1]
self.thr = 1
self.layer = layer
self.service = 0
self.reach = 0
self.part = (if truth((layer >= SEP_LAYER)) then "upper" else "full")
self.ghost = nil
self.view = 0
self.pos = self.view
if (lv >= 8) then
local oi = math.min(2, (lv - 8))
self.orbit = 1
self.tilt = (if truth(self.tall) then TILT_TALL else TILT_BAND)[(oi) + 1]
self.orbitSpeed = ORBIT_SPEED[(oi) + 1]
end
if truth(self.tall) then
self.camP = js.round(((HEADROOM * self.rows) * 2))
end
end
function LaunchSite:separate()

self.part = "upper"
self.thr = 0
hear(self.sounds, {kind = "sep", v = 1})
self.ghost = {part = "booster", d = 0, v = (-0.05), acc = (-0.025), life = 48, max = 48}
local room = (if truth(self.tall) then (math.floor((self.rows / 2)) >= 12) else (math.floor((self.columns / 2)) >= 9))
if truth(room) then
self.twinDue = true
else
self.boosterHome = true
end
end
function LaunchSite:resetToPad()

self.part = "full"
self.view = 0
self.pos = self.view
self.alt = (self.spec.mount / 2)
self.v = 0
self.returning = false
self.boosterHome = false
self.burn = 0
self.chute = 0
self.chuteOpen = 0
self.room = 0
self.lean = 0
self.ghost = nil
self.service = 1
self:go("rest")
end
function LaunchSite:unfold()

local a = (self.layer - (TILE / 2))
while (((self:scroll() - 1) - a) < (TILE + 1)) do
self.alt = (self.alt + TILE)
for i = 0, PMAX, 1 do
if not ((i < PMAX)) then break end
self.py[(i) + 1] = js.f32((self.py[(i) + 1] + (2 * TILE)))
end
end
end
function LaunchSite:focus()

self:geo()
local s = self.spec
local r0, r1 = unpack(self:partRows(self.part))
local col = ((((self.bodyPx + self.pos) + (s.bodyW / 2)) - self:viewX()) / 2)
local base = ((2 * ((self:scroll() + self.rows) - 2)) + 1)
local row = (((base - self:apx()) - (s.fly.h - ((r0 + r1) / 2))) / 2)
return {col, row}
end
-- Methods from line 1107 on live in rocket_draw.luau; scenes.luau loads it as a separate step.
local DRAW_ENV = { LaunchSite = LaunchSite, DEFAULT_COLOR = DEFAULT_COLOR, LAYER = LAYER, LIGHT = LIGHT, LIMB = LIMB, OCEAN = OCEAN, PMAX = PMAX, QUAD = QUAD, RAMPS = RAMPS, TILE = TILE, breath = breath, finite = finite, fitQuad = fitQuad, g = g, hash = hash, js = js, lowerBlock = lowerBlock, mix = mix, rampColor = rampColor, truncate = truncate, truth = truth }
local Falcon = {}
Falcon.__index = Falcon
setmetatable(Falcon, {__index = LaunchSite})
function Falcon.new(seed)
local self = setmetatable(LaunchSite.new(seed), Falcon)
self.specs = FALCON_SPECS
self.look = {tower = 5922921, arm = 2764340, carriage = 8225934, ramp = RAMPS.merlin, mechazilla = false, catches = false}
return self
end
function Falcon:twin()

return Falcon.new(self.t)
end
local Starship = {}
Starship.__index = Starship
setmetatable(Starship, {__index = LaunchSite})
function Starship.new(seed)
local self = setmetatable(LaunchSite.new(seed), Starship)
self.specs = STARSHIP_SPECS
self.look = {tower = 5133405, arm = 2369324, carriage = 9080985, ramp = RAMPS.raptor, mechazilla = true, catches = true}
return self
end
function Starship:twin()

return Starship.new((self.t + 1))
end
local EXPORTS = { falcon = Falcon.new, starship = Starship.new }
EXPORTS.__drawEnv = DRAW_ENV
return EXPORTS
