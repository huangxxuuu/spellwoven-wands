-- Moon impact keeps the real area-hit dispatch, but uses one positioned sound
-- rather than the five independently audible native explode_small proxies.
local factories,sounds,spawns={},{},{}
local dedicated=false
Asset=function() end
Prefab=function(name,fn) factories[name]=fn;return name end
TheWorld={ismastersim=true}
TheNet={IsDedicated=function() return dedicated end}
ANIM_ORIENTATION={OnGround=1}
local function noop() end
CreateEntity=function()
    local e={entity={},Transform={},valid=true,events={},tasks={}}
    e.entity.AddTransform=noop;e.entity.AddNetwork=noop;e.entity.SetPristine=noop
    e.entity.AddSoundEmitter=function()
        e.SoundEmitter={PlaySound=function(_,sound)
            sounds[#sounds+1]={name=sound,x=e.x,y=e.y,z=e.z}
        end}
    end
    e.Transform.SetPosition=function(_,x,y,z) e.x,e.y,e.z=x,y,z end
    e.Transform.GetWorldPosition=function() return e.x or 0,e.y or 0,e.z or 0 end
    e.AddTag=noop
    function e:DoTaskInTime(delay,fn) self.tasks[#self.tasks+1]={delay=delay,fn=fn} end
    function e:IsValid() return self.valid end
    function e:Remove() self.valid=false end
    return e
end
-- These factories do not affect the new effect or the real blast function.
package.loaded["nw/weapon_visual"]=function() end
package.loaded["nw/definitions"]={order={}}
require("prefabs/nw_spell_fx")
SpawnPrefab=function(name)
    spawns[#spawns+1]=name
    assert(name=="nw_moon_impact_fx","moon must not create generic audible blast clusters")
    return factories[name]()
end
package.loaded["nw/targeting"]={object_tags={},breakable=function() return false end,
    allowed=function() return true end,selected_object=function() return false end}
local hits,modifiers={},0
package.loaded["nw/expanded_hits"]={impact=function(s,e,x,z)
    hits[#hits+1]={target=e,damage=s.p.damage,x=x,z=z}
end}
package.loaded["nw/explosions"]={hit=function() modifiers=modifiers+1 end}
local Effects=require("nw/spell_effects")
local targets={}
for i=1,3 do
    local x,z=10+i*.2,20
    targets[i]={HasTag=function() return false end,
        GetDistanceSqToPoint=function(_,px,py,pz) return (x-px)^2+(z-pz)^2 end,
        Transform={GetWorldPosition=function() return x,0,z end}}
end
Effects.scan=function() return targets end
for _,headless in ipairs({false,true}) do
    dedicated=headless
    local before=#sounds
    Effects.blast({},10,20,{id="moon_fall",radius=2,damage=30,flags={}})
    assert(#sounds==before+1 and sounds[#sounds].name=="dontstarve/common/meteor_impact")
    assert(sounds[#sounds].x==10 and sounds[#sounds].y==0 and sounds[#sounds].z==20)
end
assert(#spawns==2 and #hits==6 and modifiers==6,"area damage and explicit impact modifiers retain their dispatch")
for _,hit in ipairs(hits) do assert(hit.damage==30) end
local direct=factories.nw_moon_impact_fx()
direct.Transform:SetPosition(3,0,4)
local before=#sounds
direct:SetRadius(2);direct:SetRadius(5)
assert(#sounds==before+1,"repeated size application cannot replay impact sound")
assert(direct.tasks[1].delay==.8)
direct.tasks[1].fn(direct);assert(not direct.valid)
TheWorld.ismastersim=false
local replica=factories.nw_moon_impact_fx()
assert(not replica.SetRadius and #sounds==before+1,"client replica cannot start a second sound")
print("moon impact: one native sound per landing, positioned correctly, area hits preserved")
