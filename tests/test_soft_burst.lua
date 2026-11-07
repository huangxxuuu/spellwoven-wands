-- These projectile endings keep their native fire/smoke but must not play a
-- blackpowder sound independently from every visual in the cluster.
local factories,entities,sounds,spawns={},{},{},{}
local dedicated=false
local function noop() end
Asset=noop
Prefab=function(name,fn) factories[name]=fn;return name end
TheWorld={ismastersim=true}
TheNet={IsDedicated=function() return dedicated end}
ANIM_ORIENTATION={OnGround=1}
net_float=function()
    return {v=0,value=function(self) return self.v end,set=function(self,v) self.v=v end}
end
CreateEntity=function()
    local e={GUID=#entities+1,entity={},Transform={},AnimState={},events={},tasks={},valid=true}
    entities[#entities+1]=e
    for _,key in ipairs({"AddTransform","AddNetwork","SetPristine","SetCanSleep","AddAnimState"}) do e.entity[key]=noop end
    e.entity.AddSoundEmitter=function()
        e.SoundEmitter={PlaySound=function(_,name,handle,volume)
            sounds[#sounds+1]={name=name,volume=volume,x=e.x,y=e.y,z=e.z}
        end}
    end
    e.Transform.SetFourFaced=noop
    e.Transform.SetPosition=function(_,x,y,z) e.x,e.y,e.z=x,y,z end
    e.Transform.GetWorldPosition=function() return e.x or 0,e.y or 0,e.z or 0 end
    e.Transform.SetScale=function(_,x,y,z) e.sx,e.sy,e.sz=x,y,z end
    e.Transform.SetFromProxy=function(_,guid)
        local proxy=entities[guid]
        e.x,e.y,e.z,e.sx,e.sy,e.sz=proxy.x,proxy.y,proxy.z,proxy.sx,proxy.sy,proxy.sz
    end
    for _,key in ipairs({"SetOrientation","SetFinalOffset","SetMultColour","SetLightOverride","SetScale","Hide"}) do e.AnimState[key]=noop end
    e.AnimState.SetBank=function(_,v) e.bank=v end
    e.AnimState.SetBuild=function(_,v) e.build=v end
    e.AnimState.PlayAnimation=function(_,v) e.anim=v end
    e.AddTag=noop
    function e:ListenForEvent(event,fn) self.events[event]=fn end
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
package.loaded["nw/targeting"]={object_tags={},breakable=function() return false end,
    allowed=function() return true end,selected_object=function() return false end}
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
for _,headless in ipairs({false,true}) do
    dedicated=headless
    for _,p in ipairs({{id="spore_ball",damage=16,radius=1,flags={}},
                       {id="end_beam",damage=16,radius=1.5,flags={}},
                       {quiet_burst=true,damage=16,radius=2.5,flags={}}}) do
        local begin,beforesound,beforehit=#entities,#sounds,#hits
        local spawnstart=#spawns
        Effects.blast({},10,20,p)
        local root=entities[begin+1]
        assert(spawns[spawnstart+1]=="nw_soft_blast_fx")
        assert(#spawns==spawnstart+6,"one anchor plus five visuals")
        for i=spawnstart+2,#spawns do assert(spawns[i]=="nw_silent_explode_small") end
        assert(#sounds==beforesound+1 and sounds[#sounds].volume==.35)
        assert(sounds[#sounds].name=="dontstarve/common/blackpowder_explo")
        assert(sounds[#sounds].x==10 and sounds[#sounds].y==0 and sounds[#sounds].z==20)
        assert(#hits==beforehit+2,"area-hit dispatch must not depend on sound")
        root:SetRadius(p.radius*2)
        assert(#sounds==beforesound+1 and #spawns==spawnstart+6,"resizing cannot replay a burst")
        local proxies={}
        for i=begin+2,begin+6 do proxies[#proxies+1]=entities[i] end
        local beforelocal=#entities
        for _,proxy in ipairs(proxies) do
            assert(not proxy.SoundEmitter)
            for _,task in ipairs(proxy.tasks) do
                if task.delay==0 then task.fn(proxy) end
            end
        end
        assert(#entities==beforelocal+(headless and 0 or 5))
        for i=beforelocal+1,#entities do
            local fx=entities[i]
            assert(not fx.SoundEmitter and fx.bank=="explode" and fx.build=="explode" and fx.anim=="small")
            local proxy=proxies[i-beforelocal]
            assert(fx.x==proxy.x and fx.z==proxy.z and fx.sx==proxy.sx,"native proxy registration/scale retained")
            fx.events.animover(fx);assert(not fx.valid)
        end
        for _,proxy in ipairs(proxies) do
            for _,task in ipairs(proxy.tasks) do if task.delay==1 then task.fn(proxy) end end
            assert(not proxy.valid)
        end
        assert(root.tasks[1].delay==1,"sound emitter survives its short one-shot")
        root.tasks[1].fn(root);assert(not root.valid)
    end
end
assert(#hits==12 and modifiers==12)
for _,hit in ipairs(hits) do assert(hit.damage==16) end
-- Other explosions and moon impacts keep their previous routes.
local start=#spawns
Effects.blast({},10,20,{damage=16,radius=1,flags={}})
assert(spawns[start+1]=="nw_blast_fx")
for i=start+2,#spawns do assert(spawns[i]=="explode_small") end
local before=#sounds
Effects.blast({},10,20,{id="moon_fall",damage=30,radius=2,flags={}})
assert(#sounds==before+1 and sounds[#sounds].name=="dontstarve/common/meteor_impact")
-- A replica creates only silent art; the server owns the one central sound.
TheWorld.ismastersim=false;dedicated=false
before=#sounds
local replica=factories.nw_soft_blast_fx()
assert(not replica.SetRadius)
local proxy=factories.nw_silent_explode_small()
proxy.tasks[1].fn(proxy)
assert(not entities[#entities].SoundEmitter and #sounds==before)
-- Exercise the actual terminal beam descriptor, which intentionally carries no
-- spell id into its shared damage handler.
package.loaded["nw/expanded_hits"]=nil
local Hits=require("nw/expanded_hits")
local terminal
Effects.blast=function(_,x,z,p) terminal=p end
local flags={}
Hits.finish({owner={},p={id="end_beam",end_damage=16,flags=flags,size_mult=2.5}},1,2)
assert(terminal.quiet_burst and terminal.damage==16 and terminal.radius==3.75 and terminal.flags==flags)
print("soft bursts: five silent native visuals, one 0.35-volume sound, unchanged area hits, server/client cleanup")
