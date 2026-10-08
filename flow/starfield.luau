--!strict
-- Port of Flow's hooks/starfield.ts (MIT, Rob Macrae).
local js = require('./js')
local cells = require('./cells')
local pixels = require('./pixels')
local fire = require('./fire')
local waiting = require('./waiting')
local SPEED = {0, .0025, .004, .006, .009, .013, .018, .025, .034, .046, .062}
local Scene = {}
Scene.__index = Scene
local function starColor(b, tint, warp)
 local v = math.max(0, math.min(1, b))
 if tint == 'smoke' then local g = js.round(60 + v * 110); return g * 65536 + g * 256 + g end
 local r, g, bl = 70 + v * 185, 80 + v * 175, 120 + v * 135
 if tint == 'blue' then r, g, bl = 12 + v * 30, 32 + v * 74, 140 + v * 100 end
 r -= warp * 40 * (1 - v); g -= warp * 15 * (1 - v)
 local function c(n) return math.max(0, math.min(255, js.round(n))) end
 return c(r) * 65536 + c(g) * 256 + c(bl)
end
function Scene:ensure(columns, rows)
 if columns == self.columns and rows == self.rows then return end
 self.columns, self.rows = columns, rows
 self.out = cells.Cells.new(columns, rows)
 self.bits, self.bright = table.create(columns * rows, 0), table.create(columns * rows, 0)
 self.stars = {}
end
function Scene:spawn(anyDepth)
 local x = (self.rng:f() * 2 - 1) * math.max(1, self.columns * 2 / math.max(1, self.rows * 4))
 local y = (self.rng:f() * 2 - 1) * math.max(1, self.rows * 4 / math.max(1, self.columns * 2))
 local z = if anyDepth then .04 + self.rng:f() * .96 else 1
 return {x=x, y=y, z=z, tw=self.rng:f() * 6.283}
end
function Scene:wanted()
 if self.strength <= 0 then return 0 end
 local _, seed = fire.params(self.strength)
 local coverage = math.min(160, seed + self.coverageBoost) / 100
 return js.round(self.columns * self.rows * (.035 + .035 * coverage) * (.7 + self.strength * .05))
end
function Scene:project(s, z)
 local pw, ph = self.columns * 2, self.rows * 4
 local scale = math.min(pw, ph) / 2 * .9
 local x, y = pw / 2 + s.x / z * scale, ph / 2 + s.y / z * scale
 if x < 0 or x >= pw or y < 0 or y >= ph then return nil end
 return x, y
end
function Scene:step()
 self.t += 1; self.kWait = waiting.easeWait(self.kWait, self.waiting)
 local want = self:wanted()
 while #self.stars < want do table.insert(self.stars, self:spawn(true)) end
 local n = #self.stars
 if want == 0 then table.clear(self.stars)
 elseif n > want and self.kWait == 0 then for i = n, math.max(want, n - 2) + 1, -1 do self.stars[i] = nil end end
 local speed = SPEED[math.max(0, math.min(10, self.strength)) + 1] * (1 - self.kWait)
 for i, s in self.stars do
  s.z -= speed
  if s.z <= .04 or self:project(s, s.z) == nil then self.stars[i] = self:spawn(false) end
 end
end
function Scene:plot(px, py, b)
 local x, y = math.floor(px), math.floor(py)
 local c = js.sar(y, 2) * self.columns + js.sar(x, 1)
 if c < 0 or c >= #self.bits then return end
 self.bits[c + 1] = js.bor(self.bits[c + 1], pixels.BRAILLE[js.band(x, 1) + 1][js.band(y, 3) + 1])
 if b > self.bright[c + 1] then self.bright[c + 1] = js.f32(b) end
end
function Scene:grid()
 for i = 1, #self.bits do self.bits[i], self.bright[i] = 0, 0 end
 local level = math.max(0, math.min(10, self.strength))
 local speed = SPEED[level + 1]
 local trail = if level >= 6 then (level - 6 + 1) * 1.4 else 0
 for _, s in self.stars do
  local hx, hy = self:project(s, s.z)
  if hx == nil then continue end
  local twinkle = if level <= 2 then .75 + .25 * math.sin(self.t * .35 + s.tw) else 1
  local near = 1 - s.z
  local b = (near + (1 - near) * .6 * self.kWait) * twinkle
  self:plot(hx, hy, b)
  if trail > 0 then
   local tx, ty = self:project(s, math.min(1, s.z + speed * trail))
   if tx ~= nil then
    local steps = math.ceil(math.max(math.abs(hx - tx), math.abs(hy - ty)))
    for k = 1, steps do local f = k / (steps + 1); self:plot(hx + (tx - hx) * f, hy + (ty - hy) * f, b * (1 - f) * .55) end
   end
  end
 end
 local warp = math.max(0, (level - 7) / 3)
 for i = 0, self.columns * self.rows - 1 do
  if self.bits[i + 1] == 0 then self.out:blank(i) else self.out:set(i, js.bor(0x2800, self.bits[i + 1]), starColor(self.bright[i + 1], self.tint, warp)) end
 end
 waiting.waitTone(self.out, self.kWait, self.t)
 return self.out
end
local function make(seed)
 return setmetatable({strength=8, coverageBoost=0, tint='normal', waiting=false, night=false, kWait=0, columns=0, rows=0, stars={}, out=cells.Cells.new(0,0), bits={}, bright={}, rng=cells.Rng.new(seed), t=0}, Scene)
end
return {make=make}
