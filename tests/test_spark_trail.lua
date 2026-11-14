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
            PlayAnimation=function() emitted=emitted+1 end,
            SetDeltaTimeMultiplier=function(_,rate) assert(math.abs(rate-2/3)<.000001) end,
            SetTime=function(_,age) assert(age>=0 and age<=3*(.3/15)*(2/3)+.000001) end},
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
for _,speed in ipairs({17.5,95}) do
    alive=true
    local initial_created,initial_removed,initial_emitted=created,removed,emitted
    local distance=speed*FRAMES
    trail.attach(inst)
    step(distance,0)
    local first=TheWorld._nw_spark_trails.shots[1].parts[1].fx
    local birth,birthz=first.Transform.x,first.Transform.z
    step(0,distance)
    assert(math.abs(first.Transform.x-birth-.5*distance)<.0001 and first.Transform.z==birthz)
    assert(first.Transform.y==1.4 and first.facez==z)
    local parts=TheWorld._nw_spark_trails.shots[1].parts
    assert(emitted-initial_emitted==3 and parts[2].fx.Transform.z<parts[3].fx.Transform.z)
    for i=1,60 do
        step(distance,0)
        if i>=7 then assert(TheWorld._nw_spark_trails.count==15,"steady trail has fifteen segments") end
    end
    assert(emitted-initial_emitted==103 and created-initial_created==15
        and removed==initial_removed,"50 births/s reuse fifteen sprites at default and maximum speed")
    alive=false
    step(0,0)
    assert(removed-initial_removed<15,"old sparks fade after a hit")
    for i=1,7 do step(0,0) end
    assert(tick and created>removed,"last segment still visible after eight frames")
    step(0,0)
    assert(created==removed and not tick and not TheWorld._nw_spark_trails)
end

alive,visible=true,false
local initial_created=created
for i=1,32 do trail.attach(inst) end
step(.5,0)
assert(created==initial_created,"invisible shots emit nothing")
visible=true
step(20,0)
assert(created==initial_created,"network corrections are not streaks")
local peak=0
for i=1,12 do
    step(.5,0)
    peak=math.max(peak,TheWorld._nw_spark_trails.count)
    assert(created-removed==TheWorld._nw_spark_trails.count and created-removed<=480)
end
assert(peak==480,"unlimited default must retain all 32 complete spark trails")
alive=false
for i=1,9 do
    if tick then step(0,0) end
end
assert(created==removed and not tick)

alive=true
trail.attach(inst)
step(95*FRAMES,0)
local before_slow_frame=emitted
now=now+3*FRAMES
x=x+95*3*FRAMES
tick(TheWorld)
assert(emitted-before_slow_frame==3,"slow frames catch up at most three distinct births")
alive=false
for i=1,9 do if tick then step(0,0) end end
assert(created==removed and not tick and not TheWorld._nw_trail_budget,
    "slow-frame catch-up leaves no sprites or shared budget records after expiry")
