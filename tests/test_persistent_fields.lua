RemovePhysicsColliders=function(e) e.no_terrain_collision=true end
local Stored=require("nw/persistent_fields")
local Fields=require("nw/expanded_fields")
local Executor=require("nw/executor")
local Copy=require("nw/util").copy
DEGREES=math.pi/180;FRAMES=1/30
local now=0
GetTime=function() return now end
TheWorld={};AllPlayers={}
TheSim={FindEntities=function() return {} end}
local guid=0
local function entity(userid)
    guid=guid+1
    local e={GUID=guid,userid=userid,valid=true,components={combat={}},events={},tasks={},x=0,z=0}
    function e:IsValid() return self.valid end
    function e:HasTag(tag) return tag=="playerghost" and self.ghost end
    function e:IsAsleep() return false end
    function e:ListenForEvent(name,fn,source)
        source=source or self;source.events=source.events or {}
        source.events[name]=source.events[name] or {}
        table.insert(source.events[name],{self,fn})
    end
    function e:PushEvent(name,data)
        for _,listener in ipairs(self.events[name] or {}) do
            if listener[1]:IsValid() then listener[2](self,data) end
        end
    end
    function e:Remove() self:PushEvent("onremove");self.valid=false end
    function e:DoTaskInTime(delay,fn) self.tasks[#self.tasks+1]={at=now+delay,fn=fn} end
    function e:DoPeriodicTask(period,fn,delay)
        local task={at=now+(delay or period),fn=fn,period=period,Cancel=function(self) self.cancelled=true end}
        self.tasks[#self.tasks+1]=task;return task
    end
    function e:GetDistanceSqToPoint(x,y,z) return (self.x-x)^2+(self.z-z)^2 end
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end,SetRotation=function() end,
        SetPosition=function(_,x,y,z) e.x,e.z=x,z end}
    e.AnimState={PlayAnimation=function(_,name) e.animation=name end,PushAnimation=function() end}
    function e:SetStage(id,phase) self.animation=id.."_"..phase end
    e.Physics={Stop=function() end,SetMotorVel=function(_,speed) e.speed=speed end,ClearCollisionMask=function() e.no_terrain_collision=true end}
    e.entity={SetCanSleep=function() end}
    return e
end
local function tick(e,t)
    now=t
    for _,task in ipairs(e.tasks) do
        if not task.cancelled and task.at<=now and e.valid then task.fn(e);task.at=task.period and now+task.period or math.huge end
    end
end
local owner=entity("KU_builder");AllPlayers={owner}
local placed,fired,held={},{},{}
SpawnPrefab=function(name)
    local e=entity();e.prefab=name
    function e:Launch(caster,p,x,z,dx,dz,cleanup,height,fire,payload)
        self.x,self.z=x,z
        if Stored.is(p.id) then
            cleanup();Stored.install(self);Stored.launch(self,caster,p,dx,dz,height,payload)
            placed[#placed+1]=self
        elseif p.id=="held" then
            held[#held+1]=cleanup
        else
            fired[#fired+1]={p=Copy(p),caster=caster,dx=dx,dz=dz,x=x,z=z};cleanup()
        end
    end
    return e
end
local function shot(id,payload)
    return {id=id,kind=Stored.is(id) and "field" or "projectile",speed=0,damage=22,radius=1.8,
        flags={},spread=0,payload=payload,event=payload and "break"}
end
local function execute(blocks)
    local n=0
    for _,b in ipairs(blocks) do for _,p in ipairs(b.projectiles) do n=n+(p.count or 1) end end
    assert(Executor.execute({blocks=blocks,projectile_count=n,next_state={rng_state=17}},owner,0,0,1,0,1.4))
end
local blasts=0
require("nw/spell_effects").blast=function(caster) assert(caster==owner);blasts=blasts+1 end
require("nw/spell_effects").scan=function() return {} end
-- Both crystals survive their former expiry and the owner's death/removal.
execute({{projectiles={shot("sleep_crystal"),shot("crystal_mine")}}})
assert(Executor.stats()==0 and #owner._nw_crystals==2)
local crystal,mine=placed[1],placed[2]
tick(crystal,121);tick(mine,121)
owner:PushEvent("death");owner:PushEvent("ms_becameghost")
assert(crystal.valid and mine.valid)
owner.ghost=true;crystal._nw_break();assert(blasts==0 and crystal.valid)
owner:Remove();AllPlayers={};crystal._nw_break();assert(crystal.valid)
owner=entity("KU_builder");AllPlayers={owner}
crystal._nw_break();assert(blasts==1 and not crystal.valid and #owner._nw_crystals==1)
-- Save/load preserves arming state, modified parameters and chronological caps.
local save={};mine.OnSave(mine,save);mine:Remove()
assert(save.placement.arm_left==0)
local restored=entity();Stored.install(restored);restored.OnLoad(restored,Copy(save))
assert(restored._nw_owner==owner and restored._nw_armed_at==now)
assert(restored.animation=="crystal_mine_idle","loading a permanent field does not replay arrival")
local Live=require("nw/entity_limits")
Live.configure("permanent_fields",25)
for i=1,24 do execute({{projectiles={shot("sleep_crystal")}}}) end
local before=#placed
execute({{projectiles={shot("sleep_crystal")}}})
assert(not restored.valid and #owner._nw_crystals==25 and #placed==before+1)
assert(blasts==1,"replacement must silently remove, never detonate")
while #owner._nw_crystals>0 do owner._nw_crystals[1]:Remove() end
Live.configure("permanent_fields",0)
-- Loading entities in reverse order must not change which placement is oldest.
execute({{projectiles={shot("sleep_crystal"),shot("sleep_crystal")}}})
local records={}
for _,e in ipairs(owner._nw_crystals) do local data={};e.OnSave(e,data);records[#records+1]=data end
while #owner._nw_crystals>0 do owner._nw_crystals[1]:Remove() end
local backwards={}
for i=2,1,-1 do local e=entity();Stored.install(e);e.OnLoad(e,records[i]);backwards[i]=e end
Live.configure("permanent_fields",25)
for i=1,23 do execute({{projectiles={shot("sleep_crystal")}}}) end
before=#placed;execute({{projectiles={shot("sleep_crystal")}}})
assert(not backwards[1].valid and backwards[2].valid and #placed==before+1)
assert(Live.owner_used(owner,"permanent_fields")==25,"loaded fields retain stable player ownership")
while #owner._nw_crystals>0 do owner._nw_crystals[1]:Remove() end
Live.configure("permanent_fields",0)
-- Moving placements pause while ghost/offline and retain heading across saves.
local moving=shot("sleep_crystal");moving.speed=6;moving.field_drive=true
execute({{projectiles={moving}}});local mover=placed[#placed]
assert(mover.speed==6)
owner.ghost=true;tick(mover,122);assert(mover.speed==0)
owner.ghost=false;tick(mover,123);assert(mover.speed<6 and mover.speed>5)
local motion_save={};mover.OnSave(mover,motion_save)
assert(motion_save.placement.age>0)
mover:Remove()
owner.ghost=true
local sleeping_mover=entity();Stored.install(sleeping_mover);sleeping_mover.OnLoad(sleeping_mover,motion_save)
local asleep_save={};sleeping_mover.OnSave(sleeping_mover,asleep_save)
assert(asleep_save.placement.age==motion_save.placement.age and sleeping_mover.speed==0)
sleeping_mover:Remove();owner.ghost=false
-- An egg frees its entire pending subtree, stores no functions or entities,
-- and keeps nested templates and a private RNG seed across save/load.
local arrow=shot("arrow");arrow.damage=37;arrow.flags={targets={hostile=true}};arrow.spread=7
execute({{projectiles={shot("payload_egg",2)}},{projectiles={shot("payload_egg",3)}},{projectiles={arrow}}})
local egg=placed[#placed]
assert(Executor.stats()==0)
local function serializable(data)
    assert(type(data)~="function" and type(data)~="userdata")
    if type(data)=="table" then for k,v in pairs(data) do serializable(k);serializable(v) end end
end
local eggsave={};egg.OnSave(egg,eggsave);serializable(eggsave)
assert(not eggsave.placement.payload.angles and #eggsave.placement.payload.blocks==2)
assert(eggsave.placement.payload.next_state.rng_state>0)
tick(egg,250);assert(egg.valid)
egg:Remove()
local loaded=entity();Stored.install(loaded);loaded.OnLoad(loaded,Copy(eggsave))
loaded.x=8;loaded.z=3
loaded._nw_break(owner);assert(not loaded.valid and Executor.stats()==0)
local nested=placed[#placed]
assert(nested~=egg and nested.valid)
local nested_seed=nested._nw_stored.payload.next_state.rng_state
local expected_rng=require("nw/rng").new(nested_seed):fork()
local angle=(expected_rng:next()*2-1)*7*DEGREES
nested._nw_break(owner);nested._nw_break(owner)
assert(#fired==1 and fired[1].p.damage==37 and fired[1].p.flags.targets.hostile)
assert(fired[1].x==8 and fired[1].z==3 and math.abs(fired[1].dx-math.cos(angle))<1e-9)
-- A saturated pool consumes the egg trigger but skips its new projectiles.
execute({{projectiles={shot("payload_egg",2)}},{projectiles={shot("arrow"),shot("arrow")}}})
egg=placed[#placed];Executor.set_projectile_limit(25)
local many={}
for i=1,25 do many[i]=shot("held") end
execute({{projectiles=many}})
egg._nw_break(owner);assert(not egg.valid and egg._nw_spent and Executor.stats()==25 and #fired==1)
held[1]()
execute({{projectiles={shot("payload_egg",2)}},{projectiles={shot("arrow"),shot("arrow")}}})
egg=placed[#placed];egg._nw_break(owner)
assert(not egg.valid and #fired==2 and Executor.stats()==24,"partial payload uses the single available slot")
for i=2,#held do held[i]() end
assert(Executor.stats()==0);Executor.set_projectile_limit(0)
-- The placer may have left this shard while their entity remains valid.
-- Only the current triggerer owns the payload, including nested eggs.
execute({{projectiles={shot("payload_egg",2)}},{projectiles={shot("payload_egg",3)}},{projectiles={shot("arrow")}}})
local stranger=entity("KU_triggerer");AllPlayers={stranger}
egg=placed[#placed]
assert(Fields.can_break(egg,stranger))
egg._nw_break(stranger);assert(not egg.valid)
local next_egg=placed[#placed]
assert(next_egg._nw_stored.userid==stranger.userid)
local third=entity("KU_next_triggerer");AllPlayers={third}
next_egg._nw_break(third)
assert(not next_egg.valid and fired[#fired].caster==third,"nested egg changes attribution on each trigger")
assert(Executor.stats()==0)
-- Real persistent-field save/load retains repeat counts, independent seeds and
-- inherited secondary restrictions without expanding the stored payload.
local leaf=shot("arrow");leaf.freeze=1;leaf.spread=7
local repeated={next_state={rng_state=71},projectile_count=16,blocks={
    {copies=4,copy_damage=.45,projectiles={shot("payload_egg",2)}},
    {copies=3,projectiles={leaf}},
}}
local start=#placed
assert(Executor.execute(repeated,third,0,0,1,0,1.4) and Executor.stats()==0)
local first,second=placed[start+1],placed[start+2]
local a,b=first._nw_stored.payload,second._nw_stored.payload
assert(#a.blocks==1 and a.blocks[1].copies==3 and a.projectile_count==3)
assert(a.payload_scale==.45 and not a.payload_secondary and b.payload_secondary)
assert(a.next_state.rng_state~=b.next_state.rng_state and not a.angles and not b.angles)
local saved={};second.OnSave(second,saved);serializable(saved);second:Remove()
local again=entity();Stored.install(again);again.OnLoad(again,Copy(saved))
local count=#fired
first._nw_break(third);again._nw_break(third)
assert(#fired==count+6 and Executor.stats()==0)
for i=count+1,count+6 do
    assert(math.abs(fired[i].p.damage-22*.45)<1e-9)
    assert((fired[i].p.freeze~=nil)==(i<=count+3))
end
placed[start+3]:Remove();placed[start+4]:Remove()
print("persistent fields: expiry, ghost/offline, reconnect, save/load, caps, motion, nested payloads, spread and budget retry")
