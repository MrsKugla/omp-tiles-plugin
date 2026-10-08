--!strict
-- Port of Flow's hooks/clouds/layered.ts (MIT, Rob Macrae).
-- layered.cell({x=x,y=y,sky=sky,t=t}) returns a cell or nil; snap(color,sky) quantizes it.
local js=require("./js")
local p=require("./pixels")
local hash,mix,clamp01=p.hash,p.mix,p.clamp01
local function smooth(k) return k*k*(3-2*k) end
local function smoothstep(a,b,v) return smooth(clamp01((v-a)/(b-a))) end
local function noise(u,v,salt)
 local iu,iv=math.floor(u),math.floor(v); local fu,fv=smooth(u-iu),smooth(v-iv)
 local a,b,c,d=hash(iu,iv,salt),hash(iu+1,iv,salt),hash(iu,iv+1,salt),hash(iu+1,iv+1,salt)
 local top=a+(b-a)*fu; return top+(c+(d-c)*fu-top)*fv
end
local heaps: any={}; local heapCount=0
local function build(sx,sy)
 local px,py,pr=table.create(12,0),table.create(12,0),table.create(12,0)
 local c={n=0,base=0,top=0,x0=0,x1=0,px=px,py=py,pr=pr}
 if sy<0 or sy>=3 then return c end
 local odds=if sy==0 then 0.58 elseif sy==1 then 0.54 else 0.4
 if hash(sx,sy,110)>odds then return c end
 local baseRow=6.6+sy*4.6+hash(sx,sy,111)*(4.6-1.2)
 local s=hash(sx,sy,112)
 local size=(if s<0.4 then 0.35+s elseif s<0.85 then 0.75+(s-0.4)*0.5 else 1+(s-0.85)*3)*(if sy==2 then 0.7 else 1)
 local width=8+size*20; local height=3+size*4.5+math.max(0,size-1)*5
 local cx=sx*38+7+hash(sx,sy,113)*(38-14); local base=baseRow*2
 local n0=math.max(2,math.min(7,js.round(width/6))); local rMain=height/1.2
 local k,run=0,0
 for i=0,n0-1 do
  local u=(i/(n0-1))*2-1
  local r=rMain*(0.6+0.4*(1-u*u))*(0.85+0.3*hash(sx,sy*7+i,116))
  if i>0 then run+=(pr[i]+r)*(0.55+0.2*hash(sx*31+i,sy,115)) end
  px[k+1]=run; py[k+1]=base+r*(0.12+0.25*hash(sx+i,sy,117)); pr[k+1]=r; k+=1
 end
 for i=0,n0-1 do px[i+1]=px[i+1]-run/2+cx end
 local n1=math.min(12-n0,1+math.floor(size*2.5+hash(sx,sy,118)*2))
 for j=0,n1-1 do
  local i=math.floor(hash(sx,sy+j,119)*n0*0.6+n0*0.2); local host=math.min(n0-1,math.max(0,i))
  local a=(hash(sx,sy+j,120)-0.5)*1.6; local hr=pr[host+1]
  local r=math.max(1.8,hr*(0.5+0.25*hash(sx+j,sy,121)))
  px[k+1]=px[host+1]+math.sin(a)*hr*0.75; py[k+1]=py[host+1]+math.cos(a)*hr*0.55+r*0.25; pr[k+1]=r; k+=1
 end
 for i=1,k-1 do
  local j=i
  while j>0 and py[j]+pr[j]*0.3<py[j+1]+pr[j+1]*0.3 do
   local tx,ty,tr=px[j+1],py[j+1],pr[j+1]
   px[j+1]=px[j]; py[j+1]=py[j]; pr[j+1]=pr[j]
   px[j]=tx; py[j]=ty; pr[j]=tr; j-=1
  end
 end
 local top,x0,x1=base+1,math.huge,-math.huge
 for i=1,k do top=math.max(top,py[i]+pr[i]); x0=math.min(x0,px[i]-pr[i]); x1=math.max(x1,px[i]+pr[i]) end
 if top>46 then return c end
 c.n=k; c.base=base; c.top=top; c.x0=x0-1.7; c.x1=x1+1.7; return c
end
local function heapAt(sx,sy)
 local key=sx*8+sy; local c=heaps[key]
 if c then return c end
 if heapCount>4096 then table.clear(heaps); heapCount=0 end
 c=build(sx,sy); heaps[key]=c; heapCount+=1; return c
end
local function ramp(l)
 if l<0.2 then return mix(0x7d8fb0,0xa3b2cb,l/0.2) end
 if l<0.5 then return mix(0xa3b2cb,0xd2dbe8,(l-0.2)/0.3) end
 if l<0.78 then return mix(0xd2dbe8,0xf0f3f8,(l-0.5)/0.28) end
 return mix(0xf0f3f8,0xffffff,math.min(1,(l-0.78)/0.22))
end
local outA,outC=0,0
local function cumulus(wx,qy)
 outA=0; local sxc=math.floor(wx/38); local y=qy/2; local syc=math.floor((y-6.6)/4.6)
 for dy=-2,0 do for dx=-1,1 do
  local c=heapAt(sxc+dx,syc+dy)
  if c.n==0 or qy<c.base-1 or qy>c.top+1.7 or wx<c.x0 or wx>c.x1 then continue end
  local sd,wsum,nx,ny=-math.huge,0,0,0
  for i=0,c.n-1 do
   local ox,oy,r=wx-c.px[i+1],qy-c.py[i+1],c.pr[i+1]
   local s=r-math.sqrt(ox*ox+oy*oy); if s>sd then sd=s end
   if s< -1.7 then continue end
   local w=(math.min(s,4)+1.7)*(1+i*0.12); w*=w; w*=w; w*=w
   wsum+=w; nx+=(ox/r)*w; ny+=(oy/r)*w
  end
  if wsum==0 then continue end
  local rough=(noise(wx/2.3,qy/2.1,131)-0.5)*1.8+(noise(wx/1.1,qy/1.2,132)-0.5)*0.7
  local a=smoothstep(-1.7,1.4,sd+rough); a*=smoothstep(c.base-1.8,c.base+1.6,qy+rough*0.5)
  if a<=outA then continue end
  nx/=wsum; ny/=wsum; local l2=nx*nx+ny*ny
  if l2>1 then local l=math.sqrt(l2); nx/=l; ny/=l end
  local nz=math.sqrt(math.max(0,1-nx*nx-ny*ny)); local dot=nx*(-0.45)+ny*0.82+nz*0.45
  local h=(qy-c.base)/(c.top-c.base); local lit=0.42+dot*0.72+(h-0.4)*0.6
  local under=smoothstep(-0.5,math.min(4,0.35*(c.top-c.base)),qy-c.base)
  lit=math.min(lit,0.06+under*1.1); outA=a*0.98; outC=ramp(clamp01(lit))
 end end
end
local DECK_Y,DECK_ROWS,CELL_W,CELL_H,RX,RY,DECK_ALPHA={16.8,22.8},{3,4},{15,8},{2.1,1.9},{8.5,3.8},{1.7,1.05},{0.94,0.86}
local elements: any={}; local elementCount=0
local function elementAt(k,i,j)
 local key=i*16+k*8+j; local el=elements[key]; if el then return el end
 if elementCount>4096 then table.clear(elements); elementCount=0 end
 el=table.create(5,0); local cw=CELL_W[k+1]
 local crowd=noise((i*cw)/(if k==0 then 75 else 55)+k*11.3,j*0.35+k*4.1,173)
 local odds=(if k==0 then smoothstep(0.32,0.72,crowd) else smoothstep(0.24,0.62,crowd))*(if j==DECK_ROWS[k+1]-1 then 0.5 else 0.85)
 if hash(i,j,175+k)<=odds then
  local size=0.55+0.7*hash(i,j,177+k)+0.25*crowd
  el[1]=(i+0.5+(hash(i,j,179+k)-0.5)*0.9)*cw
  el[2]=DECK_Y[k+1]+(j+0.5+(hash(i,j,181+k)-0.5)*0.85)*CELL_H[k+1]
  el[3]=RX[k+1]*size*(if crowd>0.6 then 1.25 else 1); el[4]=RY[k+1]*size; el[5]=hash(i,j,183)*6.28
 end
 elements[key]=el; elementCount+=1; return el
end
local function bank(k,x,y)
 outA=0; local y0,cw,ch=DECK_Y[k+1],CELL_W[k+1],CELL_H[k+1]
 if y<y0-1.6 or y>y0+DECK_ROWS[k+1]*ch+2 then return end
 local ci,cj=math.floor(x/cw),math.floor((y-y0)/ch); local rough=js.NaN; local best,bestLit=0,0
 for dj=-1,1 do
  local j=cj+dj; if j<0 or j>=DECK_ROWS[k+1] then continue end
  for di=-1,1 do
   local el=elementAt(k,ci+di,j); local rx=el[3]; if rx==0 then continue end
   local ox=(x-el[1])/rx; if ox< -1.4 or ox>1.4 then continue end
   local oyRows=y-el[2]; local ry=el[4]*(if oyRows<0 then 0.5 else 1.28)
   if oyRows>ry*1.3 or oyRows< -ry*1.6 then continue end
   local lump=if oyRows>0 then (1+0.28*math.sin(ox*4.2+el[5]))/1.28 else 1
   local oy=oyRows/(ry*lump)
   if rough~=rough then rough=(noise(x/1.9,y/0.75,171+k)-0.5)*0.5 end
   local e=math.sqrt(ox*ox+oy*oy)+rough; local a=1-smoothstep(0.5,1.15,e)
   if a<=best then continue end
   best=a; bestLit=clamp01(0.5+0.38*oy+0.2*(1-e)+(if k==0 then 0.05 else 0)+(rough-0.1)*0.7)
  end
 end
 if best<=0.01 then return end
 outA=best*DECK_ALPHA[k+1]; outC=if k==0 then mix(0x8b9bb8,0xeef2f8,bestLit) else mix(0x7385a8,0xd6dfee,bestLit)
end
local function cirrus(x,y)
 outA=0; if y<27.5 or y>44.6 then return end
 local patch=smoothstep(0.42,0.7,noise(x/64+4.2,y/7+1.1,161)); if patch<=0 then return end
 local f=noise(x/34+y*0.12,y/1.15,163)*0.75+noise(x/11,y/0.8,165)*0.25
 local ridge=1-math.abs(f-0.5)*2; local a=smoothstep(0.72,0.97,ridge); if a<=0 then return end
 a*=0.55+0.45*noise(x/2.2,y*3.1,167); a*=patch; a*=smoothstep(27.5,32,y)*(1-smoothstep(42.5,44.8,y))
 if a<=0.01 then return end
 outA=a*0.62; outC=mix(0x8a9dc0,0xdbe4f2,clamp01(ridge*1.2-0.2)*(1-smoothstep(30,44,y)*0.5))
end
local function half(x,y,sky)
 local col=sky; cirrus(x+0.5,y); if outA>0 then col=mix(col,outC,outA) end
 for k=1,0,-1 do bank(k,x+0.5,y); if outA>0 then col=mix(col,mix(outC,sky,smoothstep(22,32,y)*0.25),outA) end end
 if y<24.5 then cumulus(x+0.5,y*2); if outA>0 then col=mix(col,outC,outA) end end
 return col
end
local function snap(c,sky)
 local q=if js.band(js.sar(sky,16),255)<64 and js.band(js.sar(sky,8),255)<64 and js.band(sky,255)<64 then 8 else 12
 local function ch(sh)
  local s=js.band(js.sar(sky,sh),255)
  return math.max(0,math.min(255,s+js.round((js.band(js.sar(c,sh),255)-s)/q)*q))
 end
 return js.bor(js.bor(js.shl(ch(16),16),js.shl(ch(8),8)),ch(0))
end
local layered={name="layered",description="changes with height: soft cumulus low, broken banks mid, cirrus streaks high"}
function layered.cell(d)
 local top,bot=half(d.x,d.y+0.25,d.sky),half(d.x,d.y-0.25,d.sky)
 if top==d.sky and bot==d.sky then return nil end
 return {glyph=0x2580,fg=top,bg=bot}
end
return {layered=layered,snap=snap}
