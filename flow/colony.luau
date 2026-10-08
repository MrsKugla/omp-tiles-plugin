--!strict
-- Port of Flow's hooks/colony.ts (MIT, Rob Macrae).
local js=require('./js')
local cells=require('./cells')
local p=require('./pixels')
local sound=require('./sound')
local waiting=require('./waiting')
local SPEED={0,.012,.03,.06,.11,.19,.32,.52,.85,1.35,2.1}
local LAYERS={.25,.55,1}
local C={engine={0x4c535c,0x6c7580,0x8e98a3},truss=0x7c8590,spine=0x666e78,hub=0x7c8590,bladeFront={0x7d8792,0xa6b0bb,0xd0d8e0},bladeBack={0x3b424b,0x4d555f},window=0xf2d06b,windowDim=0x8a7440,windowBack=0x6e5c30,bow={0x8e98a3,0xc4ccd5},emitter=0xbfe8ff,plume={0xe8f4ff,0x9fd8ff,0x4aa8f0,0x2a6fc0},plumeSmoke={0x9a9a9a,0x707074},smoke=0xb4b4b4,smokeThin=0x606064,shield={0x1a3a58,0x245a86,0x3480bc,0x5aaee4,0x9ad6f6,0xe2f6ff},shieldBlue={0x06405a,0x076a8c,0x0a94b8,0x12c0de,0x5ae6f8,0xc8fcff},shieldSmoke={0x34485c,0x4c6278,0x6a8296,0x8aa2b4},glow={0x0c1a2a,0x112840,0x183a5c},glowBlue={0x04222e,0x063546,0x094a60},flash={0xfff8e8,0xffd480,0xff9a3a,0x8a3812},ember={0xfff2c0,0xffc04a,0xff7a22,0xc0401a,0x6a2410},rock={0xa8a091,0xc4baa9,0xe0d7c6},hot=0xff9a50,star={0x6a7488,0xa8b2c4,0xeef2fa},starBlue={0x1c4f9c,0x2d7fe0,0x86c4ff}}
local ROCK_R={2.2,3.8,6.2}
local TAU=math.pi*2
local DEFAULT=cells.DEFAULT_COLOR
local hash=p.hash1
local function trim(a,n) for i=#a,n+1,-1 do a[i]=nil end end
local Scene={};Scene.__index=Scene
function Scene:isVertical() return cells.isTall(self.columns,self.rows) end
function Scene:ensure(columns,rows)
 if columns==self.columns and rows==self.rows then return end
 self.columns,self.rows=columns,rows
 local n=columns*rows
 self.out=cells.Cells.new(columns,rows)
 self.pc,self.pk=table.create(n*4,0),table.create(n*4,0)
 for _,key in {'bits','dotColor','prio','glow','puff','puffColor','solid'} do self[key]=table.create(n,0) end
 self.rocks,self.embers,self.smoke,self.hits={},{},{},{}
 self.geo=self:layout()
 local vertical=self:isVertical()
 local along,across=if vertical then rows else columns,if vertical then columns else rows
 self.stars={}
 for i=0,math.max(6,js.round(n*.07))-1 do
  table.insert(self.stars,{u=hash(self.seedBase+i*3)*along,v=math.floor(hash(self.seedBase+i*3+1)*across),layer=math.floor(hash(self.seedBase+i*3+2)*#LAYERS),tw=hash(self.seedBase+i*7)*6.283})
 end
end
function Scene:layout()
 local v=self:isVertical()
 local A=if v then self.rows*4 else self.columns*2
 local Cd=if v then self.columns*2 else self.rows*4
 local c0=if v then 2*math.floor(self.columns/2) else 2*math.floor(self.rows)
 local aV=js.round(A*(if v then .52 else .45))+(if v then 7 else 8)
 local aN=aV-js.round((if v then 18 else 22)*.9)
 local Ls=js.round(.9*(if v then A*.25 else p.clamp(A*.22,22,66)))
 local E=js.round((if v then 5 else 4)*.9)
 local h0=E+js.round(Ls*.1)
 local b0=Ls-math.max(6,js.round(Ls*.11))
 local h1=b0-math.max(4,js.round(Ls*.07))
 local R=.9*(if v then math.min(Cd*.19,8) else Cd*.22)
 local sw=math.min(Cd/2,R*2.6)
 return {A=A,Cd=Cd,c0=c0,aS=aN-Ls,aN=aN,E=E,h0=h0,h1=h1,b0=b0,R=R,hw=(if v then 2.5 else 2)*.9,aV=aV,sw=sw,Rc=sw*sw/(2*(if v then 9 else 6)*.9)}
end
function Scene:speed()
 local l=p.clamp(self.level,0,10);local i=math.min(9,math.floor(l))
 return (SPEED[i+1]+(SPEED[i+2]-SPEED[i+1])*(l-i))*(1-self.kWait)
end
function Scene:rockSpeed() return .2+self:speed()*2 end
function Scene:arcA(c) local d=c-self.geo.c0;return self.geo.aV-d*d/(2*self.geo.Rc) end
function Scene:step()
 self.t+=1;self.kWait=waiting.easeWait(self.kWait,self.waiting)
 local want=p.clamp(self.strength,0,10)
 if js.isNaN(self.level) then self.level=want end
 self.level+=if math.abs(want-self.level)<.01 then want-self.level else (want-self.level)*.05
 local speed=self:speed();local vertical=self:isVertical()
 local along=if vertical then self.rows else self.columns
 local dir=if vertical then 1 else -1
 for _,s in self.stars do s.u+=dir*speed*LAYERS[s.layer+1];if s.u<0 then s.u+=along end;if s.u>=along then s.u-=along end end
 if self.columns==0 or self.rows==0 then return end
 self.spin=js.mod(self.spin+.022,TAU)
 local live=0
 for _,hit in self.hits do hit.age+=1;if hit.age<26 then live+=1;self.hits[live]=hit end end
 trim(self.hits,live)
 self:stepRocks();self:stepMotes()
end
function Scene:stepRocks()
 local geo=self.geo;local A,Cd,c0,sw=geo.A,geo.Cd,geo.c0,geo.sw
 local lo,hi=math.max(0,c0-sw),math.min(Cd,c0+sw)
 local l=p.clamp(self.level,0,10)
 local rate=if l<.5 then 0 else .0022*(.075/.0022)^((l-1)/9)
 if self.rng:f()<rate then
  local pick=self.rng:f();local size=if pick<.4 then 2 elseif pick<.75 then 1 else 0
  local r=ROCK_R[size+1]
  table.insert(self.rocks,{a=A+r+1,c=if hi-lo>r*2.4 then lo+r*1.15+self.rng:f()*(hi-lo-r*2.3) else c0,dc=(self.rng:f()-.5)*.08,k=.7+self.rng:f()*.6,size=size,ang=self.rng:f()*TAU,spin=(self.rng:f()-.5)*.09,seed=js.mod(self.rng:int(),10000)})
 end
 local v=self:rockSpeed();local lead=sound.leadFrames(self.strength,self.tint)
 local live=0
 for _,rock in self.rocks do
  rock.a-=v*rock.k;rock.c=p.clamp(rock.c+rock.dc,lo,hi-1);rock.ang+=rock.spin*(1+v*.3)
  local r=ROCK_R[rock.size+1];local gap=rock.a-r*.75-self:arcA(rock.c)
  if not rock.heard and gap<=lead*v*rock.k then rock.heard=true;sound.hear(self.sounds,{kind='hit',v=rock.size/2}) end
  if gap>0 then live+=1;self.rocks[live]=rock else self:burn(rock) end
 end
 trim(self.rocks,live)
end
function Scene:burn(rock)
 local a=self:arcA(rock.c)
 table.insert(self.hits,{a=a,c=rock.c,age=0,size=rock.size})
 if not rock.heard then sound.hear(self.sounds,{kind='hit',v=rock.size/2}) end
 local n=6+rock.size*5;local slope=(rock.c-self.geo.c0)/self.geo.Rc
 for i=1,n do
  local along=(self.rng:f()-.5)*(1.4+rock.size*.5)
  local out=.25+self.rng:f()*(.7+rock.size*.35)
  local life=9+math.floor(self.rng:f()*(10+rock.size*6))
  table.insert(self.embers,{a=a+.5,c=rock.c,va=out-along*slope*.5,vc=along+out*slope*.5,life=life,max=life})
 end
end
function Scene:stepMotes()
 local drift=.04+self:rockSpeed()*.04
 local live=0
 for _,m in self.embers do
  m.va=m.va*.86-drift;m.vc*=.88;m.a+=m.va;m.c+=m.vc
  local floor=self:arcA(m.c)+.3
  if m.a<floor then m.a=floor;m.va=0 end
  m.life-=1;if m.life>0 then live+=1;self.embers[live]=m end
 end
 trim(self.embers,live)
 if self.tint=='smoke' and self.strength>0 and self.t%3==0 then
  local life=20+math.floor(self.rng:f()*16)
  table.insert(self.smoke,{a=self.geo.aS-3,c=self.geo.c0+(self.rng:f()-.5)*3,va=-(.35+self:rockSpeed()*.3),vc=(self.rng:f()-.5)*.3,life=life,max=life})
 end
 live=0
 for _,m in self.smoke do m.a+=m.va;m.c+=m.vc;m.life-=1;if m.life>0 and m.a>-4 then live+=1;self.smoke[live]=m end end
 trim(self.smoke,live)
end
function Scene:starColor(layer,fade)
 local ramp=if self.tint=='blue' then C.starBlue else C.star
 local base=ramp[layer+1];local k=math.max(.15,math.min(1,fade))
 local function ch(sh) return js.round(js.band(js.sar(base,sh),255)*k) end
 return ch(16)*65536+ch(8)*256+ch(0)
end
function Scene:grid()
 local out=self.out;local w,h=self.columns,self.rows
 for i=0,w*h-1 do out:blank(i) end
 if self.strength<=0 or w==0 or h==0 then return out end
 local level=p.clamp(self.level,0,10);local speed=self:speed();local vertical=self:isVertical()
 local along=if vertical then h else w
 local function at(u,v) return if vertical then math.floor(u)*w+v else v*w+math.floor(u) end
 local dir=if vertical then 1 else -1
 local maxTrail=along*(if vertical then .25 else .6)
 for layer=0,#LAYERS-1 do for _,s in self.stars do
  if s.layer~=layer then continue end
  local trail=math.min(maxTrail,speed*LAYERS[layer+1]*9)
  local twinkle=if level<=2 then .7+.3*math.sin(self.t*.3+s.tw) else 1
  local head=math.floor(s.u)
  local glyph=if trail<.6 then (if layer==2 then '*' else '·') else (if vertical then '│' else '─')
  out:set(at(head,s.v),p.g(glyph),self:starColor(layer,twinkle))
  for k=1,math.floor(trail) do local u=js.mod(head-dir*k+along,along);out:set(at(u,s.v),p.g(if vertical then '│' else '─'),self:starColor(layer,(1-k/(trail+1))*.8)) end
 end end
 for i=1,w*h do self.bits[i]=0;self.prio[i]=0;self.glow[i]=0;self.puff[i]=0;self.solid[i]=0 end
 self:drawShield(level)
 for _,rock in self.rocks do self:drawRock(rock) end
 for _,m in self.embers do local f=m.life/m.max;self:plot(m.a,m.c,C.ember[math.min(4,math.floor((1-f)*5))+1],3) end
 self:drawSmoke()
 local blue=self.tint=='blue';local glowRamp=if blue then C.glowBlue else C.glow;local lo=if blue then .2 else .3
 for i=0,w*h-1 do
  local gl=self.glow[i+1];local bg=if gl>lo then glowRamp[math.min(2,math.floor((gl-lo)*2.5))+1] else DEFAULT
  local b=self.bits[i+1]
  if self.puff[i+1]~=0 then out:set(i,self.puff[i+1],self.puffColor[i+1])
  elseif b~=0 then out:set(i,js.bor(0x2800,b),self.dotColor[i+1],bg)
  elseif self.solid[i+1]~=0 then out:set(i,0x20,DEFAULT,bg)
  elseif bg~=DEFAULT then out:set(i,out:codePoint(i),out:foreground(i),bg) end
 end
 self:drawFlashes(out);self:drawShip(out,level);waiting.waitTone(out,self.kWait,self.t);return out
end
function Scene:cellAt(a,c)
 local vertical=self:isVertical()
 local x=math.floor(if vertical then c else a)
 local y=math.floor(if vertical then self.rows*4-a else c)
 if x<0 or y<0 or x>=self.columns*2 or y>=self.rows*4 then return -1 end
 return js.sar(y,2)*self.columns+js.sar(x,1)
end
function Scene:plot(a,c,color,prio)
 local vertical=self:isVertical()
 local x=math.floor(if vertical then c else a);local y=math.floor(if vertical then self.rows*4-a else c)
 if x<0 or y<0 or x>=self.columns*2 or y>=self.rows*4 then return end
 local cell=js.sar(y,2)*self.columns+js.sar(x,1)+1
 self.bits[cell]=js.bor(self.bits[cell],p.BRAILLE[js.band(x,1)+1][js.band(y,3)+1])
 if prio>=self.prio[cell] then self.prio[cell]=prio;self.dotColor[cell]=js.i32(color) end
end
function Scene:line(a0,c0,a1,c1,color,prio)
 local n=math.ceil(math.max(math.abs(a1-a0),math.abs(c1-c0))*1.5)+1
 for k=0,n do self:plot(a0+(a1-a0)*k/n,c0+(c1-c0)*k/n,color,prio) end
end
function Scene:drawShield(level)
 local geo=self.geo;local Cd,c0,sw=geo.Cd,geo.c0,geo.sw
 local smoke,blue=self.tint=='smoke',self.tint=='blue'
 local ramp=if smoke then C.shieldSmoke elseif blue then C.shieldBlue else C.shield
 local base=if smoke then .55+level*.03 else .16+level*.045+(if blue then .22 else 0)
 local busy=level/10
 local gutter=if smoke then (if hash(self.seedBase+js.sar(self.t,2)*13)<.3 then .35 else .75) else 1
 local c=math.max(0,c0-sw)+.25
 while c<math.min(Cd,c0+sw) do
  if smoke and hash(js.i32(c/3)*131+js.sar(self.t,1)*7+self.seedBase)<.4 then c+=.5;continue end
  local I=base
  for _,hit in self.hits do
   local d=math.abs(c-hit.c);local front=hit.age*(.9+hit.size*.25);local fade=1-hit.age/26;local power=.5+hit.size*.25
   I+=math.max(0,1-math.abs(d-front)/2.2)*fade*power
   if d<front then I+=.25*fade*power end
   if hit.age<5 and d<3+hit.size then I+=1 end
  end
  local lightI=I*gutter
  I=(I+busy*.22*(.5+.5*math.sin(c*.45-self.t*.31))+busy*.12*hash(js.i32(c)*31+self.t*17))*gutter
  local tip=math.min(1,(sw-math.abs(c-c0))/2.5);I*=tip
  if I>=.08 then
   local a=self:arcA(c);local color=ramp[math.min(#ramp-1,math.floor(I*(#ramp-.5)))+1]
   self:plot(a,c,color,1);self:plot(a+1,c,color,1)
   if blue or I>.9 then self:plot(a+2,c,color,1) end
   local cell=self:cellAt(a,c)
   if cell>=0 and not smoke and lightI*tip>self.glow[cell+1] then self.glow[cell+1]=js.f32(lightI*tip) end
  end
  c+=.5
 end
end
function Scene:drawFlashes(out)
 local w=self.columns
 for _,hit in self.hits do
  if hit.age>=5 then continue end
  local rf=(3+hit.size*1.6)*(1-hit.age/6);local vertical=self:isVertical()
  local x=if vertical then hit.c else hit.a;local y=if vertical then self.rows*4-hit.a else hit.c
  local c0,c1=math.max(0,math.floor((x-rf)/2)),math.min(w-1,math.floor((x+rf)/2))
  local r0,r1=math.max(0,math.floor((y-rf)/4)),math.min(self.rows-1,math.floor((y+rf)/4))
  for row=r0,r1 do for col=c0,c1 do
   local d=js.hypot(col*2+1-x,row*4+2-y)/rf
   if d>=1 then continue end
   local cell=row*w+col;local bg=C.flash[math.min(3,math.floor(d*2+hit.age*.7))+1];local cp=out:codePoint(cell)
   out:set(cell,cp,if cp==0x20 then DEFAULT else C.flash[1],bg)
  end end
 end
end
function Scene:cover(a,c,rad)
 local vertical=self:isVertical();local H=self.rows*4
 local x=if vertical then c else a;local y=if vertical then H-a else c
 local c0,c1=math.max(0,math.floor((x-rad)/2)),math.min(self.columns-1,math.floor((x+rad)/2))
 local r0,r1=math.max(0,math.floor((y-rad)/4)),math.min(self.rows-1,math.floor((y+rad)/4))
 for row=r0,r1 do for col=c0,c1 do
  local dx,dy=col*2+1-x,row*4+2-y
  if dx*dx+dy*dy<rad*rad*.7 then self.solid[row*self.columns+col+1]=1 end
 end end
end
function Scene:drawRock(rock)
 local r=ROCK_R[rock.size+1];local n=6+rock.size*2;local gap=rock.a-r-self:arcA(rock.c)
 local heat=if gap<12 then math.ceil((1-gap/12)*3)/3 else 0
 local color=p.mix(C.rock[rock.size+1],C.hot,heat*.8)
 self:cover(rock.a,rock.c,r)
 local pa,pc=0,0
 for i=0,n do
  local j=i%n;local ang=rock.ang+j/n*TAU;local rr=r*(.7+.45*hash(rock.seed*16+j))
  local a,c=rock.a+math.cos(ang)*rr,rock.c+math.sin(ang)*rr
  if i>0 then self:line(pa,pc,a,c,color,2) end
  pa,pc=a,c
 end
 if rock.size==2 then local ca=rock.ang+hash(rock.seed)*TAU;self:plot(rock.a+math.cos(ca)*r*.35,rock.c+math.sin(ca)*r*.35,C.rock[2],2) end
end
function Scene:drawSmoke()
 for _,m in self.smoke do
  local cell=self:cellAt(m.a,m.c)
  if cell<0 then continue end
  local young=m.life/m.max>.5
  if self.puff[cell+1]==0x2592 then continue end
  self.puff[cell+1]=if young then 0x2592 else 0x2591
  self.puffColor[cell+1]=if young then C.smoke else C.smokeThin
 end
end
function Scene:hullAt(s,d,plume,lit,px)
 local geo=self.geo;px.kind=0;px.color=0;local ad=math.abs(d)
 if s<0 then
  if -s>plume then return end
  local f=-s/plume
  if ad>2.6*(1-f)+.6 then return end
  local ramp=if self.tint=='smoke' then C.plumeSmoke else C.plume
  px.kind=2;px.color=ramp[math.min(#ramp-1,math.floor(f*#ramp+(if ad>1.2 then 1 else 0)))+1];return
 end
 local Ls=geo.aN-geo.aS
 if s>=Ls then return end
 if s<geo.E then
  local hw=if s<2 then geo.hw-1+s*.5 else geo.hw
  if ad>=hw then return end
  px.kind=2;px.color=C.engine[(if ad>hw-1.2 then 0 elseif s<2 then 1 else 2)+1];return
 end
 if s>=geo.b0 then
  local f=(s-geo.b0)/(Ls-geo.b0);local hw=(.9+2.4*math.sqrt(math.max(0,1-f*f)))*.9
  if ad>=hw then return end
  px.kind=2;px.color=if f>.82 then C.emitter else C.bow[(if ad<hw*.5 then 1 else 0)+1];return
 end
 local inSpine=ad<2
 if s>=geo.h0 and s<geo.h1 then
  if (s<geo.h0+2 or s>=geo.h1-2) and ad<geo.R*.4 then px.kind=2;px.color=C.hub;return end
  local twist=TAU*.55/(geo.h1-geo.h0)
  local bestZ,bestK,bestY=-2,-1,0
  for k=0,2 do
   local phi=self.spin+k*TAU/3+twist*(s-geo.h0);local y=geo.R*math.sin(phi);local z=math.cos(phi)
   if math.abs(d-y)<1.05+.85*math.abs(z) and z>bestZ then bestZ,bestK,bestY=z,k,y end
  end
  if bestK>=0 and (bestZ>0 or not inSpine) then
   px.kind=2;local j=math.floor((s-geo.h0)/2)
   local pane=js.band(j,1)==0 and math.abs(d-bestY)<1 and hash((bestK*977+j)*31+7)<lit
   if bestZ>0 then
    px.color=C.bladeFront[math.min(2,math.floor(bestZ*3))+1]
    if pane and bestZ>.45 and js.sar(self.t,5)%23~=(bestK*7+j)%23 then px.kind=3;px.color=if self.tint=='smoke' then C.windowDim else C.window end
   else px.color=if pane and bestZ<-.6 then C.windowBack else C.bladeBack[(if bestZ>-.5 then 1 else 0)+1] end
   return
  end
 end
 if inSpine then px.kind=1;px.color=C.spine end
end
function Scene:drawShip(out,level)
 local geo=self.geo;local vertical=self:isVertical();local w,h=self.columns,self.rows;local Hd=h*4
 local smoke=self.tint=='smoke';local flick=hash(self.seedBase+self.t*5)
 local plume=(2+level*1.5)*(.85+flick*.3)
 if smoke then plume=if flick<.35 then 0 else plume*.5 end
 plume=math.min(plume,geo.aS-1)
 local lit=math.min(1,.45+self.coverageBoost/100)
 local a0,a1=geo.aS-plume-1,geo.aN+1;local span=math.max(geo.R+2.5,geo.hw+1)
 local cLo,cHi=geo.c0-span,geo.c0+span
 local x0=math.max(0,math.floor((if vertical then cLo else a0)/2))
 local x1=math.min(w-1,math.floor((if vertical then cHi else a1)/2))
 local y0=math.max(0,math.floor((if vertical then Hd-a1 else cLo)/4))
 local y1=math.min(h-1,math.floor((if vertical then Hd-a0 else cHi)/4))
 local px={color=0,kind=0};local q,f=self.q,self.fit
 for row=y0,y1 do for col=x0,x1 do
  local cell=row*w+col;local hull,spine=false,false;local keep=-1
  for index=0,3 do
   local X=col*2+js.band(index,1)+.5;local Y=row*4+(if js.band(index,2)~=0 then 2 else 0)+1
   local a=if vertical then Hd-Y else X;local c=if vertical then X else Y
   self:hullAt(a-geo.aS,c-geo.c0,plume,lit,px)
   local k=cell*4+index+1;self.pk[k]=px.kind;self.pc[k]=px.color
   if px.kind>=2 then hull=true elseif px.kind==1 then spine=true end
   if px.kind==3 and keep<0 then keep=index end
  end
  if not hull and not spine and self:inside(col,row) then out:blank(cell);continue end
  if hull then
   for index=0,3 do q[index+1]=if self.pk[cell*4+index+1]~=0 then self.pc[cell*4+index+1] else 0 end
   p.fitQuad(q,f,p.NEAR,keep)
   if f.spread==0 then out:set(cell,0x2588,q[1]);continue end
   local mask,fg,bg=f.mask,f.fg,f.bg
   if fg==0 then mask=js.bxor(mask,15);fg=bg;bg=0 end
   out:set(cell,p.QUAD[mask+1],fg,if bg==0 then DEFAULT else bg)
  elseif spine then
   local bits=0
   for dx=0,1 do for dy=0,3 do
    local X=col*2+dx+.5;local Y=row*4+dy+.5
    local a=if vertical then Hd-Y else X;local c=if vertical then X else Y
    local j=math.floor(c-geo.c0+2)
    if j<0 or j>3 then continue end
    local i=js.mod(js.mod(math.floor(a),6)+6,6)
    local rail=j==0 or j==3;local brace=i==j+1 or i==6-j-1
    if rail or brace then bits=js.bor(bits,p.BRAILLE[dx+1][dy+1]) end
   end end
   if bits~=0 then out:set(cell,js.bor(0x2800,bits),C.truss) end
  end
 end end
end
function Scene:inside(col,row)
 local geo=self.geo;local X,Y=col*2+1,row*4+2
 local s=(if self:isVertical() then self.rows*4-Y else X)-geo.aS
 local d=math.abs((if self:isVertical() then X else Y)-geo.c0)
 if s<0 or s>=geo.aN-geo.aS then return false end
 if s>=geo.h0 and s<geo.h1 then return d<geo.R+1 end
 return d<(if s<geo.E then geo.hw else 2)
end
local function make(seed)
 local rng=cells.Rng.new(seed)
 local seedBase=js.mod(if seed~=nil then seed else rng:int(),100000)
 return setmetatable({strength=8,coverageBoost=0,sounds={},tint='normal',waiting=false,night=false,kWait=0,columns=0,rows=0,out=cells.Cells.new(0,0),stars={},t=0,seedBase=seedBase,rng=rng,level=js.NaN,pc={},pk={},bits={},dotColor={},prio={},glow={},puff={},puffColor={},solid={},rocks={},embers={},smoke={},hits={},spin=0,q={0,0,0,0},fit={mask=0,fg=0,bg=0,spread=0}},Scene)
end
return {make=make}
