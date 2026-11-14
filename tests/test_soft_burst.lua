-- These projectile endings keep their native fire/smoke but must not play a
-- blackpowder sound independently from every visual in the cluster.
local factories,entities,sounds,spawns={},{},{},{}
local dedicated=false
local function noop() end
Asset=noop
Prefab=function(name,fn) factories[name]=fn;return name end
TheWorld={ismastersim=true}
TheNet={IsDedicated=function() return dedicated end}
ANIM_ORIENTATION={OnGround=1,BillBoard=2}
net_float=function()
    return {v=0,value=function(self) return self.v end,set=function(self,v) self.v=v end}
end
CreateEntity=function()
    local e={GUID=#entities+1,entity={},Transform={},AnimState={},events={},tasks={},valid=true}
    entities[#entities+1]=e
    for _,key in ipairs({"AddTransform","AddNetwork","SetPristine","SetCanSleep","AddAnimState"}) do e.entity[key]=noop end
    e.entity.AddNetwork=function() e.networked=true end
    e.entity.AddSoundEmitter=function()
        e.SoundEmitter={PlaySound=function(_,name,handle,volume)
            sounds[#sounds+1]={name=name,volume=volume,x=e.x,y=e.y,z=e.z}
        end}
    end
    e.Transform.SetFourFaced=function() e.fourfaced=true end
    e.Transform.SetPosition=function(_,x,y,z) e.x,e.y,e.z=x,y,z end
    e.Transform.GetWorldPosition=function() return e.x or 0,e.y or 0,e.z or 0 end
    e.Transform.SetScale=function(_,x,y,z) e.sx,e.sy,e.sz=x,y,z end
    e.Transform.SetFromProxy=function(_,guid)
        local proxy=entities[guid]
        e.proxy=guid;e.x,e.y,e.z,e.sx,e.sy,e.sz=proxy.x,proxy.y,proxy.z,proxy.sx,proxy.sy,proxy.sz
    end
    for _,key in ipairs({"SetOrientation","SetFinalOffset","SetMultColour","SetLightOverride","SetScale","Hide"}) do e.AnimState[key]=noop end
    e.AnimState.SetOrientation=function(_,v) e.orientation=v end
    e.AnimState.SetBank=function(_,v) e.bank=v end
    e.AnimState.SetBuild=function(_,v) e.build=v end
    e.AnimState.PlayAnimation=function(_,v) e.anim=v end
    e.AddTag=noop
    function e:ListenForEvent(event,fn)
        local previous=self.events[event]
        self.events[event]=previous and function(...) previous(...);fn(...) end or fn
    end
    function e:DoTaskInTime(delay,fn) self.tasks[#self.tasks+1]={delay=delay,fn=fn} end
    function e:IsValid() return self.valid end
    function e:Remove() self.valid=false end
    return e
end
package.loaded["nw/weapon_visual"]=function() end
package.loaded["nw/definitions"]={order={}}
require("prefabs/nw_spell_fx")
SpawnPrefab=function(name)
    spawns[#spawns+1]=name
    if name=="explode_small" then return CreateEntity() end
    return assert(factories[name],name)()
end
package.loaded["nw/targeting"]={object_tags={},selectable_prop=function() return false end,
    selected=function() return true end,accepts=function() return true end,
    selected_object=function() return false end}
local hits,modifiers={},0
package.loaded["nw/expanded_hits"]={impact=function(s,e)
    hits[#hits+1]={damage=s.p.damage,target=e}
end}
package.loaded["nw/explosions"]={hit=function() modifiers=modifiers+1 end}
local Effects=require("nw/spell_effects")
local targets={}
for i=1,2 do
    targets[i]={HasTag=function() return false end,GetDistanceSqToPoint=function() return .1 end,
        Transform={GetWorldPosition=function() return 10+i*.1,0,20 end}}
end
Effects.scan=function() return targets end
local function flush(root)
    local tasks=root.tasks;root.tasks={}
    for _,task in ipairs(tasks) do
        if task.delay==0 then task.fn(root) else root.tasks[#root.tasks+1]=task end
    end
end
for _,headless in ipairs({false,true}) do
    dedicated=headless
    for _,p in ipairs({{id="spore_ball",damage=16,radius=1,flags={}},
                       {id="end_beam",damage=16,radius=1.5,flags={}},
                       {quiet_burst=true,damage=16,radius=2.5,flags={}},
                       {damage=16,radius=3,flags={}}}) do
        local begin,beforesound,beforehit=#entities,#sounds,#hits
        local spawnstart=#spawns
        Effects.blast({},10,20,p)
        local root=entities[begin+1]
        local soft=p.quiet_burst or p.id=="spore_ball" or p.id=="end_beam"
        assert(spawns[spawnstart+1]==(soft and "nw_soft_blast_fx" or "nw_blast_fx"))
        assert(#spawns==spawnstart+1,"only the burst anchor is replicated")
        assert(#entities==begin+1,"native proxy waits one frame before rendering")
        assert(#sounds==beforesound+1 and sounds[#sounds].volume==(soft and .35 or 1))
        assert(sounds[#sounds].name=="dontstarve/common/blackpowder_explo")
        assert(sounds[#sounds].x==10 and sounds[#sounds].y==0 and sounds[#sounds].z==20)
        assert(#hits==beforehit+2,"area-hit dispatch must not depend on sound")
        flush(root)
        assert(#entities==begin+(headless and 1 or 6),"dedicated servers create no smoke entities")
        root:SetRadius(p.radius*2)
        assert(#sounds==beforesound+1 and #spawns==spawnstart+1,"resizing cannot replay a burst")
        local after=#entities
        if root.events.nw_blastradiusdirty then root.events.nw_blastradiusdirty() end
        flush(root)
        assert(#entities==after,"deferred initialization/dirty cannot duplicate visuals")
        local networks=0
        for i=begin+1,#entities do if entities[i].networked then networks=networks+1 end end
        assert(networks==1,"one network entity replaces six for every burst")
        root:Remove()
        for i=begin+2,#entities do
            local fx=entities[i]
            assert(fx.valid and not fx.networked and not fx.SoundEmitter and fx.bank=="explode" and fx.build=="explode" and fx.anim=="small")
            assert(fx.proxy==root.GUID and not fx.fourfaced and fx.orientation==ANIM_ORIENTATION.BillBoard,"native proxy transform and billboard orientation")
            local index=i-begin-2
            local r=index==0 and 0 or p.radius*.38
            assert(fx.x==10+math.cos(index*2.399)*r and fx.z==20+math.sin(index*2.399)*r and fx.y==.15)
            assert(fx.sx==math.max(.25,p.radius/3)*(index==0 and 1.1 or .65),"same radius, layout and scale")
            fx.events.animover(fx);assert(not fx.valid)
        end
        local expires=false
        for _,task in ipairs(root.tasks) do if task.delay==1 then expires=true;task.fn(root) end end
        assert(expires and not root.valid,"native proxy retains its one-second lifetime")
    end
end
assert(#hits==16 and modifiers==16)
for _,hit in ipairs(hits) do assert(hit.damage==16) end
local before=#sounds
Effects.blast({},10,20,{id="moon_fall",damage=30,radius=2,flags={}})
assert(#sounds==before+1 and sounds[#sounds].name=="dontstarve/common/meteor_impact")
-- All explosion variants use the same one-shot silent cluster, on host and replica.
for _,name in ipairs({"nw_soft_blast_fx","nw_blast_fx","nw_lighter_burst_fx","nw_crystal_burst_fx"}) do
    for _,master in ipairs({true,false}) do
        TheWorld.ismastersim=master;dedicated=false
        before=#sounds
        local replica=factories[name]()
        local first=#entities
        flush(replica)
        assert(#entities==first,"wait for a valid radius; no zero-radius flash")
        replica.Transform:SetPosition(-10,0,40)
        if master then replica:SetRadius(3) else replica._radius:set(3);replica.events.nw_blastradiusdirty() end
        assert(#entities==first,"radius dirty also waits for positioned proxy")
        flush(replica)
        assert(#entities==first+5 and #sounds==before+(master and 1 or 0))
        assert(entities[first+1].x==-10 and entities[first+1].z==40 and entities[first+1].sx==1.1)
        replica._radius:set(4);replica.events.nw_blastradiusdirty();flush(replica)
        assert(#entities==first+5,"radius corrections must not replay the burst")
        replica:Remove()
        for i=first+1,#entities do assert(entities[i].valid and not entities[i].networked and not entities[i].SoundEmitter);entities[i].events.animover(entities[i]) end
    end
end
TheWorld.ismastersim=false
local initialized=factories.nw_soft_blast_fx()
initialized.Transform:SetPosition(6,0,7);initialized._radius:set(1)
local first=#entities;flush(initialized)
assert(#entities==first+5 and entities[first+1].x==6 and entities[first+1].z==7)
dedicated=true
local headless=factories.nw_soft_blast_fx()
first=#entities;headless._radius:set(3)
headless.events.nw_blastradiusdirty();flush(headless)
assert(#entities==first)
-- Exercise the actual terminal beam descriptor, which intentionally carries no
-- spell id into its shared damage handler.
package.loaded["nw/expanded_hits"]=nil
local Hits=require("nw/expanded_hits")
local terminal
Effects.blast=function(_,x,z,p) terminal=p end
local flags={}
Hits.finish({owner={},p={id="end_beam",end_damage=16,flags=flags,size_mult=2.5}},1,2)
assert(terminal.quiet_burst and terminal.damage==16 and terminal.radius==3.75 and terminal.flags==flags)
print("explosion clusters: five silent native billboards, one sound, host/client/dedicated cleanup and area hits")
