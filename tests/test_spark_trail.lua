FRAMES=1/30
local trail=require("nw/spark_trail")
ANIM_ORIENTATION={OnGround=1}
local now,tick,created,removed,emitted=0,nil,0,0,0
function GetTime() return now end
local function noop() end
TheWorld={DoPeriodicTask=function(_,period,fn)
    assert(period==FRAMES)
    tick=fn
    return {Cancel=function() tick=nil end}
end}
function CreateEntity()
    created=created+1
    return {entity={AddTransform=noop,AddAnimState=noop,SetCanSleep=noop},
        Transform={SetPosition=function(self,x,y,z) self.x,self.y,self.z=x,y,z end},
        AnimState={SetBank=noop,SetBuild=noop,SetOrientation=noop,SetLightOverride=noop,
            PlayAnimation=function() emitted=emitted+1 end,SetTime=function(_,age) assert(age>=0 and age<=FRAMES) end},
        AddTag=noop,ForceFacePoint=function(self,x,y,z) self.facez=z end,
        Remove=function() removed=removed+1 end}
end
local x,z,alive,visible=0,0,true,true
local inst={IsValid=function() return alive end,
    Transform={GetWorldPosition=function() return x,0,z end},
    _height={value=function() return 1.4 end},
    _visual={entity={IsVisible=function() return visible end}}}
local function step(dx,dz)
    now=now+FRAMES
    x,z=x+dx,z+dz
    tick(TheWorld)
end
trail.attach(inst)
step(.5,0)
local first=TheWorld._nw_spark_trails.shots[1].parts[1].fx
local birth=first.Transform.x
step(0,.5)
assert(math.abs(first.Transform.x-birth-.25)<.0001 and first.Transform.z==0)
assert(first.Transform.y==1.4 and first.facez==.5)
local parts=TheWorld._nw_spark_trails.shots[1].parts
assert(emitted==3 and parts[2].fx.Transform.z<parts[3].fx.Transform.z)
for i=1,60 do step(.5,0) end
assert(emitted==93 and created==9 and removed==0,"45 births/s reuse nine sprites")
alive=false
step(0,0)
assert(removed<9,"old sparks fade after a hit")
for i=1,4 do step(0,0) end
assert(tick and created>removed,"last segment still visible after five frames")
step(0,0)
assert(created==removed and not tick and not TheWorld._nw_spark_trails)

alive,visible=true,false
for i=1,32 do trail.attach(inst) end
step(.5,0)
assert(created==9,"invisible shots emit nothing")
visible=true
step(20,0)
assert(created==9,"network corrections are not streaks")
local peak=0
for i=1,12 do
    step(.5,0)
    peak=math.max(peak,TheWorld._nw_spark_trails.count)
    assert(created-removed==TheWorld._nw_spark_trails.count and created-removed<=288)
end
assert(peak==288,"unlimited default must retain all 32 complete spark trails")
alive=false
for i=1,6 do
    if tick then step(0,0) end
end
assert(created==removed and not tick)
