--!strict
-- Port of Flow's hooks/bubbles.ts (MIT, Rob Macrae).
local js=require('./js')
local cells=require('./cells')
local p=require('./pixels')
local waiting=require('./waiting')
local RISE={0,.16,.24,.32,.42,.52,.62,.74,.9,1.1,1.35}
local STREAMS={0,.8,1.4,2.2,3,3.8,4.7,6,8,11,15}
local RATE={0,.06,.07,.08,.09,.1,.11,.13,.16,.21,.28}
local WATER={0x7fb4e4,0xa8cff0,0xcfe4f8,0xeef6fe,0xffffff}
local MURK={0x6a7068,0x868b80,0xa3a69a,0xc2c3b8,0xdedfd6}
local COLD={0x6f86d8,0x95a8e6,0xbac8f2,0xdde5fa,0xf6f8ff}
local SILT={0x4a3f30,0x6b5c45,0x8c7a5c}
local TAN={0x5e4630,0x84694c,0xab9070,0xd2bc98,0xf2e6cc}
local function ramp(stops,b)
 local v=js.round(p.clamp(b)*12)/12*(#stops-1)
 local i=math.min(#stops-2,math.floor(v))
 return p.mix(stops[i+1],stops[i+2],v-i)
end
local function trim(a,n) for i=#a,n+1,-1 do a[i]=nil end end
local Scene={}; Scene.__index=Scene
function Scene:ensure(c,r)
 if c==self.columns and r==self.rows then return end
 self.columns,self.rows=c,r; self.out=cells.Cells.new(c,r)
 self.bits,self.lum,self.kind=table.create(c*r,0),table.create(c*r,0),table.create(c*r,0)
 self.bubbles,self.streams,self.drops,self.silt,self.ripples={},{},{},{},{}; self.fresh=true
end
function Scene:at(a)
 local lo=math.floor(self.s)
 return a[lo+1]+(a[math.min(10,lo+1)+1]-a[lo+1])*(self.s-lo)
end
function Scene:rise() return self:at(RISE)*math.max(1,self.rows*4/20)^.35*(1-.4*self.kWait) end
function Scene:newStream()
 local x=0
 for tries=0,5 do
  x=2+self.rng:f()*(self.columns*2-4)
  local clear=true
  for _,o in self.streams do if math.abs(o.x-x)<=5 then clear=false; break end end
  if clear then break end
 end
 return {x=x,life=40+self.rng:f()*130,rate=.6+self.rng:f()*.8,wait=0}
end
function Scene:emit(x,y,fizz)
 if #self.bubbles>=700 then return nil end
 local s=self.s
 local big=if fizz then 0 else self.rng:f()*self.rng:f()
 local r0=if fizz then .3 else .55+big*(.3+s*.12)+s*.03
 local b={x=x,y=y,bx=x,r=r0,r0=r0,vy=(if fizz then 1.3 else .75+.3*self.rng:f())*self:rise()*(1+r0*.15),ph=self.rng:f()*6.283,fq=.12+self.rng:f()*.14}
 table.insert(self.bubbles,b); return b
end
function Scene:step()
 local W,H=self.columns*2,self.rows*4
 if W==0 or H==0 then return end
 local target=p.clamp(self.strength,0,10)
 if target<=0 then
  self.s=0; table.clear(self.bubbles);table.clear(self.drops);table.clear(self.silt);table.clear(self.ripples);table.clear(self.streams);return
 end
 if self.fresh then self.s=target end
 self.s+=p.clamp(target-self.s,-.06,.06)
 self.kMurk+=p.clamp((if self.tint=='smoke' then 1 else 0)-self.kMurk,-.05,.05)
 self.kCold+=p.clamp((if self.tint=='blue' then 1 else 0)-self.kCold,-.04,.04)
 self.kWait=waiting.easeWait(self.kWait,self.waiting)
 if self.kNight<0 then self.kNight=if self.night then 1 else 0 end
 self.kNight+=p.clamp((if self.night then 1 else 0)-self.kNight,-.04,.04)
 if self.fresh then
  self.fresh=false
  local n=math.min(600,math.ceil(H/math.max(.1,self:rise())))
  for i=1,n do self:advance() end
  return
 end
 self:advance()
end
function Scene:advance()
 local W,H=self.columns*2,self.rows*4
 local s,rise=self.s,self:rise()
 self.t+=1
 local tall=if H>W then 1.8 else 1
 local want=math.max(if s<1.5 then 2 else 3,js.round(W/100*tall*self:at(STREAMS)*(1+self.coverageBoost/30)))
 if #self.streams<want and js.band(self.t,3)==0 then table.insert(self.streams,self:newStream()) end
 if #self.streams>want and js.band(self.t,3)==0 then table.remove(self.streams) end
 local rate=self:at(RATE)
 for i,st in self.streams do
  st.life-=1
  if st.life<=0 then self.streams[i]=self:newStream()
  else
   st.wait-=1
   if st.wait<=0 and self.rng:f()<rate*st.rate then
    local b=self:emit(st.x+(self.rng:f()-.5)*1.2,H+1,false)
    if b then st.wait=(b.r0*(1.6+s*.06)*2+1.5)/b.vy end
   end
  end
 end
 local fizz=W/100*(math.max(0,s-4.5)*.35+math.max(0,s-7)*.5)
 local n=fizz
 while n>0 do if self.rng:f()<n then self:emit(self.rng:f()*W,H+1,true) end; n-=1 end
 if s>7 then n=W/100*(s-7)*.8;while n>0 do if self.rng:f()<n then self:emit(self.rng:f()*W,H+2,false) end;n-=1 end end
 local live=0
 for _,b in self.bubbles do
  b.y-=b.vy; b.vy=math.min(rise*1.5,b.vy*1.003)
  local up=p.clamp((H-b.y)/math.max(20,H))
  b.r=math.min(1.2+s*.2+math.max(0,s-7)*.15,b.r0*(1+up*(.6+s*.06)))
  if s>6 then b.bx+=math.sin(b.y*.07+self.t*.03+b.ph)*(s-6)*.03 end
  b.x=b.bx+math.sin(b.ph+self.t*b.fq)*(.15+b.r*.35)
  if b.y-b.r>2 then live+=1;self.bubbles[live]=b else self:pop(b) end
 end
 trim(self.bubbles,live)
 live=0
 for _,d in self.drops do
  d.x+=d.vx;d.y+=d.vy;d.vy+=.09
  if d.y<2.5 and d.x>=0 and d.x<W then live+=1;self.drops[live]=d end
 end
 trim(self.drops,live)
 live=0
 for _,rp in self.ripples do rp.age+=1;rp.amp*=.93;if rp.amp>.08 then live+=1;self.ripples[live]=rp end end
 trim(self.ripples,live)
 if self.kMurk>.05 then
  local puffs=math.max(1,js.round(W/70))
  local k=W/100*1.6*self.kMurk
  while k>0 do
   if self.rng:f()<k and #self.silt<900 then
    local j=js.i32(self.rng:f()*puffs)
    local cx=W*p.hash1(j*31+math.floor((self.t+j*37)/90))
    table.insert(self.silt,{x=cx+(self.rng:f()+self.rng:f()-1)*8,y=H-self.rng:f()*2,vy=(.15+.85*self.rng:f()*self.rng:f())*H*.0075,ph=self.rng:f()*6.283,life=1})
   end
   k-=1
  end
 end
 live=0
 for _,v in self.silt do
  v.y-=v.vy;v.vy*=.985;v.x+=math.sin(v.y*.3+self.t*.05+v.ph)*.25;v.life-=.007+(1-self.kMurk)*.03
  if v.life>0 and v.y>3 then live+=1;self.silt[live]=v end
 end
 trim(self.silt,live)
end
function Scene:pop(b)
 local amp=.35+b.r*.35
 if #self.ripples<120 then table.insert(self.ripples,{x=b.x,age=0,amp=amp}) end
 if #self.sounds<24 then table.insert(self.sounds,{kind='pop',v=math.min(1,b.r/2.5)}) end
 local n=if b.r<.7 then (if self.rng:f()<.3 then 1 else 0) else js.round(1+b.r*1.2+self.rng:f()*2)
 for i=1,n do
  if #self.drops>=400 then break end
  local a=(self.rng:f()-.5)*2.2
  local v=.45+self.rng:f()*.45+b.r*.12
  table.insert(self.drops,{x=b.x,y=2,vx=math.sin(a)*v*.9,vy=-math.cos(a)*v})
 end
end
function Scene:surfaceAt(x)
 local y=2+math.sin(x*.11+self.t*.07)*math.sin(x*.037-self.t*.03)*self.s*.06
 for _,rp in self.ripples do
  local d=math.abs(x-rp.x);local front=rp.age*.7
  if d>front+2 then continue end
  y+=math.cos((d-front)*.9)*rp.amp*math.exp(-d*.08)
 end
 return y
end
function Scene:dot(x,y,v,kind)
 local px,py=math.floor(x),math.floor(y)
 if px<0 or py<0 or px>=self.columns*2 or py>=self.rows*4 then return end
 local c=js.sar(py,2)*self.columns+js.sar(px,1)+1
 self.bits[c]=js.bor(self.bits[c],p.BRAILLE[js.band(px,1)+1][js.band(py,3)+1])
 if v>self.lum[c] then self.lum[c]=js.f32(v);self.kind[c]=kind end
end
function Scene:grid()
 local out=self.out;local n=self.columns*self.rows
 for i=1,n do self.bits[i]=0;self.lum[i]=0 end
 if self.s<=0 or self.strength<=0 then for i=0,n-1 do out:blank(i) end;return out end
 local W,H=self.columns*2,self.rows*4
 for x=0,W-1 do
  local y=self:surfaceAt(x+.5);local lift=math.abs(y-2)
  if lift<.35 and (x+js.sar(self.t,3))%3==0 then continue end
  self:dot(x,y+.5,.12+math.min(.45,lift*.4),1)
 end
 local head=1.5+self.s*.35;local fizz=js.sar(self.t,2)
 for x=0,W-1 do
  local y0=self:surfaceAt(x+.5)
  if p.hash1(x*7919+fizz*104729+self.seedN)<.3 then self:dot(x,y0-.5,.6,1) end
  local d=0
  while d<head do
   local probability=.85*(1-d/head)^1.3+.08
   if p.hash1(x*7919+(d+1)*15485863+fizz*104729+self.seedN)<probability then self:dot(x,y0+.5+d,.82-d/head*.3,1) end
   d+=1
  end
 end
 for _,d in self.drops do self:dot(d.x,d.y,.85,0) end
 for _,v in self.silt do self:dot(v.x,v.y,.3+v.life*.7,2) end
 for _,b in self.bubbles do
  local depth=p.clamp((b.y-2)/math.max(1,H-2))
  local base=.16+(1-depth)*.22+math.min(.1,b.r*.04)
  if b.r<.8 then self:dot(b.x,b.y,base,0);continue end
  if b.r<1.3 then
   self:dot(b.x,b.y-1,base+.3,0);self:dot(b.x-1,b.y,base+.2,0);self:dot(b.x+1,b.y,base-.05,0);self:dot(b.x,b.y+1,base-.1,0);continue
  end
  local reach=math.ceil(b.r+1);local cx,cy=math.floor(b.x),math.floor(b.y)
  for dy=-reach,reach do for dx=-reach,reach do
   local ox,oy=cx+dx+.5-b.x,cy+dy+.5-b.y
   local d=math.sqrt(ox*ox+oy*oy)
   if math.abs(d-b.r)>.5 then continue end
   local facing=if d>0 then -(ox+oy)/(d*1.414) else 0
   self:dot(cx+dx,cy+dy,base+facing*.2+(if facing>.8 then .35 else 0),0)
  end end
  if b.r>=2.2 then self:dot(b.x-b.r*.42,b.y-b.r*.45,1,0) end
 end
 local km,kc,kn=js.round(self.kMurk*4)/4,js.round(self.kCold*4)/4,js.round(math.max(0,self.kNight)*8)/8
 local top=p.mix(p.mix(p.mix(0x2f86d0,0x1c140d,kn),0x4c6670,km),0x26357e,kc)
 local bottom=p.mix(p.mix(p.mix(0x14468e,0x070504,kn),0x2c3c3e,km),0x0c1238,kc)
 for i=0,n-1 do
  local row=js.i32(i/self.columns);local col=i-row*self.columns
  local swell=math.sin(col*.11+self.t*.03)*math.sin(col*.047-self.t*.019)
  local depth=p.clamp(row/math.max(1,self.rows-1)+swell*.08)
  local bg=p.mix(top,bottom,js.round(depth*12)/12)
  if self.bits[i+1]==0 then out:set(i,0x20,bg,bg);continue end
  local v=self.lum[i+1];local fg
  if self.kind[i+1]==2 then fg=ramp(SILT,v) else
   fg=ramp(WATER,v)
   if kn>0 then fg=p.mix(fg,ramp(TAN,v),kn) end
   if km>0 then fg=p.mix(fg,ramp(MURK,v*.85),km) end
   if kc>0 then fg=p.mix(fg,ramp(COLD,v),kc) end
  end
  out:set(i,js.bor(0x2800,self.bits[i+1]),fg,bg)
 end
 waiting.waitTone(out,self.kWait,self.t);return out
end
local function make(seed)
 return setmetatable({strength=8,coverageBoost=0,sounds={},tint='normal',night=false,waiting=false,kWait=0,columns=0,rows=0,out=cells.Cells.new(0,0),rng=cells.Rng.new(seed),seedN=js.i32(seed or 0),t=0,fresh=true,s=0,kMurk=0,kCold=0,kNight=-1,bubbles={},streams={},drops={},silt={},ripples={},bits={},lum={},kind={}},Scene)
end
return {make=make}
