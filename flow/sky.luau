--!strict
-- Port of Flow's hooks/sky.ts (MIT, Rob Macrae).
-- local Base=require("./sky").SkyWorld; local Balloon=setmetatable({}, {__index=Base}); Balloon.__index=Balloon
-- function Balloon.new(seed) return setmetatable(Base.new(seed),Balloon) end
-- Override :vehicleHeight(), :drawVehicle(out,top), optionally :advance(), :groundFeature(x), :scenery(x,y,sky).
-- Getters are methods: :target(), :dark(), :scroll(), :vehicleTop(), :altitude(). rowBg[r+1] uses zero-based row r.
local js=require("./js")
local cells=require("./cells")
local clouds=require("./clouds_layered")
local n=require("./night")
local p=require("./pixels")
local waiting=require("./waiting")
local mix,hash,g=p.mix,p.hash,p.g
local ALTITUDE={0,0,6,14,24,36,50,66,84,104,128}
local SKY={{0,0x9fd3f2},{24,0x6db8ec},{56,0x3f86d4},{84,0x24508f},{104,0x121f45},{114,0x070b1c},{122,0}}
local NIGHT_SKY={{0,n.NIGHT_HORIZON},{60,n.NIGHT_ZENITH},{122,0}}
local function ramp(stops,y)
 for i=2,#stops do
  local y1,c1=stops[i][1],stops[i][2]
  if y<=y1 then local y0,c0=stops[i-1][1],stops[i-1][2]; return mix(c0,c1,(y-y0)/(y1-y0)) end
 end
 return 0
end
local function skyColor(y) return if y<0 then 0x5a3d24 else ramp(SKY,y) end
local function nightSkyColor(y) return if y<0 then 0x22170e else ramp(NIGHT_SKY,y) end
local function moonlit(c,sky) return mix(mix(c,sky,0.55),0x9fb4d6,0.12) end
local SkyWorld: any={}; SkyWorld.__index=SkyWorld
function SkyWorld.new(seed)
 return setmetatable({strength=8,coverageBoost=0,tint="normal",night=false,kNight=-1,waiting=false,kWait=0,goal=-1,columns=0,rows=0,out=cells.Cells.new(0,0),rowBg={},alt=0,t=js.mod(if seed==nil then os.time()*1000 else seed,10000)},SkyWorld)
end
function SkyWorld:vehicleHeight() error("SkyWorld subclass must implement vehicleHeight") end
function SkyWorld:drawVehicle(_out,_top) error("SkyWorld subclass must implement drawVehicle") end
function SkyWorld:ensure(c,r)
 if c==self.columns and r==self.rows then return end
 self.columns=c; self.rows=r; self.out=cells.Cells.new(c,r)
end
function SkyWorld:altitude() return self.alt end
function SkyWorld:seed(altitude)
 if altitude==altitude and altitude~=math.huge and altitude~= -math.huge and altitude>=0 then self.alt=altitude end
end
function SkyWorld:target() return ALTITUDE[math.max(0,math.min(10,self.strength))+1] end
function SkyWorld:step()
 self.t+=1; local k=if self.night then 1 else 0
 if self.kNight<0 then self.kNight=k end
 self.kNight+=(k-self.kNight)*0.05
 if math.abs(k-self.kNight)<0.01 then self.kNight=k end
 self.kWait=waiting.easeWait(self.kWait,self.waiting); self:advance()
end
function SkyWorld:dark() return if self.kNight<0 then (if self.night then 1 else 0) else self.kNight end
function SkyWorld:advance()
 if not self.waiting or self.goal<0 then self.goal=self:target() end
 self.alt+=(self.goal-self.alt)*0.03*(1-self.kWait)
 if math.abs(self.goal-self.alt)<0.01 then self.alt=self.goal end
end
function SkyWorld:restTop() return math.max(0,self.rows-self:vehicleHeight()-1) end
function SkyWorld:scroll()
 local rest=self:restTop(); local ceiling=math.min(rest,math.max(1,math.floor(self.rows*0.25)))
 return math.max(0,js.round(self.alt)-(rest-ceiling))
end
function SkyWorld:vehicleTop() return self:restTop()-(js.round(self.alt)-self:scroll()) end
function SkyWorld:rowOf(y) return self.rows-1-(y-self:scroll()+1) end
function SkyWorld:wind(y) return if y<=0 then 0 else math.floor(js.mod(self.t*(0.04+y*0.002),100000)) end
function SkyWorld:skyAt(y)
 local k=self:dark(); if k<=0 then return skyColor(y) end
 if k>=1 then return nightSkyColor(y) end
 return mix(skyColor(y),nightSkyColor(y),k)
end
function SkyWorld:cloudLight(c,sky)
 local k=self:dark(); if k<=0 then return c end
 local m=moonlit(c,sky); return if k>=1 then m else mix(c,m,k)
end
function SkyWorld:groundFeature(x)
 local h=hash(x,0,1)
 if h<0.06 then return {glyph=g("♣"),fg=mix(0x2f6b2a,0x15291a,self:dark())} end
 if h<0.08 then return {glyph=g("⌂"),fg=mix(0xc9a46a,0xffd27a,self:dark())} end
 return nil
end
function SkyWorld:drawMoon(out)
 local k=self:dark(); if k<=0.02 or self.rows<3 then return end
 local x=math.floor(self.columns*n.MOON_ACROSS); local r=math.min(n.MOON_ROW,self.rows-3); local i=r*self.columns+x
 if x<self.columns and out:codePoint(i)==0x20 then
  local bg=out:background(i); out:set(i,g("●"),if k>=1 then n.MOON else mix(bg,n.MOON,k),bg)
 end
end
function SkyWorld:scenery(x,y,sky)
 if y== -1 then return {glyph=g("▀"),fg=mix(0x4f9a3d,0x1d3a1a,self:dark())} end
 if y==0 then return self:groundFeature(x) end
 if y< -1 then return nil end
 local drift=math.floor(js.mod(self.t*0.1,100000))
 local cloud=if y>=12 and y<=88 then clouds.layered.cell({x=(x+drift)/2,y=y/2,sky=sky,t=self.t}) else nil
 if cloud then
  local fg=clouds.snap(self:cloudLight(cloud.fg,sky),sky)
  local bg=clouds.snap(self:cloudLight(if cloud.bg==nil then sky else cloud.bg,sky),sky)
  cloud=if fg==sky and bg==sky then nil else {glyph=cloud.glyph,fg=fg,bg=bg}
 end
 x+=self:wind(y)
 if y>=2 and y<=28 and hash(x,y,2)<0.005 then
  return {glyph=g(if js.mod(js.sar(self.t,3),2)~=0 then "v" else "~"),fg=0x5a5a62,bg=if cloud then (if cloud.bg==nil then cloud.fg else cloud.bg) else nil}
 end
 if cloud then return cloud end
 if y>=80 or (self:dark()>0 and y>=2) then
  local prob=math.max(0.02*self:dark(),math.min(0.1,(y-80)*(0.004/2))); local h=hash(x,y,7)
  if h<prob then
   local twinkle=hash(x,y+js.sar(self.t,2),8)<0.15
   return {glyph=g(if h<prob*0.2 then "*" else "·"),fg=if twinkle then n.STAR_DIM else n.STAR}
  end
 end
 return nil
end
function SkyWorld:grid()
 local out,w,h=self.out,self.columns,self.rows
 if self.strength<=0 then for i=0,w*h-1 do out:blank(i) end; return out end
 local scroll=self:scroll(); self.rowBg={}
 for r=0,h-1 do
  local y=scroll-1+(h-1-r); local bg=self:skyAt(y); table.insert(self.rowBg,bg)
  for x=0,w-1 do
   local i=r*w+x; local s=self:scenery(x,y,bg)
   if s then out:set(i,s.glyph,s.fg,if s.bg==nil then bg else s.bg) else out:set(i,0x20,cells.DEFAULT_COLOR,bg) end
  end
 end
 if self.alt>=112 then
  for x=0,w-1 do
   local edge=(x+0.5-w/2)/(w/2); local eighths=math.floor(1+3*(1-edge*edge)+hash(x,0,74))
   out:set((h-1)*w+x,p.lowerBlock(math.max(1,math.min(4,eighths))),0x4a90d9,self.rowBg[h])
  end
 end
 self:drawMoon(out); self:drawVehicle(out,self:vehicleTop()); waiting.waitTone(out,self.kWait,self.t); return out
end
function SkyWorld:frame() return self:grid():encode() end
return {skyColor=skyColor,SkyWorld=SkyWorld}
