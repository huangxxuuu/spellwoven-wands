-- Exercise the actual local field scheduler, including replicated size,
-- moving/rotating parents, independent members and both removal paths.
local now,created,removed,started,cancelled=0,0,0,0,0
local dedicated=false
local noop=function() end
GetTime=function() return now end
TheCamera={heading=0,pitch=35}
TheNet={IsDedicated=function() return dedicated end}
ANIM_ORIENTATION={BillBoard=2}
local function events(e)
    e.events={}
    function e:ListenForEvent(name,fn) self.events[name]=fn end
    function e:RemoveEventCallback(name,fn) if self.events[name]==fn then self.events[name]=nil end end
    return e
end
TheWorld=events({})
function TheWorld:DoPeriodicTask(period,fn)
    assert(period==1/30 and not self.tick,"all fields share one task")
    started=started+1;self.tick=fn
    return {Cancel=function() cancelled=cancelled+1;self.tick=nil end}
end
CreateEntity=function()
    created=created+1
    local e={valid=true,visible=true,entity={},Transform={},AnimState={}}
    for _,name in ipairs({"AddTransform","AddAnimState","SetCanSleep"}) do e.entity[name]=noop end
    e.entity.SetParent=function() error("members must not inherit parent transform") end
    e.Transform.SetPosition=function(_,x,y,z) e.x,e.y,e.z=x,y,z end
    e.Transform.SetScale=function(_,x,y,z) assert(x==y and y==z);e.scale=x end
    for _,name in ipairs({"SetBank","SetBuild","SetOrientation","SetLightOverride"}) do e.AnimState[name]=noop end
    e.AnimState.PlayAnimation=function(_,name,loop) assert(loop);e.anim=name end
    e.AnimState.SetDeltaTimeMultiplier=function(_,speed) e.speed=speed end
    e.AnimState.SetTime=function(_,age) assert(age>=0 and age<.2);e.age=age end
    function e:AddTag() end
    function e:Hide() self.visible=false end
    function e:Show() self.visible=true end
    function e:IsValid() return self.valid end
    function e:Remove() assert(self.valid);self.valid=false;removed=removed+1 end
    return e
end
local function anchor(guid,y)
    local e=events({GUID=guid,x=4,y=y or 0,z=7,valid=true,visible=true,size=1,rotation=0})
    e.entity={IsVisible=function() return e.visible end,GetParent=function() return e.parent end}
    e.Transform={GetWorldPosition=function() return e.x,e.y,e.z end,
        GetScale=function() error("use the replicated field size, not parent scale") end,
        GetRotation=function() error("parent rotation must not rotate the group") end}
    e._nw_insect_size={value=function() return e.size end}
    function e:IsValid() return self.valid end
    function e:Remove() self.valid=false;if self.events.onremove then self.events.onremove() end end
    return e
end
local function advance()
    now=now+1/30
    if TheWorld.tick then TheWorld.tick(TheWorld) end
end
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a).." ~= "..tostring(b)) end
local Swarm=require("nw/insect_swarm_visual")
local Flight=require("nw/elemental_flight")
local bee,fly=anchor(12),anchor(13,1)
local bees,flies=Swarm.attach(bee,"bee_swarm"),Swarm.attach(fly,"fireflies")
assert(#bees.members==3 and #flies.members==2 and created==5 and started==1)
assert(Swarm.attach(bee,"bee_swarm")==bees and created==5,"repeat attach must not duplicate")
for _,s in ipairs({bees,flies}) do for _,part in ipairs(s.members) do assert(not part.fx.visible) end end
advance()
local before={}
for index,part in ipairs(bees.members) do
    assert(part.fx.visible and part.fx.anim:find("^bee_swarm_dir_") and part.y>.79 and part.y<1.01)
    before[index]={x=part.x,z=part.z}
end
for _,part in ipairs(flies.members) do assert(part.y>1 and part.y<1.2) end
assert(bees.members[1].phase~=bees.members[2].phase and bees.members[2].phase~=bees.members[3].phase)
assert(bees.members[1].playback~=bees.members[2].playback,"wing clocks must be independent")
for _=1,8 do advance() end
local a,b=bees.members[1],bees.members[2]
assert(math.abs((a.x-before[1].x)-(b.x-before[2].x))>.001
    or math.abs((a.z-before[1].z)-(b.z-before[2].z))>.001,"members must not translate as one painted group")
local positions={}
for index,part in ipairs(bees.members) do positions[index]={x=part.x,z=part.z} end
bee.rotation=180
TheWorld.tick(TheWorld)
for index,part in ipairs(bees.members) do near(part.x,positions[index].x);near(part.z,positions[index].z) end
bee.x=bee.x+3;bee.z=bee.z-2
TheWorld.tick(TheWorld)
for index,part in ipairs(bees.members) do
    near(part.x,positions[index].x+3);near(part.z,positions[index].z-2)
    assert(part.direction==Flight.direction(math.atan2(-2,3),"bee_swarm"),"facing includes actual anchor motion")
    positions[index]={x=part.x-bee.x,z=part.z-bee.z}
end
bee.size=2.5
TheWorld.tick(TheWorld)
for index,part in ipairs(bees.members) do
    near(part.x-bee.x,positions[index].x*2.5);near(part.z-bee.z,positions[index].z*2.5)
    near(part.fx.scale,2.5)
end
fly.y=0 -- A moving firefly field is on the ground, rather than parented at y=1.
TheCamera.heading=90
advance()
for _,part in ipairs(flies.members) do
    assert(part.y>.8 and part.y<1)
    assert(part.direction==Flight.direction(part.heading,"fireflies"))
    near(part.fx.age,((now-flies.started)*part.playback+part.phase)%flies.period)
end
fly.parent=anchor(20);fly.parent.visible=false;advance()
for _,part in ipairs(flies.members) do assert(not part.fx.visible,"hidden owner must hide world-space escort members") end
fly.parent.visible=true;advance()
for _,part in ipairs(flies.members) do assert(part.fx.visible) end
bee.visible=false;advance()
for _,part in ipairs(bees.members) do assert(not part.fx.visible) end
bee.visible=true;advance()
for _,part in ipairs(bees.members) do assert(part.fx.visible) end
bee:Remove()
assert(removed==3 and not bee._nw_insect_swarm and TheWorld.tick and #TheWorld._nw_insect_swarms.fields==1)
TheWorld.events.onremove()
assert(removed==5 and not fly._nw_insect_swarm and not TheWorld.tick and not TheWorld._nw_insect_swarms)
assert(not fly.events.onremove and not TheWorld.events.onremove and started==cancelled)
dedicated=true
assert(not Swarm.attach(anchor(15),"bee_swarm") and created==5 and started==1)
print("insect fields: independent members, one scheduler, replicated size, upright world placement, visibility and removal cleanup")
