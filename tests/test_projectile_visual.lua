RemovePhysicsColliders=function(e) e.no_terrain_collision=true end
-- Validate both prefab branches: a local elevated child, no gravity correction
-- writes, immutable network schema, dirty updates and explicit child cleanup.
Asset=function() end;Prefab=function(_,fn) return fn end
local dedicated=false
TheNet={IsDedicated=function() return dedicated end};TheWorld={ismastersim=false,DoPeriodicTask=function() return {Cancel=function() end} end}
local function eventable(e)
    e.events=e.events or {};e.callbacks={}
    function e:ListenForEvent(name,fn)
        self.callbacks[name]=self.callbacks[name] or {};self.callbacks[name][fn]=true
        self.events[name]=function(...)
            local callbacks={};for callback in pairs(self.callbacks[name]) do callbacks[#callbacks+1]=callback end
            for _,callback in ipairs(callbacks) do callback(...) end
        end
    end
    function e:RemoveEventCallback(name,fn)
        if self.callbacks[name] then self.callbacks[name][fn]=nil end
    end
    return e
end
eventable(TheWorld)
GetTime=function() return 0 end
local id=0
CreateEntity=function()
    id=id+1
    local e=eventable({GUID=id,events={},valid=true,scale=1,entity={},Transform={},AnimState={}})
    for _,name in ipairs({"AddTransform","AddAnimState","AddNetwork","SetCanSleep","SetPristine"}) do e.entity[name]=function() end end
    e.entity.SetParent=function(_,p) e.parent=p end
    e.Transform.SetPosition=function(_,x,y,z) e.x=x;e.y=y;e.z=z end
    e.Transform.GetWorldPosition=function() return e.x or 0,e.y or 0,e.z or 0 end
    e.Transform.SetScale=function(_,x) e.scale=x end
    e.Transform.GetScale=function() local s=e.scale or 1;return s,s,s end
    e.Transform.SetRotation=function(_,r) e.rotation=r end
    e.Transform.SetFourFaced=function() e.fourfaced=true end
    for _,name in ipairs({"SetBank","SetBuild","PlayAnimation","SetLightOverride","SetOrientation"}) do e.AnimState[name]=function() end end
    e.AnimState.SetBank=function(_,bank) e.bank=bank end
    e.AnimState.PlayAnimation=function(_,name,loop) e.anim=name;e.loop=loop end
    e.AnimState.PushAnimation=function(_,name,loop) e.queued=name end
    e.AnimState.SetDeltaTimeMultiplier=function(_,rate) e.playback=rate end
    e.AnimState.OverrideSymbol=function(_,_,_,symbol) e.symbol=symbol end
    e.AnimState.SetOrientation=function(_,orientation) e.orientation=orientation end
    e.AnimState.SetBankAndPlayAnimation=function(_,bank,animation) e.anim=animation end
    e.AnimState.SetFrame=function() end;e.AnimState.Pause=function() end
    e.AnimState.SetTime=function(_,time) e.animtime=time end
    function e:Hide() self.hidden=true end
    function e:AddTag() end
    function e:DoPeriodicTask(_,fn) self.facestep=fn end
    e.Transform.GetRotation=function() return e.rotation or 0 end
    function e:DoTaskInTime(_,fn) fn(self) end
    function e:IsValid() return self.valid end
    function e:Remove() self.valid=false;if self.events.onremove then self.events.onremove(self) end end
    return e
end
MakeInventoryPhysics=function(e) e.Physics={SetMotorVel=function(_,s) e.speed=s end,ClearCollisionMask=function() end,
    GetVelocity=function() return e.speed or 0,0,0 end,
    SetFriction=function(_,v) e.friction=v end,SetRestitution=function(_,v) e.restitution=v end} end
local function net() return {v=0,set=function(self,v) self.v=v end,value=function(self) return self.v end} end
net_byte=net;net_float=net
ANIM_ORIENTATION={OnGround=1,BillBoard=2,Default=3};TheCamera={heading=0,pitch=35};DEGREES=math.pi/180
local make=require("prefabs/nw_projectile")
local client=make();local v=client._visual
assert(client.friction==0 and client.restitution==0,"projectiles must not friction-brake or bounce on the ground")
assert(v and v.parent==client.entity and not client.Launch)
client._height:set(1.75);client._spell:set(require("nw/cards").codes.heavy)
client.events.nw_projectiledirty(client)
assert(v.y==1.75 and v.scale==1 and v.bank=="nw_elemental_flight" and v.orientation==ANIM_ORIENTATION.BillBoard)
assert(v.anim:find("^heavy_dir_") and v.loop and v.playback==.5)
client._size:set(2.5);client.events.nw_projectiledirty(client)
assert(v.scale==2.5 and v.y==1.75,"giant must not raise flight height")
client.events.nw_projectiledirty(client);assert(v.scale==2.5,"dirty events must not multiply repeatedly")
client._size:set(1);client.events.nw_projectiledirty(client);assert(v.scale==1)
client:Remove();assert(not v:IsValid())
local attached=0
package.loaded["nw/spark_trail"]={attach=function() attached=attached+1 end}
local remote=make()
assert(not remote._visual.anim)
remote._spell:set(require("nw/cards").codes.spark)
remote._height:set(1.4)
remote.events.nw_projectiledirty(remote)
remote.events.nw_projectiledirty(remote)
assert(remote._visual.anim=="head" and remote._visual.loop and attached==1)
local added=0;package.loaded['nw/projectiles'].add=function() added=added+1 end
TheWorld.ismastersim=true;DEGREES=math.pi/180
for _,headless in ipairs({false,true}) do
    dedicated=headless
    local p=make();assert((p._visual==nil)==headless)
    p:Launch({}, {id="arrow",damage=28,speed=20,lifetime=.8},4,5,1,0,function() end,1.6)
    assert(p.y==0 and p.x==4 and p.z==5 and p.speed==20 and p._height:value()==1.6)
    if not headless then assert(p._visual.y==1.6 and p._visual.scale==1) end
    local default=make()
    default:Launch({}, {id="arrow",damage=28,speed=20,lifetime=.8},4,5,1,0,function() end)
    assert(default._height:value()==require("nw/muzzle").default_height and default._shot.height==2)
    assert(default.y==0,"flight height must not lift the physical collision plane")
    if not headless then assert(default._visual.y==2) end
    for _,id in ipairs({"spark","spark_hit","spark_timer"}) do
        local fx=make()
        fx:Launch({}, {id=id,base="spark",damage=18,speed=17.5,lifetime=.8},4,5,1,0,function() end,1.6)
        if not headless then assert(fx._visual.anim=="head" and fx._visual.y==1.6) end
    end
end
assert(added==10 and attached==4)
-- A breakable spore uses one visual cue plus its original one blast. The cue
-- cannot manufacture a second damage path or execute an on-hit payload.
local _,make_spore=assert(loadfile("mod/scripts/prefabs/nw_projectile.lua"))()
local Fields=require("nw/expanded_fields")
local Effects=require("nw/spell_effects")
local Triggers=require("nw/projectile_triggers")
local Projectiles=require("nw/projectiles")
local attackable,blast,finish,contact=Fields.attackable,Effects.blast,Triggers.finish,Projectiles.contact_fx
local cues,blasts,finishes=0,0,0
Fields.attackable=function() end
Effects.blast=function() blasts=blasts+1 end
Triggers.finish=function() finishes=finishes+1 end
Projectiles.contact_fx=function(s,x,z)
    assert(s.p.id=="spore_ball" and x==4 and z==5)
    cues=cues+1
end
local spore=make_spore()
spore:Launch({}, {id="spore_ball",damage=16,speed=3,lifetime=2},4,5,1,0,function() end,1.6)
spore._nw_break()
assert(cues==1 and blasts==1 and finishes==1 and not spore:IsValid() and spore._nw_break==nil)
Fields.attackable,Effects.blast,Triggers.finish,Projectiles.contact_fx=attackable,blast,finish,contact
-- Every visible remote projectile takes its real spell-specific refresh path.
-- The lance uses a camera-facing cutout; the hoe has its own upright directions.
dedicated=false;TheWorld.ismastersim=false
for id,spell in pairs(require("nw/definitions").spells) do
    if spell.kind=="projectile" or spell.kind=="trigger" then
        local shot=make()
        shot._spell:set(require("nw/cards").codes[spell.base or id])
        shot._height:set(1.4);shot.events.nw_projectiledirty(shot)
        local art=shot._visual
        if require("nw/tool_flight").supports(spell.engraving) then
            local tool=require("nw/tool_flight").resolve(spell.engraving)
            assert(art.bank=="nw_tool_flight" and art.anim:find("^"..tool.."_dir_"))
        end
        if spell.engraving=="lighter" then assert(art.anim=="lighter_spin" and art.loop) end
        local base=spell.base or id
        if require("nw/elemental_flight").supports(base) then
            local visual_id=require("nw/elemental_flight").resolve(base)
            assert(art.bank=="nw_elemental_flight" and art.anim:find("^"..visual_id.."_dir_") and art.loop,base.." must use its animated flight bank")
            assert(shot._spell:value()==require("nw/cards").codes[base],"visual aliases must preserve the replicated card identity")
        end
        assert(art.y==1.4,id)
        if spell.engraving=="voidcloth_scythe" then
            assert(art.orientation==ANIM_ORIENTATION.OnGround and art.anim=="scythe_spin")
        else
            assert(art.orientation~=ANIM_ORIENTATION.OnGround,id)
            assert(art.hidden or art.orientation==ANIM_ORIENTATION.BillBoard or art.fourfaced,id)
        end
        if id=="land_hook" then
            assert(require("nw/elemental_flight").direction_count(id)==64 and art.anim:find("^land_hook_dir_"))
        end
        shot:Remove()
    end
end
-- The native beam has its own prefab/wire schema and never attaches the old
-- sprite trail. Its original executor reservation survives visual publication.
net_string=net;net_bool=net
local _,_,make_beam=assert(loadfile("mod/scripts/prefabs/nw_projectile.lua"))()
local attached_beams,refreshed_beams=0,0
local previous_beam_visual=package.loaded["nw/beam_visual"]
package.loaded["nw/beam_visual"]={attach=function() attached_beams=attached_beams+1 end,
    refresh=function() refreshed_beams=refreshed_beams+1 end}
local beam_client=make_beam()
assert(beam_client._beam_path and beam_client._beam_ended and not beam_client._visual and not beam_client.Launch)
assert(attached_beams==1)
dedicated=true;TheWorld.ismastersim=true
local beam=make_beam();local released=0
beam:Launch({}, {id="end_beam",damage=12,speed=26,lifetime=.75,flags={pierce_all={}}},
    1,2,1,0,function() released=released+1 end,1.4)
assert(not beam._visual and beam._shot.hits_left==math.huge and attached_beams==1)
local segments={{id=1,x1=1,z1=2,x2=2,z2=2,born=0,radius=.12}}
beam:PublishBeam(segments,.1,false)
local snapshot=beam._beam_path:value()
assert(require("nw/beam_path").decode(snapshot).segments[1].age==.1)
beam:PublishBeam(segments,.15,false)
assert(beam._beam_path:value()==snapshot,"normal publications must respect the snapshot interval")
beam:PublishBeam(segments,.16,true,true)
assert(beam._beam_ended:value()==true and beam._beam_path:value()~=snapshot)
assert(beam:IsValid() and released==0 and refreshed_beams==0,"ending the front must retain the carrier reservation")
beam:Remove();assert(released==1)
package.loaded["nw/beam_visual"]=previous_beam_visual
print("projectile visuals: elevated local sprites, native beam schema, publication throttle and reservation cleanup")
