RemovePhysicsColliders=function(e) e.no_terrain_collision=true end
-- Validate both prefab branches: a local elevated child, no gravity correction
-- writes, immutable network schema, dirty updates and explicit child cleanup.
Asset=function() end;Prefab=function(_,fn) return fn end
local dedicated=false
TheNet={IsDedicated=function() return dedicated end};TheWorld={ismastersim=false,DoPeriodicTask=function() return {Cancel=function() end} end}
local id=0
CreateEntity=function()
    id=id+1
    local e={GUID=id,events={},valid=true,entity={},Transform={},AnimState={}}
    for _,name in ipairs({"AddTransform","AddAnimState","AddNetwork","SetCanSleep","SetPristine"}) do e.entity[name]=function() end end
    e.entity.SetParent=function(_,p) e.parent=p end
    e.Transform.SetPosition=function(_,x,y,z) e.x=x;e.y=y;e.z=z end
    e.Transform.SetScale=function(_,x) e.scale=x end
    e.Transform.GetScale=function() local s=e.scale or 1;return s,s,s end
    e.Transform.SetRotation=function(_,r) e.rotation=r end
    e.Transform.SetFourFaced=function() e.fourfaced=true end
    for _,name in ipairs({"SetBank","SetBuild","PlayAnimation","SetLightOverride","SetOrientation"}) do e.AnimState[name]=function() end end
    e.AnimState.PlayAnimation=function(_,name,loop) e.anim=name;e.loop=loop end
    e.AnimState.OverrideSymbol=function(_,_,_,symbol) e.symbol=symbol end
    e.AnimState.SetOrientation=function(_,orientation) e.orientation=orientation end
    e.AnimState.SetBankAndPlayAnimation=function(_,bank,animation) e.anim=animation end
    e.AnimState.SetFrame=function() end;e.AnimState.Pause=function() end
    function e:Hide() self.hidden=true end
    function e:AddTag() end
    function e:ListenForEvent(name,fn) self.events[name]=fn end
    function e:DoPeriodicTask(_,fn) self.facestep=fn end
    e.Transform.GetRotation=function() return e.rotation or 0 end
    function e:DoTaskInTime(_,fn) fn(self) end
    function e:IsValid() return self.valid end
    function e:Remove() self.valid=false;if self.events.onremove then self.events.onremove(self) end end
    return e
end
MakeInventoryPhysics=function(e) e.Physics={SetMotorVel=function(_,s) e.speed=s end,ClearCollisionMask=function() end,
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
assert(v.y==1.75 and v.scale==2 and v.symbol=="body_heavy" and v.orientation==ANIM_ORIENTATION.BillBoard)
client._size:set(2.5);client.events.nw_projectiledirty(client)
assert(v.scale==5 and v.y==1.75,"giant must not raise flight height")
client.events.nw_projectiledirty(client);assert(v.scale==5,"dirty events must not multiply repeatedly")
client._size:set(1);client.events.nw_projectiledirty(client);assert(v.scale==2)
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
TheWorld.ismastersim=true;GetTime=function() return 0 end;DEGREES=math.pi/180
for _,headless in ipairs({false,true}) do
    dedicated=headless
    local p=make();assert((p._visual==nil)==headless)
    p:Launch({}, {id="arrow",damage=28,speed=20,lifetime=.8},4,5,1,0,function() end,1.6)
    assert(p.y==0 and p.x==4 and p.z==5 and p.speed==20 and p._height:value()==1.6)
    if not headless then assert(p._visual.y==1.6 and p._visual.scale==1.6) end
    for _,id in ipairs({"spark","spark_hit","spark_timer"}) do
        local fx=make()
        fx:Launch({}, {id=id,base="spark",damage=18,speed=17.5,lifetime=.8},4,5,1,0,function() end,1.6)
        if not headless then assert(fx._visual.anim=="head" and fx._visual.y==1.6) end
    end
end
assert(added==8 and attached==4)
-- Every visible remote projectile takes its real spell-specific refresh path.
-- The lance uses a camera-facing cutout; the hoe has its own upright directions.
dedicated=false;TheWorld.ismastersim=false
for id,spell in pairs(require("nw/definitions").spells) do
    if spell.kind=="projectile" or spell.kind=="trigger" then
        local shot=make()
        shot._spell:set(require("nw/cards").codes[spell.base or id])
        shot._height:set(1.4);shot.events.nw_projectiledirty(shot)
        local art=shot._visual
        if spell.engraving=="farm_hoe" then assert(art.anim:find("^hoe_dir_")) end
        if spell.engraving=="lighter" then assert(art.anim=="lighter_spin" and art.loop) end
        assert(art.y==1.4 and art.orientation~=ANIM_ORIENTATION.OnGround,id)
        assert(art.hidden or art.orientation==ANIM_ORIENTATION.BillBoard or art.fourfaced,id)
        shot:Remove()
    end
end
print("projectile visuals: same network schema; ground physics + elevated local sprite; dirty update and cleanup on both peers")
