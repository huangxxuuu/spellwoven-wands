-- Production sentry callbacks: final recoil completes before wilt, while
-- ammo and lifetime deadlines stop gameplay immediately.
local now,guid,tasks,shots=0,0,{},{}
local reverse_ties=false
local noop=function() end
GetTime=function() return now end
Asset=noop
Prefab=function(name,fn) return {name=name,fn=fn} end
MakeProjectilePhysics=noop
TheWorld={ismastersim=true,Map={IsPassableAtPoint=function() return true end}}

local function entity()
    guid=guid+1
    local e={GUID=guid,valid=true,x=0,z=0,components={},events={},clips={},tags={}}
    function e:IsValid() return self.valid end
    function e:IsInLimbo() return false end
    function e:HasTag(tag) return self.tags[tag]==true end
    function e:AddTag(tag) self.tags[tag]=true end
    function e:ListenForEvent(name,fn,source)
        local source=source or self
        source.events[name]=source.events[name] or {}
        source.events[name][#source.events[name]+1]={target=self,fn=fn}
    end
    function e:PushEvent(name)
        for _,listener in ipairs(self.events[name] or {}) do
            if listener.target.valid then listener.fn(self) end
        end
    end
    function e:Remove()
        if not self.valid then return end
        self.valid=false
        -- onremove listeners observe their source during removal in game.
        for _,listener in ipairs(self.events.onremove or {}) do
            if listener.target==self or listener.target.valid then listener.fn(self) end
        end
    end
    function e:DoTaskInTime(delay,fn)
        tasks[#tasks+1]={inst=self,at=now+delay,fn=fn}
    end
    function e:AddComponent(name)
        local c={}
        if name=="health" then c.SetMaxHealth=noop;c.IsDead=function() return false end
        elseif name=="combat" then
            c.CanTarget=function() return true end;c.IsAlly=function() return false end
            c.SuggestTarget=function(_,target) c.target=target end
        elseif name=="follower" then c.SetLeader=noop;c.StopLeashing=noop
        else assert(name=="inspectable") end
        self.components[name]=c
    end
    e.entity=setmetatable({},{__index=function() return noop end})
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end,
        SetPosition=function(_,x,y,z) e.x,e.z=x,z end}
    e.AnimState=setmetatable({
        PlayAnimation=function(_,name) e.anim=name;e.clips[#e.clips+1]={name=name,at=now} end,
        PushAnimation=function(_,name) e.queued=name end,
    },{__index=function() return noop end})
    return e
end
CreateEntity=entity
local function advance(target)
    while true do
        local nexttask
        for _,task in ipairs(tasks) do
            if not task.done and task.inst.valid and task.at<=target+1e-9
                and (not nexttask or task.at<nexttask.at or reverse_ties and task.at==nexttask.at) then nexttask=task end
        end
        if not nexttask then break end
        now=nexttask.at;nexttask.done=true;nexttask.fn(nexttask.inst)
    end
    now=target
end
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a).." ~= "..tostring(b)) end
local function events(e,name)
    local result={}
    for _,clip in ipairs(e.clips) do if clip.name==name then result[#result+1]=clip.at end end
    return result
end
local owner=entity();owner:AddComponent("combat")
local target=entity();target:AddComponent("combat");target:AddComponent("health");target.x=2
local available=true
local Effects=require("nw/spell_effects")
Effects.scan=function() return available and {target} or {} end
Effects.clear=function() return true end
require("nw/executor").execute=function(plan,caster,x,z,dx,dz,height)
    assert(caster==owner and plan.projectile_count==1 and height==.62)
    assert(plan.blocks[1].projectiles[1].id=="spore_sentry")
    shots[#shots+1]=now
    return true
end
local sentry=dofile("mod/scripts/prefabs/nw_garden.lua")
assert(sentry.name=="nw_spore_sentry")
local cleaned=0
local function launch(lifetime)
    now=0;tasks={};shots={};available=true;reverse_ties=false;cleaned=0
    local inst=sentry.fn()
    inst:Launch(owner,{id="spore_sentry",radius=5,damage=12,flags={},
        field_lifetime_mult=(lifetime or 5.7)/5.7},0,0,1,0,function() cleaned=cleaned+1 end)
    assert(inst.anim=="spore_grow" and inst.queued=="spore_idle")
    return inst
end

local ordinary=launch()
advance(.59);assert(#events(ordinary,"spore_fire")==0 and #shots==0)
advance(.6);near(events(ordinary,"spore_fire")[1],.6)
advance(.79);assert(#shots==0)
advance(.8);near(shots[1],.8)
advance(2.4)
assert(#shots==3 and ordinary.anim=="spore_fire" and #events(ordinary,"spore_wilt")==0)
for i=1,3 do near(shots[i],i*.8);near(events(ordinary,"spore_fire")[i],i*.8-.2) end
advance(2.59);assert(ordinary.anim=="spore_fire" and ordinary.valid)
advance(2.6);near(events(ordinary,"spore_wilt")[1],2.6)
advance(2.89);assert(ordinary.valid)
advance(2.9);assert(not ordinary.valid and #shots==3 and cleaned==1)
advance(6);assert(#shots==3 and cleaned==1)

-- Expiry during the already-pending final recoil cannot schedule two wilts.
local overlapping=launch(2.5)
advance(2.5);assert(#shots==3 and overlapping.anim=="spore_fire")
advance(2.6);assert(#events(overlapping,"spore_wilt")==1)
advance(3);assert(not overlapping.valid and cleaned==1 and #shots==3)

-- A wind-up may finish visually after expiry, but its projectile is cancelled.
local cancelled=launch(.7)
advance(.81);assert(#shots==0 and cancelled.anim=="spore_fire")
advance(1);near(events(cancelled,"spore_wilt")[1],1)
advance(1.3);assert(not cancelled.valid and cleaned==1 and #shots==0)

-- Even an adverse engine task order at the exact deadline cannot emit a shot.
local same_tick=launch(.8)
reverse_ties=true
advance(.8);assert(#shots==0 and same_tick.anim=="spore_fire")
advance(1.3);assert(not same_tick.valid and #events(same_tick,"spore_wilt")==1 and cleaned==1)

-- Without a current attack, expiry starts wilting immediately.
local idle=launch(1.1);available=false
advance(1.1);near(events(idle,"spore_wilt")[1],1.1)
advance(1.4);assert(not idle.valid and #shots==0 and cleaned==1)

-- Raw removal cancels the pending recoil tail as well as gameplay timers.
local removed=launch()
advance(2.4);removed:Remove();advance(6)
assert(#shots==3 and #events(removed,"spore_wilt")==0 and cleaned==1)
print("spore sentry: unchanged growth and firing, complete final recoil, cutoff ordering, single wilt and raw cleanup")
